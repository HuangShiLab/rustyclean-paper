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

PROJECT_DIR="${SCRATCH_DIR:-/scr/u/$USER/rustyclean-paper}"
OUT_CSV="${PROJECT_DIR}/accuracy_comparison.csv"

python "$REPO_DIR/scripts/benchmark/compute_accuracy_all.py" \
    "${PROJECT_DIR}" \
    "${OUT_CSV}"

echo "Accuracy comparison written to ${OUT_CSV}"
cat "${OUT_CSV}"
