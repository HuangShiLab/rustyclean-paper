# Fair Benchmark: RustyClean (AUTO + --skip-qc) vs Hostile

This benchmark compares **RustyClean** running in `AUTO` mode with `--skip-qc`
against **Hostile** running on the raw reads (no fastp QC), so both tools are
measured only on host-DNA removal time.

## Datasets

Four simulated metagenomes with different sizes and host-contamination levels:

| dataset | reads | host % | distribution | layout |
|---------|-------|--------|--------------|--------|
| 5M_1pct_low_even_SE | 5 M | 1 % | even | SE |
| 10M_10pct_med_even_SE | 10 M | 10 % | even | SE |
| 30M_50pct_high_skewed_SE | 30 M | 50 % | skewed | SE |
| 60M_90pct_high_lognormal_SE | 60 M | 90 % | log-normal | SE |

## Tools / versions

- RustyClean: compiled from `main` branch at `/lustre1/g/aos_shihuang/rustyclean/target/release`
- Hostile: `hostile-centrifuge` conda environment
- Host index: `/lustre1/g/aos_shihuang/databases/kneaddata/hg_39` (Bowtie2)
- Kraken2 DB (used by RustyClean AUTO when host % is high): `/lustre1/g/aos_shihuang/databases/kraken2/kraken16`

## Run

```bash
sbatch run_benchmark.sh
```

The SLURM script requests 1 node, 16 CPUs and 64 GB RAM on the `amd` partition.

## Output

- Per-dataset logs and timings: `/scr/u/shihuang/rustyclean-paper/rc_auto_skipqc_hostile_v2/`
- Aggregated metrics: `rc_auto_skipqc_hostile_metrics.csv`

Columns:

- `dataset`: simulated dataset name
- `tool`: `rustyclean_auto_skipqc` or `hostile_raw`
- `runtime_seconds`: wall-clock time in seconds
- `max_memory_kb`: peak resident memory in KB
- `output_size_bytes`: size of the cleaned R1 FASTQ
- `backend`: backend selected by RustyClean AUTO (`bowtie2` / `kraken2`) or `bowtie2` for Hostile
- `estimated_host_pct`: host percentage estimated by RustyClean AUTO survey (Hostile = `NA`)
- `timestamp`: ISO-8601 timestamp

## Notes

- RustyClean AUTO uses random subsampling (`--auto-survey`) of 100 k reads to
  estimate host percentage and then selects `bowtie2` for low-host samples and
  `kraken2` for high-host samples.
- The raw metrics file may contain ANSI escape sequences in the
  `backend`/`estimated_host_pct` fields because the RustyClean log is
  colourised. Use `clean_metrics.py` to strip them.
