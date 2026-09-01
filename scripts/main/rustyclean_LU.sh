#!/bin/bash
#SBATCH --job-name=LU_rustyclean
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=yfz96@connect.hku.hk
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=20
#SBATCH --mem=100G
#SBATCH --time=7-00:00:00
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: sbatch rustyclean_LU.sh <sample_list.txt>"
    exit 1
fi

LIST=$1
SCRIPT_DIR="/lustre1/g/aos_shihuang/data/LU/Scripts"
OUTDIR="/lustre1/g/aos_shihuang/data/LU/results/rustyclean_out"
METRICS_CSV="${OUTDIR}/rustyclean_metrics.csv"
RC_BIN="/lustre1/g/aos_shihuang/rustyclean/target/release/rustyclean"

# Host-removal backend configuration
MODE="bowtie2"                       # change to "auto" to enable adaptive selection
HOST_INDEX="/lustre1/g/aos_shihuang/databases/kneaddata/hg_39"
KRAKEN2_DB="/lustre1/g/aos_shihuang/databases/kraken2/kraken2_226"  # used only when MODE=auto
THREADS=16
WORKERS=1

mkdir -p "${OUTDIR}"

# Initialize metrics file
if [ ! -f "${METRICS_CSV}" ]; then
    echo "sample,runtime_seconds,max_memory_kb,timestamp" > "${METRICS_CSV}"
fi

source /group/aos_shihuang/conda/etc/profile.d/conda.sh
conda activate fastp
export PATH="$HOME/.conda/envs/hostile-centrifuge/bin:/group/aos_shihuang/conda/envs/kraken2/bin:/group/aos_shihuang/conda/envs/kneaddata/bin:${PATH}"

echo "============================================"
echo "RustyClean pipeline started at $(date)"
echo "Sample list: ${LIST}"
echo "Output directory: ${OUTDIR}"
echo "Mode: ${MODE}"
echo "============================================"

FAILED_LOG="${OUTDIR}/$(basename "${LIST}" .txt)_failed_samples.txt"
rm -f "${FAILED_LOG}"

TOTAL=0
SUCCESS=0
FAIL=0

while read -r sample f1 f2; do
    [ -z "$sample" ] && continue
    [[ "$sample" =~ ^# ]] && continue

    TOTAL=$((TOTAL + 1))
    echo ""
    echo "========================================"
    echo "Processing sample: ${sample}"
    echo "Time: $(date)"
    echo "R1: ${f1}"
    echo "R2: ${f2}"
    echo "========================================"

    SAMPLE_OUT="${OUTDIR}/${sample}"
    CHK_DIR="${SAMPLE_OUT}/.rustyclean_checkpoints"
    TIME_LOG="${SAMPLE_OUT}/time.log"
    mkdir -p "${SAMPLE_OUT}"

    set +e
    /usr/bin/time -v -o "${TIME_LOG}" \
        "${RC_BIN}" \
            --r1 "${f1}" \
            --r2 "${f2}" \
            --host-removal-mode "${MODE}" \
            --host-index "${HOST_INDEX}" \
            $([ "${MODE}" == "auto" ] && echo "--kraken2-db ${KRAKEN2_DB}") \
            -o "${SAMPLE_OUT}" \
            --checkpoint-dir "${CHK_DIR}" \
            -t "${THREADS}" \
            -w "${WORKERS}" \
            --resume \
            --clean \
            > "${SAMPLE_OUT}/rustyclean.log" 2>&1
    rc=$?
    set -e

    # Parse runtime and memory from GNU time output
    elapsed=$(grep "Elapsed (wall clock) time" "${TIME_LOG}" 2>/dev/null | sed -E 's/.*: //')
    runtime_seconds="unknown"
    if [[ "${elapsed}" =~ ^([0-9]+):([0-9]+\.?[0-9]*)$ ]]; then
        min=${BASH_REMATCH[1]}
        sec=${BASH_REMATCH[2]}
        runtime_seconds=$(echo "${min} * 60 + ${sec}" | bc)
    elif [[ "${elapsed}" =~ ^([0-9]+):([0-9]+):([0-9]+\.?[0-9]*)$ ]]; then
        hr=${BASH_REMATCH[1]}
        min=${BASH_REMATCH[2]}
        sec=${BASH_REMATCH[3]}
        runtime_seconds=$(echo "${hr} * 3600 + ${min} * 60 + ${sec}" | bc)
    fi
    max_mem=$(grep "Maximum resident set size" "${TIME_LOG}" 2>/dev/null | awk '{print $NF}')
    ts=$(date -Iseconds)
    echo "${sample},${runtime_seconds},${max_mem},${ts}" >> "${METRICS_CSV}"

    if [ $rc -ne 0 ]; then
        echo "ERROR: RustyClean failed for ${sample}" >&2
        echo "$sample" >> "${FAILED_LOG}"
        FAIL=$((FAIL + 1))
    else
        echo "Sample ${sample} completed successfully at $(date)}"
        SUCCESS=$((SUCCESS + 1))
    fi
done < "$LIST"

echo ""
echo "============================================"
echo "RustyClean pipeline finished at $(date)"
echo "Total samples: ${TOTAL}"
echo "Successful: ${SUCCESS}"
echo "Failed: ${FAIL}"
[ "$FAIL" -gt 0 ] && echo "Failed samples saved to: ${FAILED_LOG}"
echo "Metrics saved to: ${METRICS_CSV}"
echo "============================================"
