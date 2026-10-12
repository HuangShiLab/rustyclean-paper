use anyhow::{anyhow, Result};
use clap::Parser;
use flate2::read::MultiGzDecoder;
use flate2::write::GzEncoder;
use flate2::Compression;
use std::collections::HashSet;
use std::fs::File;
use std::io::{BufRead, BufReader, BufWriter, Write};
use std::path::{Path, PathBuf};

/// Build compact training evidence without rerunning production indexes.
///
/// The internal per-read report, Deacon retained FASTQ, and Cleanifier
/// retained FASTQ are all in source-read order.  The merger therefore streams
/// all three files in lockstep and emits only the resolver features needed for
/// threshold calibration.
#[derive(Parser, Debug)]
#[command(about = "Merge existing per-read reports with production kept-ID FASTQs")]
struct Args {
    #[arg(long)]
    dataset: String,
    /// Internal fused-mode report (not the old production_fusion report).
    #[arg(long)]
    report: PathBuf,
    #[arg(long)]
    deacon_kept: PathBuf,
    #[arg(long)]
    cleanifier_kept: PathBuf,
    #[arg(long)]
    deacon_abs3_kept: Option<PathBuf>,
    #[arg(long)]
    deacon_abs4_kept: Option<PathBuf>,
    #[arg(long)]
    deacon_abs5_kept: Option<PathBuf>,
    #[arg(long)]
    cleanifier_070_kept: Option<PathBuf>,
    #[arg(long)]
    cleanifier_090_kept: Option<PathBuf>,
    #[arg(long)]
    output: PathBuf,
    #[arg(long, default_value_t = 1)]
    sample_every: u32,
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

fn parse_report_line(line: &str) -> Result<(&str, &str, f64, f64, f64, f64, f64, f64)> {
    let fields: Vec<&str> = line.trim_end_matches(['\r', '\n']).split('\t').collect();
    if fields.len() != 11 {
        return Err(anyhow!(
            "expected 11 report columns, got {}: {line:?}",
            fields.len()
        ));
    }
    let parse = |value: &str| {
        value
            .parse::<f64>()
            .map_err(|error| anyhow!("{value}: {error}"))
    };
    Ok((
        fields[0],
        fields[1],
        parse(fields[6])?,  // microbe_witness_fraction
        parse(fields[7])?,  // host_score
        parse(fields[8])?,  // microbe_score
        parse(fields[9])?,  // gapped_component
        parse(fields[10])?, // minimizer_component
        parse(fields[4])?,  // host_gapped_fraction
    ))
}

fn main() -> Result<()> {
    let args = Args::parse();
    if args.sample_every == 0 {
        return Err(anyhow!("--sample-every must be positive"));
    }
    if let Some(parent) = args.output.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let output = File::create(&args.output)?;
    let encoder = GzEncoder::new(output, Compression::fast());
    let mut out = BufWriter::with_capacity(1024 * 1024, encoder);
    writeln!(
        out,
        "dataset\tindex\ttruth\tdeacon_keep\tcleanifier_keep\tdeacon_abs3_keep\tdeacon_abs4_keep\tdeacon_abs5_keep\tcleanifier_070_keep\tcleanifier_090_keep\tmicrobe_witness_fraction\tmicrobe_score\thost_score\tgapped_component\tminimizer_component\thost_gapped_fraction"
    )?;

    let report = BufReader::new(open_compressed(&args.report)?);
    eprintln!("importing Deacon retained IDs");
    let deacon_keep = import_kept_ids(&args.deacon_kept, "Deacon")?;
    eprintln!("Deacon imported retained={}", deacon_keep.len());
    eprintln!("importing Cleanifier retained IDs");
    let cleanifier_keep = import_kept_ids(&args.cleanifier_kept, "Cleanifier")?;
    eprintln!("Cleanifier imported retained={}", cleanifier_keep.len());
    let optional_kept = |path: &Option<PathBuf>, label: &str| -> Result<HashSet<String>> {
        match path {
            Some(value) => {
                let ids = import_kept_ids(value, label)?;
                eprintln!("{label} imported retained={}", ids.len());
                Ok(ids)
            }
            None => Ok(HashSet::new()),
        }
    };
    let deacon_abs3 = optional_kept(&args.deacon_abs3_kept, "Deacon abs3")?;
    let deacon_abs4 = optional_kept(&args.deacon_abs4_kept, "Deacon abs4")?;
    let deacon_abs5 = optional_kept(&args.deacon_abs5_kept, "Deacon abs5")?;
    let cleanifier_070 = optional_kept(&args.cleanifier_070_kept, "Cleanifier 0.70")?;
    let cleanifier_090 = optional_kept(&args.cleanifier_090_kept, "Cleanifier 0.90")?;

    let mut lines = report.lines();
    let header = lines.next().ok_or_else(|| anyhow!("empty report"))??;
    if !header.starts_with("read_id\ttruth\t") {
        return Err(anyhow!("unexpected report header: {header:?}"));
    }
    let mut index = 0_u64;
    let mut sampled = 0_u64;
    for line in lines {
        let line = line?;
        let (read_id, truth, witness, host_score, microbe_score, gapped, minimizer, host_gapped) =
            parse_report_line(&line)?;
        let deacon_kept = deacon_keep.contains(read_id);
        let cleanifier_kept = cleanifier_keep.contains(read_id);
        if index % u64::from(args.sample_every) == 0 {
            writeln!(
                out,
                "{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{:.9}\t{:.9}\t{:.9}\t{:.9}\t{:.9}\t{:.9}",
                args.dataset,
                index,
                truth,
                u8::from(deacon_kept),
                u8::from(cleanifier_kept),
                u8::from(deacon_abs3.contains(read_id)),
                u8::from(deacon_abs4.contains(read_id)),
                u8::from(deacon_abs5.contains(read_id)),
                u8::from(cleanifier_070.contains(read_id)),
                u8::from(cleanifier_090.contains(read_id)),
                witness,
                microbe_score,
                host_score,
                gapped,
                minimizer,
                host_gapped,
            )?;
            sampled += 1;
        }
        index += 1;
        if index % 5_000_000 == 0 {
            out.flush()?;
            eprintln!("{} processed={index} sampled={sampled}", args.dataset);
        }
    }
    out.flush()?;
    eprintln!(
        "{} completed records={index} sampled={sampled}",
        args.dataset
    );
    Ok(())
}
