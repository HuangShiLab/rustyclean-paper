#!/bin/bash
#SBATCH --job-name=rc_real_data
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=128G
#SBATCH --time=24:00:00
#SBATCH --array=0-2
#SBATCH --output=logs/%x-%A_%a.out
#SBATCH --error=logs/%x-%A_%a.err

set -e

source /group/aos_shihuang/conda/etc/profile.d/conda.sh

export PATH="/group/aos_shihuang/conda/envs/fastp/bin:/group/aos_shihuang/conda/envs/kraken2/bin:/group/aos_shihuang/conda/envs/kneaddata/bin:/group/aos_shihuang/conda/envs/seqtk/bin:${PATH}"
export _JAVA_OPTIONS="-Xmx32g"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
DATA_DIR="${SCRATCH_DIR:-/scr/u/$USER/rustyclean-paper}/real_data"
RESULTS_DIR="${RUNS_DIR:-/lustre1/g/aos_shihuang/rustyclean-paper/runs}/results_real_data"
METRICS_DIR="${RESULTS_DIR}/metrics"
LOGS_DIR="${RESULTS_DIR}/logs"

THREADS=16

RUSTYCLEAN="/lustre1/g/aos_shihuang/rustyclean/target/release/rustyclean"
KRAKEN2_DB="/lustre1/g/aos_shihuang/databases/kraken2/kraken16"
BT2_INDEX="/lustre1/g/aos_shihuang/databases/kneaddata/hg_39"
KNEADDATA_DB="/lustre1/g/aos_shihuang/databases/kneaddata/hg_39"

SAMPLES=(oral_saliva vaginal_swab breast_cancer_stool)
MODES=(PE SE PE)

SAMPLE="${SAMPLES[$SLURM_ARRAY_TASK_ID]}"
MODE="${MODES[$SLURM_ARRAY_TASK_ID]}"

mkdir -p "${RESULTS_DIR}"/{rustyclean_k2,rustyclean_auto,kneaddata,logs,metrics}

if [ "$MODE" = "PE" ]; then
    R1="${DATA_DIR}/${SAMPLE}/reads_R1.fastq.gz"
    R2="${DATA_DIR}/${SAMPLE}/reads_R2.fastq.gz"
    RC_INPUT="--r1 ${R1} --r2 ${R2}"
    KD_INPUT="-i1 ${R1} -i2 ${R2}"
else
    R1="${DATA_DIR}/${SAMPLE}/reads.fastq.gz"
    R2=""
    RC_INPUT="--r1 ${R1}"
    KD_INPUT="-un ${R1}"
fi

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
        runtime=$(grep "Elapsed (wall clock) time" "${timefile}" | awk -F': ' '{print $NF}')
        [ -z "${runtime}" ] && runtime="unknown"
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
# Initialize metrics file once per array
# ---------------------------------------------------------------------------
if [ ! -f "${METRICS_DIR}/performance.csv" ]; then
    echo "tool,dataset,mode,runtime_seconds,max_memory_kb,timestamp" > "${METRICS_DIR}/performance.csv"
fi

log "Job started at: $(date)"
log "Host: $(hostname)"
log "Sample: ${SAMPLE} (${MODE})"
log "Threads: ${THREADS}"

OUT_RC_K2="${RESULTS_DIR}/rustyclean_k2/${SAMPLE}"
OUT_RC_AUTO="${RESULTS_DIR}/rustyclean_auto/${SAMPLE}"
OUT_KD="${RESULTS_DIR}/kneaddata/${SAMPLE}"

mkdir -p "$OUT_RC_K2" "$OUT_RC_AUTO" "$OUT_KD"

# RustyClean Kraken2
run_timed "rustyclean_k2" "${SAMPLE}" \
    "$RUSTYCLEAN" --max-contamination 100.0 ${RC_INPUT} --kraken2-db "$KRAKEN2_DB" \
    -o "$OUT_RC_K2" -t "$THREADS" --memory-mapping \
    --checkpoint-dir "$OUT_RC_K2/.checkpoints" --clean

# RustyClean AUTO
run_timed "rustyclean_auto" "${SAMPLE}" \
    "$RUSTYCLEAN" --max-contamination 100.0 ${RC_INPUT} --mode auto --host-index "$BT2_INDEX" --kraken2-db "$KRAKEN2_DB" \
    -o "$OUT_RC_AUTO" -t "$THREADS" --memory-mapping \
    --checkpoint-dir "$OUT_RC_AUTO/.checkpoints" --clean

# KneadData
run_timed "kneaddata" "${SAMPLE}" \
    kneaddata ${KD_INPUT} --output-prefix clean \
    -db "$KNEADDATA_DB" --threads "$THREADS" \
    --output "$OUT_KD" --remove-intermediate-output

log "Job finished at: $(date)"
