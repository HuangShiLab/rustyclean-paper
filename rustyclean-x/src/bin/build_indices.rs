use anyhow::{anyhow, Result};
use clap::Parser;
use flate2::read::MultiGzDecoder;
use rustyclean_x::sequence::{canonical_kmer, encode_base, wyhash};
use std::collections::HashSet;
use std::fs::File;
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};

const K: usize = 21;
const WINDOW: usize = 41;
const GAPPED_MASKS: [u64; 2] = [0b1_1111_1111_1001_1111_1111, 0b1_1011_0111_1011_0111_1011];
const GAPPED_LENGTH: usize = 21;

#[derive(Parser, Debug)]
#[command(about = "Build sparse RustyClean-X hash indexes from FASTA references")]
struct Args {
    #[arg(long, required = true)]
    host_fasta: PathBuf,
    #[arg(long, required = true)]
    microbe_fasta: Vec<PathBuf>,
    #[arg(long, required = true)]
    outdir: PathBuf,
    #[arg(long, default_value_t = 20_000_000)]
    max_minimizer: usize,
    #[arg(long, default_value_t = 50_000_000)]
    max_gapped: usize,
    #[arg(long, default_value_t = 200_000_000)]
    max_microbial: usize,
}

fn open_fasta(path: &Path) -> Result<Box<dyn BufRead>> {
    if path.extension().and_then(|value| value.to_str()) == Some("gz") {
        Ok(Box::new(BufReader::with_capacity(
            1024 * 1024,
            MultiGzDecoder::new(File::open(path)?),
        )))
    } else {
        Ok(Box::new(BufReader::with_capacity(
            1024 * 1024,
            File::open(path)?,
        )))
    }
}

#[derive(serde::Serialize)]
struct SequenceStats {
    sequences: usize,
    bases: u64,
    valid_bases: u64,
}

fn for_each_sequence<F>(path: &Path, mut callback: F) -> Result<SequenceStats>
where
    F: FnMut(&[u8]) -> Result<()>,
{
    let reader = open_fasta(path)?;
    let mut reader = reader;
    let mut stats = SequenceStats {
        sequences: 0,
        bases: 0,
        valid_bases: 0,
    };
    let mut sequence: Vec<u8> = Vec::new();
    let mut in_sequence = false;
    let mut line = String::new();
    loop {
        line.clear();
        if reader.read_line(&mut line)? == 0 {
            break;
        }
        if line.starts_with('>') {
            if in_sequence && !sequence.is_empty() {
                callback(&sequence)?;
                stats.sequences += 1;
            }
            sequence.clear();
            in_sequence = true;
            continue;
        }
        if !in_sequence {
            continue;
        }
        let bytes = line.trim_end_matches(['\r', '\n']).as_bytes();
        stats.bases += bytes.len() as u64;
        for &base in bytes {
            let encoded = encode_base(base);
            if encoded.is_some() {
                stats.valid_bases += 1;
            }
            sequence.push(encoded.map_or(b'N', |_| base.to_ascii_uppercase()));
        }
    }
    if in_sequence && !sequence.is_empty() {
        callback(&sequence)?;
        stats.sequences += 1;
    }
    Ok(stats)
}

struct KmerState {
    forward: u64,
    reverse: u64,
    length: usize,
}

impl KmerState {
    fn new(length: usize) -> Self {
        Self {
            forward: 0,
            reverse: 0,
            length,
        }
    }

    fn push(&mut self, base: u8) -> Option<u64> {
        let code = encode_base(base)?;
        let shift = 2 * (self.length - 1);
        self.forward = ((self.forward << 2) | code) & ((1_u64 << (2 * self.length)) - 1);
        self.reverse = (self.reverse >> 2) | ((3 - code) << shift);
        Some(canonical_kmer(self.forward, self.length))
    }
}

fn gapped_hash(sequence: &[u8], start: usize, mask: u64) -> Option<u64> {
    let mut hash = 0xcbf2_9ce4_8422_2325_u64;
    for offset in 0..GAPPED_LENGTH {
        if (mask >> (GAPPED_LENGTH - 1 - offset)) & 1 == 0 {
            continue;
        }
        let code = encode_base(*sequence.get(start + offset)?)?;
        hash = (hash ^ code).wrapping_mul(0x0000_0100_0000_01B3);
    }
    Some(hash)
}

