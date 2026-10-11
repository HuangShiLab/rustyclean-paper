use anyhow::{anyhow, Result};
use clap::Parser;
use flate2::read::MultiGzDecoder;
use flate2::write::GzEncoder;
use flate2::Compression;
use rustyclean_x::config::DecisionConfig;
use rustyclean_x::evidence::gapped::GappedSeedFilter;
use rustyclean_x::evidence::microbial::MicrobialWitnessFilter;
use rustyclean_x::fastq::FastqReader;
use rustyclean_x::filter::Decision;
use rustyclean_x::fusion::score_features;
use std::collections::{HashMap, HashSet};
use std::fs::File;
use std::io::{BufRead, BufReader, BufWriter, Write};
use std::path::{Path, PathBuf};
use std::time::Instant;

#[derive(Parser, Debug)]
#[command(about = "Fuse Deacon/Cleanifier production-query decisions with microbial witness")]
struct Args {
    #[arg(long)]
    dataset: String,
    #[arg(long)]
    r1: PathBuf,
    #[arg(long)]
    truth: Option<PathBuf>,
    #[arg(long)]
    deacon_kept: PathBuf,
    #[arg(long)]
    cleanifier_kept: PathBuf,
    #[arg(long)]
    witness_index: PathBuf,
    #[arg(long)]
    outdir: PathBuf,
    #[arg(long, default_value_t = 0.30)]
    microbe_witness_fraction: f64,
    #[arg(long, default_value_t = 0.80)]
    microbe_score_rescue: f64,
    #[arg(long, default_value_t = 0.50)]
    deacon_weight: f64,
    #[arg(long, default_value_t = 0.50)]
    cleanifier_weight: f64,
}

fn open_fastq(path: &Path) -> Result<Box<dyn BufRead>> {
    let file = File::open(path)?;
    if path.extension().and_then(|value| value.to_str()) == Some("gz") {
        Ok(Box::new(BufReader::with_capacity(
            1024 * 1024,
            MultiGzDecoder::new(file),
        )))
    } else {
        Ok(Box::new(BufReader::with_capacity(1024 * 1024, file)))
    }
}

fn open_fastq_reader(path: &Path) -> Result<FastqReader<Box<dyn BufRead>>> {
    Ok(FastqReader::from_reader(open_fastq(path)?))
}

fn import_kept_ids(path: &Path, label: &str) -> Result<HashSet<String>> {
    let reader = open_fastq(path)?;
    let mut reader = BufReader::new(reader);
    let mut ids = HashSet::new();
    let mut header = String::new();
    let mut line_number = 0_u64;
    loop {
        header.clear();
        if reader.read_line(&mut header)? == 0 {
            break;
        }
        line_number += 1;
        if line_number % 4 != 1 {
            continue;
        }
        if !header.starts_with('@') {
            return Err(anyhow!(
                "invalid {label} FASTQ header at line {line_number}"
            ));
        }
        let id = header[1..]
            .split_whitespace()
            .next()
            .ok_or_else(|| anyhow!("empty {label} FASTQ ID at line {line_number}"))?;
        ids.insert(id.to_string());
    }
    Ok(ids)
}

fn open_truth(path: &Path) -> Result<BufReader<File>> {
    Ok(BufReader::new(File::open(path)?))
}

