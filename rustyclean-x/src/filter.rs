use serde::Serialize;

use crate::config::{DecisionConfig, DecisionMode};
use crate::evidence::gapped::GappedSeedFilter;
use crate::evidence::microbial::MicrobialWitnessFilter;
use crate::evidence::minimizer::MinimizerFilter;
use crate::evidence::EvidenceFeatures;
use crate::fastq::FastqRecord;
use crate::fusion::ResolvedDecision;
use crate::fusion::{resolve_scores, score_features, FusedScores};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub enum Decision {
    Keep,
    Remove,
    Boundary,
}

#[derive(Debug, Clone)]
pub struct ReadBundle {
    pub id: String,
    pub r1: FastqRecord,
    pub r2: Option<FastqRecord>,
}

#[derive(Debug, Clone, Serialize)]
pub struct Evidence {
    pub features: EvidenceFeatures,
    pub scores: FusedScores,
    pub decision: Decision,
    pub reason: &'static str,
}

/// Encode bases left-to-right into a 2-bit representation.
pub fn encode_bases(bases: &[u8]) -> Option<u64> {
    crate::sequence::encode_bases(bases)
}

fn hard_host_call(features: &EvidenceFeatures, config: &DecisionConfig) -> bool {
    let gapped_host = features.host_gapped_fraction >= config.host_gapped_fraction;
    let minimizer_host = features.minimizer_host_hits >= config.host_minimizer_hits;
    match config.host_evidence_rule {
        crate::config::HostEvidenceRule::Both => gapped_host && minimizer_host,
        crate::config::HostEvidenceRule::Either => gapped_host || minimizer_host,
    }
}

fn hard_decision(
    r1_host: bool,
    r2_host: bool,
    r1_microbe: bool,
    r2_microbe: bool,
    config: &DecisionConfig,
) -> (&'static str, Decision) {
    if r1_host || r2_host {
        let conflicting =
            (r1_host && (r1_microbe || r2_microbe)) || (r2_host && (r1_microbe || r2_microbe));
        if conflicting && !config.privacy_pair_removal {
            ("conflicting host/microbe evidence", Decision::Boundary)
        } else {
            ("confident host", Decision::Remove)
        }
    } else if r1_microbe || r2_microbe {
        if config.microbe_pair_rescue {
            ("microbial witness rescue", Decision::Keep)
        } else {
            ("microbial evidence without rescue", Decision::Boundary)
        }
    } else {
        ("ambiguous boundary read", Decision::Boundary)
    }
}

