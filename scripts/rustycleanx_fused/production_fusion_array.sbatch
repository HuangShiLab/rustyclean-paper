#!/bin/bash
#SBATCH --job-name=rcx_prod_fusion
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=120G
#SBATCH --time=24:00:00
#SBATCH --array=0-5
#SBATCH --output=/lustre1/g/aos_shihuang/rustyclean-paper/logs/rcx_production_fusion-%A_%a.out
#SBATCH --error=/lustre1/g/aos_shihuang/rustyclean-paper/logs/rcx_production_fusion-%A_%a.err

set -euo pipefail
REPO=/lustre1/g/aos_shihuang/rustyclean-paper
DATA=/scr/u/shihuang/rustyclean-paper/data/enhanced
PROD=$REPO/runs/unresolved_controls/production_index_comparison
WITNESS=$REPO/runs/rustycleanx_fused/indices/microbial.witness.hashes
OUTROOT=$REPO/runs/rustycleanx_fused/production_fusion_runs

DATASETS=(
  5M_1pct_low_even_SE
  10M_10pct_med_even_SE
  30M_50pct_high_skewed_SE
  60M_90pct_high_lognormal_SE
  100M_50pct_high_lognormal_SE
  100M_90pct_high_lognormal_SE
)
DATASET=${DATASETS[$SLURM_ARRAY_TASK_ID]}

$REPO/rustyclean-x/target/release/production_fusion \
  --dataset "$DATASET" \
  --r1 "$DATA/$DATASET/reads.fastq.gz" \
  --truth "$DATA/$DATASET/ground_truth_labels.txt" \
  --deacon-kept "$PROD/deacon/$DATASET/rep1/deacon.fastq.gz" \
  --cleanifier-kept "$PROD/cleanifier/$DATASET/rep1/cleanifier_keep.fastq.gz" \
  --witness-index "$WITNESS" \
  --outdir "$OUTROOT/$DATASET" \
  --microbe-witness-fraction 0.30 \
  --microbe-score-rescue 0.30
