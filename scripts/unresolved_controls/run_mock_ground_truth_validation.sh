#!/bin/bash
# Generate exact-ground-truth mock/real-spike-in datasets and benchmark three arms.
#SBATCH --job-name=mock_truth_validation
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err

# Resolve the real repository even when SLURM executes from a spool copy.
if [[ -n "${SLURM_SUBMIT_DIR:-}" && -f "${SLURM_SUBMIT_DIR}/scripts/unresolved_controls/lib_controls.sh" ]]; then
    CONTROL_SCRIPT_DIR="${SLURM_SUBMIT_DIR}/scripts/unresolved_controls"
else
    CONTROL_SCRIPT_DIR="/lustre1/g/aos_shihuang/rustyclean-paper/scripts/unresolved_controls"
fi
export CONTROL_SCRIPT_DIR

source "${CONTROL_SCRIPT_DIR}/lib_controls.sh"
control_require_tool fastp
control_require_tool "${HOSTILE_BIN}"
control_require_tool "${CLEANIFIER_BIN}"
[[ -x "${RUSTYCLEAN}" ]] || { echo "RustyClean not executable: ${RUSTYCLEAN}" >&2; exit 2; }
control_require_hostile_index "${HOSTILE_INDEX}"

MANIFEST="${MANIFEST:?set MANIFEST to a CSV with class,label,path,abundance rows}"
READS="${READS:-2000000}"
HOST_FRACTION="${HOST_FRACTION:-0.20}"
READ_LENGTH="${READ_LENGTH:-150}"
PAIRED="${PAIRED:-0}"
REPLICATES="${REPLICATES:-3}"
SEED="${SEED:-731}"
DATA_ROOT="${MOCK_DATA_ROOT:-${RESULTS_ROOT}/mock_truth_data}"
RESULTS_DIR="${RESULTS_ROOT}/mock_truth_validation"
METRICS="${RESULTS_DIR}/metrics/performance.csv"
ACCURACY="${RESULTS_DIR}/metrics/accuracy.csv"
LOGS="${RESULTS_DIR}/logs"
mkdir -p "${RESULTS_DIR}/metrics" "${RESULTS_DIR}/outputs" "${LOGS}" "${DATA_ROOT}" "${RESULTS_WORK_ROOT}"

