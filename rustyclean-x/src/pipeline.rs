use anyhow::{anyhow, Result};

use crate::classify::{classify, Decision};
use crate::cli::{Args, Mode};
use crate::config::DecisionConfig;
use crate::config::DecisionMode;
use crate::evidence::gapped::GappedSeedFilter;
use crate::evidence::microbial::MicrobialWitnessFilter;
use crate::evidence::minimizer::MinimizerFilter;
use crate::fastq::{FastqReader, FastqWriter};
use crate::report::ReportWriter;

pub fn run(args: Result<Args>) -> Result<()> {
    let args = args?;

    // Load indexes based on mode
    let gapped = if args.mode != Mode::Deacon {
        Some(GappedSeedFilter::from_hash_file(
            args.gapped_index
                .as_ref()
                .ok_or_else(|| anyhow!("gapped index required"))?,
        )?)
    } else {
        None
    };

    let minimizer = if args.mode != Mode::Cleanifier {
        Some(MinimizerFilter::from_hash_file(
            args.minimizer_index
                .as_ref()
                .ok_or_else(|| anyhow!("minimizer index required"))?,
            21,
            41,
        )?)
    } else {
        None
    };

    let microbial = match &args.microbial_index {
        Some(path) => Some(MicrobialWitnessFilter::from_hash_file(path, 21)?),
        None => None,
    };

    let config = build_config(&args);

    let mut reader = FastqReader::from_path(&args.r1)?;
    let mut mate = match &args.r2 {
        Some(path) => Some(FastqReader::from_path(path)?),
        None => None,
    };

    let keep_path = format!("{}.keep.fastq", args.output_prefix);
    let remove_path = format!("{}.remove.fastq", args.output_prefix);
    let boundary_path = args
        .boundary_output
        .clone()
        .unwrap_or_else(|| format!("{}.boundary.fastq", args.output_prefix));
    let mut keep = FastqWriter::from_path(&keep_path)?;
    let mut remove = FastqWriter::from_path(&remove_path)?;
    let mut boundary = FastqWriter::from_path(&boundary_path)?;
    let mut report = ReportWriter::from_path(&args.report)?;

    let mut r2_exhausted = false;
    loop {
        let r1 = reader.next_record()?;
        let r2 = match mate.as_mut() {
            Some(reader) => {
                let record = reader.next_record()?;
                if record.is_none() {
                    r2_exhausted = true;
                }
                record
            }
            None => None,
        };
        if r2_exhausted && r1.is_some() {
            return Err(anyhow!("R1 has more records than R2"));
        }

        let (r1, r2) = match (r1, r2) {
            (Some(r1), r2) => (r1, r2),
            (None, _) => break,
        };

        let gapped_ref = gapped.as_ref();
        let minimizer_ref = minimizer.as_ref();

        // Build a temporary GappedSeedFilter / MinimizerFilter stub for modes that
        // don't use one. Since `classify` requires non-optional refs, we create
        // empty stubs for unused indexes.
        let empty_gapped = GappedSeedFilter::empty(vec![]);
        let empty_minimizer = MinimizerFilter::empty(21, 41);

        let g = gapped_ref.unwrap_or(&empty_gapped);
        let m = minimizer_ref.unwrap_or(&empty_minimizer);

        let evidence = classify(
            &r1,
            r2.as_ref(),
            g,
            m,
            microbial.as_ref(),
            &config,
        );

        report.write(&r1.id(), &evidence)?;

        match evidence.decision {
            Decision::Keep => {
                keep.write(&r1)?;
                if let Some(r2) = &r2 {
                    keep.write(r2)?;
                }
            }
            Decision::Remove => {
                remove.write(&r1)?;
                if let Some(r2) = &r2 {
                    remove.write(r2)?;
                }
            }
            Decision::Boundary => {
                boundary.write(&r1)?;
                if let Some(r2) = &r2 {
                    boundary.write(r2)?;
                }
            }
        }
    }

    keep.flush()?;
    remove.flush()?;
    boundary.flush()?;


    eprintln!(
        "RustyClean-X [mode={:?}] done. output_prefix={}",
        args.mode,
        args.output_prefix
    );
    Ok(())
}

fn build_config(args: &Args) -> DecisionConfig {
    let mut config = DecisionConfig::for_profile(args.profile);
    config.host_evidence_rule = match args.host_evidence_rule {
        crate::cli::HostEvidenceRuleArg::Both => crate::config::HostEvidenceRule::Both,
        crate::cli::HostEvidenceRuleArg::Either => crate::config::HostEvidenceRule::Either,
    };
    config.decision_mode = match args.decision_mode {
        crate::cli::DecisionModeArg::Fused => DecisionMode::Fused,
        crate::cli::DecisionModeArg::Hard => DecisionMode::Hard,
    };
    config.host_gapped_weight = args.host_gapped_weight.max(0.0);
    config.host_minimizer_weight = args.host_minimizer_weight.max(0.0);
    config.host_score_remove = args.host_score_remove.clamp(0.0, 1.0);
    config.host_score_confident = args.host_score_confident.clamp(0.0, 1.0);
    config.microbe_score_rescue = args.microbe_score_rescue.max(0.0);

    // Mode-specific threshold tuning
    match args.mode {
        Mode::Deacon => {
            config.host_gapped_weight = 0.0;
            config.host_minimizer_weight = 1.0;
            if config.host_score_remove > 0.30 {
                config.host_score_remove = 0.30;
            }
        }
        Mode::Cleanifier => {
            config.host_gapped_weight = 1.0;
            config.host_minimizer_weight = 0.0;
            if config.host_score_remove > 0.28 {
                config.host_score_remove = 0.28;
            }
        }
        Mode::RustyCleanX => {}
    }

    if config.host_score_confident < config.host_score_remove {
        config.host_score_confident = config.host_score_remove;
    }

    config
}
