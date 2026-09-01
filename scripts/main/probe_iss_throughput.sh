#!/bin/bash
#SBATCH --job-name=iss_probe
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=02:00:00
#SBATCH --output=/home/%u/iss_probe_%j.out
#SBATCH --error=/home/%u/iss_probe_%j.err

# =============================================================================
# Measure InSilicoSeq throughput, then extrapolate to the full panel
# =============================================================================
# The choice between art_illumina and InSilicoSeq comes down to whether ISS can
# generate 560 million read records in acceptable time. Rather than guess, this
# generates a small sample, measures the rate, and reports what the full panel
# would cost.
#
#   sbatch scripts/main/probe_iss_throughput.sh
# =============================================================================

set -euo pipefail

if [ -z "${REPO_DIR:-}" ]; then
    for _cand in "${SLURM_SUBMIT_DIR:-}" \
                 "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)" \
                 /lustre1/g/aos_shihuang/rustyclean-paper; do
        if [ -n "$_cand" ] && [ -f "$_cand/scripts/hpc/config.sh" ]; then
            REPO_DIR="$_cand"; break
        fi
    done
fi
[ -n "${REPO_DIR:-}" ] || { echo "ERROR: cannot locate the repository. Set REPO_DIR." >&2; exit 1; }
source "$REPO_DIR/scripts/hpc/config.sh"
activate_conda

command -v iss >/dev/null 2>&1 || {
    echo "ERROR: iss not found. Install with:" >&2
    echo "  conda create -p $PROJECT_DIR/.conda_envs/iss -c conda-forge -c bioconda insilicoseq -y" >&2
    exit 1
}

PROBE_READS="${PROBE_READS:-1000000}"     # 1M records
PANEL_READS="${PANEL_READS:-560000000}"   # what the 19-dataset panel needs
CPUS="${SLURM_CPUS_PER_TASK:-16}"
WORK="${RUNS_DIR}/iss_probe"
mkdir -p "$WORK"

# A handful of small genomes is enough to measure the rate.
GENOMES="$WORK/genomes.fna"
if [ ! -s "$GENOMES" ]; then
    echo "Assembling a small genome set for the probe..."
    n=0
    for g in "$KRAKEN2_DB_MIXED"/genomes/*.fna.gz; do
        [ -f "$g" ] || continue
        zcat "$g" >> "$GENOMES"
        n=$((n+1)); [ "$n" -ge 5 ] && break
    done
    [ -s "$GENOMES" ] || { echo "ERROR: no genomes found under $KRAKEN2_DB_MIXED/genomes" >&2; exit 1; }
    echo "  using $n genome(s), $(grep -c '^>' "$GENOMES") sequence(s)"
fi

echo "Job started at: $(date)"
echo "Generating $PROBE_READS records with iss on $CPUS cpus..."
start=$(date +%s)
iss generate --genomes "$GENOMES" --n_reads "$PROBE_READS" \
    --model miseq --cpus "$CPUS" --seed 42 \
    --output "$WORK/probe" > "$WORK/iss.log" 2>&1
end=$(date +%s)

elapsed=$((end - start))
[ "$elapsed" -lt 1 ] && elapsed=1
rate=$(awk -v r="$PROBE_READS" -v s="$elapsed" 'BEGIN{printf "%.0f", r/s}')
panel_h=$(awk -v p="$PANEL_READS" -v r="$rate" 'BEGIN{printf "%.1f", p/r/3600}')

echo
echo "============================================================"
echo "  probe            : $PROBE_READS records in ${elapsed}s on $CPUS cpus"
echo "  rate             : $rate records/s"
echo "  full panel       : $PANEL_READS records"
echo "  extrapolated     : ${panel_h} h of pure generation"
echo "============================================================"
awk -v h="$panel_h" 'BEGIN{
  if (h < 12)      print "  VERDICT: comfortably feasible. Switching to InSilicoSeq is fine."
  else if (h < 36) print "  VERDICT: feasible but slow. Worth it only if GC-bias modelling matters\n           to the argument; otherwise keep art_illumina."
  else             print "  VERDICT: too slow for the full panel. Either keep art_illumina, or\n           trim the panel until this figure is acceptable."
}'
echo
echo "  Note: this measures generation only. It excludes the host reads, which"
echo "  come from a 3.1 Gb genome and are the larger share of most datasets."
echo "Job finished at: $(date)"
