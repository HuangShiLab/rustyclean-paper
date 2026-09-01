#!/bin/bash
# =============================================================================
# RustyClean Benchmark — Single Dataset × Replicate Runner
# =============================================================================
# This script is called by run_benchmark_slurm.sh for each array task.
# It runs both RustyClean and KneadData on one dataset/replicate pair.
#
# Usage:
#   bash run_single_benchmark.sh <dataset_name> <rep>

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

DATASET="$1"
REP="$2"

DATASET_DIR="$DATA_DIR/$DATASET"

if [ ! -d "$DATASET_DIR" ]; then
    echo "ERROR: Dataset directory not found: $DATASET_DIR" >&2
    exit 1
fi

if [ ! -f "$DATASET_DIR/completed.flag" ]; then
    echo "ERROR: Dataset not completed: $DATASET" >&2
    exit 1
fi

mkdir -p "$RESULTS_DIR"/rustyclean "$RESULTS_DIR"/kneaddata
mkdir -p "$RESULTS_DIR/logs" "$RESULTS_DIR/metrics"

# Initialize metrics CSV once per invocation (caller should handle header)
PERF_CSV="$RESULTS_DIR/metrics/performance.csv"
SIZE_CSV="$RESULTS_DIR/metrics/file_sizes.csv"

# Activate conda
activate_conda

# Resolve tools
RUSTYCLEAN_BIN=$(resolve_tool "$RUSTYCLEAN" "rustyclean")
KNEADDATA_BIN=$(resolve_tool "$KNEADDATA" "kneaddata")

# Detect read mode and input files
if [ -f "$DATASET_DIR/reads_R1.fastq.gz" ]; then
    PE=true
    R1="$DATASET_DIR/reads_R1.fastq.gz"
    R2="$DATASET_DIR/reads_R2.fastq.gz"
else
    PE=false
    R1="$DATASET_DIR/reads.fastq.gz"
    R2=""
fi

# Local scratch for this task
WORKDIR="$LOCAL_SCRATCH/bench_${DATASET}_rep${REP}"
mkdir -p "$WORKDIR"

# ---------------------------------------------------------------------------
# Run tool with time/memory measurement
# ---------------------------------------------------------------------------
run_tool() {
    local tool="$1"
    local cmd="$2"
    local out_dir="$3"

    local logfile="$RESULTS_DIR/logs/${tool}_${DATASET}_rep${REP}.log"
    local timefile="$RESULTS_DIR/logs/${tool}_${DATASET}_rep${REP}.time"

    echo "  Running $tool on $DATASET (rep $REP)..."

    mkdir -p "$out_dir"

    if /usr/bin/time -v echo "" >/dev/null 2>&1; then
        /usr/bin/time -v -o "$timefile" bash -c "$cmd" > "$logfile" 2>&1
    else
        echo "WARNING: GNU time not available; using built-in time" >&2
        { time bash -c "$cmd"; } > "$logfile" 2>&1
    fi

    local runtime="unknown"
    local max_mem="unknown"
    if [ -f "$timefile" ]; then
        runtime=$(grep "Elapsed (wall clock) time" "$timefile" | sed -n 's/.*Elapsed (wall clock) time.*: //p' || echo "unknown")
        max_mem=$(grep "Maximum resident set size" "$timefile" | sed -n 's/.*Maximum resident set size (kbytes): //p' || echo "unknown")
    fi

    echo "$tool,$DATASET,$REP,$runtime,$max_mem,$(date -Iseconds)" >> "$PERF_CSV"
    echo "    $tool: runtime=$runtime, max_mem=$max_mem"
}

# ---------------------------------------------------------------------------
# RustyClean
# ---------------------------------------------------------------------------
RC_OUT="$RESULTS_DIR/rustyclean/${DATASET}_rep${REP}"

if [ "$PE" = true ]; then
    RC_CMD="$RUSTYCLEAN_BIN --r1 $R1 --r2 $R2 --kraken2-db $KRAKEN2_DB -o $RC_OUT -t $N_THREADS"
else
    RC_CMD="$RUSTYCLEAN_BIN --r1 $R1 --kraken2-db $KRAKEN2_DB -o $RC_OUT -t $N_THREADS"
fi

run_tool "rustyclean" "$RC_CMD" "$RC_OUT"

RC_OUTPUT_SIZE=$(find "$RC_OUT" -name "*.fastq.gz" -exec du -cb {} + 2>/dev/null | tail -1 | cut -f1 || echo "0")
echo "rustyclean,$DATASET,$REP,output_size,$RC_OUTPUT_SIZE" >> "$SIZE_CSV"

# ---------------------------------------------------------------------------
# KneadData
# ---------------------------------------------------------------------------
KD_OUT="$RESULTS_DIR/kneaddata/${DATASET}_rep${REP}"
mkdir -p "$KD_OUT"

if [ "$PE" = true ]; then
    KD_CMD="$KNEADDATA_BIN --input1 $R1 --input2 $R2 --output-prefix clean --reference-db $KNEADDATA_DB --threads $N_THREADS --output $KD_OUT"
else
    KD_CMD="$KNEADDATA_BIN --unpaired $R1 --output-prefix clean --reference-db $KNEADDATA_DB --threads $N_THREADS --output $KD_OUT"
fi

run_tool "kneaddata" "$KD_CMD" "$KD_OUT"

KD_OUTPUT_SIZE=$(find "$KD_OUT" -name "*.fastq*" -exec du -cb {} + 2>/dev/null | tail -1 | cut -f1 || echo "0")
echo "kneaddata,$DATASET,$REP,output_size,$KD_OUTPUT_SIZE" >> "$SIZE_CSV"

# Clean up local scratch
rm -rf "$WORKDIR"

echo "Completed $DATASET rep $REP"
