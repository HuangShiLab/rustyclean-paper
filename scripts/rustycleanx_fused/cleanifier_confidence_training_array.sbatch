#!/bin/bash
#SBATCH --job-name=rcx_clean_thr
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=12:00:00
#SBATCH --array=0-1
#SBATCH --output=/lustre1/g/aos_shihuang/rustyclean-paper/logs/rcx_clean_thr-%A_%a.out
#SBATCH --error=/lustre1/g/aos_shihuang/rustyclean-paper/logs/rcx_clean_thr-%A_%a.err
set -euo pipefail
REPO=/lustre1/g/aos_shihuang/rustyclean-paper
CLEANIFIER=$REPO/.conda_envs/cleanifier/bin/cleanifier
export PATH=/home/shihuang/.conda/envs/sketch-benchmark/bin:$PATH
INDEX=$REPO/databases/cleanifier/t2t_pangenome_hla_variants_cdna_cleanifier_index_k29_w33
DATA=/scr/u/shihuang/rustyclean-paper/data/enhanced
OUT=$REPO/runs/rustycleanx_fused/confidence_sweep/cleanifier_threshold_0_$(printf "%02d" $((SLURM_ARRAY_TASK_ID*20+70)))
mkdir -p "$OUT"
THRESHOLDS=(0.70 0.90)
TH=${THRESHOLDS[$SLURM_ARRAY_TASK_ID]}
for D in 5M_1pct_low_even_SE 10M_10pct_med_even_SE 30M_50pct_high_skewed_SE; do
  mkdir -p "$OUT/$D"
  "$CLEANIFIER" filter --index "$INDEX" --fastq "$DATA/$D/reads.fastq.gz" --out "$OUT/$D/cleanifier" --threads 8 --compression gz --compression-level 1 --threshold "$TH" > "$OUT/$D/cleanifier.log" 2>&1
done
