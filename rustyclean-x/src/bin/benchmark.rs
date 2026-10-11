use anyhow::Result;
use rustyclean_x::evidence::gapped::{GappedSeedFilter, SeedMask};
use rustyclean_x::evidence::microbial::MicrobialWitnessFilter;
use rustyclean_x::evidence::minimizer::MinimizerFilter;
use rustyclean_x::evidence::EvidenceFeatures;
use rustyclean_x::fastq::FastqRecord;
use std::hint::black_box;
use std::time::Instant;

#[derive(Debug, Clone)]
struct Args {
    reads: usize,
    length: usize,
    index_kmers: usize,
    replicates: usize,
    output: std::path::PathBuf,
}

fn parse_args() -> Result<Args> {
    let mut args = Args {
        reads: 20_000,
        length: 150,
        index_kmers: 50_000,
        replicates: 3,
        output: "rustyclean_x_benchmark.tsv".into(),
    };
    let mut iterator = std::env::args().skip(1);
    while let Some(flag) = iterator.next() {
        let mut value = |name: &'static str| {
            iterator
                .next()
                .ok_or_else(|| anyhow::anyhow!("missing value for {name}"))
        };
        match flag.as_str() {
            "--reads" => args.reads = value("--reads")?.parse()?,
            "--length" => args.length = value("--length")?.parse()?,
            "--index-kmers" => args.index_kmers = value("--index-kmers")?.parse()?,
            "--replicates" => args.replicates = value("--replicates")?.parse()?,
            "--output" => args.output = value("--output")?.into(),
            "--help" | "-h" => {
                println!("usage: benchmark [--reads N] [--length N] [--index-kmers N] [--replicates N] [--output PATH]");
                std::process::exit(0);
            }
            other => return Err(anyhow::anyhow!("unknown argument: {other}")),
        }
    }
    if args.reads == 0 || args.length == 0 || args.index_kmers == 0 || args.replicates == 0 {
        return Err(anyhow::anyhow!("benchmark sizes must be greater than zero"));
    }
    Ok(args)
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

    fn base(&mut self) -> u8 {
        match self.next() & 3 {
            0 => b'A',
            1 => b'C',
            2 => b'G',
            _ => b'T',
        }
    }

    fn sequence(&mut self, length: usize) -> Vec<u8> {
        (0..length).map(|_| self.base()).collect()
    }
}

fn canonical(kmer: u64, k: usize) -> u64 {
    let mut reverse = 0u64;
    for i in 0..k {
        let base = (kmer >> (2 * i)) & 3;
        reverse |= (3 - base) << (2 * (k - i - 1));
    }
    kmer.min(reverse)
}

fn hash(value: u64) -> u64 {
    value.wrapping_mul(0x9E37_79B9_7F4A_7C15)
}

fn make_record(rng: &mut Rng, id: usize, length: usize) -> FastqRecord {
    FastqRecord {
        header: format!("@read_{id}"),
        seq: rng.sequence(length),
        qual: vec![b'I'; length],
    }
}

fn timed<F: FnMut()>(
    name: &str,
    replicate: usize,
    reads: usize,
    length: usize,
    output: &std::path::Path,
    mut function: F,
) -> Result<f64> {
    let start = Instant::now();
    function();
    let elapsed = start.elapsed();
    let seconds = elapsed.as_secs_f64();
    use std::io::Write;
    std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(output)?
        .write_all(
            format!(
                "{name}\t{replicate}\t{reads}\t{length}\t{seconds:.6}\t{:.1}\n",
                reads as f64 / seconds
            )
            .as_bytes(),
        )?;
    println!(
        "{name}\treplicate={replicate}\tseconds={seconds:.6}\treads_per_second={:.1}",
        reads as f64 / seconds
    );
    Ok(seconds)
}

