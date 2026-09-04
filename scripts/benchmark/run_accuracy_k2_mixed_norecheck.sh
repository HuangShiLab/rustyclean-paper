#!/bin/bash
#SBATCH --job-name=rc_k2_mixed_norecheck_acc
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=04:00:00
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err

# Accuracy for the mixed-library arm with the verification pass off.
# This is the configuration the pass was added to compensate for, and the
# reference the rewritten pass has to beat.

set -e
# Source config.sh so the data and results paths do not depend on how the job was
# launched. Without it SCRATCH_DIR is only set when run_all.sh exported it, and a
# bare sbatch fell back to /scr/u/$USER/rustyclean-paper -- the scratch location
# this project moved away from -- where an older, unrepaired copy of the ground
# truth still sits. The run completed and reported precision 0 for every dataset.
[ -n "${REPO_DIR:-}" ] && [ -f "$REPO_DIR/scripts/hpc/config.sh" ] && source "$REPO_DIR/scripts/hpc/config.sh"
source /group/aos_shihuang/conda/etc/profile.d/conda.sh
conda activate /lustre1/g/aos_shihuang/rustyclean-paper/.conda_envs/rustyclean-benchmark

PROJECT="${RUNS_DIR:-/lustre1/g/aos_shihuang/rustyclean-paper/runs}/k2_mixed_norecheck"
REPO=/lustre1/g/aos_shihuang/rustyclean-paper

python "$REPO/scripts/benchmark/compute_accuracy_bowtie2_recheck_v2.py" \
    "$PROJECT" \
    "$PROJECT/metrics/accuracy_k2_mixed_norecheck.csv" \
    rustyclean_k2_mixed_norecheck

echo "Done. Compare against the recheck arms with:"
echo "  python3 $REPO/scripts/main/collect_resources.py"
