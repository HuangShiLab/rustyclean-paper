#!/bin/bash
# =============================================================================
# Profile fastp I/O and CPU cost on one or more FASTQ inputs
# =============================================================================
# Local/single-job usage:
#
#   REPS=2 THREADS=16 COMPRESSION_LEVELS="1 4 6 9" \
#       bash scripts/hpc/profile_fastp_io.sh \
#       /path/to/reads.fastq.gz /path/to/profile_out
#
# PE usage:
#
#   R2=/path/to/reads_R2.fastq.gz REPS=2 bash \
#       scripts/hpc/profile_fastp_io.sh \
#       /path/to/reads_R1.fastq.gz /path/to/profile_out
#
# The CSV records wall/CPU time, maximum RSS, the job cgroup I/O delta, file
# sizes and fastp's logical read/base counts.  The first replicate is usually
# cold and the second warm; keep both rather than silently averaging them.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=cgroup_probe.sh
source "${REPO_DIR}/scripts/hpc/cgroup_probe.sh"

R1="${1:?usage: profile_fastp_io.sh R1 [OUT_DIR]}"
OUT_DIR="${2:-fastp_io_profile}"
R2="${R2:-}"
THREADS="${THREADS:-16}"
REPS="${REPS:-2}"
COMPRESSION_LEVELS="${COMPRESSION_LEVELS:-1 4 6 9}"
FASTP_BIN="${FASTP_BIN:-fastp}"
FASTP_Q="${FASTP_Q:-20}"
FASTP_MIN_LEN="${FASTP_MIN_LEN:-50}"
DETECT_PE_ADAPTERS="${DETECT_PE_ADAPTERS:-1}"
timestamp="$(date -Iseconds)"

if [[ ! -r "${R1}" ]]; then
    echo "ERROR: R1 is not readable: ${R1}" >&2
    exit 1
fi
if [[ -n "${R2}" && ! -r "${R2}" ]]; then
    echo "ERROR: R2 is not readable: ${R2}" >&2
    exit 1
fi
if ! command -v "${FASTP_BIN}" >/dev/null 2>&1; then
    echo "ERROR: fastp not found: ${FASTP_BIN}" >&2
    exit 1
fi

mkdir -p "${OUT_DIR}"
CSV="${OUT_DIR}/fastp_io_profile.csv"
if [[ ! -f "${CSV}" ]]; then
    echo "timestamp,r1,r2,rep,compression_level,threads,wall_s,user_s,sys_s,max_rss_kb,cgroup_cpu_s,cgroup_read_bytes,cgroup_write_bytes,cgroup_read_ios,cgroup_write_ios,input_bytes,output_bytes,input_reads,output_reads,input_bases,output_bases,compressed_mib_per_s,logical_mib_per_s,cpu_effective" > "${CSV}"
fi

file_bytes() {
    stat -c '%s' "$1"
}

duration_to_seconds() {
    # GNU time formats elapsed as [H:]M:S.S. It is parsed here because the
    # comparison CSVs already use decimal seconds.
    awk -F: -v t="$1" 'BEGIN { n=split(t,a,":"); s=0; for(i=1;i<=n;i++) s=s*60+a[i]; printf "%.3f", s }'
}

cgroup_io_stats() {
    # Prints four integers: read_bytes write_bytes read_ios write_ios.
    # Empty values mean the kernel/cgroup did not expose the counter.
    local rbytes="" wbytes="" rios="" wios="" line key value

    if [[ -r "/sys/fs/cgroup/io.stat" ]]; then
        while read -r line; do
            for pair in ${line}; do
                key="${pair%%=*}"
                value="${pair#*=}"
                case "${key}" in
                    rbytes) rbytes=$(( ${rbytes:-0} + value )) ;;
                    wbytes) wbytes=$(( ${wbytes:-0} + value )) ;;
                    rios)   rios=$(( ${rios:-0} + value )) ;;
                    wios)   wios=$(( ${wios:-0} + value )) ;;
                esac
            done
        done < /sys/fs/cgroup/io.stat
    elif [[ -r "/sys/fs/cgroup/blkio/blkio.throttle.io_service_bytes" ]]; then
        while read -r -a fields; do
            local n=${#fields[@]}
            for (( i=0; i<n-1; i++ )); do
                key="${fields[i]}"
                value="${fields[i+1]}"
                case "${key}" in
                    Read)  rbytes=$(( ${rbytes:-0} + value )) ;;
                    Write) wbytes=$(( ${wbytes:-0} + value )) ;;
                esac
            done
        done < /sys/fs/cgroup/blkio/blkio.throttle.io_service_bytes
    fi

    printf '%s %s %s %s\n' "${rbytes:-}" "${wbytes:-}" "${rios:-}" "${wios:-}"
}

fastp_counts() {
    # summary.before_filtering/after_filtering contain records (reads) and
    # bases for the whole sample; fastp counts each mate as one read.
    python3 - "$1" "$2" <<'PY'
import json
import sys

path, which = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as handle:
    report = json.load(handle)
node = report["summary"][which]
print(node["total_reads"], node["total_bases"])
PY
}

cgroup_probe_init

