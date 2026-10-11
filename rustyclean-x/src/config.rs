use crate::cli::Profile;

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum DecisionMode {
    /// Default: fuse minimizer and gapped-seed evidence, then apply the
    /// microbial-witness and boundary resolver.
    Fused,
    /// Ablation mode: retain the original hard OR/AND decisions.
    Hard,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HostEvidenceRule {
    /// Default: both gapped-seed and minimizer evidence must call host.
    Both,
    /// Fast mode: either host evidence source may call host.
    Either,
}

#[derive(Debug, Clone)]
pub struct DecisionConfig {
    /// Minimum fraction of evaluated gapped seeds that hit the host index.
    pub host_gapped_fraction: f64,
    /// Minimum number of host minimizer hits for a confident host call.
    pub host_minimizer_hits: u32,
    /// Whether host removal requires both evidence sources (default) or either.
    pub host_evidence_rule: HostEvidenceRule,
    /// Decision backend. `Fused` is the production default; `Hard` is kept
    /// for ablations and compatibility with the draft classifier.
    pub decision_mode: DecisionMode,
    /// Relative contribution of Cleanifier-style gapped evidence.
    pub host_gapped_weight: f64,
    /// Relative contribution of Deacon-style minimizer evidence.
    pub host_minimizer_weight: f64,
    /// Fused score required to remove a fragment.
    pub host_score_remove: f64,
    /// Score above which microbial witness cannot rescue the fragment.
    pub host_score_confident: f64,
    /// Normalized microbial witness score required for rescue.
    pub microbe_score_rescue: f64,
    /// Minimum fraction of evaluated exact k-mers/microbe witnesses supporting microbe.
    pub microbe_witness_fraction: f64,
    /// If true, any confidently host mate removes the whole fragment.
    pub privacy_pair_removal: bool,
    /// If true, any confidently microbe mate rescues the whole fragment.
    pub microbe_pair_rescue: bool,
}

impl DecisionConfig {
    pub fn for_profile(profile: Profile) -> Self {
        match profile {
            Profile::Privacy => Self {
                host_gapped_fraction: 0.18,
                host_minimizer_hits: 2,
                host_evidence_rule: HostEvidenceRule::Both,
                decision_mode: DecisionMode::Fused,
                host_gapped_weight: 0.5,
                host_minimizer_weight: 0.5,
                host_score_remove: 0.60,
                host_score_confident: 0.80,
                microbe_score_rescue: 1.00,
                microbe_witness_fraction: 0.65,
                privacy_pair_removal: true,
                microbe_pair_rescue: false,
            },
            Profile::Microbiome => Self {
                host_gapped_fraction: 0.28,
                host_minimizer_hits: 3,
                host_evidence_rule: HostEvidenceRule::Both,
                decision_mode: DecisionMode::Fused,
                host_gapped_weight: 0.5,
                host_minimizer_weight: 0.5,
                host_score_remove: 0.60,
                host_score_confident: 0.80,
                microbe_score_rescue: 1.00,
                microbe_witness_fraction: 0.45,
                privacy_pair_removal: true,
                microbe_pair_rescue: true,
            },
            Profile::Mag => Self {
                host_gapped_fraction: 0.35,
                host_minimizer_hits: 4,
                host_evidence_rule: HostEvidenceRule::Both,
                decision_mode: DecisionMode::Fused,
                host_gapped_weight: 0.5,
                host_minimizer_weight: 0.5,
                host_score_remove: 0.60,
                host_score_confident: 0.80,
                microbe_score_rescue: 1.00,
                microbe_witness_fraction: 0.55,
                privacy_pair_removal: true,
                microbe_pair_rescue: true,
            },
        }
    }
}
