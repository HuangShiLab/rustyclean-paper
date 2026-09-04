#!/bin/bash
#SBATCH --job-name=rc_baseline_k2_acc
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=04:00:00
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err

set -e
# Source config.sh so the data and results paths do not depend on how the job was
# launched. Without it SCRATCH_DIR is only set when run_all.sh exported it, and a
# bare sbatch fell back to /scr/u/$USER/rustyclean-paper -- the scratch location
# this project moved away from -- where an older, unrepaired copy of the ground
# truth still sits. The run completed and reported precision 0 for every dataset.
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
source /group/aos_shihuang/conda/etc/profile.d/conda.sh
conda activate /lustre1/g/aos_shihuang/rustyclean-paper/.conda_envs/rustyclean-benchmark

python "$REPO_DIR"/scripts/benchmark/compute_accuracy_baseline_k2.py \
    ${RUNS_DIR:-/lustre1/g/aos_shihuang/rustyclean-paper/runs}/baseline_kraken2_memmap \
    ${RUNS_DIR:-/lustre1/g/aos_shihuang/rustyclean-paper/runs}/baseline_kraken2_memmap/metrics/accuracy_baseline_kraken2_memmap.csv
