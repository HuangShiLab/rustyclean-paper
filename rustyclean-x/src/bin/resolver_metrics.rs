use anyhow::{anyhow, Result};
use clap::Parser;
use flate2::read::MultiGzDecoder;
use std::collections::HashSet;
use std::fs::File;
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};

/// Calculate exact resolver metrics from existing per-read reports and
/// production kept-read FASTQs.  No index query or FASTQ sequence decoding is
/// performed, so this is suitable for repeated validation.
#[derive(Parser, Debug)]
#[command(about = "Exact metrics for calibrated production-query resolver")]
struct Args {
    #[arg(long)]
    dataset: String,
    /// Internal fused-mode per-read report.
    #[arg(long)]
    report: PathBuf,
    #[arg(long)]
    deacon_kept: PathBuf,
    #[arg(long)]
    cleanifier_kept: PathBuf,
    #[arg(long, default_value_t = 0.30)]
    microbe_score_rescue: f64,
    #[arg(long, default_value_t = 0.50)]
    host_score_max: f64,
    #[arg(long)]
    output: PathBuf,
}

fn open_compressed(path: &Path) -> Result<Box<dyn BufRead>> {
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

fn import_kept_ids(path: &Path, label: &str) -> Result<HashSet<String>> {
    let reader = open_compressed(path)?;
    let mut reader = BufReader::new(reader);
    let mut ids = HashSet::new();
    let mut header = String::new();
    let mut discard = String::new();
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
        ids.insert(id.to_owned());
        for _ in 0..3 {
            discard.clear();
            if reader.read_line(&mut discard)? == 0 {
                return Err(anyhow!(
                    "truncated {label} FASTQ record at line {line_number}"
                ));
            }
            line_number += 1;
        }
    }
    Ok(ids)
}

fn parse_report(line: &str) -> Result<(&str, bool, f64, f64)> {
    let fields: Vec<&str> = line.trim_end_matches(['\r', '\n']).split('\t').collect();
    if fields.len() != 11 {
        return Err(anyhow!("expected 11 columns, got {}", fields.len()));
    }
    let is_host = fields[1].eq_ignore_ascii_case("host") || fields[1].eq_ignore_ascii_case("human");
    let microbe: f64 = fields[8].parse()?;
    let host: f64 = fields[7].parse()?;
    Ok((fields[0], is_host, microbe, host))
}

#[derive(Default, Debug, Clone, Copy)]
struct Counts {
    records: u64,
    host_total: u64,
    microbe_total: u64,
    host_removed: u64,
    microbe_removed: u64,
}

fn counts_for_threshold(
    report: &Path,
    deacon: &HashSet<String>,
    cleanifier: &HashSet<String>,
    microbe_threshold: f64,
    host_threshold: f64,
) -> Result<Counts> {
    let reader = BufReader::new(open_compressed(report)?);
    let mut lines = reader.lines();
    let header = lines.next().ok_or_else(|| anyhow!("empty report"))??;
    if !header.starts_with("read_id\ttruth\t") {
        return Err(anyhow!("unexpected report header"));
    }
    let mut counts = Counts::default();
    for line in lines {
        let line = line?;
        let (id, is_host, microbe_score, host_score) = parse_report(&line)?;
        let union_remove = !(deacon.contains(id) && cleanifier.contains(id));
        let rescue =
            union_remove && microbe_score >= microbe_threshold && host_score <= host_threshold;
        let removed = union_remove && !rescue;
        counts.records += 1;
        if is_host {
            counts.host_total += 1;
            counts.host_removed += u64::from(removed);
        } else {
            counts.microbe_total += 1;
            counts.microbe_removed += u64::from(removed);
        }
    }
    Ok(counts)
}

fn row(dataset: &str, rule: &str, threshold: (f64, f64), counts: Counts) -> String {
    let host_retained = counts.host_total - counts.host_removed;
    let microbe_retained = counts.microbe_total - counts.microbe_removed;
    let retained_total = host_retained + microbe_retained;
    let precision = microbe_retained as f64 / retained_total as f64;
    let recall = microbe_retained as f64 / counts.microbe_total as f64;
    let f1 = if precision + recall > 0.0 {
        2.0 * precision * recall / (precision + recall)
    } else {
        0.0
    };
    format!(
        "{}\t{}\t{:.6}\t{:.6}\t{}\t{}\t{}\t{}\t{}\t{}\t{:.9}\t{:.9}\t{:.9}",
        dataset,
        rule,
        threshold.0,
        threshold.1,
        counts.records,
        counts.host_total,
        counts.microbe_total,
        counts.host_removed,
        counts.microbe_removed,
        retained_total,
        100.0 * host_retained as f64 / counts.host_total as f64,
        100.0 * counts.microbe_removed as f64 / counts.microbe_total as f64,
        f1,
    )
}

fn main() -> Result<()> {
    let args = Args::parse();
    let deacon = import_kept_ids(&args.deacon_kept, "Deacon")?;
    let cleanifier = import_kept_ids(&args.cleanifier_kept, "Cleanifier")?;
    let calibrated = counts_for_threshold(
        &args.report,
        &deacon,
        &cleanifier,
        args.microbe_score_rescue,
        args.host_score_max,
    )?;
    let ablation = counts_for_threshold(&args.report, &deacon, &cleanifier, -1.0, 1.0)?;
    let mut output = std::io::BufWriter::new(
        File::options()
            .append(true)
            .create(true)
            .open(&args.output)?,
    );
    let path = &args.output;
    if std::fs::metadata(path)
        .map(|value| value.len())
        .unwrap_or(0)
        == 0
    {
        writeln!(output, "dataset\trule\tmicrobe_score_rescue\thost_score_max\trecords\thost_total\tmicrobe_total\thost_removed\tmicrobe_removed\tretained_total\thost_retention_pct\tmicrobial_loss_pct\tf1")?;
    }
    writeln!(
        output,
        "{}",
        row(
            &args.dataset,
            "calibrated_resolver",
            (args.microbe_score_rescue, args.host_score_max),
            calibrated
        )
    )?;
    writeln!(
        output,
        "{}",
        row(
            &args.dataset,
            "union_depletion_ablation",
            (-1.0, 1.0),
            ablation
        )
    )?;
    output.flush()?;
    println!(
        "{} completed calibrated host_retention_pct={:.9} microbial_loss_pct={:.9}",
        args.dataset,
        100.0 * (calibrated.host_total - calibrated.host_removed) as f64
            / calibrated.host_total as f64,
        100.0 * calibrated.microbe_removed as f64 / calibrated.microbe_total as f64
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_internal_report_features() {
        let line = "id\thost\tBoundary\t1\t0.1\t2\t0.2\t0.800000000\t0.300000000\t0.5\t0.5";
        let (id, is_host, microbe, host) = parse_report(line).unwrap();
        assert_eq!(id, "id");
        assert!(is_host);
        assert_eq!(microbe, 0.3);
        assert_eq!(host, 0.8);
    }

    #[test]
    fn rejects_malformed_report() {
        assert!(parse_report("id\thost\tshort").is_err());
    }
}
