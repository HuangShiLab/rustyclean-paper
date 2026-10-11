use anyhow::{anyhow, Result};
use flate2::read::MultiGzDecoder;
use rustyclean_x::evidence::gapped::GappedSeedFilter;
use rustyclean_x::evidence::microbial::MicrobialWitnessFilter;
use rustyclean_x::evidence::minimizer::MinimizerFilter;
use rustyclean_x::evidence::EvidenceFeatures;
use std::fs::File;
use std::hint::black_box;
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::time::Instant;

#[derive(Debug, Clone)]
struct Args {
    dataset: String,
    r1: PathBuf,
    limit: usize,
    index_kmers: usize,
    replicates: usize,
    output: PathBuf,
}

fn parse_args() -> Result<Args> {
    let mut args = Args {
        dataset: "dataset".into(),
        r1: PathBuf::new(),
        limit: 200_000,
        index_kmers: 1_000_000,
        replicates: 3,
        output: PathBuf::from("rustyclean_x_fastq_benchmark.tsv"),
    };
    let mut iterator = std::env::args().skip(1);
    while let Some(flag) = iterator.next() {
        let mut value = |name: &'static str| {
            iterator
                .next()
                .ok_or_else(|| anyhow!("missing value for {name}"))
        };
        match flag.as_str() {
            "--dataset" => args.dataset = value("--dataset")?,
            "--r1" => args.r1 = value("--r1")?.into(),
            "--limit" => args.limit = value("--limit")?.parse()?,
            "--index-kmers" => args.index_kmers = value("--index-kmers")?.parse()?,
            "--replicates" => args.replicates = value("--replicates")?.parse()?,
            "--output" => args.output = value("--output")?.into(),
            "--help" | "-h" => {
                println!("usage: benchmark_fastq --dataset NAME --r1 FASTQ [options]");
                std::process::exit(0);
            }
            other => return Err(anyhow!("unknown argument: {other}")),
        }
    }
    if args.limit == 0 || args.index_kmers == 0 || args.replicates == 0 {
        return Err(anyhow!("limit, index-kmers and replicates must be > 0"));
    }
    Ok(args)
}

fn open_fastq(path: &Path) -> Result<Box<dyn BufRead + Send>> {
    let file = File::open(path)?;
    if path.extension().and_then(|value| value.to_str()) == Some("gz") {
        Ok(Box::new(BufReader::with_capacity(
            256 * 1024,
            MultiGzDecoder::new(file),
        )))
    } else {
        Ok(Box::new(BufReader::with_capacity(256 * 1024, file)))
    }
}

struct Rng(u64);

impl Rng {
    fn next(&mut self) -> u64 {
        let mut x = self.0;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.0 = x;
        x
    }
}

fn make_filters(
    count: usize,
) -> Result<(GappedSeedFilter, MinimizerFilter, MicrobialWitnessFilter)> {
    let mut rng = Rng(0x5157_2026_1003_0310);
    let mut gapped = Vec::with_capacity(count);
    let mut minimizer = Vec::with_capacity(count);
    let mut witness = Vec::with_capacity(count);
    for _ in 0..count {
        gapped.push(rng.next());
        minimizer.push(rng.next());
        witness.push(rng.next());
    }
    let seed = rustyclean_x::evidence::gapped::SeedMask::new(0b1_1111_1111_1001_1111_1111, 21)?;
    Ok((
        GappedSeedFilter::with_hashes(gapped.into_iter().collect(), vec![seed]),
        MinimizerFilter::with_hashes(minimizer.into_iter().collect(), 21, 41),
        MicrobialWitnessFilter::with_hashes(witness.into_iter().collect(), 21),
    ))
}

struct ReadStats {
    records: usize,
    bases: usize,
}

