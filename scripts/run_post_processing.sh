#!/bin/bash
#SBATCH --job-name=post_process
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH --time=04:00:00
#SBATCH --output=/home/shihuang/post_process_%j.out
#SBATCH --error=/home/shihuang/post_process_%j.err

set -e

source /group/aos_shihuang/conda/etc/profile.d/conda.sh
export PATH="/group/aos_shihuang/conda/envs/rustyclean-benchmark/bin:/group/aos_shihuang/conda/envs/megahit/bin:/group/aos_shihuang/conda/envs/bracken/bin:/group/aos_shihuang/conda/envs/kraken2/bin:${PATH}"

BASE="/lustre1/g/aos_shihuang/rustyclean-paper"

echo "Job started at: $(date)"

# Cross-species accuracy
if [ -d "${BASE}/cross_species_results" ]; then
    echo "Analyzing cross-species accuracy..."
    python3 "${BASE}/scripts/analyze_accuracy_cross_species.py" \
        "${BASE}/data/cross_species_v2" \
        "${BASE}/cross_species_results" \
        "${BASE}/cross_species_results/analysis"
fi

# Real-data downstream
if [ -d "${BASE}/real_data_results" ]; then
    echo "Running real-data downstream analysis..."
    bash "${BASE}/scripts/downstream_real_data.sh"
fi

# Master integration
if [ -d "${BASE}/t2t_only_matched_panel" ]; then
    echo "Integrating all results..."
    python3 "${BASE}/scripts/integrate_results.py" "${BASE}" "${BASE}/integrated_results"
fi

echo "Job finished at: $(date)"
