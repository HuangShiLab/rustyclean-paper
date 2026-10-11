#!/bin/bash
# Equal-thread paired panel: RustyClean AUTO versus sequential fastp+Hostile.
#SBATCH --job-name=equal_thread_panel
#SBATCH --partition=intel
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --exclusive
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
control_require_tool fastp
control_require_tool "${HOSTILE_BIN}"
[[ -x "${RUSTYCLEAN}" ]] || { echo "RustyClean not executable: ${RUSTYCLEAN}" >&2; exit 2; }
control_require_file "${DEACON_INDEX}"
control_require_hostile_index "${HOSTILE_INDEX}"

DATASET="${DATASETS[$((SLURM_ARRAY_TASK_ID))]}"
DATASET_DIR="${DATA_DIR}/${DATASET}"
TRUTH="${DATASET_DIR}/ground_truth_labels.txt"
control_require_file "${TRUTH}"
R2=""
if [[ -s "${DATASET_DIR}/reads_R1.fastq.gz" ]]; then
    R1="${DATASET_DIR}/reads_R1.fastq.gz"
    R2="${DATASET_DIR}/reads_R2.fastq.gz"
    RC_INPUT=(--r1 "${R1}" --r2 "${R2}")
else
    R1="${DATASET_DIR}/reads.fastq.gz"
    RC_INPUT=(--r1 "${R1}")
fi
control_require_file "${R1}"

RESULTS_DIR="${RESULTS_ROOT}/equal_thread_panel"
METRICS="${RESULTS_DIR}/metrics/performance.csv"
ACCURACY="${RESULTS_DIR}/metrics/accuracy.csv"
LOGS="${RESULTS_DIR}/logs"
mkdir -p "${RESULTS_DIR}/metrics" "${RESULTS_DIR}/outputs" "${LOGS}" "${RESULTS_WORK_ROOT}"
WORK="${RESULTS_WORK_ROOT}/equal_thread_task${SLURM_ARRAY_TASK_ID:-0}_${SLURM_JOB_ID:-0}"
mkdir -p "${WORK}"
trap 'rm -rf "${WORK}"' EXIT
echo "dataset=${DATASET} threads=${THREADS} node=${SLURMD_NODENAME:-$(hostname)}"

# Warm input and both index types before any timed replicate.
cat "${R1}" >/dev/null
[[ -z "${R2}" ]] || cat "${R2}" >/dev/null
cat "${DEACON_INDEX}" >/dev/null
for index_file in "${HOSTILE_INDEX}".*; do
    [[ -f "${index_file}" ]] && cat "${index_file}" >/dev/null || true
done

run_rustyclean() {
    local rep="$1" out="${RESULTS_DIR}/outputs/${DATASET}/rustyclean/rep${rep}"
    mkdir -p "${out}"
    local timefile="${LOGS}/${DATASET}_rustyclean_rep${rep}.time"
    local logfile="${LOGS}/${DATASET}_rustyclean_rep${rep}.log"
    /usr/bin/time -v -o "${timefile}" "${RUSTYCLEAN}" "${RC_INPUT[@]}" \
        --deacon-index "${DEACON_INDEX}" --host-index "${HOSTILE_INDEX}" \
        --max-contamination 100.0 --fastp-compression 1 --deacon-compression-level 2 \
        --work-dir "${WORK}/rc_work_rep${rep}" --checkpoint-dir "${out}/.checkpoints" \
        --clean -o "${out}" -t "${THREADS}" >"${logfile}" 2>&1
    local elapsed rss stage
    elapsed="$(control_gnu_time_field "${timefile}" 'Elapsed \(wall clock\) time')"
    rss="$(control_gnu_time_field "${timefile}" 'Maximum resident set size')"
    stage="$(control_stage_metrics "${out}")"
    control_append_performance "${METRICS}" rustyclean_auto auto_deacon_default \
        "${DATASET}" "${rep}" "$(control_elapsed_seconds "${elapsed}")" "${rss}" \
        "{\"stage_metrics\":\"${stage}\"}"
    control_score rustyclean_auto auto_deacon_default "${DATASET}" "${rep}" "${TRUTH}" "${out}" "${ACCURACY}"
    rm -rf "${out}"
}

