#!/bin/bash
#SBATCH --job-name=acc_t2t_panels
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH --time=04:00:00
#SBATCH --output=/home/shihuang/acc_t2t_panels_%j.out
#SBATCH --error=/home/shihuang/acc_t2t_panels_%j.err

set -e

source /group/aos_shihuang/conda/etc/profile.d/conda.sh
export PATH="/group/aos_shihuang/conda/envs/rustyclean-benchmark/bin:${PATH}"

DATA_DIR="/scr/u/shihuang/rustyclean-paper/data/enhanced"
SCRIPT="/lustre1/g/aos_shihuang/rustyclean-paper/scripts/analyze_accuracy_t2t_only_panel.py"

echo "Job started at: $(date)"

# Matched panel (large datasets)
PANEL_DIR="/lustre1/g/aos_shihuang/rustyclean-paper/t2t_only_matched_panel"
if [ -d "${PANEL_DIR}" ]; then
    echo "Analyzing matched panel..."
    python3 "${SCRIPT}" "${DATA_DIR}" "${PANEL_DIR}" "${PANEL_DIR}/analysis"
fi

# Extended panel (low-host + 30%)
EXT_DIR="/lustre1/g/aos_shihuang/rustyclean-paper/t2t_only_extended_panel"
if [ -d "${EXT_DIR}" ]; then
    echo "Analyzing extended panel..."
    python3 "${SCRIPT}" "${DATA_DIR}" "${EXT_DIR}" "${EXT_DIR}/analysis"
fi

# PE panel
PE_DIR="/lustre1/g/aos_shihuang/rustyclean-paper/t2t_only_pe_panel"
if [ -d "${PE_DIR}" ]; then
    echo "Analyzing PE panel..."
    python3 "${SCRIPT}" "${DATA_DIR}" "${PE_DIR}" "${PE_DIR}/analysis"
fi

echo "Job finished at: $(date)"
