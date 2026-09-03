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
source /group/aos_shihuang/conda/etc/profile.d/conda.sh
conda activate /lustre1/g/aos_shihuang/rustyclean-paper/.conda_envs/rustyclean-benchmark

python /lustre1/g/aos_shihuang/rustyclean/compute_accuracy_baseline_k2.py \
    ${RUNS_DIR:-/lustre1/g/aos_shihuang/rustyclean-paper/runs}/baseline_kraken2_memmap \
    ${RUNS_DIR:-/lustre1/g/aos_shihuang/rustyclean-paper/runs}/baseline_kraken2_memmap/metrics/accuracy_baseline_kraken2_memmap.csv
