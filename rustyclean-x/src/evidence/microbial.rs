use anyhow::Result;
use std::collections::HashSet;
use std::path::Path;

use super::EvidenceFeatures;
use crate::fastq::FastqRecord;
use crate::sequence::{canonical_kmer, encode_bases, wyhash};

#[derive(Debug)]
pub struct MicrobialWitnessFilter {
    witness_hashes: HashSet<u64>,
    k: usize,
}

impl MicrobialWitnessFilter {
    pub fn from_hash_file(path: impl AsRef<Path>, k: usize) -> Result<Self> {
        if k == 0 || k > 32 {
            return Err(anyhow::anyhow!("k must be between 1 and 32"));
        }
        let text = std::fs::read_to_string(path)?;
        let witness_hashes = text
            .lines()
            .filter_map(|line| line.split_whitespace().next())
            .filter_map(|value| value.parse::<u64>().ok())
            .collect();
        Ok(Self { witness_hashes, k })
    }

    pub fn with_hashes(witness_hashes: HashSet<u64>, k: usize) -> Self {
        Self { witness_hashes, k }
    }

    pub fn add_evidence(&self, record: &FastqRecord, features: &mut EvidenceFeatures) {
        if record.seq.len() < self.k {
            return;
        }
        for start in 0..=(record.seq.len() - self.k) {
            let Some(kmer) = encode_bases(&record.seq[start..start + self.k]) else {
                continue;
            };
            features.evaluated_microbial_kmers += 1;
            let canonical = canonical_kmer(kmer, self.k);
            if self.witness_hashes.contains(&wyhash(canonical)) {
                features.microbial_witness_hits += 1;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sequence::reverse_complement_kmer;

    #[test]
    fn recognizes_forward_and_reverse_complement_witnesses() {
        let kmer = encode_bases(b"ACGTACGTACGT").unwrap();
        let rc = reverse_complement_kmer(kmer, 12);
        let forward_hash = wyhash(canonical_kmer(kmer, 12));
        let reverse_hash = wyhash(canonical_kmer(rc, 12));
        let hashes = [forward_hash, reverse_hash].into_iter().collect();
        let filter = MicrobialWitnessFilter {
            witness_hashes: hashes,
            k: 12,
        };
        let mut record = FastqRecord {
            header: "@test".into(),
            seq: b"ACGTACGTACGT".to_vec(),
            qual: vec![b'I'; 12],
        };
        let mut features = EvidenceFeatures::default();
        filter.add_evidence(&record, &mut features);
        assert_eq!(features.microbial_witness_hits, 1);

        record.seq = b"ACGTACGTACGT".to_vec();
        features = EvidenceFeatures::default();
        filter.add_evidence(&record, &mut features);
        assert_eq!(features.microbial_witness_hits, 1);
    }
}
