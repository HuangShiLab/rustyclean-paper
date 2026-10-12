#!/bin/bash
#SBATCH --job-name=rcx_cal_evid
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=12:00:00
#SBATCH --array=0-5
#SBATCH --output=/lustre1/g/aos_shihuang/rustyclean-paper/logs/rcx_cal_evid-%A_%a.out
#SBATCH --error=/lustre1/g/aos_shihuang/rustyclean-paper/logs/rcx_cal_evid-%A_%a.err
set -euo pipefail
REPO=/lustre1/g/aos_shihuang/rustyclean-paper
SCRATCH=/scr/u/shihuang/rustyclean-paper/data/enhanced
PROD=$REPO/runs/unresolved_controls/production_index_comparison
INTERNAL=$REPO/runs/rustycleanx_fused/full_runs
OUT=$REPO/runs/rustycleanx_fused/calibration_evidence
DATASETS=(5M_1pct_low_even_SE 10M_10pct_med_even_SE 30M_50pct_high_skewed_SE 60M_90pct_high_lognormal_SE 100M_50pct_high_lognormal_SE 100M_90pct_high_lognormal_SE)
D=${DATASETS[$SLURM_ARRAY_TASK_ID]}
mkdir -p "$OUT"
"$REPO/rustyclean-x/target/release/calibration_evidence" \
  --dataset "$D" \
  --report "$INTERNAL/$D/per_read_report.tsv.gz" \
  --deacon-kept "$PROD/deacon/$D/rep1/deacon.fastq.gz" \
  --cleanifier-kept "$PROD/cleanifier/$D/rep1/cleanifier_keep.fastq.gz" \
  --output "$OUT/$D.sample5.tsv.gz" \
  --sample-every 5
