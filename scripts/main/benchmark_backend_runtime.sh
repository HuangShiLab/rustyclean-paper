#!/bin/bash
#SBATCH --job-name=backend_runtime
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=128G
#SBATCH --time=08:00:00
#SBATCH --output=/home/%u/backend_runtime_%j.out
#SBATCH --error=/home/%u/backend_runtime_%j.err

set -e

source /group/aos_shihuang/conda/etc/profile.d/conda.sh
export PATH="/group/aos_shihuang/conda/envs/fastp/bin:/group/aos_shihuang/conda/envs/kraken2/bin:/group/aos_shihuang/conda/envs/bowtie2/bin:$HOME/.local/bin:${PATH}"

DATA_DIR="${SCRATCH_DIR:-/scr/u/$USER/rustyclean-paper}/data/enhanced"
RESULTS_DIR="${RUNS_DIR:-/lustre1/g/aos_shihuang/rustyclean-paper/runs}/backend_runtime_v2"
METRICS_DIR="${RESULTS_DIR}/metrics"
LOGS_DIR="${RESULTS_DIR}/logs"

THREADS=8
RUSTYCLEAN="/lustre1/g/aos_shihuang/rustyclean/target/release/rustyclean"
KRAKEN2_DB="/lustre1/g/aos_shihuang/databases/rustyclean_human_t2t_only/kraken2/t2t_only"
BT2_INDEX="${HOSTILE_INDEX:-$HOME/.local/share/hostile/human-t2t-hla}"
MM_INDEX="${HOSTILE_INDEX:-$HOME/.local/share/hostile/human-t2t-hla}.mmi"
CF_INDEX="/lustre1/g/aos_shihuang/databases/centrifuge/host_indexes/human_t2t_hla_cf"

DATASETS=(
    "5M_1pct_low_even_SE"
    "10M_10pct_med_even_SE"
    "30M_50pct_high_skewed_SE"
    "60M_90pct_high_lognormal_SE"
)

MODES=("bowtie2" "kraken2" "minimap2" "centrifuge")

mkdir -p "${METRICS_DIR}" "${LOGS_DIR}"

echo "Job started at: $(date)"
echo "Host: $(hostname)"
echo "Threads: ${THREADS}"

if [ ! -f "${METRICS_DIR}/performance.csv" ]; then
    echo "tool,dataset,rep,runtime_seconds,max_memory_kb,timestamp" > "${METRICS_DIR}/performance.csv"
fi

parse_time() {
    local timefile="$1"
    local runtime="unknown"
    local max_mem="unknown"
    if [ -f "${timefile}" ]; then
        runtime=$(grep "Elapsed (wall clock) time" "${timefile}" | awk -F': ' '{print $NF}')
        [ -z "${runtime}" ] && runtime="unknown"
        max_mem=$(grep "Maximum resident set size (kbytes):" "${timefile}" | awk '{print $NF}' || echo "unknown")
    fi

    local runtime_sec="unknown"
    if [ "${runtime}" != "unknown" ] && [ -n "${runtime}" ]; then
        runtime_sec=$(echo "${runtime}" | awk -F: '{
            if (NF == 3) { printf "%d", $1*3600 + $2*60 + $3 }
            else if (NF == 2) { printf "%d", $1*60 + $2 }
            else { printf "%d", $1 }
        }')
    fi
    echo "${runtime_sec} ${max_mem}"
}

for MODE in "${MODES[@]}"; do
    echo "=== Mode: ${MODE} ==="
    for DATASET in "${DATASETS[@]}"; do
        R1="${DATA_DIR}/${DATASET}/reads.fastq.gz"
        if [ ! -f "${R1}" ]; then
            echo "WARNING: Input not found: ${R1}" >&2
            continue
        fi

        OUT="${RESULTS_DIR}/${MODE}/${DATASET}"
        rm -rf "${OUT}"
        mkdir -p "${OUT}"
        logfile="${LOGS_DIR}/${MODE}_${DATASET}.log"
        timefile="${LOGS_DIR}/${MODE}_${DATASET}.time"

        EXTRA_ARGS=""
        if [ "${MODE}" == "kraken2" ]; then
            EXTRA_ARGS="--kraken2-db ${KRAKEN2_DB}"
        elif [ "${MODE}" == "bowtie2" ]; then
            EXTRA_ARGS="--host-index ${BT2_INDEX}"
        elif [ "${MODE}" == "minimap2" ]; then
            EXTRA_ARGS="--host-index ${MM_INDEX}"
        elif [ "${MODE}" == "centrifuge" ]; then
            EXTRA_ARGS="--host-index ${CF_INDEX}"
        fi

        echo "  [${MODE}] Running on ${DATASET}..."
        /usr/bin/time -v -o "${timefile}" \
            "${RUSTYCLEAN}" \
                --mode "${MODE}" \
                --skip-qc \
                --r1 "${R1}" \
                ${EXTRA_ARGS} \
                --max-contamination 100.0 \
                -o "${OUT}" \
                -t "${THREADS}" \
                --checkpoint-dir "${OUT}/.checkpoints" \
                --clean \
                > "${logfile}" 2>&1 || {
            echo "  [${MODE}] FAILED on ${DATASET}" >&2
            echo "${MODE},${DATASET},1,FAILED,,$(date -Iseconds)" >> "${METRICS_DIR}/performance.csv"
            continue
        }

        read runtime_sec max_mem < <(parse_time "${timefile}")
        echo "${MODE},${DATASET},1,${runtime_sec},${max_mem},$(date -Iseconds)" >> "${METRICS_DIR}/performance.csv"
        echo "  [${MODE}] Done: runtime=${runtime_sec}s, max_mem=${max_mem}kB"
    done
done

echo "Job finished at: $(date)"
