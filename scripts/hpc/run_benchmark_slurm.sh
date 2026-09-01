#!/bin/bash
#SBATCH --job-name=rustyclean_benchmark
#SBATCH --output=logs/%x-%A_%a.out
#SBATCH --error=logs/%x-%A_%a.err
#SBATCH --array=1-54%12
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --partition=amd

# =============================================================================
# RustyClean Benchmark — Main SLURM Array Job
# =============================================================================
# Runs RustyClean and KneadData for one dataset/replicate pair per task.
#
# Default array size: 18 datasets × 3 replicates = 54 tasks.
# Adjust --array and --cpus-per-task for your cluster.
# Use --dependency after data generation completes, e.g.:
#   sbatch --dependency=afterok:<generate_job_id> scripts/hpc/run_benchmark_slurm.sh

set -euo pipefail

PROJECT_DIR="/lustre1/g/aos_shihuang/rustyclean-paper"
cd "$PROJECT_DIR"
# Locate the repository. SLURM copies the batch script to a spool directory, so
# $0 does not point into the repo under sbatch, and config.sh cannot be found via
# a variable that config.sh itself defines.
if [ -z "${REPO_DIR:-}" ]; then
    for _cand in "${SLURM_SUBMIT_DIR:-}" \
                 "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)" \
                 /lustre1/g/aos_shihuang/rustyclean-paper; do
        if [ -n "$_cand" ] && [ -f "$_cand/scripts/hpc/config.sh" ]; then
            REPO_DIR="$_cand"; break
        fi
    done
fi
if [ -z "${REPO_DIR:-}" ]; then
    echo "ERROR: cannot locate the repository. Set REPO_DIR to its path." >&2
    exit 1
fi
source "$REPO_DIR/scripts/hpc/config.sh"

# Activate conda
activate_conda

mkdir -p "$RESULTS_DIR/logs" "$RESULTS_DIR/metrics"

# Initialize CSVs with headers (atomic to avoid race conditions in array)
PERF_CSV="$RESULTS_DIR/metrics/performance.csv"
SIZE_CSV="$RESULTS_DIR/metrics/file_sizes.csv"

if [ ! -f "$PERF_CSV" ]; then
    echo "tool,dataset,rep,runtime_seconds,max_memory_kb,timestamp" > "$PERF_CSV"
fi
if [ ! -f "$SIZE_CSV" ]; then
    echo "tool,dataset,rep,metric,value" > "$SIZE_CSV"
fi

# ---------------------------------------------------------------------------
# Map array task to dataset/replicate
# ---------------------------------------------------------------------------
DATASETS=(
    5M_1pct_low_even_SE 5M_5pct_low_even_SE
    10M_1pct_med_lognormal_SE 10M_5pct_med_lognormal_SE
    10M_10pct_med_even_SE 10M_30pct_med_lognormal_SE
    20M_50pct_med_lognormal_PE 30M_50pct_high_skewed_SE
    30M_70pct_med_lognormal_SE 30M_90pct_med_lognormal_SE
    60M_90pct_high_lognormal_SE 60M_99pct_med_lognormal_SE
    100M_50pct_high_lognormal_SE 100M_90pct_high_lognormal_SE
    20M_10pct_med_even_PE 20M_50pct_med_lognormal_PE 20M_90pct_med_lognormal_PE
    10M_0pct_med_lognormal_SE 10M_100pct_med_lognormal_SE
)

N_DATASETS=${#DATASETS[@]}
N_REPS=3

TASK_ID=${SLURM_ARRAY_TASK_ID:-1}
TASK_INDEX=$((TASK_ID - 1))

DATASET_INDEX=$((TASK_INDEX / N_REPS))
REP=$((TASK_INDEX % N_REPS + 1))
DATASET="${DATASETS[$DATASET_INDEX]}"

echo "Task $TASK_ID -> Dataset: $DATASET, Replicate: $REP"

# Run the single benchmark
bash "$SCRIPT_DIR/run_single_benchmark.sh" "$DATASET" "$REP"
