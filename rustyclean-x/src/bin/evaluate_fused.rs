use anyhow::{anyhow, Result};
use clap::Parser;
use flate2::read::MultiGzDecoder;
use flate2::write::GzEncoder;
use flate2::Compression;
use rustyclean_x::config::DecisionConfig;
use rustyclean_x::evidence::gapped::GappedSeedFilter;
use rustyclean_x::evidence::microbial::MicrobialWitnessFilter;
use rustyclean_x::evidence::minimizer::MinimizerFilter;
use rustyclean_x::fastq::FastqReader;
use rustyclean_x::filter::{classify, Decision};
use std::collections::HashMap;
use std::fs::File;
use std::io::{BufRead, BufReader, BufWriter, Write};
use std::path::{Path, PathBuf};
use std::time::Instant;

#[derive(Parser, Debug)]
#[command(about = "Evaluate RustyClean-X fused decisions against ordered per-read truth")]
struct Args {
    #[arg(long)]
    dataset: String,
    #[arg(long)]
    r1: PathBuf,
    #[arg(long)]
    truth: PathBuf,
    #[arg(long)]
    gapped_index: PathBuf,
    #[arg(long)]
    minimizer_index: PathBuf,
    #[arg(long)]
    witness_index: PathBuf,
    #[arg(long)]
    outdir: PathBuf,
    #[arg(long, default_value_t = 0.07)]
    host_gapped_fraction: f64,
    #[arg(long, default_value_t = 1)]
    host_minimizer_hits: u32,
    #[arg(long, default_value_t = 0.30)]
    microbe_witness_fraction: f64,
    #[arg(long, default_value_t = 0.60)]
    host_score_remove: f64,
    #[arg(long, default_value_t = 0.80)]
    host_score_confident: f64,
    #[arg(long, default_value_t = 1.00)]
    microbe_score_rescue: f64,
    #[arg(long, default_value_t = 0.5)]
    host_gapped_weight: f64,
    #[arg(long, default_value_t = 0.5)]
    host_minimizer_weight: f64,
}

#[derive(Default)]
struct Counts {
    records: u64,
    host_total: u64,
    microbe_total: u64,
    host_removed: u64,
    microbe_removed: u64,
    boundary_true_host: u64,
    boundary_true_microbe: u64,
}

fn truth_label<'a>(line: &'a str, path: &Path) -> Result<(&'a str, &'a str)> {
    let (id, label) = line
        .trim_end_matches(['\r', '\n'])
        .split_once('\t')
        .ok_or_else(|| anyhow!("bad truth line in {}: {line:?}", path.display()))?;
    Ok((id, label))
}

fn retained(decision: Decision) -> bool {
    decision != Decision::Remove
}

fn open_fastq(path: &Path) -> Result<FastqReader<Box<dyn BufRead>>> {
    let file = File::open(path)?;
    let reader: Box<dyn BufRead> =
        if path.extension().and_then(|value| value.to_str()) == Some("gz") {
            Box::new(BufReader::with_capacity(
                1024 * 1024,
                MultiGzDecoder::new(file),
            ))
        } else {
            Box::new(BufReader::with_capacity(1024 * 1024, file))
        };
    Ok(FastqReader::from_reader(reader))
}

