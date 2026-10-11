use anyhow::Result;
use rustyclean_x::evidence::gapped::SeedMask;
use rustyclean_x::fastq::{FastqReader, FastqWriter};
use rustyclean_x::sequence::{canonical_kmer, encode_bases, wyhash};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

const HOST: &[u8] = b"ACGTTACGATCGATCGATCGATCGATCGACGTTACGATCGATCGATCGATCGATCG";
const MICROBE: &[u8] = b"TTTTACCCGGGTTTTACCCGGGTTTTACCC";

fn unique_dir(name: &str) -> PathBuf {
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let dir = std::env::temp_dir().join(format!(
        "rustyclean-x-{name}-{}-{nanos}",
        std::process::id()
    ));
    fs::create_dir_all(&dir).unwrap();
    dir
}

fn write_hash_file(path: &Path, hashes: &[u64]) -> Result<()> {
    let mut text = String::new();
    for hash in hashes {
        text.push_str(&hash.to_string());
        text.push('\n');
    }
    fs::write(path, text)?;
    Ok(())
}

fn write_fastq(path: &Path, records: &[(&str, &[u8])]) -> Result<()> {
    let mut writer = FastqWriter::from_path(path)?;
    for (header, sequence) in records {
        writer.write(&rustyclean_x::fastq::FastqRecord {
            header: header.to_string(),
            seq: sequence.to_vec(),
            qual: vec![b'I'; sequence.len()],
        })?;
    }
    writer.flush()?;
    Ok(())
}

fn read_ids(path: &Path) -> Result<Vec<String>> {
    let mut reader = FastqReader::from_path(path)?;
    let mut ids = Vec::new();
    while let Some(record) = reader.next_record()? {
        ids.push(record.id().to_string());
    }
    Ok(ids)
}

#[test]
fn end_to_end_smoke_separates_host_and_microbe() -> Result<()> {
    let dir = unique_dir("end-to-end");
    let gapped_path = dir.join("gapped.hashes");
    let minimizer_path = dir.join("minimizer.hashes");
    let microbial_path = dir.join("microbial.hashes");
    let r1_path = dir.join("reads.fastq");
    let output = dir.join("output");
    let report = dir.join("report.tsv");

    // Build a gapped host index containing every seed hash from the host read.
    let masks = vec![
        SeedMask::new(0b1_1111_1111_1001_1111_1111, 21).unwrap(),
        SeedMask::new(0b1_1011_0111_1011_0111_1011, 21).unwrap(),
    ];
    let mut gapped_hashes = Vec::new();
    for mask in &masks {
        for start in 0..=(HOST.len() - mask.length) {
            if let Some((hash, _)) = mask.hash_sequence(HOST, start) {
                gapped_hashes.push(hash);
            }
        }
    }
    write_hash_file(&gapped_path, &gapped_hashes)?;

    // Include every canonical host k-mer as an eligible minimizer.
    let k = 21;
    let mut minimizer_hashes = Vec::new();
    for start in 0..=(HOST.len() - k) {
        let kmer = encode_bases(&HOST[start..start + k]).unwrap();
        minimizer_hashes.push(wyhash(canonical_kmer(kmer, k)));
    }
    write_hash_file(&minimizer_path, &minimizer_hashes)?;

    // Include every canonical microbial k-mer as a witness.
    let mut witness_hashes = Vec::new();
    for start in 0..=(MICROBE.len() - k) {
        let kmer = encode_bases(&MICROBE[start..start + k]).unwrap();
        witness_hashes.push(wyhash(canonical_kmer(kmer, k)));
    }
    write_hash_file(&microbial_path, &witness_hashes)?;

    write_fastq(&r1_path, &[("host", HOST), ("microbe", MICROBE)])?;

    let status = Command::new(env!("CARGO_BIN_EXE_rustyclean-x"))
        .args([
            "--r1",
            r1_path.to_str().unwrap(),
            "--output-prefix",
            output.to_str().unwrap(),
            "--gapped-index",
            gapped_path.to_str().unwrap(),
            "--minimizer-index",
            minimizer_path.to_str().unwrap(),
            "--microbial-index",
            microbial_path.to_str().unwrap(),
            "--profile",
            "microbiome",
            "--report",
            report.to_str().unwrap(),
            "--boundary-output",
            dir.join("boundary.fastq").to_str().unwrap(),
        ])
        .status()?;
    assert!(status.success());

    let removed = read_ids(&dir.join("output.remove.fastq"))?;
    let kept = read_ids(&dir.join("output.keep.fastq"))?;
    let boundary = read_ids(&dir.join("boundary.fastq"))?;
    assert_eq!(removed, vec!["host".to_string()]);
    assert_eq!(kept, vec!["microbe".to_string()]);
    assert!(boundary.is_empty());

    let report = fs::read_to_string(&report)?;
    assert!(report.contains("fused host evidence"));
    assert!(report.contains("microbial witness rescue"));

    fs::remove_dir_all(&dir).ok();
    Ok(())
}

