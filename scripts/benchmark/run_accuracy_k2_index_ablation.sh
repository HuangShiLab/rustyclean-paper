#!/bin/bash
#SBATCH --job-name=rc_k2_ablation_acc
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=04:00:00
#SBATCH --output=/home/%u/rc_k2_ablation_acc_%j.out
#SBATCH --error=/home/%u/rc_k2_ablation_acc_%j.err

# Accuracy for the mixed-database arm of the Kraken2 index ablation.
# The human-only arm is the default run, benchmark_bowtie2_recheck_v2.sh.

set -e
source /group/aos_shihuang/conda/etc/profile.d/conda.sh
conda activate /lustre1/g/aos_shihuang/rustyclean-paper/.conda_envs/rustyclean-benchmark

PROJECT="${RUNS_DIR:-/lustre1/g/aos_shihuang/rustyclean-paper/runs}/k2_index_ablation"
REPO=/lustre1/g/aos_shihuang/rustyclean-paper

python "$REPO/scripts/benchmark/compute_accuracy_bowtie2_recheck_v2.py" \
    "$PROJECT" \
    "$PROJECT/metrics/accuracy_k2_mixed.csv" \
    rustyclean_k2_mixed

echo "Done. Compare the two arms with:"
echo "  python $REPO/scripts/benchmark/compare_k2_index_ablation.py"
