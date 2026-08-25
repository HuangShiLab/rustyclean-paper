#!/bin/bash
#SBATCH --job-name=rc_cross_species
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=80G
#SBATCH --time=12:00:00
#SBATCH --array=0-17
#SBATCH --output=%x_%A_%a.out
#SBATCH --error=%x_%A_%a.err

set -e

source /group/aos_shihuang/conda/etc/profile.d/conda.sh

export PATH="/group/aos_shihuang/conda/envs/fastp/bin:/group/aos_shihuang/conda/envs/kraken2/bin:/group/aos_shihuang/conda/envs/kneaddata/bin:/group/aos_shihuang/conda/envs/seqtk/bin:/home/shihuang/.conda/envs/hostile-centrifuge/bin:${PATH}"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
DATA_DIR="/scr/u/shihuang/rustyclean-paper/data/cross_species"
RESULTS_DIR="/lustre1/g/aos_shihuang/rustyclean-paper/results_cross_species"
METRICS_DIR="${RESULTS_DIR}/metrics"
LOGS_DIR="${RESULTS_DIR}/logs"

THREADS=8

RUSTYCLEAN="/lustre1/g/aos_shihuang/rustyclean/target/release/rustyclean"
KRAKEN2_DB="/lustre1/g/aos_shihuang/databases/kraken2/kraken16"
CF_INDEX="/lustre1/g/aos_shihuang/databases/centrifuge/host_indexes/multi_host_cf"
BT2_INDEX="/lustre1/g/aos_shihuang/databases/host_genomes_cross/multi_host_bt2"
KNEADDATA_DB="/lustre1/g/aos_shihuang/databases/host_genomes_cross/multi_host_bt2"

HOSTS=(human mouse rat pig rice monkey)
DATASETS=(10M_10pct_med_even_SE 30M_50pct_med_lognormal_SE 60M_90pct_high_lognormal_SE)

# Build flat dataset list
ALL_DATASETS=()
for host in "${HOSTS[@]}"; do
    for ds in "${DATASETS[@]}"; do
        ALL_DATASETS+=("${host}_${ds}")
    done
done

DATASET="${ALL_DATASETS[$SLURM_ARRAY_TASK_ID]}"
mkdir -p "${RESULTS_DIR}"/{
    rustyclean_k2,rustyclean_bt2,rustyclean_auto,rustyclean_cf,
    kneaddata,hostile,logs,metrics
}

R1="${DATA_DIR}/${DATASET}/reads.fastq.gz"
GT="${DATA_DIR}/${DATASET}/ground_truth_labels.txt"

if [ ! -f "$R1" ]; then
    echo "ERROR: input not found: $R1"
    exit 1
fi

log() { echo "[$(date +%H:%M:%S)] $*"; }

run_timed() {
    local tool_name="$1"
    local dataset="$2"
    shift 2
    local cmd="$*"

    local logfile="${LOGS_DIR}/${tool_name}_${dataset}.log"
    local timefile="${LOGS_DIR}/${tool_name}_${dataset}.time"

    log "  [${tool_name}] Running on ${dataset}..."
    /usr/bin/time -v -o "${timefile}" bash -c "${cmd}" > "${logfile}" 2>&1 || {
        log "  [${tool_name}] FAILED on ${dataset}"
        echo "${tool_name},${dataset},FAILED,,$(date -Iseconds)" >> "${METRICS_DIR}/performance.csv"
        return 1
    }

    local runtime="unknown"
    local max_mem="unknown"
    if [ -f "${timefile}" ]; then
        runtime=$(grep "Elapsed (wall clock) time" "${timefile}" | sed -n 's/.*Elapsed (wall clock) time: //p' || echo "unknown")
        max_mem=$(grep "Maximum resident set size" "${timefile}" | sed -n 's/.*Maximum resident set size (kbytes): //p' || echo "unknown")
    fi

    local runtime_sec="unknown"
    if [ "${runtime}" != "unknown" ]; then
        runtime_sec=$(echo "${runtime}" | awk -F: '{
            if (NF == 3) { printf "%d", $1*3600 + $2*60 + $3 }
            else if (NF == 2) { printf "%d", $1*60 + $2 }
            else { printf "%d", $1 }
        }')
    fi

    echo "${tool_name},${dataset},${runtime_sec},${max_mem},$(date -Iseconds)" >> "${METRICS_DIR}/performance.csv"
    log "  [${tool_name}] Done: runtime=${runtime_sec}s, max_mem=${max_mem}kB"
}

# ---------------------------------------------------------------------------
# Initialize metrics file once per array (race safe via append)
# ---------------------------------------------------------------------------
if [ ! -f "${METRICS_DIR}/performance.csv" ]; then
    echo "tool,dataset,runtime_seconds,max_memory_kb,timestamp" > "${METRICS_DIR}/performance.csv"
fi

log "Job started at: $(date)"
log "Host: $(hostname)"
log "Dataset: ${DATASET}"
log "Threads: ${THREADS}"

OUT_RC_K2="${RESULTS_DIR}/rustyclean_k2/${DATASET}"
OUT_RC_BT2="${RESULTS_DIR}/rustyclean_bt2/${DATASET}"
OUT_RC_AUTO="${RESULTS_DIR}/rustyclean_auto/${DATASET}"
OUT_RC_CF="${RESULTS_DIR}/rustyclean_cf/${DATASET}"
OUT_KD="${RESULTS_DIR}/kneaddata/${DATASET}"
OUT_HOSTILE="${RESULTS_DIR}/hostile/${DATASET}"

mkdir -p "$OUT_RC_K2" "$OUT_RC_BT2" "$OUT_RC_AUTO" "$OUT_RC_CF" "$OUT_KD" "$OUT_HOSTILE"

# RustyClean Kraken2
run_timed "rustyclean_k2" "$DATASET" "$RUSTYCLEAN --r1 $R1 --kraken2-db $KRAKEN2_DB -o $OUT_RC_K2 -t $THREADS --memory-mapping"

# RustyClean Bowtie2
run_timed "rustyclean_bt2" "$DATASET" "$RUSTYCLEAN --r1 $R1 --mode bowtie2 --host-index $BT2_INDEX -o $OUT_RC_BT2 -t $THREADS"

# RustyClean AUTO
run_timed "rustyclean_auto" "$DATASET" "$RUSTYCLEAN --r1 $R1 --mode auto --host-index $BT2_INDEX --kraken2-db $KRAKEN2_DB -o $OUT_RC_AUTO -t $THREADS --memory-mapping"

# RustyClean Centrifuge (if index exists)
if [ -f "${CF_INDEX}.1.cf" ]; then
    run_timed "rustyclean_cf" "$DATASET" "$RUSTYCLEAN --r1 $R1 --mode centrifuge --host-index $CF_INDEX -o $OUT_RC_CF -t $THREADS"
else
    log "  [rustyclean_cf] Skipped: index not found"
fi

# KneadData
run_timed "kneaddata" "$DATASET" "kneaddata -i1 $R1 -db $KNEADDATA_DB -o $OUT_KD -t $THREADS --remove-intermediate-output"

# Hostile (human-only; skip for non-human hosts)
if [[ "$DATASET" == human_* ]]; then
    run_timed "hostile" "$DATASET" "hostile clean --fastq $R1 --out-dir $OUT_HOSTILE --threads $THREADS"
else
    log "  [hostile] Skipped: human-only tool"
fi

log "Job finished at: $(date)"
