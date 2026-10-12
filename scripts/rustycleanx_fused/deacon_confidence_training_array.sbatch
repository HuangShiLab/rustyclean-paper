#!/bin/bash
#SBATCH --job-name=rcx_deac_thr
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=08:00:00
#SBATCH --array=0-2
#SBATCH --output=/lustre1/g/aos_shihuang/rustyclean-paper/logs/rcx_deac_thr-%A_%a.out
#SBATCH --error=/lustre1/g/aos_shihuang/rustyclean-paper/logs/rcx_deac_thr-%A_%a.err
set -euo pipefail
REPO=/lustre1/g/aos_shihuang/rustyclean-paper
DEACON=/home/shihuang/.conda/envs/sketch-benchmark/bin/deacon
INDEX=/lustre1/g/aos_shihuang/databases/deacon/panhuman-1.k31w15.idx
DATA=/scr/u/shihuang/rustyclean-paper/data/enhanced
ABS=(3 4 5)
A=${ABS[$SLURM_ARRAY_TASK_ID]}
OUT=$REPO/runs/rustycleanx_fused/confidence_sweep/deacon_abs${A}
mkdir -p "$OUT"
for D in 5M_1pct_low_even_SE 10M_10pct_med_even_SE 30M_50pct_high_skewed_SE; do
  mkdir -p "$OUT/$D"
  "$DEACON" filter "$INDEX" "$DATA/$D/reads.fastq.gz" --deplete --output "$OUT/$D/deacon.fastq.gz" --threads 8 --compression-level 1 --abs-threshold "$A" --summary "$OUT/$D/summary.json" > "$OUT/$D/deacon.log" 2>&1
done
