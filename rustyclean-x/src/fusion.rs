use serde::Serialize;

use crate::config::DecisionConfig;
use crate::evidence::EvidenceFeatures;

/// Continuous evidence derived from the shared one-pass feature extraction.
///
/// Scores are dimensionless.  A value of `1.0` means "at the configured
/// decision threshold"; values above/below that indicate stronger/weaker
/// evidence.  The host score is a weighted fusion, not a hard OR/AND vote.
#[derive(Debug, Clone, Copy, PartialEq, Serialize)]
pub struct FusedScores {
    pub host_score: f64,
    pub microbe_score: f64,
    pub gapped_component: f64,
    pub minimizer_component: f64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub struct ResolvedDecision {
    pub remove: bool,
    pub rescue_keep: bool,
    pub boundary: bool,
}

fn bounded_ratio(value: f64, threshold: f64) -> f64 {
    if !threshold.is_finite() || threshold <= 0.0 || !value.is_finite() {
        return 0.0;
    }
    (value / threshold).clamp(0.0, 1.0)
}

/// Convert raw dual-index and microbial-witness features into bounded scores.
pub fn score_features(features: &EvidenceFeatures, config: &DecisionConfig) -> FusedScores {
    let gapped_component =
        bounded_ratio(features.host_gapped_fraction, config.host_gapped_fraction);
    let minimizer_component = bounded_ratio(
        f64::from(features.minimizer_host_hits),
        f64::from(config.host_minimizer_hits),
    );
    let microbe_score = bounded_ratio(
        features.microbe_witness_fraction,
        config.microbe_witness_fraction,
    );

    let gapped_weight = config.host_gapped_weight.max(0.0);
    let minimizer_weight = config.host_minimizer_weight.max(0.0);
    let total_weight = gapped_weight + minimizer_weight;
    let host_score = if total_weight > 0.0 {
        ((gapped_weight * gapped_component + minimizer_weight * minimizer_component) / total_weight)
            .clamp(0.0, 1.0)
    } else {
        0.0
    };

    FusedScores {
        host_score,
        microbe_score,
        gapped_component,
        minimizer_component,
    }
}

/// Resolve fused scores and mate disagreement into the final action.
///
/// The resolver is intentionally conservative:
/// * concordant strong host evidence removes a fragment;
/// * strong microbial witness can rescue a moderate host signal;
/// * moderate/conflicting evidence is routed to `Boundary` rather than removed.
pub fn resolve_scores(
    scores: &FusedScores,
    mate_host_conflict: bool,
    config: &DecisionConfig,
) -> (&'static str, ResolvedDecision) {
    let host_remove = scores.host_score >= config.host_score_remove;
    let host_confident = scores.host_score >= config.host_score_confident;
    let microbe_rescue = scores.microbe_score >= config.microbe_score_rescue && !host_confident;
    let rescue_keep = microbe_rescue && !mate_host_conflict;
    let boundary = !host_remove && !rescue_keep || mate_host_conflict;

    let reason = if host_remove && !microbe_rescue {
        "fused host evidence"
    } else if microbe_rescue {
        "microbial witness rescue"
    } else if mate_host_conflict {
        "discordant mate host evidence"
    } else {
        "boundary evidence sent to resolver"
    };

    (
        reason,
        ResolvedDecision {
            remove: host_remove,
            rescue_keep,
            boundary,
        },
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn config() -> DecisionConfig {
        DecisionConfig::for_profile(crate::cli::Profile::Microbiome)
    }

    fn features(gapped: f64, minimizer: f64, microbe: f64) -> EvidenceFeatures {
        EvidenceFeatures {
            host_gapped_fraction: gapped,
            minimizer_host_hits: minimizer as u32,
            microbe_witness_fraction: microbe,
            ..Default::default()
        }
    }

    #[test]
    fn concordant_dual_evidence_is_required_for_default_removal() {
        let cfg = config();
        let one_source = score_features(&features(1.0, 0.0, 0.0), &cfg);
        assert!((one_source.host_score - 0.5).abs() < 1e-12);

        let both = score_features(&features(1.0, 100.0, 0.0), &cfg);
        assert!((both.host_score - 1.0).abs() < 1e-12);
        assert!(both.host_score >= cfg.host_score_remove);
    }

    #[test]
    fn strong_microbial_witness_can_rescue_moderate_host_signal() {
        let cfg = config();
        let scores = score_features(&features(0.14, 1.0, 1.0), &cfg);
        let (reason, resolved) = resolve_scores(&scores, false, &cfg);
        let remove = resolved.remove;
        let rescue = resolved.rescue_keep;
        let boundary = resolved.boundary;
        assert_eq!(reason, "microbial witness rescue");
        assert!(!remove);
        assert!(rescue);
        assert!(!boundary);
    }

    #[test]
    fn confident_fused_host_evidence_overrides_witness() {
        let cfg = config();
        let scores = score_features(&features(1.0, 100.0, 1.0), &cfg);
        let (reason, resolved) = resolve_scores(&scores, false, &cfg);
        let remove = resolved.remove;
        let rescue = resolved.rescue_keep;
        let _boundary = resolved.boundary;
        assert_eq!(reason, "fused host evidence");
        assert!(remove);
        assert!(!rescue);
    }
}
