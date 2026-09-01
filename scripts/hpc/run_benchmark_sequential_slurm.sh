#!/bin/bash
#SBATCH --job-name=rustyclean_benchmark_all
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=168:00:00
#SBATCH --partition=amd

# =============================================================================
# RustyClean Benchmark — Sequential All-in-One SLURM Job
# =============================================================================
# Runs RustyClean and KneadData for all datasets × replicates sequentially
# in a single job. Useful when job submission limits are restrictive.

set -euo pipefail

PROJECT_DIR="/lustre1/g/aos_shihuang/rustyclean-paper"
SCRATCH_DIR="/scr/u/shihuang/rustyclean-paper"
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

activate_conda

mkdir -p "$RESULTS_DIR"/rustyclean "$RESULTS_DIR"/kneaddata
mkdir -p "$RESULTS_DIR/logs" "$RESULTS_DIR/metrics"

# Run tools from the scratch results directory so any default temp/checkpoint
# files are written to the same filesystem as the outputs (avoids cross-device
# rename/hardlink errors).
cd "$RESULTS_DIR"
export TMPDIR="$RESULTS_DIR/.tmp"
mkdir -p "$TMPDIR"

# Initialize CSVs (preserve existing progress)
PERF_CSV="$RESULTS_DIR/metrics/performance.csv"
SIZE_CSV="$RESULTS_DIR/metrics/file_sizes.csv"
if [ ! -f "$PERF_CSV" ]; then
    echo "tool,dataset,rep,runtime_seconds,max_memory_kb,timestamp" > "$PERF_CSV"
fi
if [ ! -f "$SIZE_CSV" ]; then
    echo "tool,dataset,rep,metric,value" > "$SIZE_CSV"
fi

record_exists() {
    local tool="$1"
    local dataset="$2"
    local rep="$3"
    awk -F, -v t="$tool" -v d="$dataset" -v r="$rep" '
        NR > 1 && $1 == t && $2 == d && $3 == r { found=1; exit }
        END { exit found ? 0 : 1 }
    ' "$PERF_CSV" 2>/dev/null
}

rustyclean_output_exists() {
    local out_dir="$1"
    [ -d "$out_dir" ] && find "$out_dir" -name "*.fastq.gz" -print -quit 2>/dev/null | grep -q .
}

kneaddata_output_exists() {
    local out_dir="$1"
    [ -d "$out_dir" ] && find "$out_dir" \( -name "*clean*.fastq*" ! -name "*contam*" ! -name "*trim*" \) -print -quit 2>/dev/null | grep -q .
}

remove_perf_record() {
    local tool="$1" dataset="$2" rep="$3"
    local tmp="${PERF_CSV}.tmp"
    awk -F, -v t="$tool" -v d="$dataset" -v r="$rep" 'NR==1 || !($1==t && $2==d && $3==r)' "$PERF_CSV" > "$tmp" && mv "$tmp" "$PERF_CSV"
}

remove_size_record() {
    local tool="$1" dataset="$2" rep="$3"
    local tmp="${SIZE_CSV}.tmp"
    awk -F, -v t="$tool" -v d="$dataset" -v r="$rep" 'NR==1 || !($1==t && $2==d && $3==r)' "$SIZE_CSV" > "$tmp" && mv "$tmp" "$SIZE_CSV"
}

cleanup_rustyclean_checkpoints() {
    local out_dir="$1"
    if [ -d "$out_dir/.checkpoints" ]; then
        rm -rf "$out_dir/.checkpoints"
        echo "    Removed RustyClean checkpoints to save space."
    fi
}

cleanup_kneaddata_intermediates() {
    local out_dir="$1"
    find "$out_dir" -type f \
        \( -name "reformatted_identifiers*" \
        -o -name "decompressed_*_reads" \
        -o -name "clean.trimmed*.fastq" \
        -o -name "clean.repeats.removed*.fastq" \
        -o -name "*contam.fastq" \
        \) -delete 2>/dev/null || true
    echo "    Removed KneadData intermediate files."
}

# Resolve tools
RUSTYCLEAN_BIN=$(resolve_tool "$RUSTYCLEAN" "rustyclean")
KNEADDATA_BIN=$(resolve_tool "$KNEADDATA" "kneaddata")

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

N_REPS=3

run_tool() {
    local tool="$1"
    local dataset="$2"
    local rep="$3"
    local cmd="$4"
    local out_dir="$5"

    local logfile="$RESULTS_DIR/logs/${tool}_${dataset}_rep${rep}.log"
    local timefile="$RESULTS_DIR/logs/${tool}_${dataset}_rep${rep}.time"

    echo "  Running $tool on $dataset (rep $rep)..."
    mkdir -p "$out_dir"

    if /usr/bin/time -v echo "" >/dev/null 2>&1; then
        /usr/bin/time -v -o "$timefile" bash -c "$cmd" > "$logfile" 2>&1
    else
        echo "WARNING: GNU time not available" >&2
        { time bash -c "$cmd"; } > "$logfile" 2>&1
    fi

    local runtime="unknown"
    local max_mem="unknown"
    if [ -f "$timefile" ]; then
        runtime=$(grep "Elapsed (wall clock) time" "$timefile" | sed -n 's/.*Elapsed (wall clock) time.*: //p' || echo "unknown")
        max_mem=$(grep "Maximum resident set size" "$timefile" | sed -n 's/.*Maximum resident set size (kbytes): //p' || echo "unknown")
    fi

    echo "$tool,$dataset,$rep,$runtime,$max_mem,$(date -Iseconds)" >> "$PERF_CSV"
    echo "    Done: runtime=$runtime, max_mem=$max_mem"
}

