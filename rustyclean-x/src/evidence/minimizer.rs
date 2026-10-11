use anyhow::Result;
use std::collections::HashSet;
use std::path::Path;

use super::EvidenceFeatures;
use crate::fastq::FastqRecord;
use crate::sequence::{canonical_kmer, encode_bases, wyhash};

/// Deacon-style minimizer evidence.
///
/// For each consecutive `window`-bp window in the read, select one canonical
/// k-mer using a stable hashed order. This is the standard minimizer definition:
/// `window >= k` and windows advance by one base.
#[derive(Debug)]
pub struct MinimizerFilter {
    minimizer_hashes: HashSet<u64>,
    k: usize,
    window: usize,
}

impl MinimizerFilter {
    pub fn from_hash_file(path: impl AsRef<Path>, k: usize, window: usize) -> Result<Self> {
        if k == 0 || k > 32 {
            return Err(anyhow::anyhow!("k must be between 1 and 32"));
        }
        if window < k {
            return Err(anyhow::anyhow!("window must be greater than or equal to k"));
        }
        let text = std::fs::read_to_string(path)?;
        let minimizer_hashes = text
            .lines()
            .filter_map(|line| line.split_whitespace().next())
            .filter_map(|value| value.parse::<u64>().ok())
            .collect();
        Ok(Self {
            minimizer_hashes,
            k,
            window,
        })
    }

    pub fn empty(k: usize, window: usize) -> Self {
        Self {
            minimizer_hashes: HashSet::new(),
            k,
            window,
        }
    }

    pub fn with_hashes(minimizer_hashes: HashSet<u64>, k: usize, window: usize) -> Self {
        Self {
            minimizer_hashes,
            k,
            window,
        }
    }

    pub fn add_evidence(&self, record: &FastqRecord, features: &mut EvidenceFeatures) {
        if record.seq.len() < self.window {
            return;
        }

        // For each w-bp minimizer window, choose one canonical k-mer by stable
        // hash. Every candidate contains no ambiguous base; windows containing N
        // are skipped.
        for window_start in 0..=(record.seq.len() - self.window) {
            let window_end = window_start + self.window;
            let mut best: Option<(u64, u64)> = None;
            let mut valid_window = false;

            for start in window_start..=window_end - self.k {
                let Some(kmer) = encode_bases(&record.seq[start..start + self.k]) else {
                    continue;
                };
                valid_window = true;
                let canonical = canonical_kmer(kmer, self.k);
                let hash = wyhash(canonical);
                best = match best {
                    Some((best_hash, best_kmer)) if best_hash <= hash => {
                        Some((best_hash, best_kmer))
                    }
                    _ => Some((hash, canonical)),
                };
            }

            if valid_window {
                features.evaluated_minimizer_windows += 1;
                if let Some((hash, _)) = best {
                    if self.minimizer_hashes.contains(&hash) {
                        features.minimizer_host_hits += 1;
                    }
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hashes_for(seq: &[u8], k: usize, window: usize) -> Vec<Option<u64>> {
        let mut out = Vec::new();
        for start in 0..=(seq.len() - window) {
            let mut best: Option<(u64, u64)> = None;
            for start_k in start..=start + window - k {
                let Some(kmer) = encode_bases(&seq[start_k..start_k + k]) else {
                    continue;
                };
                let canonical = canonical_kmer(kmer, k);
                let hash = wyhash(canonical);
                best = match best {
                    Some(old) if old.0 <= hash => Some(old),
                    _ => Some((hash, canonical)),
                };
            }
            out.push(best.map(|(hash, _)| hash));
        }
        out
    }

    #[test]
    fn uses_one_minimizer_per_w_window() {
        let seq = b"ACGTACGTAC";
        let hashes = hashes_for(seq, 3, 4);
        assert_eq!(hashes.len(), seq.len() - 4 + 1);
        assert!(hashes.iter().all(|value| value.is_some()));
    }

    #[test]
    fn skips_windows_containing_ambiguous_bases() {
        let seq = b"ACGTNACGTA";
        let hashes = hashes_for(seq, 3, 4);
        assert_eq!(hashes.len(), seq.len() - 4 + 1);
        assert!(hashes[2].is_none());
        assert!(hashes[0].is_some());
    }

    #[test]
    fn rejects_invalid_configuration() {
        let result = MinimizerFilter::from_hash_file("/dev/null", 0, 4);
        assert!(result.is_err());
        let result = MinimizerFilter::from_hash_file("/dev/null", 3, 2);
        assert!(result.is_err());
    }
}
