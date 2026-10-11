use anyhow::Result;
use std::collections::HashSet;
use std::path::Path;

use super::EvidenceFeatures;
use crate::fastq::FastqRecord;
use crate::sequence::encode_base;

/// A gapped seed mask. A `1` bit is inspected; a `0` bit is a wildcard and
/// therefore tolerates substitutions at that position.
#[derive(Debug, Clone)]
pub struct SeedMask {
    pub length: usize,
    pub mask: u64,
    pub weight: usize,
}

impl SeedMask {
    pub fn new(mask: u64, length: usize) -> Result<Self> {
        if length == 0 || length > 64 {
            return Err(anyhow::anyhow!("seed length must be between 1 and 64"));
        }
        let selected_mask = mask & ((1_u64 << length) - 1);
        let weight = selected_mask.count_ones() as usize;
        if weight == 0 {
            return Err(anyhow::anyhow!("seed mask has no inspected positions"));
        }
        Ok(Self {
            length,
            mask: selected_mask,
            weight,
        })
    }

    /// Hash inspected positions left-to-right. Wildcard positions never affect
    /// the hash, which is what makes the seed tolerant to substitutions.
    pub fn hash_sequence(&self, sequence: &[u8], start: usize) -> Option<(u64, usize)> {
        if start + self.length > sequence.len() {
            return None;
        }
        let mut hash = 0xcbf2_9ce4_8422_2325_u64;
        let mut inspected = 0_usize;
        for offset in 0..self.length {
            let inspected_here = (self.mask >> (self.length - 1 - offset)) & 1 == 1;
            if !inspected_here {
                continue;
            }
            let encoded = encode_base(sequence[start + offset])?;
            hash = (hash ^ encoded).wrapping_mul(0x0000_0100_0000_01B3);
            inspected += 1;
        }
        Some((hash, inspected))
    }
}

/// Draft Cleanifier-style gapped-seed evidence index. Production will replace
/// the HashSet with a checksummed Cuckoo/Bloom filter.
#[derive(Debug)]
pub struct GappedSeedFilter {
    seed_hashes: HashSet<u64>,
    masks: Vec<SeedMask>,
}

impl GappedSeedFilter {
    pub fn from_hash_file(path: impl AsRef<Path>) -> Result<Self> {
        let text = std::fs::read_to_string(path)?;
        let seed_hashes = text
            .lines()
            .filter_map(|line| line.split_whitespace().next())
            .filter_map(|value| value.parse::<u64>().ok())
            .collect();
        let masks = vec![
            SeedMask::new(0b1_1111_1111_1001_1111_1111, 21)?,
            SeedMask::new(0b1_1011_0111_1011_0111_1011, 21)?,
        ];
        Ok(Self { seed_hashes, masks })
    }

    pub fn empty(masks: Vec<SeedMask>) -> Self {
        Self {
            seed_hashes: HashSet::new(),
            masks,
        }
    }

    pub fn with_hashes(seed_hashes: HashSet<u64>, masks: Vec<SeedMask>) -> Self {
        Self { seed_hashes, masks }
    }

    pub fn add_evidence(&self, record: &FastqRecord, features: &mut EvidenceFeatures) {
        for mask in &self.masks {
            if record.seq.len() < mask.length {
                continue;
            }
            for start in 0..=(record.seq.len() - mask.length) {
                features.evaluated_gapped_seeds += 1;
                if let Some((hash, inspected)) = mask.hash_sequence(&record.seq, start) {
                    if inspected == mask.weight && self.seed_hashes.contains(&hash) {
                        features.gapped_host_hits += 1;
                    }
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hash_at(mask: u64, length: usize, sequence: &[u8], start: usize) -> Option<(u64, usize)> {
        SeedMask::new(mask, length)
            .unwrap()
            .hash_sequence(sequence, start)
    }

    #[test]
    fn wildcard_positions_tolerate_substitutions() {
        let mask = 0b1101;
        let sequence = b"ACGT";
        let mutated = b"ACTT";
        let first = hash_at(mask, 4, sequence, 0).unwrap();
        let second = hash_at(mask, 4, mutated, 0).unwrap();
        // Position 3 is a wildcard, so a substitution there cannot change hash.
        assert_eq!(first, second);
    }

    #[test]
    fn inspected_positions_change_hash() {
        let mask = 0b1101;
        let sequence = b"ACGT";
        let mutated = b"ACGA";
        assert_ne!(hash_at(mask, 4, sequence, 0), hash_at(mask, 4, mutated, 0));
    }

    #[test]
    fn rejects_empty_masks() {
        assert!(SeedMask::new(0, 4).is_err());
    }
}
