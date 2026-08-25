#!/bin/bash
#SBATCH --job-name=rustyclean_cleanup
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=2:00:00
#SBATCH --partition=amd

set -euo pipefail

RESULTS_DIR="/scr/u/shihuang/rustyclean-paper/results"

echo "Disk usage before cleanup:"
df -h /scr/u/shihuang

echo ""
echo "Removing KneadData intermediate files (trimmed, repeats, contam, reformatted)..."
find "$RESULTS_DIR/kneaddata" -type f \
    \( -name "reformatted_identifiers*" \
    -o -name "decompressed_*_reads" \
    -o -name "clean.trimmed*.fastq" \
    -o -name "clean.repeats.removed*.fastq" \
    -o -name "*contam.fastq" \
    \) -delete

echo "Removing RustyClean checkpoints for completed runs..."
find "$RESULTS_DIR/rustyclean" -type d -name ".checkpoints" -exec rm -rf {} +

echo "Removing failed 100M_50pct_high_lognormal_SE_rep1 KneadData output..."
rm -rf "$RESULTS_DIR/kneaddata/100M_50pct_high_lognormal_SE_rep1"

echo ""
echo "Disk usage after cleanup:"
df -h /scr/u/shihuang

echo "Cleanup complete."
