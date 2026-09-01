#!/bin/bash
#SBATCH --job-name=rc_modes_k2_only
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=80G
#SBATCH --time=12:00:00
#SBATCH --array=0-3
#SBATCH --output=%x_%A_%a.out
#SBATCH --error=%x_%A_%a.err

set -e

source /group/aos_shihuang/conda/etc/profile.d/conda.sh
export PATH="/group/aos_shihuang/conda/envs/fastp/bin:/group/aos_shihuang/conda/envs/kraken2/bin:/group/aos_shihuang/conda/envs/seqtk/bin:${PATH}"

DATA_DIR="${SCRATCH_DIR:-/scr/u/$USER/rustyclean-paper}/data/enhanced"
RESULTS_DIR="${RUNS_DIR:-/lustre1/g/aos_shihuang/rustyclean-paper/runs}/results_rc_modes"
METRICS_DIR="${RESULTS_DIR}/metrics"
LOGS_DIR="${RESULTS_DIR}/logs"

THREADS=8

RUSTYCLEAN="/lustre1/g/aos_shihuang/rustyclean/target/release/rustyclean"
KRAKEN2_DB="/lustre1/g/aos_shihuang/databases/kraken2/kraken16"

DATASETS=(
    "5M_1pct_low_even_SE"
    "10M_10pct_med_even_SE"
    "30M_50pct_high_skewed_SE"
    "60M_90pct_high_lognormal_SE"
)

DATASET="${DATASETS[$SLURM_ARRAY_TASK_ID]}"
R1="${DATA_DIR}/${DATASET}/reads.fastq.gz"

mkdir -p "${RESULTS_DIR}"/kraken2 "${METRICS_DIR}" "${LOGS_DIR}"

echo "Job started at: $(date)"
echo "Host: $(hostname)"
echo "Dataset: ${DATASET}"

OUT="${RESULTS_DIR}/kraken2/${DATASET}"
rm -rf "${OUT}"
mkdir -p "${OUT}"

LOG="${LOGS_DIR}/kraken2_${DATASET}.log"
TIME="${LOGS_DIR}/kraken2_${DATASET}.time"

/usr/bin/time -v -o "${TIME}" \
    "${RUSTYCLEAN}" --max-contamination 100.0 --r1 "${R1}" --mode kraken2 --kraken2-db "${KRAKEN2_DB}" \
    -o "${OUT}" -t "${THREADS}" \
    --checkpoint-dir "${OUT}/.checkpoints" --clean > "${LOG}" 2>&1 || {
    echo "[kraken2] FAILED on ${DATASET}"
    echo "kraken2,${DATASET},FAILED,,$(date -Iseconds)" >> "${METRICS_DIR}/performance.csv"
    exit 1
}

runtime=$(grep "Elapsed (wall clock) time" "${TIME}" | awk -F': ' '{print $NF}')
max_mem=$(grep "Maximum resident set size" "${TIME}" | sed -n 's/.*Maximum resident set size (kbytes): //p')
runtime_sec=$(echo "${runtime}" | awk -F: '{
    if (NF == 3) { printf "%d", $1*3600 + $2*60 + $3 }
    else if (NF == 2) { printf "%d", $1*60 + $2 }
    else { printf "%d", $1 }
}')

echo "kraken2,${DATASET},${runtime_sec},${max_mem},$(date -Iseconds)" >> "${METRICS_DIR}/performance.csv"
