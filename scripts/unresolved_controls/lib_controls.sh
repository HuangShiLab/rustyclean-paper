#!/bin/bash
# Shared, override-friendly cluster settings for unresolved-control runners.
set -euo pipefail

CONTROL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROLS_REPO_DIR="${CONTROLS_REPO_DIR:-$(cd "${CONTROL_SCRIPT_DIR}/../.." && pwd)}"

export THREADS="${THREADS:-16}"
export REPS="${REPS:-3}"
export DATA_DIR="${DATA_DIR:-/scr/u/${USER}/rustyclean-paper/data/enhanced}"
export RESULTS_ROOT="${RESULTS_ROOT:-/lustre1/g/aos_shihuang/rustyclean-paper/runs/unresolved_controls}"
export RUSTYCLEAN="${RUSTYCLEAN:-/lustre1/g/aos_shihuang/rustyclean/target/release/rustyclean}"
export DEACON_INDEX="${DEACON_INDEX:-/lustre1/g/aos_shihuang/databases/deacon/panhuman-1.k31w15.idx}"
export HOSTILE_INDEX="${HOSTILE_INDEX:-$HOME/.local/share/hostile/human-t2t-hla}"
export CLEANIFIER_BIN="${CLEANIFIER_BIN:-cleanifier}"
export HOSTILE_BIN="${HOSTILE_BIN:-/home/shihuang/.local/bin/hostile}"
export CLEANIFIER_INDEX="${CLEANIFIER_INDEX:-/lustre1/g/aos_shihuang/rustyclean-paper/databases/cleanifier/human}"
export PYTHONBIN="${PYTHONBIN:-python3}"
export RESULTS_WORK_ROOT="${RESULTS_WORK_ROOT:-${RESULTS_ROOT}/work}"
export PATH="/lustre1/g/aos_shihuang/rustyclean-paper/.conda_envs/cleanifier/bin:/group/aos_shihuang/conda/envs/fastp/bin:/home/shihuang/.conda/envs/sketch-benchmark/bin:/home/shihuang/.local/bin:/home/shihuang/.cargo/bin:${PATH}"

control_require_tool() {
    local tool="$1"
    command -v "${tool}" >/dev/null 2>&1 || { echo "ERROR: required tool not found: ${tool}" >&2; exit 2; }
}

control_require_file() {
    local file="$1"
    [[ -s "${file}" ]] || { echo "ERROR: required file missing/empty: ${file}" >&2; exit 2; }
}

control_require_hostile_index() {
    local prefix="$1"
    [[ -s "${prefix}.1.bt2" || -s "${prefix}.1.bt2l" ]] || {
        echo "ERROR: Bowtie2/Hostile index missing at prefix: ${prefix}" >&2
        exit 2
    }
}

control_elapsed_seconds() {
    "${PYTHONBIN}" - "$1" <<'PY'
import sys
print(sum(float(x) * 60 ** i for i, x in enumerate(reversed(sys.argv[1].split(':')))))
PY
}

control_gnu_time_field() {
    awk -v pattern="$2" 'index($0, pattern) {print $NF; exit}' "$1"
}

control_stage_metrics() {
    find "$1" -name stage_metrics.json -print -quit 2>/dev/null || true
}

control_stage_field() {
    local stage_json="$1" key="$2"
    [[ -n "${stage_json}" && -s "${stage_json}" ]] || return 0
    "${PYTHONBIN}" - "${stage_json}" "${key}" <<'PY'
import json, sys
try:
    print(json.load(open(sys.argv[1], encoding='utf-8')).get(sys.argv[2], ''))
except Exception:
    pass
PY
}

control_append_performance() {
    local csv="$1" tool="$2" condition="$3" dataset="$4" rep="$5" runtime="$6" rss="$7" extra="${8:-{}}"
    mkdir -p "$(dirname "${csv}")"
    [[ -s "${csv}" ]] || echo "tool,condition,dataset,rep,runtime_s,max_memory_kb,threads,node,timestamp,extra" > "${csv}"
    "${PYTHONBIN}" - "${csv}" "${tool}" "${condition}" "${dataset}" "${rep}" \
        "${runtime}" "${rss}" "${THREADS}" "${SLURMD_NODENAME:-$(hostname)}" "${extra}" <<'PY'
import csv, datetime, json, sys
path = sys.argv[1]
tool, condition, dataset, rep, runtime, rss, threads, node, extra = sys.argv[2:]
try:
    extra_obj = json.loads(extra)
except Exception:
    extra_obj = {"raw": extra}
with open(path, 'a', newline='', encoding='utf-8') as handle:
    writer = csv.writer(handle, lineterminator='\n')
    writer.writerow([tool, condition, dataset, rep, runtime, rss, threads, node,
                     datetime.datetime.now().isoformat(timespec='seconds'),
                     json.dumps(extra_obj, sort_keys=True)])
PY
}

control_score() {
    "${PYTHONBIN}" "${CONTROL_SCRIPT_DIR}/score_retained_reads.py" \
        "$1" "$2" "$3" "$4" "$5" "$6" "$7"
}

control_have_performance() {
    [[ -s "$1" ]] || return 1
    "${PYTHONBIN}" - "$@" <<'PY'
import csv, sys
path, tool, condition, dataset, rep = sys.argv[1:]
with open(path, newline='', encoding='utf-8') as handle:
    for row in csv.DictReader(handle):
        if (row.get('tool') == tool and row.get('condition') == condition and
                row.get('dataset') == dataset and row.get('rep') == rep):
            raise SystemExit(0)
raise SystemExit(1)
PY
}
