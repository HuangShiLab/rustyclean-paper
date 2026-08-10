#!/bin/bash
# =============================================================================
# RustyClean Benchmark - Main Execution Script
# =============================================================================
# Compares RustyClean vs KneadData on simulated and real metagenome data.
#
# Usage: bash scripts/run_benchmark.sh [data_dir] [output_dir]
# Default data_dir: ./data/simulated
# Default output_dir: ./results

set -e

DATA_DIR="${1:-./data/simulated}"
RESULTS_DIR="${2:-./results}"
N_REPLICATES=3
THREADS=8

# Tool paths
RUSTYCLEAN="${RUSTYCLEAN:-rustyclean}"
KNEADDATA="${KNEADDATA:-kneaddata}"
KRAKEN2_DB="${KRAKEN2_DB:-$HOME/benchmark_env/databases/minikraken2_v1_8GB}"
KNEADDATA_DB="${KNEADDATA_DB:-$HOME/benchmark_env/databases/kneaddata_human_db}"

echo "========================================"
echo "RustyClean vs KneadData Benchmark"
echo "========================================"
echo "Data: $DATA_DIR"
echo "Results: $RESULTS_DIR"
echo "Replicates: $N_REPLICATES"
echo "Threads: $THREADS"
echo ""

command -v "$RUSTYCLEAN" >/dev/null 2>&1 || { echo "ERROR: RustyClean not found"; exit 1; }
command -v "$KNEADDATA" >/dev/null 2>&1 || { echo "ERROR: KneadData not found"; exit 1; }

mkdir -p "$RESULTS_DIR"/{rustyclean,kneaddata,logs,metrics}

# Performance tracking
run_with_benchmark() {
    local tool_name="$1"
    local dataset_name="$2"
    local rep="$3"
    local cmd="$4"
    
    local logfile="$RESULTS_DIR/logs/${tool_name}_${dataset_name}_rep${rep}.log"
    local timefile="$RESULTS_DIR/logs/${tool_name}_${dataset_name}_rep${rep}.time"
    
    echo "  Running $tool_name on $dataset_name (rep $rep)..."
    
    if /usr/bin/time -v echo "" >/dev/null 2>&1; then
        /usr/bin/time -v -o "$timefile" bash -c "$cmd" > "$logfile" 2>&1
    else
        { time bash -c "$cmd"; } > "$logfile" 2>&1
    fi
    
    local runtime="unknown"
    local max_mem="unknown"
    
    if [ -f "$timefile" ]; then
        runtime=$(grep "Elapsed (wall clock) time" "$timefile" | sed -n 's/.*Elapsed (wall clock) time.*: //p' || echo "unknown")
        max_mem=$(grep "Maximum resident set size" "$timefile" | sed -n 's/.*Maximum resident set size (kbytes): //p' || echo "unknown")
    fi
    
    echo "$tool_name,$dataset_name,$rep,$runtime,$max_mem,$(date -Iseconds)" >> "$RESULTS_DIR/metrics/performance.csv"
    echo "    Done: runtime=$runtime, max_mem=$max_mem"
}

echo "tool,dataset,rep,runtime_seconds,max_memory_kb,timestamp" > "$RESULTS_DIR/metrics/performance.csv"

# ---------------------------------------------------------------------------
# Find datasets
# ---------------------------------------------------------------------------

echo "[1/3] Scanning datasets..."

DATASETS=()
for dir in "$DATA_DIR"/*/; do
    if [ -f "$dir/completed.flag" ]; then
        DATASETS+=("$(basename "$dir")")
    fi
done

if [ ${#DATASETS[@]} -eq 0 ]; then
    echo "ERROR: No completed datasets found in $DATA_DIR"
    exit 1
fi

echo "Found ${#DATASETS[@]} datasets:"
for ds in "${DATASETS[@]}"; do
    echo "  - $ds"
done

# ---------------------------------------------------------------------------
# Run benchmarks
# ---------------------------------------------------------------------------

echo ""
echo "[2/3] Running benchmarks..."

for dataset in "${DATASETS[@]}"; do
    echo ""
    echo "=== Dataset: $dataset ==="
    
    DATASET_DIR="$DATA_DIR/$dataset"
    
    if [ -f "$DATASET_DIR/reads_R1.fastq.gz" ]; then
        PE=true
        R1="$DATASET_DIR/reads_R1.fastq.gz"
        R2="$DATASET_DIR/reads_R2.fastq.gz"
        echo "  Mode: Paired-end"
    else
        PE=false
        R1="$DATASET_DIR/reads.fastq.gz"
        R2=""
        echo "  Mode: Single-end"
    fi
    
    for rep in $(seq 1 $N_REPLICATES); do
        echo "  --- Replicate $rep ---"
        
        # RustyClean
        RC_OUT="$RESULTS_DIR/rustyclean/${dataset}_rep${rep}"
        mkdir -p "$RC_OUT"
        
        if [ "$PE" = true ]; then
            RC_CMD="$RUSTYCLEAN --r1 $R1 --r2 $R2 --kraken2-db $KRAKEN2_DB -o $RC_OUT -t $THREADS"
        else
            RC_CMD="$RUSTYCLEAN --r1 $R1 --kraken2-db $KRAKEN2_DB -o $RC_OUT -t $THREADS"
        fi
        
        run_with_benchmark "rustyclean" "$dataset" "$rep" "$RC_CMD"
        
        RC_OUTPUT_SIZE=$(find "$RC_OUT" -name "*.fastq.gz" -exec du -cb {} + 2>/dev/null | tail -1 | cut -f1 || echo "0")
        echo "rustyclean,$dataset,$rep,output_size,$RC_OUTPUT_SIZE" >> "$RESULTS_DIR/metrics/file_sizes.csv"
        
        # KneadData
        KD_OUT="$RESULTS_DIR/kneaddata/${dataset}_rep${rep}"
        mkdir -p "$KD_OUT"
        
        if [ "$PE" = true ]; then
            KD_CMD="$KNEADDATA --input1 $R1 --input2 $R2 --output-prefix clean --reference-db $KNEADDATA_DB --threads $THREADS --output $KD_OUT"
        else
            KD_CMD="$KNEADDATA --unpaired $R1 --output-prefix clean --reference-db $KNEADDATA_DB --threads $THREADS --output $KD_OUT"
        fi
        
        run_with_benchmark "kneaddata" "$dataset" "$rep" "$KD_CMD"
        
        KD_OUTPUT_SIZE=$(find "$KD_OUT" -name "*.fastq*" -exec du -cb {} + 2>/dev/null | tail -1 | cut -f1 || echo "0")
        echo "kneaddata,$dataset,$rep,output_size,$KD_OUTPUT_SIZE" >> "$RESULTS_DIR/metrics/file_sizes.csv"
        
    done
    
    echo "  Dataset $dataset completed."
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "[3/3] Benchmark execution complete!"
echo ""
echo "Results: $RESULTS_DIR"
echo "Performance: $RESULTS_DIR/metrics/performance.csv"
echo "File sizes: $RESULTS_DIR/metrics/file_sizes.csv"
echo "Logs: $RESULTS_DIR/logs/"
echo ""
echo "Next steps:"
echo "  python scripts/analyze_accuracy.py $DATA_DIR $RESULTS_DIR"
echo "  python scripts/analyze_performance.py $RESULTS_DIR"