/// Classify a fragment with a single shared feature-extraction pass.
///
/// Both mate records are already parsed before this function is called.  The
/// default backend is score fusion; the hard OR/AND classifier remains
/// available as an ablation backend.
pub fn classify(
    r1: &FastqRecord,
    r2: Option<&FastqRecord>,
    gapped: &GappedSeedFilter,
    minimizer: &MinimizerFilter,
    microbial: Option<&MicrobialWitnessFilter>,
    config: &DecisionConfig,
) -> Evidence {
    let r1_features = EvidenceFeatures::extract_fused(r1, gapped, minimizer, microbial);
    let r2_features =
        r2.map(|record| EvidenceFeatures::extract_fused(record, gapped, minimizer, microbial));
    let mut features = r1_features.clone();
    if let Some(mate) = r2_features.as_ref() {
        features.merge(mate);
    }

    if config.decision_mode == DecisionMode::Hard {
        let r1_host = hard_host_call(&r1_features, config);
        let r2_host = r2_features
            .as_ref()
            .map(|features| hard_host_call(features, config))
            .unwrap_or(false);
        let r1_microbe = r1_features.microbe_witness_fraction >= config.microbe_witness_fraction;
        let r2_microbe = r2_features
            .as_ref()
            .map(|features| features.microbe_witness_fraction >= config.microbe_witness_fraction)
            .unwrap_or(false);
        let (reason, decision) = hard_decision(r1_host, r2_host, r1_microbe, r2_microbe, config);
        let scores = score_features(&features, config);
        return Evidence {
            features,
            scores,
            decision,
            reason,
        };
    }

    let scores = score_features(&features, config);
    let r1_host = hard_host_call(&r1_features, config);
    let r2_host = r2_features
        .as_ref()
        .map(|features| hard_host_call(features, config))
        .unwrap_or(false);
    let mate_host_conflict = r2_features.is_some() && r1_host != r2_host;
    let (reason, resolved) = resolve_scores(&scores, mate_host_conflict, config);
    let ResolvedDecision {
        remove,
        rescue_keep: microbe_rescued,
        ..
    } = resolved;

    let decision = if remove {
        Decision::Remove
    } else if microbe_rescued {
        Decision::Keep
    } else {
        Decision::Boundary
    };

    Evidence {
        features,
        scores,
        decision,
        reason,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::evidence::gapped::SeedMask;
    use crate::sequence::{canonical_kmer, encode_bases, wyhash};

    fn host_filters(sequence: &[u8]) -> (GappedSeedFilter, MinimizerFilter) {
        let mask = SeedMask::new(0b1111_1111_1111_1111_1111, 21).unwrap();
        let mut hashes = Vec::new();
        for start in 0..=(sequence.len() - mask.length) {
            if let Some((hash, _)) = mask.hash_sequence(sequence, start) {
                hashes.push(hash);
            }
        }
        let gapped = GappedSeedFilter::with_hashes(hashes.into_iter().collect(), vec![mask]);

        let k = 21;
        let mut minimizer_hashes = Vec::new();
        for start in 0..=(sequence.len() - k) {
            let kmer = encode_bases(&sequence[start..start + k]).unwrap();
            minimizer_hashes.push(wyhash(canonical_kmer(kmer, k)));
        }
        let minimizer = MinimizerFilter::with_hashes(
            minimizer_hashes.into_iter().collect(),
            k,
            25.min(sequence.len()),
        );
        (gapped, minimizer)
    }

    #[test]
    fn helper_gapped_index_hits_host() {
        let host = b"ACGTTACGATCGATCGATCGATCGATCGACGTTACGATCGATCGATCGATCGATCG";
        let (gapped, _) = host_filters(host);
        let read = record("@host", host);
        let mut features = EvidenceFeatures::default();
        gapped.add_evidence(&read, &mut features);
        eprintln!("gapped={:?}", features.gapped_host_hits);
        assert!(features.gapped_host_hits > 0);
    }

    fn microbial_filter(sequence: &[u8]) -> MicrobialWitnessFilter {
        let k = 21;
        let mut hashes = Vec::new();
        for start in 0..=(sequence.len() - k) {
            let kmer = encode_bases(&sequence[start..start + k]).unwrap();
            hashes.push(wyhash(canonical_kmer(kmer, k)));
        }
        MicrobialWitnessFilter::with_hashes(hashes.into_iter().collect(), k)
    }

    fn record(header: &str, sequence: &[u8]) -> FastqRecord {
        FastqRecord {
            header: header.to_string(),
            seq: sequence.to_vec(),
            qual: vec![b'I'; sequence.len()],
        }
    }

    #[test]
    fn fused_concordant_host_is_removed() {
        let host = b"ACGTTACGATCGATCGATCGATCGATCGACGTTACGATCGATCGATCGATCGATCG";
        let (gapped, minimizer) = host_filters(host);
        let read = record("@host", host);
        let config = DecisionConfig::for_profile(crate::cli::Profile::Microbiome);
        let evidence = classify(&read, None, &gapped, &minimizer, None, &config);
        assert_eq!(evidence.decision, Decision::Remove);
        assert_eq!(evidence.reason, "fused host evidence");
        assert!(evidence.scores.host_score >= config.host_score_remove);
    }

    #[test]
    fn one_dual_index_source_alone_goes_to_boundary() {
        let host = b"ACGTTACGATCGATCGATCGATCGATCGACGTTACGATCGATCGATCGATCGATCG";
        let (_, minimizer) = host_filters(host);
        let mask = SeedMask::new(0b1111_1111_1111_1111_1111, 21).unwrap();
        let gapped = GappedSeedFilter::with_hashes(Default::default(), vec![mask]);
        let read = record("@one-source", host);
        let config = DecisionConfig::for_profile(crate::cli::Profile::Microbiome);
        let evidence = classify(&read, None, &gapped, &minimizer, None, &config);
        assert_eq!(evidence.decision, Decision::Boundary);
        assert!((evidence.scores.host_score - 0.5).abs() < 1e-12);
    }

    #[test]
    fn microbial_witness_rescues_moderate_host_signal() {
        let host = b"ACGTTACGATCGATCGATCGATCGATCGACGTTACGATCGATCGATCGATCGATCG";
        let _microbe = b"TTTTACCCGGGTTTTACCCGGGTTTTACCCGGGTTTTACCCGGGTTTTACCC";
        let (_, minimizer) = host_filters(host);
        let mask = SeedMask::new(0b1111_1111_1111_1111_1111, 21).unwrap();
        let gapped = GappedSeedFilter::with_hashes(Default::default(), vec![mask]);
        let witness = microbial_filter(host);
        let read = record("@microbial-like-host", host);
        let config = DecisionConfig::for_profile(crate::cli::Profile::Microbiome);
        let evidence = classify(&read, None, &gapped, &minimizer, Some(&witness), &config);
        assert_eq!(evidence.decision, Decision::Keep);
        assert_eq!(evidence.reason, "microbial witness rescue");
    }

    #[test]
    fn microbial_read_without_host_evidence_is_kept() {
        let microbe = b"TTTTACCCGGGTTTTACCCGGGTTTTACCCGGGTTTTACCCGGGTTTTACCC";
        let (gapped, minimizer) =
            host_filters(b"ACGTTACGATCGATCGATCGATCGATCGACGTTACGATCGATCGATCGATCGATCG");
        let witness = microbial_filter(microbe);
        let read = record("@microbe", microbe);
        let config = DecisionConfig::for_profile(crate::cli::Profile::Microbiome);
        let evidence = classify(&read, None, &gapped, &minimizer, Some(&witness), &config);
        assert_eq!(evidence.decision, Decision::Keep);
    }

    #[test]
    fn evidence_free_read_remains_boundary() {
        let (gapped, minimizer) =
            host_filters(b"ACGTTACGATCGATCGATCGATCGATCGACGTTACGATCGATCGATCGATCGATCG");
        let read = record("@boundary", b"NNNNNNNNNNNNNNNNNNNNNNNNNNNNNN");
        let config = DecisionConfig::for_profile(crate::cli::Profile::Microbiome);
        let evidence = classify(&read, None, &gapped, &minimizer, None, &config);
        assert_eq!(evidence.decision, Decision::Boundary);
    }

    #[test]
    fn hard_mode_retains_original_both_rule() {
        let host = b"ACGTTACGATCGATCGATCGATCGATCGACGTTACGATCGATCGATCGATCGATCG";
        let (_, minimizer) = host_filters(host);
        let mask = SeedMask::new(0b1111_1111_1111_1111_1111, 21).unwrap();
        let gapped = GappedSeedFilter::with_hashes(Default::default(), vec![mask]);
        let read = record("@one-source", host);
        let mut config = DecisionConfig::for_profile(crate::cli::Profile::Microbiome);
        config.decision_mode = DecisionMode::Hard;
        let evidence = classify(&read, None, &gapped, &minimizer, None, &config);
        assert_eq!(evidence.decision, Decision::Boundary);
    }
}
