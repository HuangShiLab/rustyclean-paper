#!/bin/bash
#SBATCH --job-name=rustyclean_downstream
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err
#SBATCH --cpus-per-task=16
#SBATCH --mem=128G
#SBATCH --time=168:00:00
#SBATCH --partition=amd

# =============================================================================
# RustyClean Benchmark — Downstream Analysis (SLURM)
# =============================================================================
# Runs taxonomy, assembly, CheckM2, and diversity analysis.

set -euo pipefail

PROJECT_DIR="/lustre1/g/aos_shihuang/rustyclean-paper"
SCRATCH_DIR="/scr/u/shihuang/rustyclean-paper"
cd "$PROJECT_DIR"
SCRIPT_DIR="$SCRATCH_DIR/hpc"
source "$SCRIPT_DIR/config.sh"

activate_conda

# Ensure tools are available
KRAKEN2_BIN=$(resolve_tool "$KRAKEN2" "kraken2")
export BRACKEN_DB="${BRACKEN_DB:-$KRAKEN2_DB}"
command -v bracken >/dev/null 2>&1 || echo "WARNING: bracken not found"
command -v megahit >/dev/null 2>&1 || echo "WARNING: megahit not found"
command -v checkm2 >/dev/null 2>&1 || echo "WARNING: checkm2 not found"

bash "$SCRIPT_DIR/../scripts/downstream_analysis.sh" "$RESULTS_DIR" "$DATA_DIR"

echo "Downstream analysis completed."
