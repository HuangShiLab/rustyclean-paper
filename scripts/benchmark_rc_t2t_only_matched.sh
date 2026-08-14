#!/bin/bash
#SBATCH --job-name=rc_t2t_only_matched
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=04:00:00
#SBATCH --array=0-3
#SBATCH --output=/home/shihuang/rc_t2t_only_matched_%A_%a.out
#SBATCH --error=/home/shihuang/rc_t2t_only_matched_%A_%a.err

set -e

source /group/aos_shihuang/conda/etc/profile.d/conda.sh

export PATH="/group/aos_shihuang/conda/envs/fastp/bin:/group/aos_shihuang/conda/envs/kraken2/bin:/group/aos_shihuang/conda/envs/bowtie2/bin:${PATH}"

DATA_DIR="/scr/u/shihuang/rustyclean-paper/data/enhanced"
RESULTS_DIR="/lustre1/g/aos_shihuang/rustyclean-paper/rustyclean_t2t_only_matched"
METRICS_DIR="${RESULTS_DIR}/metrics"
LOGS_DIR="${RESULTS_DIR}/logs"

THREADS=8
RUSTYCLEAN="/lustre1/g/aos_shihuang/rustyclean/target/release/rustyclean"
KRAKEN2_DB="/lustre1/g/aos_shihuang/databases/rustyclean_human_t2t_only/kraken2/t2t_only"
BT2_INDEX="/home/shihuang/.local/share/hostile/human-t2t-hla"

DATASETS=(
    "30M_50pct_high_skewed_SE"
    "60M_90pct_high_lognormal_SE"
    "100M_50pct_high_lognormal_SE"
    "100M_90pct_high_lognormal_SE"
)

DATASET="${DATASETS[$SLURM_ARRAY_TASK_ID]}"
R1="${DATA_DIR}/${DATASET}/reads.fastq.gz"

mkdir -p "${METRICS_DIR}" "${LOGS_DIR}"

echo "Job started at: $(date)"
echo "Host: $(hostname)"
echo "Dataset: ${DATASET}"
echo "Threads: ${THREADS}"
echo "Kraken2 DB: ${KRAKEN2_DB}"
echo "Bowtie2 index: ${BT2_INDEX}"

if [ ! -f "${R1}" ]; then
    echo "ERROR: Input not found: ${R1}" >&2
    exit 1
fi

# Init metrics file
if [ ! -f "${METRICS_DIR}/performance.csv" ]; then
    echo "tool,dataset,rep,runtime_seconds,max_memory_kb,timestamp" > "${METRICS_DIR}/performance.csv"
fi

for REP in 1 2 3; do
    OUT="${RESULTS_DIR}/rustyclean_t2t_only/${DATASET}/rep_${REP}"
    rm -rf "${OUT}"
    mkdir -p "${OUT}"

    logfile="${LOGS_DIR}/rustyclean_t2t_only_${DATASET}_rep${REP}.log"
    timefile="${LOGS_DIR}/rustyclean_t2t_only_${DATASET}_rep${REP}.time"

    echo "  [rep ${REP}] Running RustyClean T2T-only on ${DATASET}..."

    /usr/bin/time -v -o "${timefile}" \
        "${RUSTYCLEAN}" \
            --mode auto \
            --skip-qc \
            --auto-survey \
            --r1 "${R1}" \
            --kraken2-db "${KRAKEN2_DB}" \
            --host-index "${BT2_INDEX}" \
            --max-contamination 100.0 \
            -o "${OUT}" \
            -t "${THREADS}" \
            --checkpoint-dir "${OUT}/.checkpoints" \
            --clean \
            > "${logfile}" 2>&1 || {
        echo "  [rep ${REP}] FAILED on ${DATASET}" >&2
        echo "rustyclean_t2t_only,${DATASET},${REP},FAILED,,$(date -Iseconds)" >> "${METRICS_DIR}/performance.csv"
        continue
    }

    runtime="unknown"
    max_mem="unknown"
    if [ -f "${timefile}" ]; then
        runtime=$(grep "Elapsed (wall clock) time" "${timefile}" | awk -F': ' '{print $NF}')
        [ -z "${runtime}" ] && runtime="unknown"
        max_mem=$(grep "Maximum resident set size (kbytes):" "${timefile}" | awk '{print $NF}' || echo "unknown")
    fi

    runtime_sec="unknown"
    if [ "${runtime}" != "unknown" ] && [ -n "${runtime}" ]; then
        runtime_sec=$(echo "${runtime}" | awk -F: '{
            if (NF == 3) { printf "%d", $1*3600 + $2*60 + $3 }
            else if (NF == 2) { printf "%d", $1*60 + $2 }
            else { printf "%d", $1 }
        }')
    fi

    ts=$(date -Iseconds)
    echo "rustyclean_t2t_only,${DATASET},${REP},${runtime_sec},${max_mem},${ts}" >> "${METRICS_DIR}/performance.csv"
    echo "  [rep ${REP}] Done: runtime=${runtime_sec}s, max_mem=${max_mem}kB"
done

echo "Job finished at: $(date)"