run_hostile() {
    local rep="$1" out="${RESULTS_DIR}/outputs/${DATASET}/hostile/rep${rep}"
    local trimmed="${WORK}/hostile_trimmed_rep${rep}.fastq.gz"
    mkdir -p "${out}"
    local fastp_time="${LOGS}/${DATASET}_hostile_fastp_rep${rep}.time"
    local hostile_time="${LOGS}/${DATASET}_hostile_rep${rep}.time"
    if [[ -n "${R2}" ]]; then
        /usr/bin/time -v -o "${fastp_time}" fastp --in1 "${R1}" --in2 "${R2}" \
            --out1 "${trimmed}" --out2 "${trimmed%.fastq.gz}_R2.fastq.gz" \
            --json "${out}/fastp.json" --html "${out}/fastp.html" --thread "${THREADS}" \
            --compression 1 --cut_front --cut_tail --qualified_quality_phred 20 \
            --length_required 50 >"${LOGS}/${DATASET}_hostile_fastp_rep${rep}.log" 2>&1
        HOSTILE_INPUT=(--fastq1 "${trimmed}" --fastq2 "${trimmed%.fastq.gz}_R2.fastq.gz")
    else
        /usr/bin/time -v -o "${fastp_time}" fastp --in1 "${R1}" --out1 "${trimmed}" \
            --json "${out}/fastp.json" --html "${out}/fastp.html" --thread "${THREADS}" \
            --compression 1 --cut_front --cut_tail --qualified_quality_phred 20 \
            --length_required 50 >"${LOGS}/${DATASET}_hostile_fastp_rep${rep}.log" 2>&1
        HOSTILE_INPUT=(--fastq1 "${trimmed}")
    fi
    /usr/bin/time -v -o "${hostile_time}" "${HOSTILE_BIN}" clean "${HOSTILE_INPUT[@]}" \
        --aligner bowtie2 --index "${HOSTILE_INDEX}" -o "${out}" \
        --threads "${THREADS}" --airplane --force >"${LOGS}/${DATASET}_hostile_rep${rep}.log" 2>&1
    local runtime rss
    runtime="$("${PYTHONBIN}" - "${fastp_time}" "${hostile_time}" <<'PY'
import sys
def seconds(path):
    for line in open(path, encoding='utf-8'):
        if line.strip().startswith('Elapsed (wall clock) time'):
            value = line.strip().split()[-1]
            return sum(float(x) * 60 ** i for i, x in enumerate(reversed(value.split(':'))))
    raise SystemExit(f'missing elapsed time in {path}')
print(f'{seconds(sys.argv[1]) + seconds(sys.argv[2]):.3f}')
PY
)"
    rss="$(control_gnu_time_field "${hostile_time}" 'Maximum resident set size')"
    control_append_performance "${METRICS}" fastp_hostile fastp_plus_hostile \
        "${DATASET}" "${rep}" "${runtime}" "${rss}" \
        '{"wall_rule":"sum sequential stages","rss_rule":"maximum stage RSS"}'
    control_score fastp_hostile fastp_plus_hostile "${DATASET}" "${rep}" "${TRUTH}" "${out}" "${ACCURACY}"
    rm -rf "${out}"
    rm -f "${trimmed}" "${trimmed%.fastq.gz}_R2.fastq.gz"
}

for rep in $(seq 1 "${REPS}"); do
    control_have_performance "${METRICS}" rustyclean_auto auto_deacon_default "${DATASET}" "${rep}" || run_rustyclean "${rep}"
    control_have_performance "${METRICS}" fastp_hostile fastp_plus_hostile "${DATASET}" "${rep}" || run_hostile "${rep}"
done
