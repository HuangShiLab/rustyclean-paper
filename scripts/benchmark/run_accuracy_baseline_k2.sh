#!/bin/bash
#SBATCH --job-name=rc_baseline_k2_acc
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=04:00:00
#SBATCH --output=/home/shihuang/rc_baseline_k2_acc_%j.out
#SBATCH --error=/home/shihuang/rc_baseline_k2_acc_%j.err

set -e
source /group/aos_shihuang/conda/etc/profile.d/conda.sh
conda activate /lustre1/g/aos_shihuang/rustyclean-paper/.conda_envs/rustyclean-benchmark

python /lustre1/g/aos_shihuang/rustyclean/compute_accuracy_baseline_k2.py \
    /lustre1/g/aos_shihuang/rustyclean-paper/baseline_kraken2_memmap \
    /lustre1/g/aos_shihuang/rustyclean-paper/baseline_kraken2_memmap/metrics/accuracy_baseline_kraken2_memmap.csv
