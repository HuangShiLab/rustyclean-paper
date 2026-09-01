#!/bin/bash
#SBATCH --job-name=rc_acc_skipqc
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=02:00:00
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err
set -e
python3 /lustre1/g/aos_shihuang/rustyclean-paper/scripts/main/compute_skipqc_accuracy.py
