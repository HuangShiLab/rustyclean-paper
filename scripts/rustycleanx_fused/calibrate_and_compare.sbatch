#!/bin/bash
#SBATCH --job-name=rcx_calibrate
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH --time=08:00:00
#SBATCH --output=/lustre1/g/aos_shihuang/rustyclean-paper/logs/rcx_calibrate-%j.out
#SBATCH --error=/lustre1/g/aos_shihuang/rustyclean-paper/logs/rcx_calibrate-%j.err

set -euo pipefail
REPO=/lustre1/g/aos_shihuang/rustyclean-paper
RUNROOT=$REPO/runs/rustycleanx_fused
OUT=$RUNROOT/calibration

TRAIN=(5M_1pct_low_even_SE 10M_10pct_med_even_SE 30M_50pct_high_skewed_SE)
VALID=(60M_90pct_high_lognormal_SE 100M_50pct_high_lognormal_SE 100M_90pct_high_lognormal_SE)

python3 "$REPO/scripts/rustycleanx_fused/calibrate_fused.py" \
  --run-root "$RUNROOT/full_runs" \
  --train-datasets "${TRAIN[@]}" \
  --validation-datasets "${VALID[@]}" \
  --outdir "$OUT" \
  --host-target-pct 0.05 \
  --sample-every 1000

python3 "$REPO/scripts/rustycleanx_fused/summarize_same_version.py" \
  --fused-root "$RUNROOT/full_runs" \
  --production-metrics "$REPO/runs/unresolved_controls/production_index_comparison/metrics" \
  --combined-accuracy "$REPO/runs/unresolved_controls/summary/combined_accuracy.csv" \
  --combined-performance "$REPO/runs/unresolved_controls/summary/combined_performance.csv" \
  --datasets 5M_1pct_low_even_SE 10M_10pct_med_even_SE 30M_50pct_high_skewed_SE 60M_90pct_high_lognormal_SE 100M_50pct_high_lognormal_SE 100M_90pct_high_lognormal_SE \
  --output "$REPO/runs/unresolved_controls/summary/rustycleanx_fused_same_version_summary.tsv"
