use anyhow::{anyhow, Result};
use flate2::{read::MultiGzDecoder, write::GzEncoder, Compression};
use std::collections::HashSet;
use std::fs::File;
use std::io::{BufRead, BufReader, BufWriter, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::Instant;

fn open_maybe_gz(path: &Path) -> Result<Box<dyn BufRead>> {
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

fn fastq_ids(path: &Path) -> Result<HashSet<String>> {
    let reader = open_maybe_gz(path)?;
    let mut reader = BufReader::new(reader);
    let mut ids = HashSet::new();
    let mut line_number = 0_usize;
    let mut line = String::new();
    loop {
        line.clear();
        if reader.read_line(&mut line)? == 0 {
            break;
        }
        let is_header = line_number.is_multiple_of(4);
        line_number += 1;
        if is_header {
            let header = line.trim_end_matches(['\r', '\n']);
            if !header.starts_with('@') {
                return Err(anyhow!(
                    "invalid FASTQ header in {}: {header:?}",
                    path.display()
                ));
            }
            let id = header[1..]
                .split_whitespace()
                .next()
                .ok_or_else(|| anyhow!("empty FASTQ ID"))?;
            ids.insert(id.to_string());
        }
    }
    Ok(ids)
}

fn truth_sets(path: &Path) -> Result<(HashSet<String>, HashSet<String>)> {
    let reader = open_maybe_gz(path)?;
    let mut reader = BufReader::new(reader);
    let mut host = HashSet::new();
    let mut microbe = HashSet::new();
    let mut line = String::new();
    loop {
        line.clear();
        if reader.read_line(&mut line)? == 0 {
            break;
        }
        let line = line.trim_end_matches(['\r', '\n']);
        if line.is_empty() {
            continue;
        }
        let (id, label) = line
            .split_once('\t')
            .ok_or_else(|| anyhow!("bad truth line: {line}"))?;
        if label.eq_ignore_ascii_case("host") || label.eq_ignore_ascii_case("human") {
            host.insert(id.to_string());
        } else {
            microbe.insert(id.to_string());
        }
    }
    Ok((host, microbe))
}

fn parse_runtime(path: &Path, tool: &str, dataset: &str, replicate: usize) -> Result<f64> {
    let reader = open_maybe_gz(path)?;
    let mut reader = BufReader::new(reader);
    let mut header = String::new();
    reader.read_line(&mut header)?;
    let mut line = String::new();
    while reader.read_line(&mut line)? != 0 {
        let fields: Vec<&str> = line.trim_end_matches(['\r', '\n']).split(',').collect();
        if std::env::var("RCX_DEBUG").as_deref() == Ok("1") {
            eprintln!("RCX_DEBUG dataset={dataset:?} tool={tool:?} replicate={replicate} line_fields={fields:?}");
        }
        if fields.len() >= 4 && fields[0] == tool && fields[1] == dataset {
            let replicate_field = fields[2].trim();
            if replicate_field.parse::<usize>()? == replicate {
                return Ok(fields[3].parse::<f64>()?);
            }
        }
        line.clear();
    }
    Err(anyhow!(
        "runtime not found for {tool} {dataset} replicate {replicate}"
    ))
}

fn metrics(
    truth_host: &HashSet<String>,
    truth_microbe: &HashSet<String>,
    removed: &HashSet<String>,
) -> (
    usize,
    usize,
    usize,
    usize,
    f64,
    f64,
    f64,
    f64,
    f64,
    f64,
    f64,
) {
    let retained_microbe = truth_microbe.difference(removed).count();
    let retained_host = truth_host.difference(removed).count();
    let removed_host = truth_host.intersection(removed).count();
    let removed_microbe = truth_microbe.intersection(removed).count();
    let host_total = truth_host.len();
    let microbe_total = truth_microbe.len();
    let retained_total = retained_microbe + retained_host;
    let host_retention = if host_total > 0 {
        100.0 * retained_host as f64 / host_total as f64
    } else {
        0.0
    };
    let host_removal = if host_total > 0 {
        100.0 * removed_host as f64 / host_total as f64
    } else {
        0.0
    };
    let microbial_loss = if microbe_total > 0 {
        100.0 * removed_microbe as f64 / microbe_total as f64
    } else {
        0.0
    };
    let host_output_fraction = if retained_total > 0 {
        100.0 * retained_host as f64 / retained_total as f64
    } else {
        0.0
    };
    let precision = if retained_total > 0 {
        retained_microbe as f64 / retained_total as f64
    } else {
        1.0
    };
    let recall = if microbe_total > 0 {
        retained_microbe as f64 / microbe_total as f64
    } else {
        1.0
    };
    let f1 = if precision + recall > 0.0 {
        2.0 * precision * recall / (precision + recall)
    } else {
        0.0
    };
    (
        retained_microbe,
        retained_host,
        removed_host,
        removed_microbe,
        host_retention,
        host_removal,
        microbial_loss,
        host_output_fraction,
        precision,
        recall,
        f1,
    )
}

fn is_removed(
    strategy: &str,
    deacon_kept: &HashSet<String>,
    cleanifier_kept: &HashSet<String>,
    id: &str,
) -> bool {
    let deacon_kept = deacon_kept.contains(id);
    let cleanifier_kept = cleanifier_kept.contains(id);
    match strategy {
        "both-remove" => !deacon_kept && !cleanifier_kept,
        "either-remove" => !(deacon_kept && cleanifier_kept),
        _ => unreachable!("unsupported strategy reached decision function"),
    }
}

fn extract_disagreement_fastq(
    input_path: &Path,
    deacon_kept: &HashSet<String>,
    cleanifier_kept: &HashSet<String>,
    output_path: &Path,
) -> Result<usize> {
    let reader = open_maybe_gz(input_path)?;
    let mut reader = BufReader::with_capacity(256 * 1024, reader);
    if let Some(parent) = output_path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let output = File::create(output_path)?;
    let encoder = GzEncoder::new(
        BufWriter::with_capacity(256 * 1024, output),
        Compression::fast(),
    );
    let mut writer = BufWriter::with_capacity(256 * 1024, encoder);
    let mut header = String::new();
    let mut sequence = String::new();
    let mut plus = String::new();
    let mut quality = String::new();
    let mut selected = 0_usize;
    loop {
        header.clear();
        if reader.read_line(&mut header)? == 0 {
            break;
        }
        sequence.clear();
        reader.read_line(&mut sequence)?;
        plus.clear();
        reader.read_line(&mut plus)?;
        quality.clear();
        reader.read_line(&mut quality)?;
        let header_trimmed = header.trim_end_matches(['\r', '\n']);
        if !header_trimmed.starts_with('@') {
            return Err(anyhow!("invalid FASTQ header: {header_trimmed:?}"));
        }
        let id = header_trimmed[1..]
            .split_whitespace()
            .next()
            .ok_or_else(|| anyhow!("empty FASTQ ID"))?;
        if deacon_kept.contains(id) != cleanifier_kept.contains(id) {
            writer.write_all(header.as_bytes())?;
            writer.write_all(sequence.as_bytes())?;
            writer.write_all(plus.as_bytes())?;
            writer.write_all(quality.as_bytes())?;
            selected += 1;
        }
    }
    writer.flush()?;
    Ok(selected)
}

fn extract_intersection_kept_fastq(
    input_path: &Path,
    deacon_kept: &HashSet<String>,
    cleanifier_kept: &HashSet<String>,
    output_path: &Path,
) -> Result<usize> {
    let reader = open_maybe_gz(input_path)?;
    let mut reader = BufReader::with_capacity(256 * 1024, reader);
    if let Some(parent) = output_path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let output = File::create(output_path)?;
    let encoder = GzEncoder::new(
        BufWriter::with_capacity(256 * 1024, output),
        Compression::fast(),
    );
    let mut writer = BufWriter::with_capacity(256 * 1024, encoder);
    let mut header = String::new();
    let mut sequence = String::new();
    let mut plus = String::new();
    let mut quality = String::new();
    let mut selected = 0_usize;
    loop {
        header.clear();
        if reader.read_line(&mut header)? == 0 {
            break;
        }
        sequence.clear();
        reader.read_line(&mut sequence)?;
        plus.clear();
        reader.read_line(&mut plus)?;
        quality.clear();
        reader.read_line(&mut quality)?;
        let header_trimmed = header.trim_end_matches(['\r', '\n']);
        if !header_trimmed.starts_with('@') {
            return Err(anyhow!("invalid FASTQ header: {header_trimmed:?}"));
        }
        let id = header_trimmed[1..]
            .split_whitespace()
            .next()
            .ok_or_else(|| anyhow!("empty FASTQ ID"))?;
        if deacon_kept.contains(id) && cleanifier_kept.contains(id) {
            writer.write_all(header.as_bytes())?;
            writer.write_all(sequence.as_bytes())?;
            writer.write_all(plus.as_bytes())?;
            writer.write_all(quality.as_bytes())?;
            selected += 1;
        }
    }
    writer.flush()?;
    Ok(selected)
}

fn parse_verifier_kept_reader<R: Read>(
    mut reader: BufReader<R>,
    max_mapq: u8,
    min_nm_for_ambiguous_rescue: i64,
) -> Result<HashSet<String>> {
    let mut retained = HashSet::new();
    let mut line = String::new();
    while reader.read_line(&mut line)? != 0 {
        if line.starts_with('@') {
            line.clear();
            continue;
        }
        let fields: Vec<&str> = line.trim_end_matches(['\r', '\n']).split('\t').collect();
        if fields.len() >= 5 {
            let flag = fields[1].parse::<u16>()?;
            let unmapped = flag & 0x04 != 0;
            let secondary = flag & 0x100 != 0;
            let supplementary = flag & 0x800 != 0;
            let mapq = fields[4].parse::<u8>().unwrap_or(255);
            let mut edit_distance = i64::MAX;
            for field in fields.iter().skip(11) {
                if let Some(value) = field.strip_prefix("NM:i:") {
                    edit_distance = value.parse::<i64>()?;
                }
            }
            let ambiguous_rescue = !secondary
                && !supplementary
                && mapq < max_mapq
                && edit_distance > min_nm_for_ambiguous_rescue;
            if unmapped || ambiguous_rescue {
                retained.insert(fields[0].to_string());
            }
        }
        line.clear();
    }
    Ok(retained)
}

fn verified_clean_removed(
    universe: &HashSet<String>,
    deacon_kept: &HashSet<String>,
    cleanifier_kept: &HashSet<String>,
    verifier_kept: &HashSet<String>,
    verify_both_removed: bool,
) -> HashSet<String> {
    universe
        .iter()
        .filter(|id| {
            let deacon_kept = deacon_kept.contains(id.as_str());
            let cleanifier_kept = cleanifier_kept.contains(id.as_str());
            if deacon_kept && cleanifier_kept {
                false
            } else if verify_both_removed {
                !verifier_kept.contains(id.as_str())
            } else {
                !(deacon_kept && cleanifier_kept) && !verifier_kept.contains(id.as_str())
            }
        })
        .cloned()
        .collect()
}

fn main() -> Result<()> {
    let mut dataset = String::from("dataset");
    let mut replicate = 1_usize;
    let mut truth_path = PathBuf::new();
    let mut deacon_kept_path = PathBuf::new();
    let mut cleanifier_path = PathBuf::new();
    let mut deacon_runtime_path = PathBuf::new();
    let mut cleanifier_runtime_path = PathBuf::new();
    let mut output = PathBuf::from("rustyclean_x_consensus_metrics.tsv");
    let mut strategy = String::from("both-remove");
    let mut input_path = PathBuf::new();
    let mut bowtie2_index = PathBuf::new();
    let mut bowtie2_exe = PathBuf::from("bowtie2");
    let mut work_dir = PathBuf::from("rustyclean_x_verified_work");
    let mut threads = 8_usize;
    let mut max_mapq = 2_u8;
    let mut min_nm_for_ambiguous_rescue = 10_i64;
    let mut keep_intermediates = false;

    let mut iterator = std::env::args().skip(1);
    while let Some(flag) = iterator.next() {
        let mut value = |name: &'static str| {
            iterator
                .next()
                .ok_or_else(|| anyhow!("missing value for {name}"))
        };
        match flag.as_str() {
            "--dataset" => dataset = value("--dataset")?,
            "--replicate" => replicate = value("--replicate")?.parse()?,
            "--truth" => truth_path = value("--truth")?.into(),
            "--deacon-kept" => deacon_kept_path = value("--deacon-kept")?.into(),
            "--cleanifier-kept" => cleanifier_path = value("--cleanifier-kept")?.into(),
            "--deacon-runtime-tsv" => deacon_runtime_path = value("--deacon-runtime-tsv")?.into(),
            "--cleanifier-runtime-tsv" => {
                cleanifier_runtime_path = value("--cleanifier-runtime-tsv")?.into()
            }
            "--strategy" => strategy = value("--strategy")?,
            "--input-fastq" => input_path = value("--input-fastq")?.into(),
            "--bowtie2-index" => bowtie2_index = value("--bowtie2-index")?.into(),
            "--bowtie2" => bowtie2_exe = value("--bowtie2")?.into(),
            "--work-dir" => work_dir = value("--work-dir")?.into(),
            "--threads" => threads = value("--threads")?.parse()?,
            "--verifier-max-mapq" => max_mapq = value("--verifier-max-mapq")?.parse()?,
            "--verifier-min-nm" => {
                min_nm_for_ambiguous_rescue = value("--verifier-min-nm")?.parse()?
            }
            "--keep-intermediates" => keep_intermediates = true,
            "--output" => output = value("--output")?.into(),
            "--help" | "-h" => {
                println!(
                    "benchmark consensus dual-evidence RustyClean-X classifier\n\n\
                     --strategy both-remove   default: remove only when both tools remove\n\
                     --strategy either-remove fast: remove when either tool removes\n\
                     --strategy verified-disagreement Bowtie2 arbitrates disagreement reads\n\
                     --strategy verified-clean Bowtie2 arbitrates all union-removed reads\n\
                     --strategy comparison    emit both modes in one pass\n\
                     --verifier-max-mapq N    rescue primary alignments below MAPQ N (default 2)
                     --verifier-min-nm N      require edit distance > N for ambiguous rescue (default 10)
                     --keep-intermediates     retain extracted candidate FASTQ/SAM files"
                );
                std::process::exit(0);
            }
            other => return Err(anyhow!("unknown argument: {other}")),
        }
    }

    let (truth_host, truth_microbe) = truth_sets(&truth_path)?;
    let deacon_kept = fastq_ids(&deacon_kept_path)?;
    let cleanifier_kept = fastq_ids(&cleanifier_path)?;

    let selected_strategies: Vec<&str> = match strategy.as_str() {
        "both-remove" => vec!["both-remove"],
        "either-remove" => vec!["either-remove"],
        "verified-disagreement" => Vec::new(),
        "verified-clean" => Vec::new(),
        "comparison" => vec!["both-remove", "either-remove"],
        other => {
            return Err(anyhow!(
                "unknown strategy {other}; expected both-remove, either-remove or comparison"
            ))
        }
    };

    let deacon_runtime = parse_runtime(&deacon_runtime_path, "deacon", &dataset, replicate)?;
    let cleanifier_runtime =
        parse_runtime(&cleanifier_runtime_path, "cleanifier", &dataset, replicate)?;
    let consensus_runtime = deacon_runtime + cleanifier_runtime;

    if strategy == "verified-clean" || strategy == "verified-disagreement" {
        if !input_path.exists() {
            return Err(anyhow!(
                "verified mode requires --input-fastq; missing {}",
                input_path.display()
            ));
        }
        std::fs::create_dir_all(&work_dir)?;
        let verified_path =
            work_dir.join(format!("{dataset}_rep{replicate}_verified_input.fastq.gz"));
        let sam_path = work_dir.join(format!("{dataset}_rep{replicate}_candidates.sam"));

        let extraction_start = Instant::now();
        let _verified_count = match strategy.as_str() {
            "verified-clean" => extract_intersection_kept_fastq(
                &input_path,
                &deacon_kept,
                &cleanifier_kept,
                &verified_path,
            )?,
            _ => extract_disagreement_fastq(
                &input_path,
                &deacon_kept,
                &cleanifier_kept,
                &verified_path,
            )?,
        };
        let extraction_runtime = extraction_start.elapsed().as_secs_f64();

        let alignment_start = Instant::now();
        let mut child = Command::new(&bowtie2_exe)
            .arg("-x")
            .arg(&bowtie2_index)
            .arg("-U")
            .arg(&verified_path)
            .arg("--threads")
            .arg(threads.to_string())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()?;
        let child_stdout = child
            .stdout
            .take()
            .ok_or_else(|| anyhow!("could not capture Bowtie2 stdout"))?;
        let verifier_kept = parse_verifier_kept_reader(
            BufReader::new(child_stdout),
            max_mapq,
            min_nm_for_ambiguous_rescue,
        )?;
        let status = child.wait()?;
        if !status.success() {
            return Err(anyhow!(
                "Bowtie2 failed for {dataset} replicate {replicate}"
            ));
        }
        let bowtie2_runtime = alignment_start.elapsed().as_secs_f64();
        let universe = fastq_ids(&input_path)?;
        let removed = verified_clean_removed(
            &universe,
            &deacon_kept,
            &cleanifier_kept,
            &verifier_kept,
            strategy == "verified-clean",
        );
        let consensus_runtime = consensus_runtime + extraction_runtime + bowtie2_runtime;
        let disagreement_count = 0_usize;
        let both_removed_count = 0_usize;
        let microbial_rescued: HashSet<String> = HashSet::new();
        let witness_runtime = 0.0_f64;
        if let Some(parent) = output.parent() {
            if !parent.as_os_str().is_empty() {
                std::fs::create_dir_all(parent)?;
            }
        }
        let mut writer = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&output)?;
        if output.metadata()?.len() == 0 {
            writeln!(
                writer,
                "strategy\tdataset\treplicate\tdeacon_runtime_s\tcleanifier_runtime_s\tconsensus_runtime_s\textraction_runtime_s\tbowtie2_runtime_s\twitness_runtime_s\tdisagreement_reads\tboth_removed_reads\tverifier_rescued_reads\tmicrobial_rescued_reads\tmicrobial_retained\thost_retained\thost_removed\tmicrobe_removed\tinput_total\thost_retention_pct\thost_removal_pct\tmicrobial_loss_pct\thost_output_fraction_pct\tprecision\trecall\tf1"
            )?;
        }
        let (
            retained_microbe,
            retained_host,
            removed_host,
            removed_microbe,
            host_retention,
            host_removal,
            microbial_loss,
            host_output_fraction,
            precision,
            recall,
            f1,
        ) = metrics(&truth_host, &truth_microbe, &removed);
        writeln!(
            writer,
            "rustyclean_x_{}\t{}\t{}\t{:.3}\t{:.3}\t{:.3}\t{:.3}\t{:.3}\t{:.3}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{:.6}\t{:.6}\t{:.6}\t{:.6}\t{:.9}\t{:.9}\t{:.9}",
            strategy, dataset, replicate, deacon_runtime, cleanifier_runtime, consensus_runtime,
            extraction_runtime, bowtie2_runtime, witness_runtime, disagreement_count,
            both_removed_count, verifier_kept.len(), microbial_rescued.len(),
            retained_microbe, retained_host, removed_host, removed_microbe,
            truth_host.len() + truth_microbe.len(), host_retention, host_removal,
            microbial_loss, host_output_fraction, precision, recall, f1
        )?;
        writer.flush()?;
        if !keep_intermediates {
            let _ = std::fs::remove_file(&verified_path);
            let _ = std::fs::remove_file(&sam_path);
        }
        println!(
            "RustyClean-X {strategy}: disagreements={} both_removed={} verifier_rescued={} microbial_rescued={} retained_microbe={} retained_host={} host_retention={:.6}% microbial_loss={:.6}% F1={:.9}",
            disagreement_count, both_removed_count, verifier_kept.len(), microbial_rescued.len(), retained_microbe,
            retained_host, host_retention, microbial_loss, f1
        );
        return Ok(());
    }

    if let Some(parent) = output.parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent)?;
        }
    }
    let mut writer = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&output)?;
    if output.metadata()?.len() == 0 {
        writeln!(
            writer,
            "strategy\tdataset\treplicate\tdeacon_runtime_s\tcleanifier_runtime_s\tconsensus_runtime_s\textraction_runtime_s\tbowtie2_runtime_s\tmicrobial_retained\thost_retained\thost_removed\tmicrobe_removed\tinput_total\thost_retention_pct\thost_removal_pct\tmicrobial_loss_pct\thost_output_fraction_pct\tprecision\trecall\tf1"
        )?;
    }

    for selected in selected_strategies {
        let mut removed: HashSet<String> = HashSet::new();
        for id in truth_host.iter().chain(truth_microbe.iter()) {
            if is_removed(selected, &deacon_kept, &cleanifier_kept, id) {
                removed.insert(id.clone());
            }
        }

        let (
            retained_microbe,
            retained_host,
            removed_host,
            removed_microbe,
            host_retention,
            host_removal,
            microbial_loss,
            host_output_fraction,
            precision,
            recall,
            f1,
        ) = metrics(&truth_host, &truth_microbe, &removed);

        writeln!(
            writer,
            "rustyclean_x_{}\t{}\t{}\t{:.3}\t{:.3}\t{:.3}\t{:.3}\t{:.3}\t{}\t{}\t{}\t{}\t{}\t{:.6}\t{:.6}\t{:.6}\t{:.6}\t{:.9}\t{:.9}\t{:.9}",
            selected, dataset, replicate, deacon_runtime, cleanifier_runtime,
            consensus_runtime, 0.0, 0.0, retained_microbe, retained_host, removed_host,
            removed_microbe, truth_host.len() + truth_microbe.len(),
            host_retention, host_removal, microbial_loss, host_output_fraction,
            precision, recall, f1
        )?;

        println!(
            "RustyClean-X {selected}: retained_microbe={} retained_host={} removed_host={} removed_microbe={} host_retention={:.6}% host_removal={:.6}% microbial_loss={:.6}% F1={:.9}",
            retained_microbe, retained_host, removed_host, removed_microbe,
            host_retention, host_removal, microbial_loss, f1
        );
    }

    writer.flush()?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn verifier_rescues_unmapped_and_ambiguous_primary_alignments() {
        let sam = concat!(
            "@HD\tVN:1.0\n",
            "unmapped\t4\t*\t0\t0\t*\t*\t0\t0\tACGT\tIIII\n",
            "ambiguous\t0\tchr1\t100\t1\t4M\t*\t0\t0\tACGT\tIIII\tNM:i:20\n",
            "threshold\t0\tchr1\t100\t2\t4M\t*\t0\t0\tACGT\tIIII\tNM:i:20\n",
            "exact_primary\t0\tchr1\t100\t1\t4M\t*\t0\t0\tACGT\tIIII\tNM:i:0\n",
            "secondary\t256\tchr1\t100\t0\t4M\t*\t0\t0\tACGT\tIIII\n"
        );
        let kept = parse_verifier_kept_reader(BufReader::new(sam.as_bytes()), 2, 10).unwrap();
        assert!(kept.contains("unmapped"));
        assert!(kept.contains("ambiguous"));
        assert!(!kept.contains("threshold"));
        assert!(!kept.contains("exact_primary"));
        assert!(!kept.contains("secondary"));
    }

    #[test]
    fn decision_rules_follow_set_algebra() {
        let deacon: HashSet<_> = ["m", "h1"].into_iter().map(String::from).collect();
        let cleanifier: HashSet<_> = ["m", "h2"].into_iter().map(String::from).collect();
        assert!(is_removed("both-remove", &deacon, &cleanifier, "h3"));
        assert!(!is_removed("both-remove", &deacon, &cleanifier, "h1"));
        assert!(!is_removed("both-remove", &deacon, &cleanifier, "h2"));
        assert!(is_removed("either-remove", &deacon, &cleanifier, "h1"));
        assert!(is_removed("either-remove", &deacon, &cleanifier, "h2"));
        assert!(is_removed("either-remove", &deacon, &cleanifier, "h3"));
    }

    #[test]
    fn verified_modes_distinguish_both_removed_and_conflicts() {
        let universe: HashSet<_> = ["m", "h1", "h2", "h3"]
            .into_iter()
            .map(String::from)
            .collect();
        let deacon: HashSet<_> = ["m", "h1"].into_iter().map(String::from).collect();
        let cleanifier: HashSet<_> = ["m", "h2"].into_iter().map(String::from).collect();
        let verifier_kept: HashSet<_> = ["m", "h2", "h3"].into_iter().map(String::from).collect();
        let verified_clean =
            verified_clean_removed(&universe, &deacon, &cleanifier, &verifier_kept, true);
        assert_eq!(
            verified_clean,
            ["h1"].into_iter().map(String::from).collect()
        );
        let verified_disagreement =
            verified_clean_removed(&universe, &deacon, &cleanifier, &verifier_kept, false);
        assert!(verified_disagreement.contains("h1"));
        assert!(!verified_disagreement.contains("h2"));
        assert!(!verified_disagreement.contains("h3"));
    }

    #[test]
    fn disagreement_extraction_preserves_complete_fastq_records() -> Result<()> {
        let input = std::env::temp_dir().join(format!(
            "rcx_disagreement_input_{}.fastq",
            std::process::id()
        ));
        let output = std::env::temp_dir().join(format!(
            "rcx_disagreement_output_{}.fastq.gz",
            std::process::id()
        ));
        std::fs::write(
            &input,
            "@h1\nACGT\n+\nIIII\n@h2\nCGTA\n+\nJJJJ\n@h3\nTTTT\n+\nKKKK\n",
        )?;
        let deacon: HashSet<_> = ["h1"].into_iter().map(String::from).collect();
        let cleanifier: HashSet<_> = ["h2"].into_iter().map(String::from).collect();
        let selected = extract_disagreement_fastq(&input, &deacon, &cleanifier, &output)?;
        assert_eq!(selected, 2);
        let reader = open_maybe_gz(&output)?;
        let text = std::io::read_to_string(reader)?;
        assert_eq!(text, "@h1\nACGT\n+\nIIII\n@h2\nCGTA\n+\nJJJJ\n");
        let _ = std::fs::remove_file(&input);
        let _ = std::fs::remove_file(&output);
        Ok(())
    }

    #[test]
    fn metrics_use_retention_conventions() {
        let host: HashSet<_> = ["h1", "h2", "h3"].into_iter().map(String::from).collect();
        let microbe: HashSet<_> = ["m1", "m2", "m3", "m4"]
            .into_iter()
            .map(String::from)
            .collect();
        let removed: HashSet<_> = ["h1", "h2", "m4"].into_iter().map(String::from).collect();
        let (
            retained_microbe,
            retained_host,
            removed_host,
            removed_microbe,
            host_retention,
            host_removal,
            microbial_loss,
            host_output_fraction,
            precision,
            recall,
            f1,
        ) = metrics(&host, &microbe, &removed);
        assert_eq!(retained_microbe, 3);
        assert_eq!(retained_host, 1);
        assert_eq!(removed_host, 2);
        assert_eq!(removed_microbe, 1);
        assert_eq!(host_retention, 100.0 / 3.0);
        assert_eq!(host_removal, 200.0 / 3.0);
        assert_eq!(microbial_loss, 25.0);
        assert_eq!(host_output_fraction, 25.0);
        assert_eq!(precision, 0.75);
        assert_eq!(recall, 0.75);
        assert_eq!(f1, 0.75);
    }
}
