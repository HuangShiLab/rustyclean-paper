#!/bin/bash
#SBATCH --job-name=fastp_deacon_io
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=12:00:00
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err

set -euo pipefail

# SLURM does not inherit the interactive module/conda PATH. Add the fixed
# cluster tool locations used by the current benchmark suite.
export PATH="/home/shihuang/.conda/envs/sketch-benchmark/bin:/group/aos_shihuang/conda/envs/fastp/bin:/lustre1/g/aos_shihuang/tools/samtools/samtools-1.21:${PATH}"

# This benchmark measures the fastp -> Deacon handoff, so verification is
# disabled by default. Set RECHECK=1 to measure the complete AUTO pipeline on
# high-host samples, but do not mix those rows with handoff-only timings.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# SLURM copies the batch script to a spool directory, so BASH_SOURCE is not a
# reliable way to locate the repository after submission.
if [[ -z "${REPO_DIR:-}" ]]; then
    for _candidate in \
        "${SLURM_SUBMIT_DIR:-}" \
        "$(cd "${SCRIPT_DIR}/../.." 2>/dev/null && pwd)" \
        /lustre1/g/aos_shihuang/rustyclean-paper; do
        if [[ -n "${_candidate}" && -f "${_candidate}/scripts/hpc/cgroup_probe.sh" ]]; then
            REPO_DIR="${_candidate}"
            break
        fi
    done
fi
if [[ -z "${REPO_DIR:-}" || ! -f "${REPO_DIR}/scripts/hpc/cgroup_probe.sh" ]]; then
    echo "ERROR: cannot locate rustyclean-paper repository for cgroup_probe.sh" >&2
    exit 1
fi

# shellcheck source=cgroup_probe.sh
source "${REPO_DIR}/scripts/hpc/cgroup_probe.sh"

RUSTYCLEAN="${RUSTYCLEAN:-/lustre1/g/aos_shihuang/rustyclean/target/release/rustyclean}"
DEACON_INDEX="${DEACON_INDEX:-/lustre1/g/aos_shihuang/databases/deacon/panhuman-1.k31w15.idx}"
HOST_INDEX="${HOST_INDEX:-/home/shihuang/.local/share/hostile/human-t2t-hla}"
DATA_DIR="${DATA_DIR:-/scr/u/${USER}/rustyclean-paper/data/enhanced}"
RESULTS_DIR="${RESULTS_DIR:-/lustre1/g/aos_shihuang/rustyclean-paper/runs/fastp_deacon_io}"
THREADS="${THREADS:-16}"
REPS="${REPS:-2}"
RECHECK="${RECHECK:-0}"
FASTP_LEVELS="${FASTP_LEVELS:-1 2 4 6}"
DEACON_LEVEL="${DEACON_LEVEL:-2}"
DEACON_COMPRESSION_THREADS="${DEACON_COMPRESSION_THREADS:-0}"
OUTPUT_ON_SCRATCH="${OUTPUT_ON_SCRATCH:-1}"
DEACON_SERVER="${DEACON_SERVER:-0}"
LOCAL_SCRATCH="${LOCAL_SCRATCH:-${TMPDIR:-/tmp}/rustyclean_io_${SLURM_JOB_ID:-$$}}"

if [[ -n "${DATASETS:-}" ]]; then
    read -r -a DATASETS <<< "${DATASETS}"
else
    DATASETS=(
        "5M_1pct_low_even_SE"
        "10M_10pct_med_even_SE"
        "100M_90pct_high_lognormal_SE"
    )
fi

mkdir -p "${RESULTS_DIR}/metrics" "${RESULTS_DIR}/logs" "${LOCAL_SCRATCH}"

SERVER_DIR="${LOCAL_SCRATCH}/deacon_server"
SERVER_PID=""
cleanup_deacon_server() {
    if [[ -n "${SERVER_PID}" ]]; then
        (
            cd "${SERVER_DIR}" || exit 0
            deacon --use-server server stop >/dev/null 2>&1 || true
        )
        kill "${SERVER_PID}" 2>/dev/null || true
        wait "${SERVER_PID}" 2>/dev/null || true
    fi
}
trap cleanup_deacon_server EXIT

if [[ "${DEACON_SERVER}" = "1" ]]; then
    mkdir -p "${SERVER_DIR}"
    (
        cd "${SERVER_DIR}"
        deacon server start -t "${THREADS}" > server.log 2>&1
    ) &
    SERVER_PID=$!
    for _ in $(seq 1 300); do
        [[ -S "${SERVER_DIR}/deacon_server_socket" ]] && break
        kill -0 "${SERVER_PID}" 2>/dev/null || break
        sleep 0.2
    done
    if [[ ! -S "${SERVER_DIR}/deacon_server_socket" ]]; then
        echo "ERROR: Deacon server socket was not created" >&2
        cat "${SERVER_DIR}/server.log" >&2 || true
        exit 1
    fi
fi
CSV="${RESULTS_DIR}/metrics/fastp_deacon_io.csv"
echo "dataset,rep,fastp_compression,deacon_compression,deacon_compression_threads,threads,recheck,status,wall_s,user_s,sys_s,max_rss_kb,cgroup_cpu_s,fastp_ms,deacon_ms,recheck_ms,finalize_ms,deacon_seqs_in,deacon_seqs_out,deacon_bp_in,deacon_bp_out,deacon_total_s,deacon_bp_per_s" > "${CSV}"

parse_time_field() {
    local timefile="$1" pattern="$2"
    awk -F': ' -v pattern="${pattern}" '$0 ~ pattern {print $NF; exit}' "${timefile}"
}

elapsed_to_seconds() {
    awk -F: -v t="$1" 'BEGIN { n=split(t,a,":"); s=0; for(i=1;i<=n;i++) s=s*60+a[i]; printf "%.3f", s }'
}

