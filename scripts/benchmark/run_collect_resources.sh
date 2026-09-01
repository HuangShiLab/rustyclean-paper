#!/bin/bash
#SBATCH --job-name=rc_collect_resources
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --time=00:30:00
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err

# Merge the per-task metric files each benchmark array leaves behind, then
# summarise runtime and peak memory for the whole panel in one table.
#
# Runs last, after every benchmark, because it reads their output. It is also
# safe to run by hand at any point to see how far the panel has got.

set -euo pipefail

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPO_DIR="$(dirname "$REPO_DIR")"
[ -f "$REPO_DIR/scripts/hpc/config.sh" ] || {
    echo "ERROR: cannot locate the repository. Set REPO_DIR." >&2; exit 1; }
source "$REPO_DIR/scripts/hpc/config.sh"
activate_conda

echo "Job started at: $(date)"

python3 "$REPO_DIR/scripts/main/collect_resources.py"

echo
echo "Summary written to ${RUNS_DIR}/summary/"
echo "  resources.csv  every runtime and peak-memory measurement, one row each"
echo "  sacct.txt      SLURM's own accounting, as a check on /usr/bin/time"
echo "Job finished at: $(date)"
