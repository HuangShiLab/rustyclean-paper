#!/bin/bash
#SBATCH --job-name=rcx_verified
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=120G
#SBATCH --time=12:00:00
#SBATCH --output=/lustre1/g/aos_shihuang/rustyclean-paper/logs/rcx_verified-%j.out
#SBATCH --error=/lustre1/g/aos_shihuang/rustyclean-paper/logs/rcx_verified-%j.err

set -euo pipefail
bash /lustre1/g/aos_shihuang/rustyclean-paper/scripts/unresolved_controls/benchmark_verified_consensus_production.sh