append_stage_metrics() {
    local dataset="$1" rep="$2" level="$3" status="$4" wall_s="$5" user="$6" sys="$7" \
        rss="$8" cpu="$9" stage_json="${10}"

    python3 - "${CSV}" "${dataset}" "${rep}" "${level}" "${DEACON_LEVEL}" \
        "${DEACON_COMPRESSION_THREADS}" "${THREADS}" "${RECHECK}" "${status}" \
        "${wall_s}" "${user}" "${sys}" "${rss}" "${cpu}" "${stage_json}" <<'PY'
import csv
import json
import sys

(
    csv_path,
    dataset,
    rep,
    fastp_level,
    deacon_level,
    deacon_cthreads,
    threads,
    recheck,
    status,
    wall_s,
    user_s,
    sys_s,
    max_rss_kb,
    cgroup_cpu_s,
    stage_json,
) = sys.argv[1:]

try:
    with open(stage_json, encoding="utf-8") as handle:
        metrics = json.load(handle)
    summary = metrics.get("deacon_summary") or {}
except (OSError, json.JSONDecodeError):
    metrics = {}
    summary = {}

with open(csv_path, "a", newline="", encoding="utf-8") as handle:
    writer = csv.writer(handle, lineterminator="\n")
    writer.writerow([
        dataset,
        rep,
        fastp_level,
        deacon_level,
        deacon_cthreads,
        threads,
        recheck,
        status,
        wall_s,
        user_s,
        sys_s,
        max_rss_kb,
        cgroup_cpu_s,
        metrics.get("fastp_ms", ""),
        metrics.get("deacon_ms", ""),
        metrics.get("bowtie2_recheck_ms", ""),
        metrics.get("finalize_ms", ""),
        summary.get("seqs_in", ""),
        summary.get("seqs_out", ""),
        summary.get("bp_in", ""),
        summary.get("bp_out", ""),
        summary.get("time", ""),
        summary.get("bp_per_second", ""),
    ])
PY
}

cgroup_probe_init

for dataset in "${DATASETS[@]}"; do
    dataset_dir="${DATA_DIR}/${dataset}"
    if [[ -f "${dataset_dir}/reads_R1.fastq.gz" ]]; then
        r1="${dataset_dir}/reads_R1.fastq.gz"
        r2="${dataset_dir}/reads_R2.fastq.gz"
        input_args=(--r1 "${r1}" --r2 "${r2}")
    elif [[ -f "${dataset_dir}/reads.fastq.gz" ]]; then
        input_args=(--r1 "${dataset_dir}/reads.fastq.gz")
    else
        echo "WARNING: input missing for ${dataset}; skipped" >&2
        continue
    fi

    for level in ${FASTP_LEVELS}; do
        for rep in $(seq 1 "${REPS}"); do
            if [[ "${OUTPUT_ON_SCRATCH}" = "1" ]]; then
                out="${LOCAL_SCRATCH}/outputs/${dataset}/fastp${level}/rep${rep}"
            else
                out="${RESULTS_DIR}/${dataset}/fastp${level}/rep${rep}"
            fi
            work="${LOCAL_SCRATCH}/work/${dataset}/fastp${level}/rep${rep}"
            rm -rf "${out}" "${work}"
            mkdir -p "${out}" "${work}"
            time_log="${RESULTS_DIR}/logs/${dataset}_fastp${level}_rep${rep}.time"
            run_log="${RESULTS_DIR}/logs/${dataset}_fastp${level}_rep${rep}.log"

            recheck_args=(--no-bowtie2-recheck)
            if [[ "${RECHECK}" = "1" ]]; then
                recheck_args=()
            fi

            echo "[run] dataset=${dataset} fastp=${level} rep=${rep}"
            status=ok
            if ! cgroup_run "${time_log}" \
                "${RUSTYCLEAN}" \
                    "${input_args[@]}" \
                    --deacon-index "${DEACON_INDEX}" \
                    --host-index "${HOST_INDEX}" \
                    --max-contamination 100.0 \
                    --fastp-compression "${level}" \
                    --deacon-compression-level "${DEACON_LEVEL}" \
                    --deacon-compression-threads "${DEACON_COMPRESSION_THREADS}" \
                    --use-deacon-server \
                    --deacon-server-dir "${SERVER_DIR}" \
                    --work-dir "${work}" \
                    --checkpoint-dir "${out}/.checkpoints" \
                    --clean \
                    -o "${out}" \
                    -t "${THREADS}" \
                    "${recheck_args[@]}" > "${run_log}" 2>&1; then
                status=failed
            fi

            wall=$(awk '/Elapsed \(wall clock\) time/ {print $NF; exit}' "${time_log}")
            user=$(awk '/User time \(seconds\)/ {print $NF; exit}' "${time_log}")
            sys=$(awk '/System time \(seconds\)/ {print $NF; exit}' "${time_log}")
            rss=$(awk '/Maximum resident set size/ {print $NF; exit}' "${time_log}" 2>/dev/null || true)
            wall_s=$(elapsed_to_seconds "${wall:-0}")
            stage_json="$(find "${out}" -name stage_metrics.json -print -quit 2>/dev/null || true)"

            append_stage_metrics \
                "${dataset}" "${rep}" "${level}" "${status}" "${wall_s}" \
                "${user:-}" "${sys:-}" "${rss:-}" "${CG_CPU_SECONDS:-}" \
                "${stage_json}"

            [[ "${status}" = "ok" ]] || echo "WARNING: run failed; see ${run_log}" >&2
        done
    done
done

rm -rf "${LOCAL_SCRATCH}"
echo "Benchmark complete: ${CSV}"