fn insert_bounded(set: &mut HashSet<u64>, value: u64, max: usize) {
    if set.len() < max {
        set.insert(value);
    }
}

fn main() -> Result<()> {
    let args = Args::parse();
    std::fs::create_dir_all(&args.outdir)?;

    let mut gapped: HashSet<u64> = HashSet::new();
    let mut minimizer: HashSet<u64> = HashSet::new();
    let host_stats = for_each_sequence(&args.host_fasta, |sequence| {
        let mut state = KmerState::new(K);
        let mut window: Vec<u64> = Vec::with_capacity(WINDOW - K + 1);
        for (position, &base) in sequence.iter().enumerate() {
            match state.push(base) {
                Some(canonical) => {
                    if window.len() == WINDOW - K + 1 {
                        window.remove(0);
                    }
                    window.push(wyhash(canonical));
                    if window.len() == WINDOW - K + 1 && position + 1 >= WINDOW {
                        if let Some(selected) = window.iter().copied().min() {
                            if minimizer.len() < args.max_minimizer {
                                minimizer.insert(selected);
                            }
                        }
                    }
                }
                None => {
                    state = KmerState::new(K);
                    window.clear();
                    continue;
                }
            }

            if position % 10 == 0 && position + GAPPED_LENGTH <= sequence.len() {
                for &mask in &GAPPED_MASKS {
                    if let Some(hash) = gapped_hash(sequence, position, mask) {
                        insert_bounded(&mut gapped, hash, args.max_gapped);
                    }
                }
            }
        }
        Ok(())
    })?;
    if gapped.is_empty() || minimizer.is_empty() {
        return Err(anyhow!("host FASTA produced no indexed seeds"));
    }

    let mut witness: HashSet<u64> = HashSet::new();
    let mut all_microbe_stats = SequenceStats {
        sequences: 0,
        bases: 0,
        valid_bases: 0,
    };
    for path in &args.microbe_fasta {
        let stats = for_each_sequence(path, |sequence| {
            let mut state = KmerState::new(K);
            for base in sequence {
                match state.push(*base) {
                    Some(canonical) => {
                        if witness.len() < args.max_microbial {
                            let hash = wyhash(canonical);
                            if hash.is_multiple_of(3) {
                                witness.insert(hash);
                            }
                        }
                    }
                    None => {
                        state = KmerState::new(K);
                    }
                }
            }
            Ok(())
        })?;
        all_microbe_stats.sequences += stats.sequences;
        all_microbe_stats.bases += stats.bases;
        all_microbe_stats.valid_bases += stats.valid_bases;
    }
    if witness.is_empty() {
        return Err(anyhow!("microbial FASTA produced no witness seeds"));
    }

    let write_hash = |path: &Path, set: &HashSet<u64>| -> Result<usize> {
        let file = File::create(path)?;
        let mut writer = std::io::BufWriter::new(file);
        for value in set {
            writeln!(writer, "{value}")?;
        }
        writer.flush()?;
        Ok(set.len())
    };
    let gapped_count = write_hash(&args.outdir.join("host.gapped.hashes"), &gapped)?;
    let minimizer_count = write_hash(&args.outdir.join("host.minimizer.hashes"), &minimizer)?;
    let witness_count = write_hash(&args.outdir.join("microbial.witness.hashes"), &witness)?;

    let summary = serde_json::json!({
        "k": K,
        "window": WINDOW,
        "host_fasta": args.host_fasta,
        "microbe_fastas": args.microbe_fasta,
        "host": host_stats,
        "microbe": all_microbe_stats,
        "indexes": {
            "gapped": gapped_count,
            "minimizer": minimizer_count,
            "witness": witness_count,
        },
        "max_limits": {
            "gapped": args.max_gapped,
            "minimizer": args.max_minimizer,
            "witness": args.max_microbial,
        }
    });
    std::fs::write(
        args.outdir.join("index_manifest.json"),
        serde_json::to_string_pretty(&summary)?,
    )?;
    println!("built gapped={gapped_count} minimizer={minimizer_count} witness={witness_count}");
    Ok(())
}
