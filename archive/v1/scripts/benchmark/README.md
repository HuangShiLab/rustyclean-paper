# Benchmark: RustyClean AUTO (with QC) vs KneadData

This benchmark compares the **full pipelines** of RustyClean and KneadData on
simulated metagenomes:

- **RustyClean AUTO**: `fastp` QC + adaptive host-removal (`bowtie2` for low host
  fraction, `kraken2` for high host fraction).
- **KneadData**: `Trimmomatic` QC + `Bowtie2` host removal.

This is **not** the `--skip-qc` / raw-reads comparison; both tools perform QC
and host removal.

## Datasets

Four simulated metagenomes spanning different sizes and host-contamination
levels:

| dataset | reads | host % | distribution | layout |
|---------|-------|--------|--------------|--------|
| 5M_1pct_low_even_SE | 5 M | 1 % | even | SE |
| 10M_10pct_med_even_SE | 10 M | 10 % | even | SE |
| 30M_50pct_high_skewed_SE | 30 M | 50 % | skewed | SE |
| 60M_90pct_high_lognormal_SE | 60 M | 90 % | log-normal | SE |

## Tools / versions

- RustyClean: compiled from `main` branch at `/lustre1/g/aos_shihuang/rustyclean/target/release`
- KneadData: `/group/aos_shihuang/conda/envs/kneaddata/bin/kneaddata`
- Host index (Bowtie2): `/lustre1/g/aos_shihuang/databases/kneaddata/hg_39`
- Kraken2 DB: `/lustre1/g/aos_shihuang/databases/kraken2/kraken16`

## Run

```bash
sbatch run_benchmark.sh
```

The SLURM script requests 1 node, 16 CPUs and 64 GB RAM on the `amd` partition
for 24 h.

## Output

- Per-dataset logs and timings: `/scr/u/shihuang/rustyclean-paper/auto_vs_kneaddata/`
- Aggregated metrics: `auto_vs_kneaddata_metrics.csv`

Columns:

- `dataset`: simulated dataset name
- `tool`: `rustyclean_auto` or `kneaddata`
- `runtime_seconds`: wall-clock time in seconds (GNU `time -v`)
- `max_memory_kb`: peak resident memory in KB (GNU `time -v`)
- `output_size_bytes`: size of the final cleaned SE FASTQ file
- `backend`: backend selected by RustyClean AUTO (`bowtie2` / `kraken2`), or
  `bowtie2` for KneadData
- `estimated_host_pct`: host percentage estimated by RustyClean AUTO survey
- `timestamp`: ISO-8601 timestamp

## Notes

- RustyClean AUTO uses random subsampling (`--auto-survey`) of 100 k reads to
  estimate host percentage and then selects `bowtie2` for low-host samples and
  `kraken2` for high-host samples.
- KneadData produces uncompressed FASTQ output, whereas RustyClean produces
  gzip-compressed FASTQ. The `output_size_bytes` values are therefore not
  directly comparable; they are recorded for completeness.
- Each dataset uses an isolated `--checkpoint-dir` so that RustyClean does not
  accidentally resume from a previous run.