fn main() -> Result<()> {
    let args = Args::parse();
    if !args.r1.is_file() {
        return Err(anyhow!("FASTQ does not exist: {}", args.r1.display()));
    }
    std::fs::create_dir_all(&args.outdir)?;
    let report_path = args.outdir.join("per_read_report.tsv.gz");
    let metrics_path = args.outdir.join("metrics.tsv");
    let histogram_path = args.outdir.join("score_histogram.tsv");

    let gapped = GappedSeedFilter::from_hash_file(&args.gapped_index)?;
    let minimizer = MinimizerFilter::from_hash_file(&args.minimizer_index, 21, 41)?;
    let witness = MicrobialWitnessFilter::from_hash_file(&args.witness_index, 21)?;

    let mut config = DecisionConfig::for_profile(rustyclean_x::cli::Profile::Microbiome);
    config.decision_mode = rustyclean_x::config::DecisionMode::Fused;
    config.host_gapped_fraction = args.host_gapped_fraction;
    config.host_minimizer_hits = args.host_minimizer_hits;
    config.microbe_witness_fraction = args.microbe_witness_fraction;
    config.host_gapped_weight = args.host_gapped_weight;
    config.host_minimizer_weight = args.host_minimizer_weight;
    config.host_score_remove = args.host_score_remove;
    config.host_score_confident = args.host_score_confident;
    config.microbe_score_rescue = args.microbe_score_rescue;

    let mut fastq = open_fastq(&args.r1)?;
    let truth_reader = BufReader::new(File::open(&args.truth)?);
    let mut truth_lines = truth_reader.lines();
    let report_file = File::create(&report_path)?;
    let report_encoder = GzEncoder::new(report_file, Compression::fast());
    let mut report = BufWriter::with_capacity(1024 * 1024, report_encoder);
    writeln!(
        report,
        "read_id\ttruth\tprediction\tretained\thost_gapped_fraction\tminimizer_host_hits\tmicrobe_witness_fraction\thost_score\tmicrobe_score\tgapped_component\tminimizer_component"
    )?;

    let mut counts = Counts::default();
    let mut histogram: HashMap<(u8, u8, bool), u64> = HashMap::new();
    let started = Instant::now();

    loop {
        let record = match fastq.next_record()? {
            Some(value) => value,
            None => break,
        };
        let truth_line = truth_lines
            .next()
            .ok_or_else(|| anyhow!("truth ended before FASTQ record {}", counts.records + 1))??;
        let (truth_id, truth_label) = truth_label(&truth_line, &args.truth)?;
        if truth_id != record.id() {
            return Err(anyhow!(
                "truth/FASTQ order mismatch at record {}: {} != {}",
                counts.records + 1,
                record.id(),
                truth_id
            ));
        }
        let is_host =
            truth_label.eq_ignore_ascii_case("host") || truth_label.eq_ignore_ascii_case("human");
        let evidence = classify(&record, None, &gapped, &minimizer, Some(&witness), &config);
        let removed = !retained(evidence.decision);

        counts.records += 1;
        if is_host {
            counts.host_total += 1;
            if removed {
                counts.host_removed += 1;
            }
            if evidence.decision == Decision::Boundary {
                counts.boundary_true_host += 1;
            }
        } else {
            counts.microbe_total += 1;
            if removed {
                counts.microbe_removed += 1;
            }
            if evidence.decision == Decision::Boundary {
                counts.boundary_true_microbe += 1;
            }
        }

        let host_bin = (evidence.scores.host_score * 20.0).round().clamp(0.0, 20.0) as u8;
        let microbe_bin = (evidence.scores.microbe_score * 20.0)
            .round()
            .clamp(0.0, 20.0) as u8;
        *histogram
            .entry((host_bin, microbe_bin, is_host))
            .or_insert(0) += 1;

        writeln!(
            report,
            "{}\t{}\t{:?}\t{}\t{:.9}\t{}\t{:.9}\t{:.9}\t{:.9}\t{:.9}\t{:.9}",
            record.id(),
            truth_label,
            evidence.decision,
            u8::from(!removed),
            evidence.features.host_gapped_fraction,
            evidence.features.minimizer_host_hits,
            evidence.features.microbe_witness_fraction,
            evidence.scores.host_score,
            evidence.scores.microbe_score,
            evidence.scores.gapped_component,
            evidence.scores.minimizer_component,
        )?;
        if counts.records % 1_000_000 == 0 {
            report.flush()?;
            let elapsed = started.elapsed().as_secs_f64();
            eprintln!(
                "processed={} elapsed={:.2}s rate={:.0} reads/s",
                counts.records,
                elapsed,
                counts.records as f64 / elapsed
            );
        }
    }
    if truth_lines.next().is_some() {
        return Err(anyhow!("truth has more records than FASTQ"));
    }
    report.flush()?;

    let host_retained = counts.host_total - counts.host_removed;
    let microbe_retained = counts.microbe_total - counts.microbe_removed;
    let retained_total = host_retained + microbe_retained;
    let precision = if retained_total > 0 {
        microbe_retained as f64 / retained_total as f64
    } else {
        1.0
    };
    let recall = if counts.microbe_total > 0 {
        microbe_retained as f64 / counts.microbe_total as f64
    } else {
        1.0
    };
    let f1 = if precision + recall > 0.0 {
        2.0 * precision * recall / (precision + recall)
    } else {
        0.0
    };

    let mut metrics = File::create(&metrics_path)?;
    writeln!(
        metrics,
        "dataset\trecords\thost_total\tmicrobe_total\thost_removed\thost_retained\thost_retention_pct\tmicrobe_removed\tmicrobe_retained\tmicrobial_loss_pct\tboundary_true_host\tboundary_true_microbe\tretained_total\thost_output_fraction_pct\tprecision\trecall\tf1\tseconds"
    )?;
    writeln!(
        metrics,
        "{}\t{}\t{}\t{}\t{}\t{}\t{:.9}\t{}\t{}\t{:.9}\t{}\t{}\t{}\t{:.9}\t{:.12}\t{:.12}\t{:.12}\t{:.3}",
        args.dataset,
        counts.records,
        counts.host_total,
        counts.microbe_total,
        counts.host_removed,
        host_retained,
        percentage(host_retained, counts.host_total),
        counts.microbe_removed,
        microbe_retained,
        percentage(counts.microbe_removed, counts.microbe_total),
        counts.boundary_true_host,
        counts.boundary_true_microbe,
        retained_total,
        percentage(host_retained, retained_total),
        precision,
        recall,
        f1,
        started.elapsed().as_secs_f64()
    )?;

    let mut histogram_file = BufWriter::new(File::create(&histogram_path)?);
    writeln!(
        histogram_file,
        "host_score_bin\tmicrobe_score_bin\ttruth_host\ttruth_microbe"
    )?;
    let mut keys: Vec<_> = histogram.into_iter().collect();
    keys.sort_unstable();
    for ((host_bin, microbe_bin, is_host), count) in keys {
        if is_host {
            writeln!(histogram_file, "{host_bin}\t{microbe_bin}\t{count}\t0")?;
        } else {
            writeln!(histogram_file, "{host_bin}\t{microbe_bin}\t0\t{count}")?;
        }
    }

    writeln!(
        std::io::stderr(),
        "completed records={} host_retention={:.6}% microbial_loss={:.6}% F1={:.9}",
        counts.records,
        percentage(host_retained, counts.host_total),
        percentage(counts.microbe_removed, counts.microbe_total),
        f1
    )?;
    Ok(())
}

fn percentage(numerator: u64, denominator: u64) -> f64 {
    if denominator > 0 {
        100.0 * numerator as f64 / denominator as f64
    } else {
        0.0
    }
}
