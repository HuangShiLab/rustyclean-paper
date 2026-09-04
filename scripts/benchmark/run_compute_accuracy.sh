#!/bin/bash
#SBATCH --job-name=rc_accuracy_all
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=yfz96@connect.hku.hk
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=6:00:00
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err

set -euo pipefail

# Source config.sh so the path does not depend on how the job was launched: the
# fallback below points at the scratch location this project moved away from,
# where an older, unrepaired copy of the ground truth still sits.
# Derive the repository rather than trusting an inherited REPO_DIR: run_all.sh
# exports it, but a bare sbatch does not, and an empty REPO_DIR turned the script
# path into /scripts/benchmark/... and killed the job in one second.
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
PROJECT_DIR="${SCRATCH_DIR:-/scr/u/$USER/rustyclean-paper}"
OUT_CSV="${PROJECT_DIR}/accuracy_comparison.csv"

python "$REPO_DIR/scripts/benchmark/compute_accuracy_all.py" \
    "${PROJECT_DIR}" \
    "${OUT_CSV}"

echo "Accuracy comparison written to ${OUT_CSV}"
cat "${OUT_CSV}"
