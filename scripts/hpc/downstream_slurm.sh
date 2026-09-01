#!/bin/bash
#SBATCH --job-name=rustyclean_downstream
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err
#SBATCH --cpus-per-task=16
#SBATCH --mem=128G
#SBATCH --time=168:00:00
#SBATCH --partition=amd

# =============================================================================
# RustyClean Benchmark — Downstream Analysis (SLURM)
# =============================================================================
# Runs taxonomy, assembly, CheckM2, and diversity analysis.

set -euo pipefail

PROJECT_DIR="/lustre1/g/aos_shihuang/rustyclean-paper"
SCRATCH_DIR="/scr/u/shihuang/rustyclean-paper"
cd "$PROJECT_DIR"
# Locate the repository. SLURM copies the batch script to a spool directory, so
# $0 does not point into the repo under sbatch, and config.sh cannot be found via
# a variable that config.sh itself defines.
if [ -z "${REPO_DIR:-}" ]; then
    for _cand in "${SLURM_SUBMIT_DIR:-}" \
                 "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)" \
                 /lustre1/g/aos_shihuang/rustyclean-paper; do
        if [ -n "$_cand" ] && [ -f "$_cand/scripts/hpc/config.sh" ]; then
            REPO_DIR="$_cand"; break
        fi
    done
fi
if [ -z "${REPO_DIR:-}" ]; then
    echo "ERROR: cannot locate the repository. Set REPO_DIR to its path." >&2
    exit 1
fi
source "$REPO_DIR/scripts/hpc/config.sh"
SCRIPT_DIR="$REPO_DIR/scripts/hpc"

activate_conda

# Ensure tools are available
KRAKEN2_BIN=$(resolve_tool "$KRAKEN2" "kraken2")
export BRACKEN_DB="${BRACKEN_DB:-$KRAKEN2_DB}"
command -v bracken >/dev/null 2>&1 || echo "WARNING: bracken not found"
command -v megahit >/dev/null 2>&1 || echo "WARNING: megahit not found"
command -v checkm2 >/dev/null 2>&1 || echo "WARNING: checkm2 not found"

bash "$SCRIPT_DIR/../main/downstream_analysis.sh" "$RESULTS_DIR" "$DATA_DIR"

echo "Downstream analysis completed."