for dataset in "${DATASETS[@]}"; do
    DATASET_DIR="$DATA_DIR/$dataset"

    if [ ! -f "$DATASET_DIR/completed.flag" ]; then
        echo "WARNING: Dataset $dataset not completed. Skipping."
        continue
    fi

    # Detect read mode
    if [ -f "$DATASET_DIR/reads_R1.fastq.gz" ]; then
        R1="$DATASET_DIR/reads_R1.fastq.gz"
        R2="$DATASET_DIR/reads_R2.fastq.gz"
        PE=true
    else
        R1="$DATASET_DIR/reads.fastq.gz"
        R2=""
        PE=false
    fi

    for rep in $(seq 1 $N_REPS); do
        echo "=== Dataset: $dataset | Rep: $rep ==="

        # RustyClean
        RC_OUT="$RESULTS_DIR/rustyclean/${dataset}_rep${rep}"
        if record_exists "rustyclean" "$dataset" "$rep" && rustyclean_output_exists "$RC_OUT"; then
            echo "  Skipping rustyclean on $dataset (rep $rep) — output present."
        else
            if record_exists "rustyclean" "$dataset" "$rep"; then
                echo "  Stale rustyclean record for $dataset (rep $rep); removing old metrics and rerunning."
                remove_perf_record "rustyclean" "$dataset" "$rep"
                remove_size_record "rustyclean" "$dataset" "$rep"
            fi
            if [ "$PE" = true ]; then
                RC_CMD="$RUSTYCLEAN_BIN --r1 $R1 --r2 $R2 --kraken2-db $KRAKEN2_DB -o $RC_OUT -t $N_THREADS --checkpoint-dir $RC_OUT/.checkpoints --resume"
            else
                RC_CMD="$RUSTYCLEAN_BIN --r1 $R1 --kraken2-db $KRAKEN2_DB -o $RC_OUT -t $N_THREADS --checkpoint-dir $RC_OUT/.checkpoints --resume"
            fi
            run_tool "rustyclean" "$dataset" "$rep" "$RC_CMD" "$RC_OUT"
            RC_OUTPUT_SIZE=$(find "$RC_OUT" -name "*.fastq.gz" -exec du -cb {} + 2>/dev/null | tail -1 | cut -f1 || echo "0")
            echo "rustyclean,$dataset,$rep,output_size,$RC_OUTPUT_SIZE" >> "$SIZE_CSV"
            cleanup_rustyclean_checkpoints "$RC_OUT"
        fi

        # KneadData
        KD_OUT="$RESULTS_DIR/kneaddata/${dataset}_rep${rep}"
        if record_exists "kneaddata" "$dataset" "$rep" && kneaddata_output_exists "$KD_OUT"; then
            echo "  Skipping kneaddata on $dataset (rep $rep) — output present."
        else
            if record_exists "kneaddata" "$dataset" "$rep"; then
                echo "  Stale kneaddata record for $dataset (rep $rep); removing old metrics and output."
                remove_perf_record "kneaddata" "$dataset" "$rep"
                remove_size_record "kneaddata" "$dataset" "$rep"
                rm -rf "$KD_OUT"
            fi
            mkdir -p "$KD_OUT"
            # Increase Java heap for Trimmomatic (default often too small for PE 20M+ reads)
            export _JAVA_OPTIONS="-Xmx32g"
            if [ "$PE" = true ]; then
                KD_CMD="$KNEADDATA_BIN --input1 $R1 --input2 $R2 --output-prefix clean --reference-db $KNEADDATA_DB --threads $N_THREADS --output $KD_OUT --remove-intermediate-output"
            else
                KD_CMD="$KNEADDATA_BIN --unpaired $R1 --output-prefix clean --reference-db $KNEADDATA_DB --threads $N_THREADS --output $KD_OUT --remove-intermediate-output"
            fi
            run_tool "kneaddata" "$dataset" "$rep" "$KD_CMD" "$KD_OUT"
            # Compress KneadData's uncompressed clean outputs to save scratch space
            find "$KD_OUT" -name "*clean*.fastq" ! -name "*contam*" ! -name "*trim*" -exec pigz -p "$N_THREADS" {} + 2>/dev/null || true
            KD_OUTPUT_SIZE=$(find "$KD_OUT" -name "*clean*.fastq*" ! -name "*contam*" ! -name "*trim*" -exec du -cb {} + 2>/dev/null | tail -1 | cut -f1 || echo "0")
            echo "kneaddata,$dataset,$rep,output_size,$KD_OUTPUT_SIZE" >> "$SIZE_CSV"
            cleanup_kneaddata_intermediates "$KD_OUT"
        fi
    done
done

echo "Benchmark complete."
