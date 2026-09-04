#!/bin/bash
#SBATCH --job-name=mem_accounting_probe
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=64G
#SBATCH --time=00:30:00
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err

# =============================================================================
# Why do /usr/bin/time and sacct disagree about memory by 3 to 12 times?
# =============================================================================
# The panel's memory figures come from /usr/bin/time, which reports the peak RSS
# of the process it launched. sacct reports the cgroup's peak, and on this
# cluster (JobAcctGatherType = jobacct_gather/cgroup) that is 3 to 12 times
# higher on every job. Across the backend comparison the sacct figure tracks
# dataset size (r = 0.755) rather than the tool, which points at reclaimable
# page cache being charged to the cgroup.
#
# This job settles it by measuring one thing: read a large file, discard it, and
# watch the job's OWN cgroup before and after. cat holds a few hundred kB, so if
# the cgroup grows by roughly the size of the file, the growth is page cache and
# sacct's MaxRSS is a job footprint rather than a memory requirement.
#
#   sbatch scripts/diagnose_memory_accounting.sh
# =============================================================================

set -euo pipefail

if [ -z "${REPO_DIR:-}" ]; then
    for _cand in "${SLURM_SUBMIT_DIR:-}" \
                 "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)" \
                 /lustre1/g/aos_shihuang/rustyclean-paper; do
        if [ -n "$_cand" ] && [ -f "$_cand/scripts/hpc/config.sh" ]; then
            REPO_DIR="$_cand"; break
        fi
    done
fi
[ -n "${REPO_DIR:-}" ] || { echo "ERROR: cannot locate the repository." >&2; exit 1; }
source "$REPO_DIR/scripts/hpc/config.sh"

OUT="${RUNS_DIR:-$REPO_DIR/runs}/summary/memory_accounting_probe.txt"
mkdir -p "$(dirname "$OUT")"
exec > "$OUT" 2>&1          # one destination; the earlier tee lost the timing output

BIG=$(find "$DATA_DIR" -name 'reads*.fastq.gz' -size +1G 2>/dev/null | head -1)
[ -n "$BIG" ] || { echo "ERROR: no dataset larger than 1 GB under $DATA_DIR" >&2; exit 1; }
BYTES=$(stat -c %s "$BIG")

echo "Job:  ${SLURM_JOB_ID:-none}   node: $(hostname)"
echo "File: $BIG"
printf 'Size: %.2f GB\n\n' "$(echo "$BYTES" | awk '{print $1/1073741824}')"

# The job's own cgroup, not the node's. /proc/self/cgroup gives the path
# relative to the mount; the previous version read /sys/fs/cgroup/memory.stat
# directly, which describes the whole machine and says nothing about this job.
CG_REL=$(awk -F: '$1=="0"{print $3} $2=="memory"{print $3}' /proc/self/cgroup | head -1)
CG="/sys/fs/cgroup${CG_REL}"
echo "cgroup: $CG"
[ -d "$CG" ] || { echo "ERROR: cannot find this job's cgroup" >&2; exit 1; }

gb () { awk -v b="$1" 'BEGIN{printf "%.2f", b/1073741824}'; }
read_field () {   # read_field <file> <key>   (cgroup v2 memory.stat)
    [ -r "$CG/$1" ] && awk -v k="$2" '$1==k{print $2}' "$CG/$1" || echo ""
}
current () {
    for f in memory.current memory.usage_in_bytes; do
        [ -r "$CG/$f" ] && { cat "$CG/$f"; return; }
    done
    echo 0
}

BEFORE_CUR=$(current)
BEFORE_FILE=$(read_field memory.stat file)
BEFORE_ANON=$(read_field memory.stat anon)

echo
echo "=== before reading ==="
printf '  memory.current %8s GB\n' "$(gb "$BEFORE_CUR")"
[ -n "$BEFORE_ANON" ] && printf '  anon           %8s GB\n' "$(gb "$BEFORE_ANON")"
[ -n "$BEFORE_FILE" ] && printf '  file (cache)   %8s GB\n' "$(gb "$BEFORE_FILE")"

echo
echo "=== reading the file and discarding it ==="
TIMEFILE=$(mktemp)
/usr/bin/time -v cat "$BIG" > /dev/null 2> "$TIMEFILE"
grep -E 'Maximum resident set size|Elapsed \(wall' "$TIMEFILE" | sed 's/^\s*/  /'
CAT_KB=$(awk -F': ' '/Maximum resident set size/{print $2}' "$TIMEFILE")
rm -f "$TIMEFILE"

AFTER_CUR=$(current)
AFTER_FILE=$(read_field memory.stat file)
AFTER_ANON=$(read_field memory.stat anon)

echo
echo "=== after reading ==="
printf '  memory.current %8s GB\n' "$(gb "$AFTER_CUR")"
[ -n "$AFTER_ANON" ] && printf '  anon           %8s GB\n' "$(gb "$AFTER_ANON")"
[ -n "$AFTER_FILE" ] && printf '  file (cache)   %8s GB\n' "$(gb "$AFTER_FILE")"

echo
echo "=== the comparison that settles it ==="
printf '  file on disk                    %8s GB\n' "$(gb "$BYTES")"
printf '  cgroup grew by                  %8s GB\n' "$(gb "$((AFTER_CUR - BEFORE_CUR))")"
[ -n "$AFTER_FILE" ] && [ -n "$BEFORE_FILE" ] && \
    printf '  of which page cache             %8s GB\n' "$(gb "$((AFTER_FILE - BEFORE_FILE))")"
printf '  cat peak RSS (/usr/bin/time)    %8s GB\n' "$(gb "$(( ${CAT_KB:-0} * 1024 ))")"

echo
echo "cat needs a few hundred kB. If the cgroup grew by roughly the size of the"
echo "file, and the growth is in the cache line, then sacct's MaxRSS counts"
echo "reclaimable page cache and is not a memory requirement -- in which case the"
echo "figures to publish are the /usr/bin/time ones already in the report."
echo
scontrol show config 2>/dev/null | grep -iE 'JobAcctGatherType|JobAcctGatherParams' | sed 's/^/  /'