#[test]
fn paired_smoke_keeps_mates_together() -> Result<()> {
    let dir = unique_dir("paired");
    let gapped_path = dir.join("gapped.hashes");
    let minimizer_path = dir.join("minimizer.hashes");
    let microbial_path = dir.join("microbial.hashes");
    let r1_path = dir.join("R1.fastq");
    let r2_path = dir.join("R2.fastq");
    let output = dir.join("output");

    // Reuse the SE host index material.
    let masks = vec![
        SeedMask::new(0b1_1111_1111_1001_1111_1111, 21).unwrap(),
        SeedMask::new(0b1_1011_0111_1011_0111_1011, 21).unwrap(),
    ];
    let mut gapped_hashes = Vec::new();
    for mask in &masks {
        for start in 0..=(HOST.len() - mask.length) {
            if let Some((hash, _)) = mask.hash_sequence(HOST, start) {
                gapped_hashes.push(hash);
            }
        }
    }
    write_hash_file(&gapped_path, &gapped_hashes)?;

    let k = 21;
    let mut hashes = Vec::new();
    for start in 0..=(HOST.len() - k) {
        let kmer = encode_bases(&HOST[start..start + k]).unwrap();
        hashes.push(wyhash(canonical_kmer(kmer, k)));
    }
    write_hash_file(&minimizer_path, &hashes)?;

    // Empty microbial witness means the host fragment is removed.
    write_hash_file(&microbial_path, &[])?;

    write_fastq(
        &r1_path,
        &[("pair_host_R1", HOST), ("pair_microbe_R1", MICROBE)],
    )?;
    write_fastq(
        &r2_path,
        &[("pair_host_R2", HOST), ("pair_microbe_R2", MICROBE)],
    )?;

    let status = Command::new(env!("CARGO_BIN_EXE_rustyclean-x"))
        .args([
            "--r1",
            r1_path.to_str().unwrap(),
            "--r2",
            r2_path.to_str().unwrap(),
            "--output-prefix",
            output.to_str().unwrap(),
            "--gapped-index",
            gapped_path.to_str().unwrap(),
            "--minimizer-index",
            minimizer_path.to_str().unwrap(),
            "--microbial-index",
            microbial_path.to_str().unwrap(),
            "--profile",
            "privacy",
            "--report",
            dir.join("report.tsv").to_str().unwrap(),
        ])
        .status()?;
    assert!(status.success());

    let removed = read_ids(&dir.join("output.remove.fastq"))?;
    let kept = read_ids(&dir.join("output.keep.fastq"))?;
    assert_eq!(
        removed,
        vec!["pair_host_R1".to_string(), "pair_host_R2".to_string()]
    );
    assert_eq!(
        kept,
        vec!["pair_microbe_R1".to_string(), "pair_microbe_R2".to_string()]
    );

    fs::remove_dir_all(&dir).ok();
    Ok(())
}
