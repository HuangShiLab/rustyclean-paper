#!/bin/bash
# =============================================================================
# RustyClean Benchmark — Sync Project to HPC
# =============================================================================
# Syncs the benchmark codebase to the HPC home/project directory.
# Does NOT sync large data or results by default.
#
# Usage:
#   bash hpc/sync_to_hpc.sh [user@hpc_host]
#
# Example:
#   bash hpc/sync_to_hpc.sh shihuang@hpc.example.com

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

HPC_HOST="${1:-}"
if [ -z "$HPC_HOST" ]; then
    echo "Usage: bash hpc/sync_to_hpc.sh [user@hpc_host]"
    echo ""
    echo "Please provide your HPC login host."
    exit 1
fi

# Read PROJECT_DIR from HPC config (local copy) to know remote destination
HPC_PROJECT_DIR="/scratch/$USER/rustyclean-paper"
if [ -f "$SCRIPT_DIR/config.sh" ]; then
    HPC_PROJECT_DIR=$(grep "^export PROJECT_DIR=" "$SCRIPT_DIR/config.sh" | cut -d'"' -f2 || echo "$HPC_PROJECT_DIR")
fi

echo "Syncing project to HPC..."
echo "  Local:  $PROJECT_DIR"
echo "  Remote: $HPC_HOST:$HPC_PROJECT_DIR"
echo ""

# Sync code and scripts, excluding large local data/conda/results
rsync -avz --delete \
    --exclude='minimal_env/' \
    --exclude='data/' \
    --exclude='results/' \
    --exclude='analysis/' \
    --exclude='logs/' \
    --exclude='.git/' \
    --exclude='*.tgz' \
    --exclude='*.tar.gz' \
    "$PROJECT_DIR/" "$HPC_HOST:$HPC_PROJECT_DIR/"

echo ""
echo "Sync complete."
echo "Next steps on HPC:"
echo "  ssh $HPC_HOST"
echo "  cd $HPC_PROJECT_DIR"
echo "  bash hpc/setup_hpc_env.sh"
echo "  cd genomes && bash download_genomes.sh"
echo "  cd $HPC_PROJECT_DIR"
echo "  bash hpc/submit_all.sh"
