pub mod gapped;
pub mod microbial;
pub mod minimizer;

use serde::Serialize;

use crate::fastq::FastqRecord;
use gapped::GappedSeedFilter;
use microbial::MicrobialWitnessFilter;
use minimizer::MinimizerFilter;

#[derive(Debug, Clone, Default, Serialize)]
pub struct EvidenceFeatures {
    pub evaluated_gapped_seeds: u32,
    pub gapped_host_hits: u32,
    pub evaluated_minimizer_windows: u32,
    pub minimizer_host_hits: u32,
    pub evaluated_microbial_kmers: u32,
    pub microbial_witness_hits: u32,
    pub host_gapped_fraction: f64,
    pub host_minimizer_fraction: f64,
    pub microbe_witness_fraction: f64,
    pub mean_base_quality: f64,
}

impl EvidenceFeatures {
    pub fn update_derived(&mut self) {
        self.host_gapped_fraction = ratio(self.gapped_host_hits, self.evaluated_gapped_seeds);
        self.host_minimizer_fraction =
            ratio(self.minimizer_host_hits, self.evaluated_minimizer_windows);
        self.microbe_witness_fraction =
            ratio(self.microbial_witness_hits, self.evaluated_microbial_kmers);
    }

    pub fn merge(&mut self, other: &EvidenceFeatures) {
        self.evaluated_gapped_seeds += other.evaluated_gapped_seeds;
        self.gapped_host_hits += other.gapped_host_hits;
        self.evaluated_minimizer_windows += other.evaluated_minimizer_windows;
        self.minimizer_host_hits += other.minimizer_host_hits;
        self.evaluated_microbial_kmers += other.evaluated_microbial_kmers;
        self.microbial_witness_hits += other.microbial_witness_hits;
        self.mean_base_quality = weighted_mean(self.mean_base_quality, other.mean_base_quality);
        self.update_derived();
    }

    /// This is the fused extraction pass. The record is parsed once by the
    /// caller, and all evidence sources operate on the same in-memory bases.
    pub fn extract_fused(
        record: &FastqRecord,
        gapped: &GappedSeedFilter,
        minimizer: &MinimizerFilter,
        microbial: Option<&MicrobialWitnessFilter>,
    ) -> Self {
        let mut features = Self::default();
        gapped.add_evidence(record, &mut features);
        minimizer.add_evidence(record, &mut features);
        if let Some(microbial) = microbial {
            microbial.add_evidence(record, &mut features);
        }
        features.mean_base_quality = mean_quality(&record.qual);
        features.update_derived();
        features
    }
}

fn ratio(numerator: u32, denominator: u32) -> f64 {
    if denominator == 0 {
        0.0
    } else {
        numerator as f64 / denominator as f64
    }
}

fn weighted_mean(left: f64, right: f64) -> f64 {
    if left == 0.0 {
        right
    } else if right == 0.0 {
        left
    } else {
        (left + right) / 2.0
    }
}

fn mean_quality(quality: &[u8]) -> f64 {
    if quality.is_empty() {
        return 0.0;
    }
    let sum: u32 = quality
        .iter()
        .map(|value| value.saturating_sub(33) as u32)
        .sum();
    sum as f64 / quality.len() as f64
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::fastq::FastqRecord;

    #[test]
    fn fused_features_match_individual_sources() {
        let record = FastqRecord {
            header: "@fused".into(),
            seq: b"ACGTACGTACGTACGT".to_vec(),
            qual: vec![b'I'; 16],
        };
        let gapped = GappedSeedFilter::empty(Vec::new());
        let minimizer = MinimizerFilter::empty(5, 10);
        let fused = EvidenceFeatures::extract_fused(&record, &gapped, &minimizer, None);

        let mut individual = EvidenceFeatures::default();
        gapped.add_evidence(&record, &mut individual);
        minimizer.add_evidence(&record, &mut individual);
        individual.update_derived();

        assert_eq!(
            fused.evaluated_gapped_seeds,
            individual.evaluated_gapped_seeds
        );
        assert_eq!(
            fused.evaluated_minimizer_windows,
            individual.evaluated_minimizer_windows
        );
    }

    #[test]
    fn mean_quality_uses_phred_offset_33() {
        let record = FastqRecord {
            header: "@q".into(),
            seq: b"ACGT".to_vec(),
            qual: vec![b'I'; 4],
        };
        let gapped = GappedSeedFilter::empty(Vec::new());
        let minimizer = MinimizerFilter::empty(3, 3);
        let features = EvidenceFeatures::extract_fused(&record, &gapped, &minimizer, None);
        assert_eq!(features.mean_base_quality, 40.0);
    }
}