fn main() -> Result<()> {
    let args = parse_args()?;
    let mut rng = Rng(0x2026_1003_5C4E_D5C5);

    // Synthetic host-like evidence indexes. These measure algorithmic query cost;
    // they are not a substitute for the real human pangenome indexes.
    let mut gapped_hashes = Vec::with_capacity(args.index_kmers);
    let mut minimizer_hashes = Vec::with_capacity(args.index_kmers);
    let mut witness_hashes = Vec::with_capacity(args.index_kmers);
    let seed = SeedMask::new(0b1_1111_1111_1001_1111_1111, 21)?;
    let reference = rng.sequence(args.index_kmers + 21);
    for start in 0..args.index_kmers {
        if let Some((value, _)) = seed.hash_sequence(&reference, start) {
            gapped_hashes.push(value);
        }
        let kmer_start = start % (reference.len() - 21);
        if let Some(kmer) = black_box(rustyclean_x::sequence::encode_bases(
            &reference[kmer_start..kmer_start + 21],
        )) {
            minimizer_hashes.push(hash(canonical(kmer, 21)));
            witness_hashes.push(hash(canonical(kmer, 21)));
        }
    }

    let gapped = GappedSeedFilter::with_hashes(gapped_hashes.into_iter().collect(), vec![seed]);
    let minimizer = MinimizerFilter::with_hashes(minimizer_hashes.into_iter().collect(), 21, 41);
    let witness = MicrobialWitnessFilter::with_hashes(witness_hashes.into_iter().collect(), 21);

    let records: Vec<FastqRecord> = (0..args.reads)
        .map(|id| make_record(&mut rng, id, args.length))
        .collect();

    if args.output.parent().is_some() {
        std::fs::create_dir_all(args.output.parent().unwrap())?;
    }
    std::fs::write(
        &args.output,
        "mode\treplicate\treads\tlength\tseconds\treads_per_second\n",
    )?;

    for replicate in 1..=args.replicates {
        timed(
            "parse_only",
            replicate,
            args.reads,
            args.length,
            &args.output,
            || {
                for record in black_box(&records) {
                    black_box(record.seq.len());
                    black_box(record.qual.first());
                }
            },
        )?;
    }

    for replicate in 1..=args.replicates {
        timed(
            "gapped_only",
            replicate,
            args.reads,
            args.length,
            &args.output,
            || {
                for record in black_box(&records) {
                    let mut features = EvidenceFeatures::default();
                    gapped.add_evidence(black_box(record), &mut features);
                    black_box(features.gapped_host_hits);
                }
            },
        )?;
    }

    for replicate in 1..=args.replicates {
        timed(
            "minimizer_only",
            replicate,
            args.reads,
            args.length,
            &args.output,
            || {
                for record in black_box(&records) {
                    let mut features = EvidenceFeatures::default();
                    minimizer.add_evidence(black_box(record), &mut features);
                    black_box(features.minimizer_host_hits);
                }
            },
        )?;
    }

    for replicate in 1..=args.replicates {
        timed(
            "fused_gapped_minimizer",
            replicate,
            args.reads,
            args.length,
            &args.output,
            || {
                for record in black_box(&records) {
                    let features = EvidenceFeatures::extract_fused(
                        black_box(record),
                        &gapped,
                        &minimizer,
                        None,
                    );
                    black_box(features.host_gapped_fraction);
                    black_box(features.host_minimizer_fraction);
                }
            },
        )?;
    }

    for replicate in 1..=args.replicates {
        timed(
            "fused_with_witness",
            replicate,
            args.reads,
            args.length,
            &args.output,
            || {
                for record in black_box(&records) {
                    let features = EvidenceFeatures::extract_fused(
                        black_box(record),
                        &gapped,
                        &minimizer,
                        Some(&witness),
                    );
                    black_box(features.host_gapped_fraction);
                    black_box(features.microbe_witness_fraction);
                }
            },
        )?;
    }

    println!("output={}", args.output.display());
    Ok(())
}
