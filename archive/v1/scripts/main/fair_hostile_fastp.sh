#!/bin/bash
#SBATCH --job-name=fair_hostile_fastp
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=yfz96@connect.hku.hk
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --chdir=/scr/u/shihuang/rustyclean-paper
#SBATCH --output=/scr/u/shihuang/rustyclean-paper/logs/fair_hostile_fastp_%j.out
#SBATCH --error=/scr/u/shihuang/rustyclean-paper/logs/fair_hostile_fastp_%j.err

set -euo pipefail

# Avoid conda activate to prevent writes to /home/shihuang
export PATH="/lustre1/g/aos_shihuang/tools/samtools/samtools-1.21:/home/shihuang/.conda/envs/hostile-centrifuge/bin:/group/aos_shihuang/conda/envs/fastp/bin:${PATH}"

DATA_DIR="/scr/u/shihuang/rustyclean-paper/data/enhanced"
OUTDIR="/scr/u/shihuang/rustyclean-paper/fair_hostile_fastp"
mkdir -p "${OUTDIR}"

METRICS="${OUTDIR}/hostile_fastp_metrics.csv"
echo "dataset,step,runtime_seconds,max_memory_kb,timestamp" > "${METRICS}"

DATASETS=(
    "5M_1pct_low_even_SE"
    "10M_10pct_med_even_SE"
    "30M_50pct_high_skewed_SE"
    "60M_90pct_high_lognormal_SE"
)

parse_time_log() {
    local time_log=$1
    local elapsed
    elapsed=$(grep "Elapsed (wall clock) time" "${time_log}" | sed -E 's/.*: //')
    local runtime_seconds="unknown"
    if [[ "${elapsed}" =~ ^([0-9]+):([0-9]+\.?[0-9]*)$ ]]; then
        local min=${BASH_REMATCH[1]}
        local sec=${BASH_REMATCH[2]}
        runtime_seconds=$(echo "${min} * 60 + ${sec}" | bc)
    elif [[ "${elapsed}" =~ ^([0-9]+):([0-9]+):([0-9]+\.?[0-9]*)$ ]]; then
        local hr=${BASH_REMATCH[1]}
        local min=${BASH_REMATCH[2]}
        local sec=${BASH_REMATCH[3]}
        runtime_seconds=$(echo "${hr} * 3600 + ${min} * 60 + ${sec}" | bc)
    fi
    local max_mem
    max_mem=$(grep "Maximum resident set size" "${time_log}" | awk '{print $NF}')
    echo "${runtime_seconds},${max_mem}"
}

for dataset in "${DATASETS[@]}"; do
    echo "============================================"
    echo "Dataset: ${dataset}"
    echo "============================================"

    r1="${DATA_DIR}/${dataset}/reads.fastq.gz"
    ds_out="${OUTDIR}/${dataset}"
    mkdir -p "${ds_out}"

    # --- fastp only ---
    echo "[1/2] Running fastp ..."
    trimmed="${ds_out}/${dataset}_trimmed.fastq.gz"
    time_log="${ds_out}/fastp.time.log"
    /usr/bin/time -v -o "${time_log}" \
        fastp \
            --in1 "${r1}" \
            --out1 "${trimmed}" \
            --json "${ds_out}/fastp.json" \
            --thread 4 \
            --compression 6 \
            --cut_front \
            --cut_tail \
            --qualified_quality_phred 20 \
            --length_required 50 \
            > "${ds_out}/fastp.log" 2>&1
    read -r fp_runtime fp_mem <<< "$(parse_time_log "${time_log}")"
    echo "${dataset},fastp,${fp_runtime},${fp_mem},$(date -Iseconds)" >> "${METRICS}"
    echo "fastp: ${fp_runtime}s, ${fp_mem}KB"

    # --- Hostile on fastp-trimmed reads ---
    echo "[2/2] Running Hostile on trimmed reads ..."
    hostile_out="${ds_out}/hostile_out"
    mkdir -p "${hostile_out}"
    time_log="${ds_out}/hostile.time.log"
    /usr/bin/time -v -o "${time_log}" \
        hostile clean \
            --fastq1 "${trimmed}" \
            --aligner bowtie2 \
            -o "${hostile_out}" \
            -t 8 \
            --airplane \
            > "${ds_out}/hostile.log" 2>&1
    read -r hs_runtime hs_mem <<< "$(parse_time_log "${time_log}")"
    echo "${dataset},hostile_after_fastp,${hs_runtime},${hs_mem},$(date -Iseconds)" >> "${METRICS}"
    echo "Hostile: ${hs_runtime}s, ${hs_mem}KB"

done

echo "============================================"
echo "All done. Metrics: ${METRICS}"
echo "============================================"
