#!/bin/bash
#SBATCH --job-name=rc_auto_boundary
#SBATCH --array=0-5
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=128G
#SBATCH --time=06:00:00
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


# The hardcoded PATH below lists fastp, kraken2 and bowtie2 only. minimap2 and
# centrifuge live in the project conda environment, so centrifuge failed on
# every dataset with "not found in PATH" while the other backends ran -- a
# comparison silently missing one of the four things it compares. Prepend the
# project environment as well, which is what activate_conda does.
if [ -z "${REPO_DIR:-}" ]; then
    for _cand in "${SLURM_SUBMIT_DIR:-}" \
                 "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)" \
                 /lustre1/g/aos_shihuang/rustyclean-paper; do
        if [ -n "$_cand" ] && [ -f "$_cand/scripts/hpc/config.sh" ]; then
            REPO_DIR="$_cand"; break
        fi
    done
fi
if [ -n "${REPO_DIR:-}" ] && [ -f "$REPO_DIR/scripts/hpc/config.sh" ]; then
    source "$REPO_DIR/scripts/hpc/config.sh"
    activate_conda
else
    source /group/aos_shihuang/conda/etc/profile.d/conda.sh
fi
export PATH="/group/aos_shihuang/conda/envs/fastp/bin:/group/aos_shihuang/conda/envs/kraken2/bin:/group/aos_shihuang/conda/envs/bowtie2/bin:$HOME/.local/bin:${PATH}"

DATA_DIR="${SCRATCH_DIR:-/scr/u/$USER/rustyclean-paper}/data/enhanced"
RESULTS_DIR="${RUNS_DIR:-/lustre1/g/aos_shihuang/rustyclean-paper/runs}/auto_decision_boundary"
METRICS_DIR="${RESULTS_DIR}/metrics"
# Own file per experiment: these scripts run concurrently, and a shared
# performance.csv interleaved their rows under a single header.
METRICS_FILE="${METRICS_DIR}/performance_auto_boundary${ARRAY_TAG}.csv"
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

# Fixed 10 M read count, varying host fraction, to isolate the backend crossover.
DATASETS=(
    "10M_0pct_med_lognormal_SE"
    "10M_1pct_med_lognormal_SE"
    "10M_5pct_med_lognormal_SE"
    "10M_10pct_med_even_SE"
    "10M_30pct_med_lognormal_SE"
    "10M_100pct_med_lognormal_SE"
)

if [ -n "${SLURM_ARRAY_TASK_ID:-}" ]; then
    if [ "$SLURM_ARRAY_TASK_ID" -ge "${#DATASETS[@]}" ]; then
        echo "array task $SLURM_ARRAY_TASK_ID is past the end of ${#DATASETS[@]} datasets; nothing to do"
        exit 0
    fi
    DATASETS=( "${DATASETS[$SLURM_ARRAY_TASK_ID]}" )
    echo "array task $SLURM_ARRAY_TASK_ID -> ${DATASETS[0]}"
fi

MODES=("bowtie2" "kraken2")

mkdir -p "${METRICS_DIR}" "${LOGS_DIR}"

echo "Job started at: $(date)"
echo "Host: $(hostname)"
echo "Threads: ${THREADS}"

# Start each run from a fresh file. Writing the header only when the file is
# absent meant a rerun appended to the previous run's rows, so the first
# backend comparison (with centrifuge failing and the large Bowtie2 index) and
# the second sat in one CSV and were averaged together.
echo "mode,dataset,rep,runtime_seconds,max_memory_kb,timestamp" > "${METRICS_FILE}"

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

        echo "  [${MODE}] Running on ${DATASET}..."
        /usr/bin/time -v -o "${timefile}" \
            "${RUSTYCLEAN}" \
                --mode "${MODE}" \
                --skip-qc \
                --r1 "${R1}" \
                --host-index "${BT2_INDEX}" \
                --kraken2-db "${KRAKEN2_DB}" \
                --max-contamination 100.0 \
                -o "${OUT}" \
                -t "${THREADS}" \
                --checkpoint-dir "${OUT}/.checkpoints" \
                --clean \
                > "${logfile}" 2>&1 || {
            echo "  [${MODE}] FAILED on ${DATASET}" >&2
            echo "${MODE},${DATASET},1,FAILED,,$(date -Iseconds)" >> "${METRICS_FILE}"
            continue
        }

        read runtime_sec max_mem < <(parse_time "${timefile}")
        echo "${MODE},${DATASET},1,${runtime_sec},${max_mem},$(date -Iseconds)" >> "${METRICS_FILE}"
        echo "  [${MODE}] Done: runtime=${runtime_sec}s, max_mem=${max_mem}kB"
    done
done

echo "Job finished at: $(date)"
