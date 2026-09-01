#!/bin/bash
#SBATCH --job-name=rc_auto_skipqc_v2
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=yfz96@connect.hku.hk
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err

set -euo pipefail

# Tools: RustyClean, Hostile, fastp, bowtie2, samtools, kraken2, seqtk
export PATH="/lustre1/g/aos_shihuang/rustyclean/target/release:/lustre1/g/aos_shihuang/tools/samtools/samtools-1.21:$HOME/.conda/envs/hostile-centrifuge/bin:/group/aos_shihuang/conda/envs/fastp/bin:/group/aos_shihuang/conda/envs/kraken2/bin:/group/aos_shihuang/conda/envs/seqtk/bin:${PATH}"

DATA_DIR="${SCRATCH_DIR:-/scr/u/$USER/rustyclean-paper}/data/enhanced"
OUTDIR="${SCRATCH_DIR:-/scr/u/$USER/rustyclean-paper}/rc_auto_skipqc_hostile_v2"
mkdir -p "${OUTDIR}"

METRICS="${OUTDIR}/rc_auto_skipqc_hostile_metrics.csv"
echo "dataset,tool,runtime_seconds,max_memory_kb,output_size_bytes,backend,estimated_host_pct,timestamp" > "${METRICS}"

DATASETS=(
    "5M_1pct_low_even_SE"
    "5M_5pct_low_even_SE"
    "10M_10pct_med_even_SE"
    "30M_50pct_high_skewed_SE"
    "30M_70pct_med_lognormal_SE"
    "30M_90pct_med_lognormal_SE"
    "60M_90pct_high_lognormal_SE"
    "60M_99pct_med_lognormal_SE"
)

KRAKEN2_DB="${KRAKEN2_DB:-/lustre1/g/aos_shihuang/databases/rustyclean_human_t2t_only/kraken2/t2t_only}"
HOST_INDEX="${BOWTIE2_INDEX:?BOWTIE2_INDEX is not set; source scripts/hpc/config.sh}"
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

    # --- RustyClean AUTO + --skip-qc ---
    echo "[1/2] Running RustyClean AUTO --skip-qc ..."
    rc_out="${ds_out}/rc_auto_skipqc"
    rc_ckpt="${ds_out}/rc_auto_skipqc_ckpt"
    rm -rf "${rc_out}" "${rc_ckpt}"
    time_log="${ds_out}/rc_auto_skipqc.time.log"
    /usr/bin/time -v -o "${time_log}" \
        rustyclean \
            --r1 "${r1}" \
            --host-removal-mode auto \
            --kraken2-db "${KRAKEN2_DB}" \
            --host-index "${HOST_INDEX}" \
            --auto-survey \
            --skip-qc \
            -o "${rc_out}" \
            -t "${THREADS}" \
            --checkpoint-dir "${rc_ckpt}" \
            > "${ds_out}/rc_auto_skipqc.log" 2>&1
    read -r rc_runtime rc_mem <<< "$(parse_time_log "${time_log}")"
    rc_clean=$(find "${rc_out}" -name '*_clean_R1.fastq.gz' -print -quit)
    rc_size=$(stat -c%s "${rc_clean}" 2>/dev/null || echo "unknown")
    rc_backend=$(grep "chosen_backend" "${ds_out}/rc_auto_skipqc.log" 2>/dev/null | tail -1 | sed -E 's/.*chosen_backend=\"([^\"]+)\".*/\1/' || echo "unknown")
    rc_hostpct=$(grep "estimated_host_pct" "${ds_out}/rc_auto_skipqc.log" 2>/dev/null | tail -1 | sed -E 's/.*estimated_host_pct=\"([^\"]+)\".*/\1/' || echo "unknown")
    echo "${dataset},rustyclean_auto_skipqc,${rc_runtime},${rc_mem},${rc_size},${rc_backend},${rc_hostpct},$(date -Iseconds)" >> "${METRICS}"
    echo "RustyClean AUTO --skip-qc: ${rc_runtime}s, ${rc_mem}KB, backend=${rc_backend}, host_pct=${rc_hostpct}, size=${rc_size}B"

    # --- Hostile on raw reads ---
    echo "[2/2] Running Hostile on raw reads ..."
    hostile_out="${ds_out}/hostile_raw"
    rm -rf "${hostile_out}"
    time_log="${ds_out}/hostile_raw.time.log"
    /usr/bin/time -v -o "${time_log}" \
        hostile clean \
            --fastq1 "${r1}" \
            --aligner bowtie2 \
            --index "${HOST_INDEX}" \
            -o "${hostile_out}" \
            -t "${THREADS}" \
            --airplane \
            > "${ds_out}/hostile_raw.log" 2>&1
    read -r hs_runtime hs_mem <<< "$(parse_time_log "${time_log}")"
    hs_clean=$(find "${hostile_out}" -name '*.fastq.gz' -print -quit)
    hs_size=$(stat -c%s "${hs_clean}" 2>/dev/null || echo "unknown")
    echo "${dataset},hostile_raw,${hs_runtime},${hs_mem},${hs_size},bowtie2,NA,$(date -Iseconds)" >> "${METRICS}"
    echo "Hostile raw: ${hs_runtime}s, ${hs_mem}KB, size=${hs_size}B"

done

echo "============================================"
echo "All done. Metrics: ${METRICS}"
cat "${METRICS}"
echo "============================================"
