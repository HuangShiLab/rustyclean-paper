#!/bin/bash
#SBATCH --job-name=rc_bt2recheck_acc
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=04:00:00
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err

set -e

# Locate the repository (SLURM copies the batch script to a spool directory).
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
source /group/aos_shihuang/conda/etc/profile.d/conda.sh
conda activate /lustre1/g/aos_shihuang/rustyclean-paper/.conda_envs/rustyclean-benchmark

python "$REPO_DIR/scripts/benchmark/compute_accuracy_bowtie2_recheck_v2.py" \
    /lustre1/g/aos_shihuang/rustyclean-paper/bowtie2_recheck_v2 \
    /lustre1/g/aos_shihuang/rustyclean-paper/bowtie2_recheck_v2/metrics/accuracy_bowtie2_recheck.csv
