#!/bin/bash
#SBATCH --job-name=rcx_fastq_bench
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=12:00:00
#SBATCH --array=0-5
#SBATCH --output=logs/rcx_fastq_bench_%A_%a.out
#SBATCH --error=logs/rcx_fastq_bench_%A_%a.err

set -euo pipefail

REPO_DIR="/lustre1/g/aos_shihuang/rustyclean-paper"
cd "$REPO_DIR/rustyclean-x"
mkdir -p ../logs benchmark

export PATH="/home/shihuang/.cargo/bin:${PATH}"
command -v cargo >/dev/null || { echo "cargo not found" >&2; exit 1; }
cargo build --release --bin benchmark_fastq

DATA_DIR="/scr/u/shihuang/rustyclean-paper/data/enhanced"
OUT_DIR="$REPO_DIR/rustyclean-x/benchmark/simulated_fastq"
mkdir -p "$OUT_DIR"

DATASETS=(
  "5M_1pct_low_even_SE"
  "10M_10pct_med_even_SE"
  "30M_50pct_high_skewed_SE"
  "60M_90pct_high_lognormal_SE"
  "100M_50pct_high_lognormal_SE"
  "100M_90pct_high_lognormal_SE"
)
DATASET="${DATASETS[$SLURM_ARRAY_TASK_ID]}"
R1="${DATA_DIR}/${DATASET}/reads.fastq.gz"

"$REPO_DIR/rustyclean-x/target/release/benchmark_fastq" \
  --dataset "$DATASET" \
  --r1 "$R1" \
  --limit 200000 \
  --index-kmers 1000000 \
  --replicates 3 \
  --output "$OUT_DIR/${DATASET}.tsv"

mkdir -p "$REPO_DIR/runs/unresolved_controls/summary"
cp "$OUT_DIR/${DATASET}.tsv" "$REPO_DIR/runs/unresolved_controls/summary/${DATASET}.fastq_benchmark.tsv"
