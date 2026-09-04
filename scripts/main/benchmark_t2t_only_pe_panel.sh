#!/bin/bash
#SBATCH --job-name=t2t_pe_panel
#SBATCH --array=0-2
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=128G
#SBATCH --time=08:00:00
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err

set -e

# Each dataset runs as its own SLURM array task, so they execute concurrently on
# different nodes instead of one after another inside a single job. Metrics go
# to a per-task file because concurrent appends to one CSV interleave; the
# stage-6 collector merges them. Running this script directly, with no array,
# processes the whole list and writes the unsuffixed file, as before.
ARRAY_TAG=""
[ -n "${SLURM_ARRAY_TASK_ID:-}" ] && ARRAY_TAG=".task${SLURM_ARRAY_TASK_ID}"


source /group/aos_shihuang/conda/etc/profile.d/conda.sh
export PATH="/group/aos_shihuang/conda/envs/fastp/bin:/group/aos_shihuang/conda/envs/kraken2/bin:/group/aos_shihuang/conda/envs/bowtie2/bin:/group/aos_shihuang/conda/envs/kneaddata/bin:$HOME/.local/bin:${PATH}"

DATA_DIR="${SCRATCH_DIR:-/scr/u/$USER/rustyclean-paper}/data/enhanced"
RESULTS_DIR="${RUNS_DIR:-/lustre1/g/aos_shihuang/rustyclean-paper/runs}/t2t_only_pe_panel"
METRICS_DIR="${RESULTS_DIR}/metrics"
# Own file per experiment: these scripts run concurrently, and a shared
# performance.csv interleaved their rows under a single header.
METRICS_FILE="${METRICS_DIR}/performance_pe_panel${ARRAY_TAG}.csv"
LOGS_DIR="${RESULTS_DIR}/logs"

THREADS=8
RUSTYCLEAN="/lustre1/g/aos_shihuang/rustyclean/target/release/rustyclean"
KRAKEN2_DB="/lustre1/g/aos_shihuang/databases/rustyclean_human_t2t_only/kraken2/t2t_only"
# RustyClean must be measured against the indexes this project builds, not
# against Hostile's. Hostile's default reference is T2T plus IPD-IMGT/HLA
# while every index here is T2T alone, so pointing RustyClean at it made the
# backend comparison a test of differing reference content rather than of the
# algorithms, and gave a script named t2t_only results that included HLA.
BT2_INDEX="${BOWTIE2_INDEX:?BOWTIE2_INDEX is not set; source scripts/hpc/config.sh}"
KNEADDATA_DB="/lustre1/g/aos_shihuang/databases/kneaddata/hg_39"

DATASETS=(
    "20M_10pct_med_even_PE"
    "20M_50pct_med_lognormal_PE"
    "20M_90pct_med_lognormal_PE"
)

if [ -n "${SLURM_ARRAY_TASK_ID:-}" ]; then
    if [ "$SLURM_ARRAY_TASK_ID" -ge "${#DATASETS[@]}" ]; then
        echo "array task $SLURM_ARRAY_TASK_ID is past the end of ${#DATASETS[@]} datasets; nothing to do"
        exit 0
    fi
    DATASETS=( "${DATASETS[$SLURM_ARRAY_TASK_ID]}" )
    echo "array task $SLURM_ARRAY_TASK_ID -> ${DATASETS[0]}"
fi

mkdir -p "${METRICS_DIR}" "${LOGS_DIR}"

echo "Job started at: $(date)"
echo "Host: $(hostname)"
echo "Threads: ${THREADS}"

# Start each run from a fresh file. Writing the header only when the file is
# absent meant a rerun appended to the previous run's rows, so the first
# backend comparison (with centrifuge failing and the large Bowtie2 index) and
# the second sat in one CSV and were averaged together.
echo "tool,dataset,rep,runtime_seconds,max_memory_kb,timestamp" > "${METRICS_FILE}"

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

