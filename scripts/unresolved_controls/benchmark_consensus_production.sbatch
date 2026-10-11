#!/bin/bash
#SBATCH --job-name=rcx_consensus
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=160G
#SBATCH --time=12:00:00
#SBATCH --output=/lustre1/g/aos_shihuang/rustyclean-paper/logs/rcx_consensus-%j.out
#SBATCH --error=/lustre1/g/aos_shihuang/rustyclean-paper/logs/rcx_consensus-%j.err

set -euo pipefail
bash /lustre1/g/aos_shihuang/rustyclean-paper/scripts/unresolved_controls/benchmark_consensus_production.sh