for level in ${COMPRESSION_LEVELS}; do
    for rep in $(seq 1 "${REPS}"); do
        run_dir="${OUT_DIR}/level${level}_rep${rep}"
        rm -rf "${run_dir}"
        mkdir -p "${run_dir}"

        if [[ -n "${R2}" ]]; then
            out1="${run_dir}/trimmed_R1.fastq.gz"
            out2="${run_dir}/trimmed_R2.fastq.gz"
            input_args=(--in1 "${R1}" --in2 "${R2}" --out1 "${out1}" --out2 "${out2}")
            output_path="${out1}"
        else
            out1="${run_dir}/trimmed.fastq.gz"
            input_args=(--in1 "${R1}" --out1 "${out1}")
            output_path="${out1}"
        fi

        json_report="${run_dir}/fastp.json"
        html_report="${run_dir}/fastp.html"
        time_log="${run_dir}/time.txt"
        fastp_log="${run_dir}/fastp.log"

        cmd=(
            "${FASTP_BIN}"
            "${input_args[@]}"
            --json "${json_report}"
            --html "${html_report}"
            --thread "${THREADS}"
            --compression "${level}"
            --cut_front
            --cut_tail
            --qualified_quality_phred "${FASTP_Q}"
            --length_required "${FASTP_MIN_LEN}"
        )
        if [[ -n "${R2}" && "${DETECT_PE_ADAPTERS}" = "1" ]]; then
            cmd+=(--detect_adapter_for_pe)
        fi

        input_bytes=$(file_bytes "${R1}")
        if [[ -n "${R2}" ]]; then
            input_bytes=$(( input_bytes + $(file_bytes "${R2}") ))
        fi
        read_io_before=$(cgroup_io_stats)

        echo "[profile] level=${level} rep=${rep} threads=${THREADS}"
        cgroup_run "${time_log}" "${cmd[@]}" > "${fastp_log}" 2>&1

        read_io_after=$(cgroup_io_stats)
        io_delta=$(python3 - "$read_io_before" "$read_io_after" <<'PY'
import sys

before = [int(x) if x else 0 for x in sys.argv[1].split()]
after = [int(x) if x else 0 for x in sys.argv[2].split()]
before += [0] * (4 - len(before))
after += [0] * (4 - len(after))
print(*(a - b for a, b in zip(after, before)))
PY
)

        wall=$(awk -F': ' '/Elapsed \(wall clock\) time/ {print $NF; exit}' "${time_log}")
        user=$(awk -F': ' '/User time \(seconds\)/ {print $NF; exit}' "${time_log}")
        sys=$(awk -F': ' '/System time \(seconds\)/ {print $NF; exit}' "${time_log}")
        rss=$(awk '/Maximum resident set size/ {print $NF; exit}' "${time_log}")
        wall_s=$(duration_to_seconds "${wall}")

        output_bytes=$(file_bytes "${output_path}")
        if [[ -n "${R2}" ]]; then
            output_bytes=$(( output_bytes + $(file_bytes "${out2}") ))
        fi

        read in_reads in_bases < <(fastp_counts "${json_report}" before)
        read out_reads out_bases < <(fastp_counts "${json_report}" after)
        cgroup_cpu="${CG_CPU_SECONDS:-}"

        python3 - "$CSV" "$timestamp" "$R1" "$R2" "$rep" "$level" "$THREADS" \
            "$wall_s" "$user" "$sys" "$rss" "$cgroup_cpu" $io_delta \
            "$input_bytes" "$output_bytes" "$in_reads" "$out_reads" \
            "$in_bases" "$out_bases" <<'PY' >> "${CSV}"
import csv
import sys

(
    path,
    timestamp,
    r1,
    r2,
    rep,
    level,
    threads,
    wall_s,
    user_s,
    sys_s,
    max_rss_kb,
    cgroup_cpu_s,
    cgroup_read_bytes,
    cgroup_write_bytes,
    cgroup_read_ios,
    cgroup_write_ios,
    input_bytes,
    output_bytes,
    input_reads,
    output_reads,
    input_bases,
    output_bases,
) = sys.argv[1:]

wall_s = float(wall_s)
compressed_mib_per_s = (int(input_bytes) / 1024**2) / wall_s
logical_mib_per_s = (int(input_bases) * 2 / 1024**2) / wall_s
user_eff = float(user_s) / wall_s
sys_eff = float(sys_s) / wall_s
cpu_effective = user_eff + sys_eff

with open(path, "a", newline="", encoding="utf-8") as handle:
    writer = csv.writer(handle, lineterminator="\n")
    writer.writerow([
        timestamp,
        r1,
        r2,
        rep,
        level,
        threads,
        f"{wall_s:.3f}",
        user_s,
        sys_s,
        max_rss_kb,
        cgroup_cpu_s,
        cgroup_read_bytes,
        cgroup_write_bytes,
        cgroup_read_ios,
        cgroup_write_ios,
        input_bytes,
        output_bytes,
        input_reads,
        output_reads,
        input_bases,
        output_bases,
        f"{compressed_mib_per_s:.2f}",
        f"{logical_mib_per_s:.2f}",
        f"{cpu_effective:.2f}",
    ])
PY
    done
done

echo "Profile complete: ${CSV}"
