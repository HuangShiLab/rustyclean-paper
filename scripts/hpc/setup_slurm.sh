#!/bin/bash
#SBATCH --job-name=rustyclean_setup
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=8:00:00
#SBATCH --partition=amd

# =============================================================================
# RustyClean Benchmark — HPC Environment Setup Job
# =============================================================================
# Runs scripts/hpc/setup_hpc_env.sh on a compute node.
# After completion, submit the benchmark with:
#   bash scripts/hpc/submit_all.sh

set -euo pipefail

PROJECT_DIR="/lustre1/g/aos_shihuang/rustyclean-paper"
cd "$PROJECT_DIR"

bash scripts/hpc/setup_hpc_env.sh
