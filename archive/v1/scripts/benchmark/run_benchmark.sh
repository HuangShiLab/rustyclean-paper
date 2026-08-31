#!/bin/bash
#SBATCH --job-name=rc_auto_vs_kneaddata
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
#SBATCH --output=/scr/u/shihuang/rustyclean-paper/logs/rc_auto_vs_kneaddata_%j.out
#SBATCH --error=/scr/u/shihuang/rustyclean-paper/logs/rc_auto_vs_kneaddata_%j.err

set -euo pipefail

# Tool paths
export PATH="/lustre1/g/aos_shihuang/rustyclean/target/release:/group/aos_shihuang/conda/envs/kneaddata/bin:/group/aos_shihuang/conda/envs/fastp/bin:/group/aos_shihuang/conda/envs/kraken2/bin:/group/aos_shihuang/conda/envs/seqtk/bin:/lustre1/g/aos_shihuang/tools/samtools/samtools-1.21:${PATH}"

DATA_DIR="/scr/u/shihuang/rustyclean-paper/data/enhanced"
OUTDIR="/scr/u/shihuang/rustyclean-paper/auto_vs_kneaddata"
mkdir -p "${OUTDIR}"

METRICS="${OUTDIR}/auto_vs_kneaddata_metrics.csv"
echo "dataset,tool,runtime_seconds,max_memory_kb,output_size_bytes,backend,estimated_host_pct,timestamp" > "${METRICS}"

DATASETS=(
    "5M_1pct_low_even_SE"
    "10M_10pct_med_even_SE"
    "30M_50pct_high_skewed_SE"
    "60M_90pct_high_lognormal_SE"
)

KRAKEN2_DB="/lustre1/g/aos_shihuang/databases/kraken2/kraken16"
HOST_INDEX="/lustre1/g/aos_shihuang/databases/kneaddata/hg_39"
THREADS=8

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

    # --- RustyClean AUTO (with QC) ---
    echo "[1/2] Running RustyClean AUTO (with fastp QC) ..."
    rc_out="${ds_out}/rc_auto"
    rc_ckpt="${ds_out}/rc_auto_ckpt"
    rm -rf "${rc_out}" "${rc_ckpt}"
    time_log="${ds_out}/rc_auto.time.log"
    /usr/bin/time -v -o "${time_log}" \
        rustyclean \
            --r1 "${r1}" \
            --host-removal-mode auto \
            --kraken2-db "${KRAKEN2_DB}" \
            --host-index "${HOST_INDEX}" \
            --auto-survey \
            -o "${rc_out}" \
            -t "${THREADS}" \
            --checkpoint-dir "${rc_ckpt}" \
            > "${ds_out}/rc_auto.log" 2>&1
    IFS=, read -r rc_runtime rc_mem <<< "$(parse_time_log "${time_log}")"
    rc_clean=$(find "${rc_out}" \( -name '*_clean_R1.fastq.gz' -o -name '*_clean.fastq.gz' \) -print -quit)
    rc_size=$(stat -c%s "${rc_clean}" 2>/dev/null || echo "unknown")
    rc_backend=$(sed 's/\x1b\[[0-9;]*m//g' "${ds_out}/rc_auto.log" 2>/dev/null | grep "chosen_backend" | tail -1 | sed -E 's/.*chosen_backend=\"?([^\"]+)\"?.*/\1/' || echo "unknown")
    rc_hostpct=$(sed 's/\x1b\[[0-9;]*m//g' "${ds_out}/rc_auto.log" 2>/dev/null | grep "estimated_host_pct" | tail -1 | sed -E 's/.*estimated_host_pct=\"?([^\"]+)\"?.*/\1/' || echo "unknown")
    echo "${dataset},rustyclean_auto,${rc_runtime},${rc_mem},${rc_size},${rc_backend},${rc_hostpct},$(date -Iseconds)" >> "${METRICS}"
    echo "RustyClean AUTO: ${rc_runtime}s, ${rc_mem}KB, backend=${rc_backend}, host_pct=${rc_hostpct}, size=${rc_size}B"

    # --- KneadData (QC + host removal) ---
    echo "[2/2] Running KneadData ..."
    kd_out="${ds_out}/kneaddata"
    rm -rf "${kd_out}"
    time_log="${ds_out}/kneaddata.time.log"
    /usr/bin/time -v -o "${time_log}" \
        kneaddata \
            -un "${r1}" \
            -db "${HOST_INDEX}" \
            -o "${kd_out}" \
            -t "${THREADS}" \
            > "${ds_out}/kneaddata.log" 2>&1
    IFS=, read -r kd_runtime kd_mem <<< "$(parse_time_log "${time_log}")"
    # KneadData SE final clean reads: prefer *clean*.fastq, otherwise largest excluding intermediates
    kd_clean=$(find "${kd_out}" -maxdepth 1 -type f -name '*clean*.fastq' -print -quit 2>/dev/null)
    if [[ -z "${kd_clean}" ]]; then
        kd_clean=$(find "${kd_out}" -maxdepth 1 -type f -name '*.fastq' ! -name '*contam*' ! -name '*trimmed*' ! -name '*repeats*' -printf '%s %p\n' 2>/dev/null | sort -nr | head -1 | awk '{print $2}')
    fi
    kd_size=$(stat -c%s "${kd_clean}" 2>/dev/null || echo "unknown")
    echo "${dataset},kneaddata,${kd_runtime},${kd_mem},${kd_size},bowtie2,NA,$(date -Iseconds)" >> "${METRICS}"
    echo "KneadData: ${kd_runtime}s, ${kd_mem}KB, size=${kd_size}B"

done

echo "============================================"
echo "All done. Metrics: ${METRICS}"
cat "${METRICS}"
echo "============================================"