mapfile -t CANDIDATES < <(find "$(dirname "${CLEANIFIER_INDEX}")" -maxdepth 1 \( -name '*.filter' -o -name '*.hash' \) -print 2>/dev/null | sort)
((${#CANDIDATES[@]} > 0)) || { echo "Cleanifier human index missing" >&2; exit 2; }
CLEANIFIER_INDEX_BASE="${CANDIDATES[0]%.*}"

generate_dataset() {
    local rep="$1"
    local dataset="mock_${READS}_${HOST_FRACTION}_${READ_LENGTH}_rep${rep}"
    local out="${DATA_ROOT}/${dataset}"
    if [[ -s "${out}/ground_truth_labels.txt" && (-s "${out}/reads.fastq.gz" || -s "${out}/reads_R1.fastq.gz") ]]; then
        echo "${dataset}"
        return
    fi
    local paired_args=()
    [[ "${PAIRED}" = "1" ]] && paired_args=(--paired)
    "${PYTHONBIN}" "${CONTROL_SCRIPT_DIR}/generate_mock_ground_truth.py" \
        --manifest "${MANIFEST}" --output-dir "${out}" --reads "${READS}" \
        --host-fraction "${HOST_FRACTION}" --read-length "${READ_LENGTH}" \
        --seed "$((SEED + rep))" "${paired_args[@]}" >"${out}/generator_stdout.json"
    echo "${dataset}"
}

mapfile -t MOCK_DATASETS < <(for rep in $(seq 1 "${REPLICATES}"); do generate_dataset "${rep}"; done)

for dataset in "${MOCK_DATASETS[@]}"; do
    data="${DATA_ROOT}/${dataset}"
    truth="${data}/ground_truth_labels.txt"
    control_require_file "${truth}"
    rep="${dataset##*_rep}"
    work="${RESULTS_WORK_ROOT}/mock_truth_${SLURM_JOB_ID:-0}_${dataset}"
    mkdir -p "${work}"
    if [[ -s "${data}/reads_R1.fastq.gz" ]]; then
        RC_INPUT=(--r1 "${data}/reads_R1.fastq.gz" --r2 "${data}/reads_R2.fastq.gz")
        CLEAN_INPUT=(--fastq "${data}/reads_R1.fastq.gz" --pairs "${data}/reads_R2.fastq.gz")
        HOST_R1="${data}/reads_R1.fastq.gz"
        HOST_R2="${data}/reads_R2.fastq.gz"
    else
        RC_INPUT=(--r1 "${data}/reads.fastq.gz")
        CLEAN_INPUT=(--fastq "${data}/reads.fastq.gz")
        HOST_R1="${data}/reads.fastq.gz"
        HOST_R2=""
    fi

    rc_out="${RESULTS_DIR}/outputs/${dataset}/rustyclean"
    mkdir -p "${rc_out}"
    control_have_performance "${METRICS}" rustyclean_auto auto_deacon_default "${dataset}" "${rep}" || {
        /usr/bin/time -v -o "${LOGS}/${dataset}_rustyclean.time" "${RUSTYCLEAN}" "${RC_INPUT[@]}" \
            --deacon-index "${DEACON_INDEX}" --host-index "${HOSTILE_INDEX}" \
            --max-contamination 100.0 --fastp-compression 1 --deacon-compression-level 2 \
            --work-dir "${work}/rc_work" --checkpoint-dir "${rc_out}/.checkpoints" --clean \
            -o "${rc_out}" -t "${THREADS}" >"${LOGS}/${dataset}_rustyclean.log" 2>&1
        control_append_performance "${METRICS}" rustyclean_auto auto_deacon_default "${dataset}" "${rep}" \
            "$(control_elapsed_seconds "$(control_gnu_time_field "${LOGS}/${dataset}_rustyclean.time" 'Elapsed \(wall clock\) time')")" \
            "$(control_gnu_time_field "${LOGS}/${dataset}_rustyclean.time" 'Maximum resident set size')"
        control_score rustyclean_auto auto_deacon_default "${dataset}" "${rep}" "${truth}" "${rc_out}" "${ACCURACY}"
        rm -rf "${rc_out}"
    }

    hostile_out="${RESULTS_DIR}/outputs/${dataset}/hostile"
    trimmed="${work}/trimmed.fastq.gz"
    mkdir -p "${hostile_out}"
    if [[ -n "${HOST_R2}" ]]; then
        fastp --in1 "${HOST_R1}" --in2 "${HOST_R2}" --out1 "${trimmed}" \
            --out2 "${trimmed%.fastq.gz}_R2.fastq.gz" --json "${hostile_out}/fastp.json" \
            --html "${hostile_out}/fastp.html" --thread "${THREADS}" --compression 1 \
            --cut_front --cut_tail --qualified_quality_phred 20 --length_required 50 \
            >"${LOGS}/${dataset}_fastp.log" 2>&1
        HOSTILE_INPUT=(--fastq1 "${trimmed}" --fastq2 "${trimmed%.fastq.gz}_R2.fastq.gz")
    else
        fastp --in1 "${HOST_R1}" --out1 "${trimmed}" --json "${hostile_out}/fastp.json" \
            --html "${hostile_out}/fastp.html" --thread "${THREADS}" --compression 1 \
            --cut_front --cut_tail --qualified_quality_phred 20 --length_required 50 \
            >"${LOGS}/${dataset}_fastp.log" 2>&1
        HOSTILE_INPUT=(--fastq1 "${trimmed}")
    fi
    control_have_performance "${METRICS}" fastp_hostile fastp_plus_hostile "${dataset}" "${rep}" || {
        /usr/bin/time -v -o "${LOGS}/${dataset}_hostile.time" "${HOSTILE_BIN}" clean "${HOSTILE_INPUT[@]}" \
            --aligner bowtie2 --index "${HOSTILE_INDEX}" -o "${hostile_out}" \
            --threads "${THREADS}" --airplane --force >"${LOGS}/${dataset}_hostile.log" 2>&1
        control_append_performance "${METRICS}" fastp_hostile fastp_plus_hostile "${dataset}" "${rep}" \
            "$(control_elapsed_seconds "$(control_gnu_time_field "${LOGS}/${dataset}_hostile.time" 'Elapsed \(wall clock\) time')")" \
            "$(control_gnu_time_field "${LOGS}/${dataset}_hostile.time" 'Maximum resident set size')" \
            '{"timing_note":"Hostile stage only; fastp logged separately"}'
        control_score fastp_hostile fastp_plus_hostile "${dataset}" "${rep}" "${truth}" "${hostile_out}" "${ACCURACY}"
        rm -rf "${hostile_out}"
    }

    cleanifier_out="${RESULTS_DIR}/outputs/${dataset}/cleanifier"
    mkdir -p "${cleanifier_out}"
    control_have_performance "${METRICS}" cleanifier threshold_0.5 "${dataset}" "${rep}" || {
        /usr/bin/time -v -o "${LOGS}/${dataset}_cleanifier.time" "${CLEANIFIER_BIN}" filter \
            "${CLEAN_INPUT[@]}" --index "${CLEANIFIER_INDEX_BASE}" --out "${cleanifier_out}/cleanifier" \
            --threads "${THREADS}" --compression gz --compression-level 1 --compression-threads 2 \
            --threshold 0.5 >"${LOGS}/${dataset}_cleanifier.log" 2>&1
        control_append_performance "${METRICS}" cleanifier threshold_0.5 "${dataset}" "${rep}" \
            "$(control_elapsed_seconds "$(control_gnu_time_field "${LOGS}/${dataset}_cleanifier.time" 'Elapsed \(wall clock\) time')")" \
            "$(control_gnu_time_field "${LOGS}/${dataset}_cleanifier.time" 'Maximum resident set size')"
        control_score cleanifier threshold_0.5 "${dataset}" "${rep}" "${truth}" "${cleanifier_out}" "${ACCURACY}"
        rm -rf "${cleanifier_out}"
    }
    rm -rf "${work}"
done
