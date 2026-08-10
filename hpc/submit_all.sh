#!/bin/bash
# =============================================================================
# RustyClean Benchmark — Master HPC Submission Script
# =============================================================================
# Submits the full benchmark pipeline to SLURM with proper dependencies.
#
# Usage:
#   bash hpc/submit_all.sh
#
# Steps:
#   1. Data generation (array job)
#   2. Benchmark runs (array job, depends on data generation)
#   3. Downstream analysis (single job, depends on benchmark)
#   4. Analysis & figures (single job, depends on downstream)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

echo "========================================"
echo "RustyClean Benchmark — HPC Submission"
echo "========================================"
echo "Project: $PROJECT_DIR"
echo "Data:    $DATA_DIR"
echo "Results: $RESULTS_DIR"
echo ""

# Create directories
mkdir -p "$PROJECT_DIR" "$DATA_DIR" "$RESULTS_DIR" "$ANALYSIS_DIR" "$LOG_DIR"

# ---------------------------------------------------------------------------
# Step 1: Data generation
# ---------------------------------------------------------------------------
echo "[1/4] Submitting data generation job array..."
GEN_JOB=$(sbatch --parsable "$SCRIPT_DIR/generate_data_slurm.sh")
echo "  Job ID: $GEN_JOB"

# ---------------------------------------------------------------------------
# Step 2: Benchmark
# ---------------------------------------------------------------------------
echo ""
echo "[2/4] Submitting benchmark job array (depends on data generation)..."
BENCH_JOB=$(sbatch --parsable --dependency=afterok:"$GEN_JOB" "$SCRIPT_DIR/run_benchmark_slurm.sh")
echo "  Job ID: $BENCH_JOB"

# ---------------------------------------------------------------------------
# Step 3: Downstream analysis
# ---------------------------------------------------------------------------
echo ""
echo "[3/4] Submitting downstream analysis job..."
DOWN_JOB=$(sbatch --parsable --dependency=afterok:"$BENCH_JOB" "$SCRIPT_DIR/downstream_slurm.sh")
echo "  Job ID: $DOWN_JOB"

# ---------------------------------------------------------------------------
# Step 4: Generate figures and report
# ---------------------------------------------------------------------------
echo ""
echo "[4/4] Submitting analysis & figures job..."
ANALYSIS_JOB=$(sbatch --parsable --dependency=afterok:"$DOWN_JOB" "$SCRIPT_DIR/analyze_slurm.sh")
echo "  Job ID: $ANALYSIS_JOB"

echo ""
echo "========================================"
echo "All jobs submitted."
echo "========================================"
echo "Monitor with:"
echo "  squeue -u $USER"
echo "  sacct -j $GEN_JOB,$BENCH_JOB,$DOWN_JOB,$ANALYSIS_JOB"
echo ""
echo "After completion, results will be in:"
echo "  $RESULTS_DIR"
echo "  $ANALYSIS_DIR"
