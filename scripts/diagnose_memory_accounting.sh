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
# cluster that is 3 to 12 times higher on every job. Across the backend
# comparison the sacct figure tracks dataset size (r = 0.755) rather than the
# tool, and even a 5M dataset reads 19-29 GB where the Kraken2 hash table is
# 4.3 GB -- both of which point at reclaimable page cache being counted.
#
# This job settles it. It runs no analysis at all: it reads a large file and
# discards it. Any memory sacct reports beyond a few MB can only be page cache.
#
#   sbatch scripts/diagnose_memory_accounting.sh
#   sacct -j <jobid> --format=JobID,MaxRSS,MaxVMSize,Elapsed --units=G
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

BIG=$(find "$DATA_DIR" -name 'reads*.fastq.gz' -size +1G 2>/dev/null | head -1)
[ -n "$BIG" ] || { echo "ERROR: no dataset larger than 1 GB under $DATA_DIR" >&2; exit 1; }

echo "Job:  ${SLURM_JOB_ID:-none}   node: $(hostname)"
echo "File: $BIG ($(du -h "$BIG" | cut -f1))"
echo

echo "=== 1. read the file and discard it, under /usr/bin/time ==="
# cat holds a few hundred kB. Everything else the cgroup charges for this step
# is page cache.
/usr/bin/time -v cat "$BIG" > /dev/null 2> >(grep -E 'Maximum resident|Elapsed' >&2)

echo
echo "=== 2. what the kernel says this cgroup is using ==="
for f in /sys/fs/cgroup/memory/slurm/uid_$(id -u)/job_${SLURM_JOB_ID}/memory.max_usage_in_bytes \
         /sys/fs/cgroup/memory.peak \
         /sys/fs/cgroup/memory.current; do
    [ -r "$f" ] && printf '  %-72s %s\n' "$f" "$(awk '{printf "%.1f GB", $1/1073741824}' "$f")"
done
# cgroup v1 splits the total into rss and cache; v2 calls the latter "file".
for f in /sys/fs/cgroup/memory/slurm/uid_$(id -u)/job_${SLURM_JOB_ID}/memory.stat \
         /sys/fs/cgroup/memory.stat; do
    if [ -r "$f" ]; then
        echo "  --- $f"
        grep -E '^(rss|cache|file|anon) ' "$f" | awk '{printf "      %-8s %.1f GB\n", $1, $2/1073741824}'
        break
    fi
done

echo
echo "=== 3. how this cluster gathers job accounting ==="
scontrol show config 2>/dev/null | grep -iE 'JobAcctGatherType|JobAcctGatherParams' | sed 's/^/  /'

echo
echo "Read step 1 against step 2. cat needs well under 1 GB, so a cgroup peak in"
echo "the tens of GB is page cache, and sacct's MaxRSS is a job footprint that"
echo "includes reclaimable cache -- not a memory requirement. In that case the"
echo "figures to publish are the /usr/bin/time ones already in the report."
