#!/bin/bash
# Cleanifier 1.3.x on the six simulated datasets; fixed default threshold 0.5.
#SBATCH --job-name=cleanifier_panel
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --time=24:00:00
#SBATCH --array=0-5
#SBATCH --output=logs/%x-%A_%a.out
#SBATCH --error=logs/%x-%A_%a.err

# Resolve the real repository even when SLURM executes from a spool copy.
if [[ -n "${SLURM_SUBMIT_DIR:-}" && -f "${SLURM_SUBMIT_DIR}/scripts/unresolved_controls/lib_controls.sh" ]]; then
    CONTROL_SCRIPT_DIR="${SLURM_SUBMIT_DIR}/scripts/unresolved_controls"
else
    CONTROL_SCRIPT_DIR="/lustre1/g/aos_shihuang/rustyclean-paper/scripts/unresolved_controls"
fi
export CONTROL_SCRIPT_DIR

source "${CONTROL_SCRIPT_DIR}/lib_controls.sh"
mapfile -t DATASETS < <(cat "${CONTROL_SCRIPT_DIR}/datasets_six.txt")
control_require_tool "${CLEANIFIER_BIN}"
CLEANIFIER_VERSION="$("${CLEANIFIER_BIN}" --version 2>&1 | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
[[ -n "${CLEANIFIER_VERSION}" ]] || { echo "cannot determine Cleanifier version" >&2; exit 2; }

DATASET="${DATASETS[$((SLURM_ARRAY_TASK_ID))]}"
DATASET_DIR="${DATA_DIR}/${DATASET}"
TRUTH="${DATASET_DIR}/ground_truth_labels.txt"
control_require_file "${TRUTH}"
if [[ -s "${DATASET_DIR}/reads_R1.fastq.gz" ]]; then
    INPUT=(--fastq "${DATASET_DIR}/reads_R1.fastq.gz" --pairs "${DATASET_DIR}/reads_R2.fastq.gz")
    INPUT_FILES=("${DATASET_DIR}/reads_R1.fastq.gz" "${DATASET_DIR}/reads_R2.fastq.gz")
else
    INPUT=(--fastq "${DATASET_DIR}/reads.fastq.gz")
    INPUT_FILES=("${DATASET_DIR}/reads.fastq.gz")
fi

RESULTS_DIR="${RESULTS_ROOT}/cleanifier_benchmark"
METRICS="${RESULTS_DIR}/metrics/performance.csv"
ACCURACY="${RESULTS_DIR}/metrics/accuracy.csv"
ENVIRONMENT="${RESULTS_DIR}/environment.txt"
LOGS="${RESULTS_DIR}/logs"
mkdir -p "${RESULTS_DIR}/metrics" "${RESULTS_DIR}/outputs" "${LOGS}" "${RESULTS_WORK_ROOT}"
WORK="${RESULTS_WORK_ROOT}/cleanifier_task${SLURM_ARRAY_TASK_ID:-0}_${SLURM_JOB_ID:-0}"
mkdir -p "${WORK}"
trap 'rm -rf "${WORK}"' EXIT

if [[ ! -s "${ENVIRONMENT}" ]]; then
    {
        echo "cleanifier_version=${CLEANIFIER_VERSION}"
        echo "index_setting=${CLEANIFIER_INDEX}"
        "${CLEANIFIER_BIN}" filter --help 2>&1 | sed -n '1,160p'
    } >"${ENVIRONMENT}"
fi

if [[ -s "${CLEANIFIER_INDEX}.filter" || -s "${CLEANIFIER_INDEX}.hash" ]]; then
    INDEX_BASE="${CLEANIFIER_INDEX}"
else
    mapfile -t CANDIDATES < <(find "$(dirname "${CLEANIFIER_INDEX}")" -maxdepth 1 \( -name '*.filter' -o -name '*.hash' \) -print 2>/dev/null | sort)
    ((${#CANDIDATES[@]} > 0)) || {
        echo "Cleanifier index missing; run: ${CLEANIFIER_BIN} download --checksum --dir '$(dirname "${CLEANIFIER_INDEX}")'" >&2
        exit 2
    }
    INDEX_BASE="${CANDIDATES[0]%.*}"
fi

for rep in $(seq 1 "${REPS}"); do
    control_have_performance "${METRICS}" cleanifier threshold_0.5 "${DATASET}" "${rep}" && continue
    out="${RESULTS_DIR}/outputs/${DATASET}/rep${rep}"
    prefix="${out}/cleanifier"
    mkdir -p "${out}"
    timefile="${LOGS}/${DATASET}_rep${rep}.time"
    logfile="${LOGS}/${DATASET}_rep${rep}.log"
    for file in "${INPUT_FILES[@]}"; do cat "${file}" >/dev/null; done
    for file in "${INDEX_BASE}.filter" "${INDEX_BASE}.hash" "${INDEX_BASE}.info"; do
        if [[ -e "${file}" ]]; then cat "${file}" >/dev/null; fi
    done
    /usr/bin/time -v -o "${timefile}" "${CLEANIFIER_BIN}" filter "${INPUT[@]}" \
        --index "${INDEX_BASE}" --out "${prefix}" --threads "${THREADS}" \
        --compression gz --compression-level 1 --compression-threads 2 --threshold 0.5 \
        >"${logfile}" 2>&1
    elapsed="$(control_gnu_time_field "${timefile}" 'Elapsed \(wall clock\) time')"
    rss="$(control_gnu_time_field "${timefile}" 'Maximum resident set size')"
    control_append_performance "${METRICS}" cleanifier threshold_0.5 "${DATASET}" "${rep}" \
        "$(control_elapsed_seconds "${elapsed}")" "${rss}" \
        "{\"cleanifier_version\":\"${CLEANIFIER_VERSION}\",\"index\":\"${INDEX_BASE}\"}"
    control_score cleanifier threshold_0.5 "${DATASET}" "${rep}" "${TRUTH}" "${out}" "${ACCURACY}"
    rm -rf "${out}"
done