for DATASET in "${DATASETS[@]}"; do
    R1="${DATA_DIR}/${DATASET}/reads_R1.fastq.gz"
    R2="${DATA_DIR}/${DATASET}/reads_R2.fastq.gz"
    if [ ! -f "${R1}" ] || [ ! -f "${R2}" ]; then
        echo "WARNING: Input not found: ${R1} / ${R2}" >&2
        continue
    fi

    echo "=== Processing dataset: ${DATASET} ==="

    # RustyClean T2T-only, 3 replicates
    for REP in 1 2 3; do
        OUT="${RESULTS_DIR}/rustyclean_t2t_only/${DATASET}/rep_${REP}"
        rm -rf "${OUT}"
        mkdir -p "${OUT}"
        logfile="${LOGS_DIR}/rustyclean_t2t_only_${DATASET}_rep${REP}.log"
        timefile="${LOGS_DIR}/rustyclean_t2t_only_${DATASET}_rep${REP}.time"

        echo "  [RC rep ${REP}] Running RustyClean T2T-only..."
        /usr/bin/time -v -o "${timefile}" \
            "${RUSTYCLEAN}" \
                --mode auto \
                --skip-qc \
                --auto-survey \
                --r1 "${R1}" --r2 "${R2}" \
                --kraken2-db "${KRAKEN2_DB}" \
                --host-index "${BT2_INDEX}" \
                --max-contamination 100.0 \
                -o "${OUT}" \
                -t "${THREADS}" \
                --checkpoint-dir "${OUT}/.checkpoints" \
                --clean \
                > "${logfile}" 2>&1 || {
            echo "  [RC rep ${REP}] FAILED on ${DATASET}" >&2
            echo "rustyclean_t2t_only,${DATASET},${REP},FAILED,,$(date -Iseconds)" >> "${METRICS_FILE}"
            continue
        }

        read runtime_sec max_mem < <(parse_time "${timefile}")
        echo "rustyclean_t2t_only,${DATASET},${REP},${runtime_sec},${max_mem},$(date -Iseconds)" >> "${METRICS_FILE}"
        echo "  [RC rep ${REP}] Done: runtime=${runtime_sec}s, max_mem=${max_mem}kB"
    done

    # Hostile PE
    HL_OUT="${RESULTS_DIR}/hostile/${DATASET}"
    rm -rf "${HL_OUT}"
    mkdir -p "${HL_OUT}"
    hl_log="${LOGS_DIR}/hostile_${DATASET}.log"
    hl_time="${LOGS_DIR}/hostile_${DATASET}.time"

    echo "  [Hostile] Running Hostile..."
    /usr/bin/time -v -o "${hl_time}" \
        hostile clean --fastq1 "${R1}" --fastq2 "${R2}" -o "${HL_OUT}" \
            --aligner bowtie2 --threads "${THREADS}" --force \
            > "${hl_log}" 2>&1 || {
        echo "  [Hostile] FAILED on ${DATASET}" >&2
        echo "hostile,${DATASET},1,FAILED,,$(date -Iseconds)" >> "${METRICS_FILE}"
    }
    read hl_runtime hl_mem < <(parse_time "${hl_time}")
    echo "hostile,${DATASET},1,${hl_runtime},${hl_mem},$(date -Iseconds)" >> "${METRICS_FILE}"
    echo "  [Hostile] Done: runtime=${hl_runtime}s, max_mem=${hl_mem}kB"

    # KneadData PE
    KD_OUT="${RESULTS_DIR}/kneaddata/${DATASET}"
    rm -rf "${KD_OUT}"
    mkdir -p "${KD_OUT}"
    kd_log="${LOGS_DIR}/kneaddata_${DATASET}.log"
    kd_time="${LOGS_DIR}/kneaddata_${DATASET}.time"

    echo "  [KneadData] Running KneadData..."
    /usr/bin/time -v -o "${kd_time}" \
        kneaddata -i1 "${R1}" -i2 "${R2}" --output-prefix clean \
            -db "${KNEADDATA_DB}" --threads "${THREADS}" \
            --output "${KD_OUT}" --remove-intermediate-output \
            > "${kd_log}" 2>&1 || {
        echo "  [KneadData] FAILED on ${DATASET}" >&2
        echo "kneaddata,${DATASET},1,FAILED,,$(date -Iseconds)" >> "${METRICS_FILE}"
    }
    read kd_runtime kd_mem < <(parse_time "${kd_time}")
    echo "kneaddata,${DATASET},1,${kd_runtime},${kd_mem},$(date -Iseconds)" >> "${METRICS_FILE}"
    echo "  [KneadData] Done: runtime=${kd_runtime}s, max_mem=${kd_mem}kB"

done

echo "Job finished at: $(date)"
