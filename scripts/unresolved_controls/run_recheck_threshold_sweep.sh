#!/bin/bash
# Sweep the RustyClean conditional verification threshold on all six datasets.
#SBATCH --job-name=rc_threshold_sweep
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
[[ -x "${RUSTYCLEAN}" ]] || { echo "RustyClean not executable: ${RUSTYCLEAN}" >&2; exit 2; }
control_require_file "${DEACON_INDEX}"
control_require_hostile_index "${HOSTILE_INDEX}"
read -r -a THRESHOLDS <<< "${THRESHOLDS:-0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.50 0.60 0.80 1.01}"
DATASET="${DATASETS[$((SLURM_ARRAY_TASK_ID))]}"
DATASET_DIR="${DATA_DIR}/${DATASET}"
TRUTH="${DATASET_DIR}/ground_truth_labels.txt"
control_require_file "${TRUTH}"
if [[ -s "${DATASET_DIR}/reads_R1.fastq.gz" ]]; then
    INPUT=(--r1 "${DATASET_DIR}/reads_R1.fastq.gz" --r2 "${DATASET_DIR}/reads_R2.fastq.gz")
else
    INPUT=(--r1 "${DATASET_DIR}/reads.fastq.gz")
fi

RESULTS_DIR="${RESULTS_ROOT}/${RESULTS_SUBDIR:-threshold_sweep}"
METRICS="${RESULTS_DIR}/metrics/performance.csv"
ACCURACY="${RESULTS_DIR}/metrics/accuracy.csv"
LOGS="${RESULTS_DIR}/logs"
mkdir -p "${RESULTS_DIR}/metrics" "${RESULTS_DIR}/outputs" "${LOGS}" "${RESULTS_WORK_ROOT}"
WORK="${RESULTS_WORK_ROOT}/threshold_task${SLURM_ARRAY_TASK_ID:-0}_${SLURM_JOB_ID:-0}"
mkdir -p "${WORK}"
trap 'rm -rf "${WORK}"' EXIT

for threshold in "${THRESHOLDS[@]}"; do
    condition="threshold_${threshold}"
    for rep in $(seq 1 "${REPS}"); do
        control_have_performance "${METRICS}" rustyclean_auto "${condition}" "${DATASET}" "${rep}" && continue
        out="${RESULTS_DIR}/outputs/${DATASET}/${condition}/rep${rep}"
        mkdir -p "${out}"
        timefile="${LOGS}/${DATASET}_${condition}_rep${rep}.time"
        logfile="${LOGS}/${DATASET}_${condition}_rep${rep}.log"
        /usr/bin/time -v -o "${timefile}" "${RUSTYCLEAN}" "${INPUT[@]}" \
            --deacon-index "${DEACON_INDEX}" --host-index "${HOSTILE_INDEX}" \
            --recheck-threshold "${threshold}" --max-contamination 100.0 \
            --fastp-compression 1 --deacon-compression-level 2 \
            --work-dir "${WORK}/${condition}_work_rep${rep}" \
            --checkpoint-dir "${out}/.checkpoints" --clean -o "${out}" -t "${THREADS}" \
            >"${logfile}" 2>&1
        elapsed="$(control_gnu_time_field "${timefile}" 'Elapsed \(wall clock\) time')"
        rss="$(control_gnu_time_field "${timefile}" 'Maximum resident set size')"
        stage="$(control_stage_metrics "${out}")"
        recheck_ms="$(control_stage_field "${stage}" bowtie2_recheck_ms)"
        deacon_prop="$(control_stage_field "${stage}" deacon_removed_proportion)"
        [[ -n "${recheck_ms}" ]] || recheck_ms=null
        control_append_performance "${METRICS}" rustyclean_auto "${condition}" "${DATASET}" "${rep}" \
            "$(control_elapsed_seconds "${elapsed}")" "${rss}" \
            "{\"threshold\":${threshold},\"bowtie2_recheck_ms\":${recheck_ms},\"deacon_removed_proportion\":\"${deacon_prop}\"}"
        control_score rustyclean_auto "${condition}" "${DATASET}" "${rep}" "${TRUTH}" "${out}" "${ACCURACY}"
        rm -rf "${out}"
    done
done
