#!/bin/bash
#SBATCH --job-name=rustyclean_analyze
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err
#SBATCH --cpus-per-task=4
#SBATCH --mem=128G
#SBATCH --time=2:00:00
#SBATCH --partition=amd

# =============================================================================
# RustyClean Benchmark — Analysis & Figures (SLURM)
# =============================================================================
# Generates accuracy metrics, performance visualizations, and final report.

set -euo pipefail

PROJECT_DIR="/lustre1/g/aos_shihuang/rustyclean-paper"
SCRATCH_DIR="/scr/u/shihuang/rustyclean-paper"
cd "$PROJECT_DIR"
# Locate the repository. SLURM copies the batch script to a spool directory, so
# $0 does not point into the repo under sbatch, and config.sh cannot be found via
# a variable that config.sh itself defines.
if [ -z "${REPO_DIR:-}" ]; then
    for _cand in "${SLURM_SUBMIT_DIR:-}" \
                 "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)" \
                 /lustre1/g/aos_shihuang/rustyclean-paper; do
        if [ -n "$_cand" ] && [ -f "$_cand/scripts/hpc/config.sh" ]; then
            REPO_DIR="$_cand"; break
        fi
    done
fi
if [ -z "${REPO_DIR:-}" ]; then
    echo "ERROR: cannot locate the repository. Set REPO_DIR to its path." >&2
    exit 1
fi
source "$REPO_DIR/scripts/hpc/config.sh"
SCRIPT_DIR="$REPO_DIR/scripts/hpc"

activate_conda

mkdir -p "$ANALYSIS_DIR/figures"

echo "[1/4] Accuracy analysis..."
python "$SCRIPT_DIR/../main/analyze_accuracy.py" "$DATA_DIR" "$RESULTS_DIR" "$ANALYSIS_DIR"

echo ""
echo "[2/4] Performance analysis..."
python "$SCRIPT_DIR/../main/analyze_performance.py" "$RESULTS_DIR" "$ANALYSIS_DIR"

echo ""
echo "[3/4] Publication figures..."
python "$SCRIPT_DIR/../main/plot_publication_figures_v2.py" "$RESULTS_DIR" "$ANALYSIS_DIR/figures"

echo ""
echo "[4/4] Report generation..."
python "$SCRIPT_DIR/../main/generate_report.py" "$RESULTS_DIR" "$ANALYSIS_DIR/report.md"

echo ""
echo "Analysis complete. Results in $ANALYSIS_DIR"
