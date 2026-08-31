#!/bin/bash
#SBATCH --job-name=rc_acc_t2t_only_matched
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH --time=02:00:00
#SBATCH --output=/home/shihuang/rc_acc_t2t_only_matched_%j.out
#SBATCH --error=/home/shihuang/rc_acc_t2t_only_matched_%j.err

set -e

source /group/aos_shihuang/conda/etc/profile.d/conda.sh
export PATH="/group/aos_shihuang/conda/envs/rustyclean-benchmark/bin:${PATH}"

DATA_DIR="/scr/u/shihuang/rustyclean-paper/data/enhanced"
RESULTS_DIR="/lustre1/g/aos_shihuang/rustyclean-paper/rustyclean_t2t_only_matched"
OUTPUT_DIR="${RESULTS_DIR}/analysis"
SCRIPT="/lustre1/g/aos_shihuang/rustyclean-paper/scripts/main/main/analyze_accuracy_skipqc_matched.py"

mkdir -p "${OUTPUT_DIR}"

echo "Job started at: $(date)"
echo "Computing accuracy for RustyClean T2T-only matched panel..."

python3 "${SCRIPT}" "${DATA_DIR}" "${RESULTS_DIR}" "${OUTPUT_DIR}" rustyclean_t2t_only

echo "Job finished at: $(date)"
