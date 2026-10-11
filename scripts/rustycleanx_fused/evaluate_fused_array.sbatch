#!/bin/bash
#SBATCH --job-name=rcx_fused_eval
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=80G
#SBATCH --time=24:00:00
#SBATCH --array=0-5
#SBATCH --output=/lustre1/g/aos_shihuang/rustyclean-paper/logs/rcx_fused_eval-%A_%a.out
#SBATCH --error=/lustre1/g/aos_shihuang/rustyclean-paper/logs/rcx_fused_eval-%A_%a.err

set -euo pipefail
REPO=/lustre1/g/aos_shihuang/rustyclean-paper
DATA=/scr/u/shihuang/rustyclean-paper/data/enhanced
INDICES=$REPO/runs/rustycleanx_fused/indices
OUTROOT=$REPO/runs/rustycleanx_fused/full_runs

DATASETS=(
  5M_1pct_low_even_SE
  10M_10pct_med_even_SE
  30M_50pct_high_skewed_SE
  60M_90pct_high_lognormal_SE
  100M_50pct_high_lognormal_SE
  100M_90pct_high_lognormal_SE
)
DATASET=${DATASETS[$SLURM_ARRAY_TASK_ID]}

$REPO/rustyclean-x/target/release/evaluate_fused \
  --dataset "$DATASET" \
  --r1 "$DATA/$DATASET/reads.fastq.gz" \
  --truth "$DATA/$DATASET/ground_truth_labels.txt" \
  --gapped-index "$INDICES/host.gapped.hashes" \
  --minimizer-index "$INDICES/host.minimizer.hashes" \
  --witness-index "$INDICES/microbial.witness.hashes" \
  --outdir "$OUTROOT/$DATASET" \
  --host-gapped-fraction 0.07 \
  --host-minimizer-hits 1 \
  --microbe-witness-fraction 0.30 \
  --host-score-remove 0.60 \
  --host-score-confident 0.80 \
  --microbe-score-rescue 1.00
