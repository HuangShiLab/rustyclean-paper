# Bowtie2 re-check benchmark

This directory contains the scripts and results used to evaluate the optional
Bowtie2 re-check step in RustyClean.

## What is being tested

When RustyClean uses Kraken2 as the host-removal backend, some true host reads
may be reported as "unclassified" by Kraken2 (especially with a small or
host-only database). The Bowtie2 re-check step takes these unclassified reads
and aligns them against a Bowtie2 host index, removing any additional host
reads found.

The benchmark compares two configurations on high-host simulated metagenomes:

1. **baseline_kraken2_memmap**: Kraken2 with `--memory-mapping`, no Bowtie2 re-check.
2. **bowtie2_recheck_v2**: Kraken2 with `--memory-mapping` + Bowtie2 re-check of
   unclassified reads.

Both use `--host-removal-mode auto --auto-survey` so that the backend is chosen
automatically based on a light-weight Bowtie2 survey of the input.

## Files

- `scripts/benchmark_baseline_kraken2_memmap.sh` — SLURM benchmark script for the baseline.
- `scripts/benchmark_bowtie2_recheck_v2.sh` — SLURM benchmark script with `--bowtie2-recheck`.
- `scripts/run_accuracy_baseline_k2.sh` — SLURM wrapper to compute accuracy for the baseline.
- `scripts/run_accuracy_bowtie2_recheck_v2.sh` — SLURM wrapper to compute accuracy for the recheck run.
- `scripts/compute_accuracy_baseline_k2.py` — Accuracy computation for the baseline results.
- `scripts/compute_accuracy_bowtie2_recheck_v2.py` — Accuracy computation for the recheck results.
- `scripts/compare_bowtie2_recheck.py` — Generates F1 and runtime comparison figures.
- `scripts/reparse_bowtie2_recheck_times.sh` — Helper to re-parse GNU `time -v` logs if the initial CSV parser misread the elapsed time.
- `results/accuracy_*.csv` — Per-read accuracy metrics (accuracy, precision, recall, F1).
- `results/performance_*.csv` — Runtime and peak memory.
- `results/f1_comparison.png` — F1 comparison across datasets.
- `results/runtime_comparison.png` — Runtime comparison across datasets.

## Key findings

| Dataset | Host % | Baseline F1 | +Bowtie2 re-check F1 | ΔF1 | Runtime overhead |
|---|---|---|---|---|---|
| 30M_50pct_high_skewed_SE | 50% | 0.9890 | 0.9974 | +0.0084 | ~+5.7% |
| 60M_90pct_high_lognormal_SE | 90% | 0.9299 | 0.9942 | +0.0643 | ~+20.3% |
| 100M_50pct_high_lognormal_SE | 50% | 0.9912 | 0.9976 | +0.0064 | ~0% |
| 100M_90pct_high_lognormal_SE | 90% | 0.9299 | 0.9943 | +0.0644 | ~+1.3% |

- The largest accuracy gain is observed for **90% host** samples, where Kraken2
  alone leaves many host reads unclassified.
- Runtime overhead is modest and can be negative for very large samples because
  Bowtie2 re-check removes additional host reads before downstream processing.
- Peak memory remains essentially unchanged (~15.5 GB), dominated by the
  Kraken2 database.

## Implementation note

Starting from the code in the `bowtie2-recheck` branch, Bowtie2 re-check is
**automatically enabled in auto mode when the surveyed host fraction exceeds
 the high threshold** (default 30%). Users can still force it on or off with
`--bowtie2-recheck`.