fn main() -> Result<()> {
    let args = Args::parse();
    std::fs::create_dir_all(&args.outdir)?;
    let started = Instant::now();

    eprintln!("importing Deacon production-query retained IDs");
    let deacon_keep = import_kept_ids(&args.deacon_kept, "Deacon")?;
    eprintln!("Deacon imported retained={}", deacon_keep.len());
    eprintln!("importing Cleanifier production-query retained IDs");
    let cleanifier_keep = import_kept_ids(&args.cleanifier_kept, "Cleanifier")?;
    eprintln!("Cleanifier imported retained={}", cleanifier_keep.len());

    let witness = MicrobialWitnessFilter::from_hash_file(&args.witness_index, 21)?;
    // Dummy host filters are required by the shared single-pass extractor.  No
    // host query is made through them in production-fusion mode.
    let empty_gapped = GappedSeedFilter::empty(Vec::new());
    let empty_minimizer = rustyclean_x::evidence::minimizer::MinimizerFilter::empty(21, 41);

    let mut config = DecisionConfig::for_profile(rustyclean_x::cli::Profile::Microbiome);
    config.decision_mode = rustyclean_x::config::DecisionMode::Fused;
    config.microbe_witness_fraction = args.microbe_witness_fraction;
    config.microbe_score_rescue = args.microbe_score_rescue;

    let total_weight = args.deacon_weight + args.cleanifier_weight;
    if total_weight <= 0.0 {
        return Err(anyhow!("production weights must sum to > 0"));
    }

    let mut fastq = open_fastq_reader(&args.r1)?;
    let mut truth_lines = args
        .truth
        .as_ref()
        .map(|path| open_truth(path))
        .transpose()?
        .map(|reader| reader.lines());
    let report_path = args.outdir.join("per_read_report.tsv.gz");
    let report_file = File::create(&report_path)?;
    let report_encoder = GzEncoder::new(report_file, Compression::fast());
    let mut report = BufWriter::with_capacity(1024 * 1024, report_encoder);
    writeln!(
        report,
        "read_id\ttruth\tprediction\tretained\tdeacon_remove\tcleanifier_remove\tdisagreement\tproduction_score\tmicrobe_score\tmicrobe_witness_fraction"
    )?;

    let mut counts = Counts::default();
    let mut histogram: HashMap<(u8, u8, bool), u64> = HashMap::new();
    loop {
        let record = match fastq.next_record()? {
            Some(value) => value,
            None => break,
        };
        let truth_label = match truth_lines.as_mut() {
            Some(lines) => {
                let truth_line = lines.next().ok_or_else(|| {
                    anyhow!("truth ended before FASTQ record {}", counts.records + 1)
                })??;
                let (truth_id, truth_label) =
                    truth_label(&truth_line, args.truth.as_ref().unwrap())?;
                if truth_id != record.id() {
                    return Err(anyhow!(
                        "truth/FASTQ order mismatch at record {}: {} != {}",
                        counts.records + 1,
                        record.id(),
                        truth_id
                    ));
                }
                truth_label.to_string()
            }
            None => "unlabeled".to_string(),
        };
        let is_host =
            truth_label.eq_ignore_ascii_case("host") || truth_label.eq_ignore_ascii_case("human");
        let deacon_remove = !deacon_keep.contains(record.id());
        let cleanifier_remove = !cleanifier_keep.contains(record.id());
        let disagreement = deacon_remove != cleanifier_remove;

        // Production query evidence is binary. Convert it to a bounded score
        // before applying the witness/boundary resolver.
        let production_score = (args.deacon_weight * f64::from(deacon_remove)
            + args.cleanifier_weight * f64::from(cleanifier_remove))
            / total_weight;

        // Shared one-pass witness extraction. Host indexes above are not queried.
        let features = rustyclean_x::evidence::EvidenceFeatures::extract_fused(
            &record,
            &empty_gapped,
            &empty_minimizer,
            Some(&witness),
        );
        let _scores = score_features(&features, &config);
        let microbe_score =
            (features.microbe_witness_fraction / config.microbe_witness_fraction).clamp(0.0, 1.0);

        let remove = if deacon_remove && cleanifier_remove {
            true
        } else if !deacon_remove && !cleanifier_remove {
            false
        } else {
            // Host-clean disagreement policy: remove unless the independent
            // microbial witness confidently identifies the read.
            microbe_score < args.microbe_score_rescue
        };
        let decision = if remove {
            Decision::Remove
        } else {
            Decision::Keep
        };
        let retained = !remove;

        counts.records += 1;
        if args.truth.is_some() && is_host {
            counts.host_total += 1;
            if remove {
                counts.host_removed += 1;
            }
            if decision == Decision::Boundary {
                counts.boundary_true_host += 1;
            }
        } else if args.truth.is_some() {
            counts.microbe_total += 1;
            if remove {
                counts.microbe_removed += 1;
            }
            if decision == Decision::Boundary {
                counts.boundary_true_microbe += 1;
            }
        }

        let production_bin = (production_score * 20.0).round().clamp(0.0, 20.0) as u8;
        let microbe_bin = (microbe_score * 20.0).round().clamp(0.0, 20.0) as u8;
        *histogram
            .entry((production_bin, microbe_bin, is_host))
            .or_insert(0) += 1;

        writeln!(
            report,
            "{}\t{}\t{:?}\t{}\t{}\t{}\t{}\t{:.9}\t{:.9}\t{:.9}",
            record.id(),
            truth_label,
            decision,
            u8::from(retained),
            u8::from(deacon_remove),
            u8::from(cleanifier_remove),
            u8::from(disagreement),
            production_score,
            microbe_score,
            features.microbe_witness_fraction,
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
    if truth_lines
        .as_mut()
        .is_some_and(|lines| lines.next().is_some())
    {
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

    let mut metrics = BufWriter::new(File::create(args.outdir.join("metrics.tsv"))?);
    writeln!(
        metrics,
        "dataset\trecords\thost_total\tmicrobe_total\thost_removed\thost_retained\thost_retention_pct\tmicrobe_removed\tmicrobe_retained\tmicrobial_loss_pct\tboundary_true_host\tboundary_true_microbe\tretained_total\thost_output_fraction_pct\tprecision\trecall\tf1\tdeacon_imported\tcleanifier_imported\tseconds"
    )?;
    writeln!(
        metrics,
        "{}\t{}\t{}\t{}\t{}\t{}\t{:.9}\t{}\t{}\t{:.9}\t{}\t{}\t{}\t{:.9}\t{:.12}\t{:.12}\t{:.12}\t{}\t{}\t{:.3}",
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
        deacon_keep.len(),
        cleanifier_keep.len(),
        started.elapsed().as_secs_f64()
    )?;

    let mut hist_file = BufWriter::new(File::create(args.outdir.join("score_histogram.tsv"))?);
    writeln!(
        hist_file,
        "production_score_bin\tmicrobe_score_bin\ttruth_host\ttruth_microbe"
    )?;
    let mut keys: Vec<_> = histogram.into_iter().collect();
    keys.sort_unstable();
    for ((production_bin, microbe_bin, is_host), count) in keys {
        if is_host {
            writeln!(hist_file, "{production_bin}\t{microbe_bin}\t{count}\t0")?;
        } else {
            writeln!(hist_file, "{production_bin}\t{microbe_bin}\t0\t{count}")?;
        }
    }
    Ok(())
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

fn percentage(numerator: u64, denominator: u64) -> f64 {
    if denominator > 0 {
        100.0 * numerator as f64 / denominator as f64
    } else {
        0.0
    }
}
