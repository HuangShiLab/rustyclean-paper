#!/bin/bash
# Some HKU SLURM batch wrappers fail before script execution for sourced RC
# runners; equivalent --wrap jobs execute reliably. All outputs stay under BASE.
set -euo pipefail
BASE=/lustre1/g/aos_shihuang/rustyclean-paper
mkdir -p "$BASE/logs"
COMMON=(
  --partition=amd --qos=normal --nodes=1 --ntasks=1
  --cpus-per-task=16 --mem=32G --time=24:00:00 --array=0-5
  --chdir="$BASE"
  --output="$BASE/logs/%x-%A_%a.out"
  --error="$BASE/logs/%x-%A_%a.err"
)
sbatch "${COMMON[@]}" --job-name=rc_always_recheck \
  --export=ALL,RESULTS_SUBDIR=always_recheck,THRESHOLDS=0.00,REPS=3 \
  --wrap="exec bash '$BASE/scripts/unresolved_controls/run_recheck_threshold_sweep.sh'"
sbatch "${COMMON[@]}" --job-name=rc_threshold_sweep \
  --export=ALL,RESULTS_SUBDIR=threshold_sweep,THRESHOLDS='0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.50 0.60 0.80 1.01',REPS=1 \
  --wrap="exec bash '$BASE/scripts/unresolved_controls/run_recheck_threshold_sweep.sh'"
