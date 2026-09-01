#!/bin/bash
#SBATCH --job-name=real_data
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=128G
#SBATCH --time=24:00:00
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err

set -e

source /group/aos_shihuang/conda/etc/profile.d/conda.sh
export PATH="/group/aos_shihuang/conda/envs/fastp/bin:/group/aos_shihuang/conda/envs/kraken2/bin:/group/aos_shihuang/conda/envs/bowtie2/bin:/group/aos_shihuang/conda/envs/kneaddata/bin:$HOME/.local/bin:${PATH}"

DATA_BASE="${SCRATCH_DIR:-/scr/u/$USER/rustyclean-paper}/real_data"
RESULTS_DIR="${RUNS_DIR:-/lustre1/g/aos_shihuang/rustyclean-paper/runs}/real_data_results"
METRICS_DIR="${RESULTS_DIR}/metrics"
LOGS_DIR="${RESULTS_DIR}/logs"

THREADS=8
RUSTYCLEAN="/lustre1/g/aos_shihuang/rustyclean/target/release/rustyclean"
KRAKEN2_DB="/lustre1/g/aos_shihuang/databases/rustyclean_human_t2t_only/kraken2/t2t_only"
BT2_INDEX="${HOSTILE_INDEX:-$HOME/.local/share/hostile/human-t2t-hla}"
KNEADDATA_DB="/lustre1/g/aos_shihuang/databases/kneaddata/hg_39"

mkdir -p "${METRICS_DIR}" "${LOGS_DIR}"

echo "Job started at: $(date)"
echo "Host: $(hostname)"
echo "Threads: ${THREADS}"

if [ ! -f "${METRICS_DIR}/performance.csv" ]; then
    echo "tool,sample,layout,runtime_seconds,max_memory_kb,timestamp" > "${METRICS_DIR}/performance.csv"
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

run_sample() {
    local sample="$1"
    local layout="$2"
    local r1="$3"
    local r2="$4"

    echo "=== Sample: ${sample} (${layout}) ==="

    # RustyClean auto
    OUT="${RESULTS_DIR}/rustyclean/${sample}"
    rm -rf "${OUT}"
    mkdir -p "${OUT}"
    logfile="${LOGS_DIR}/rustyclean_${sample}.log"
    timefile="${LOGS_DIR}/rustyclean_${sample}.time"

    echo "  [RustyClean auto] Running..."
    local input_args="--r1 ${r1}"
    if [ "${layout}" == "PE" ]; then
        input_args="--r1 ${r1} --r2 ${r2}"
    fi

    /usr/bin/time -v -o "${timefile}" \
        "${RUSTYCLEAN}" \
            --mode auto \
            --auto-survey \
            ${input_args} \
            --kraken2-db "${KRAKEN2_DB}" \
            --host-index "${BT2_INDEX}" \
            --max-contamination 100.0 \
            -o "${OUT}" \
            -t "${THREADS}" \
            --checkpoint-dir "${OUT}/.checkpoints" \
            --clean \
            > "${logfile}" 2>&1 || {
        echo "  [RustyClean auto] FAILED on ${sample}" >&2
        echo "rustyclean,${sample},${layout},FAILED,,$(date -Iseconds)" >> "${METRICS_DIR}/performance.csv"
    }
    read rc_runtime rc_mem < <(parse_time "${timefile}")
    echo "rustyclean,${sample},${layout},${rc_runtime},${rc_mem},$(date -Iseconds)" >> "${METRICS_DIR}/performance.csv"
    echo "  [RustyClean auto] Done: runtime=${rc_runtime}s, max_mem=${rc_mem}kB"

    # KneadData
    KD_OUT="${RESULTS_DIR}/kneaddata/${sample}"
    rm -rf "${KD_OUT}"
    mkdir -p "${KD_OUT}"
    kd_log="${LOGS_DIR}/kneaddata_${sample}.log"
    kd_time="${LOGS_DIR}/kneaddata_${sample}.time"

    echo "  [KneadData] Running..."
    local kd_input="-un ${r1}"
    if [ "${layout}" == "PE" ]; then
        kd_input="-i1 ${r1} -i2 ${r2}"
    fi

    /usr/bin/time -v -o "${kd_time}" \
        kneaddata ${kd_input} --output-prefix clean \
            -db "${KNEADDATA_DB}" --threads "${THREADS}" \
            --output "${KD_OUT}" --remove-intermediate-output \
            > "${kd_log}" 2>&1 || {
        echo "  [KneadData] FAILED on ${sample}" >&2
        echo "kneaddata,${sample},${layout},FAILED,,$(date -Iseconds)" >> "${METRICS_DIR}/performance.csv"
    }
    read kd_runtime kd_mem < <(parse_time "${kd_time}")
    echo "kneaddata,${sample},${layout},${kd_runtime},${kd_mem},$(date -Iseconds)" >> "${METRICS_DIR}/performance.csv"
    echo "  [KneadData] Done: runtime=${kd_runtime}s, max_mem=${kd_mem}kB"
}

# Oral saliva: PE
run_sample "oral_saliva" "PE" \
    "${DATA_BASE}/oral_saliva/reads_R1.fastq.gz" \
    "${DATA_BASE}/oral_saliva/reads_R2.fastq.gz"

# Vaginal swab: SE
run_sample "vaginal_swab" "SE" \
    "${DATA_BASE}/vaginal_swab/reads.fastq.gz" ""

# Breast cancer stool: PE
run_sample "breast_cancer_stool" "PE" \
    "${DATA_BASE}/breast_cancer_stool/reads_R1.fastq.gz" \
    "${DATA_BASE}/breast_cancer_stool/reads_R2.fastq.gz"

echo "Job finished at: $(date)"