fn scan_mode(
    path: &Path,
    limit: usize,
    mode: &str,
    gapped: Option<&GappedSeedFilter>,
    minimizer: Option<&MinimizerFilter>,
    witness: Option<&MicrobialWitnessFilter>,
) -> Result<ReadStats> {
    let mut reader = open_fastq(path)?;
    let mut stats = ReadStats {
        records: 0,
        bases: 0,
    };
    let mut header = String::new();
    let mut sequence = String::new();
    let mut plus = String::new();
    let mut quality = String::new();

    while stats.records < limit {
        header.clear();
        sequence.clear();
        plus.clear();
        quality.clear();
        if reader.read_line(&mut header)? == 0 {
            break;
        }
        reader.read_line(&mut sequence)?;
        reader.read_line(&mut plus)?;
        reader.read_line(&mut quality)?;
        if !header.starts_with('@') {
            return Err(anyhow!(
                "invalid FASTQ header at record {}",
                stats.records + 1
            ));
        }
        let sequence = std::mem::take(&mut sequence);
        let quality = std::mem::take(&mut quality);
        let sequence = trim_newline(sequence.into());
        let quality = trim_newline(quality.into());
        if sequence.len() != quality.len() {
            return Err(anyhow!(
                "sequence/quality mismatch at record {}",
                stats.records + 1
            ));
        }
        stats.records += 1;
        stats.bases += sequence.len();

        black_box(&header);
        black_box(&quality);
        match mode {
            "parse_only" => black_box(sequence.len()),
            "gapped_only" => {
                let record = dummy_record(&sequence, &quality);
                let mut features = EvidenceFeatures::default();
                if let Some(gapped) = gapped {
                    gapped.add_evidence(&record, &mut features);
                }
                black_box(features.gapped_host_hits as usize)
            }
            "minimizer_only" => {
                let record = dummy_record(&sequence, &quality);
                let mut features = EvidenceFeatures::default();
                if let Some(minimizer) = minimizer {
                    minimizer.add_evidence(&record, &mut features);
                }
                black_box(features.minimizer_host_hits as usize)
            }
            "fused_gapped_minimizer" => {
                let record = dummy_record(&sequence, &quality);
                let features = EvidenceFeatures::extract_fused(
                    &record,
                    gapped.expect("gapped filter required"),
                    minimizer.expect("minimizer filter required"),
                    None,
                );
                black_box(features.host_gapped_fraction);
                black_box(features.host_minimizer_fraction as usize)
            }
            "fused_with_witness" => {
                let record = dummy_record(&sequence, &quality);
                let features = EvidenceFeatures::extract_fused(
                    &record,
                    gapped.expect("gapped filter required"),
                    minimizer.expect("minimizer filter required"),
                    Some(witness.expect("witness filter required")),
                );
                black_box(features.host_gapped_fraction);
                black_box(features.microbe_witness_fraction as usize)
            }
            other => return Err(anyhow!("unknown benchmark mode: {other}")),
        };
    }
    Ok(stats)
}

fn trim_newline(mut values: Vec<u8>) -> Vec<u8> {
    while values
        .last()
        .is_some_and(|value| *value == b'\n' || *value == b'\r')
    {
        values.pop();
    }
    values
}

fn dummy_record(sequence: &[u8], quality: &[u8]) -> rustyclean_x::fastq::FastqRecord {
    rustyclean_x::fastq::FastqRecord {
        header: "@benchmark".into(),
        seq: sequence.to_vec(),
        qual: quality.to_vec(),
    }
}

#[allow(clippy::too_many_arguments)]
fn append_result(
    output: &Path,
    dataset: &str,
    mode: &str,
    replicate: usize,
    limit: usize,
    stats: &ReadStats,
    compressed_bytes: u64,
    seconds: f64,
) -> Result<()> {
    let records_per_s = if seconds > 0.0 {
        stats.records as f64 / seconds
    } else {
        f64::NAN
    };
    let bases_per_s = if seconds > 0.0 {
        stats.bases as f64 / seconds
    } else {
        f64::NAN
    };
    let mut file = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(output)?;
    writeln!(
        file,
        "{}\t{}\t{}\t{}\t{}\t{}\t{}\t{:.6}\t{:.1}\t{:.1}",
        dataset,
        mode,
        replicate,
        limit,
        stats.records,
        stats.bases,
        compressed_bytes,
        seconds,
        records_per_s,
        bases_per_s
    )?;
    Ok(())
}

fn main() -> Result<()> {
    let args = parse_args()?;
    if !args.r1.is_file() {
        return Err(anyhow!("FASTQ does not exist: {}", args.r1.display()));
    }
    let compressed_bytes = args.r1.metadata()?.len();
    let (gapped, minimizer, witness) = make_filters(args.index_kmers)?;
    let output = args.output.clone();
    if let Some(parent) = output.parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent)?;
        }
    }
    std::fs::write(
        &output,
        "dataset\tmode\treplicate\tlimit\trecords\tbases\tcompressed_bytes\tseconds\trecords_per_s\tbases_per_s\n",
    )?;

    let modes = [
        "parse_only",
        "gapped_only",
        "minimizer_only",
        "fused_gapped_minimizer",
        "fused_with_witness",
    ];
    for mode in modes {
        for replicate in 1..=args.replicates {
            let start = Instant::now();
            let stats = scan_mode(
                &args.r1,
                args.limit,
                mode,
                Some(&gapped),
                Some(&minimizer),
                Some(&witness),
            )?;
            let seconds = start.elapsed().as_secs_f64();
            append_result(
                &args.output,
                &args.dataset,
                mode,
                replicate,
                args.limit,
                &stats,
                compressed_bytes,
                seconds,
            )?;
            println!(
                "{}\t{}\trep={}\trecords={}\tbases={}\tseconds={:.3}",
                args.dataset, mode, replicate, stats.records, stats.bases, seconds
            );
        }
    }
    println!("output={}", output.display());
    Ok(())
}
