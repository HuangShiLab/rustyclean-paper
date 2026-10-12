#!/bin/bash
#SBATCH --job-name=rcx_cal_ver
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --output=/lustre1/g/aos_shihuang/rustyclean-paper/logs/rcx_cal_ver-%j.out
#SBATCH --error=/lustre1/g/aos_shihuang/rustyclean-paper/logs/rcx_cal_ver-%j.err
set -euo pipefail
REPO=/lustre1/g/aos_shihuang/rustyclean-paper
DATA=/scr/u/shihuang/rustyclean-paper/data/enhanced
PROD=$REPO/runs/unresolved_controls/production_index_comparison
BIN=$REPO/rustyclean-x/target/release/consensus_benchmark
OUT=$REPO/runs/unresolved_controls/summary/rustyclean_x_calibrated_verified_disagreement_metrics.tsv
WORK=$REPO/runs/rustycleanx_fused/calibrated_verified_work
BOWTIE2=$HOME/.conda/envs/hostile-centrifuge/bin/bowtie2
INDEX=$HOME/.local/share/hostile/human-t2t-hla
mkdir -p "$WORK"
for D in 5M_1pct_low_even_SE 10M_10pct_med_even_SE 30M_50pct_high_skewed_SE 60M_90pct_high_lognormal_SE 100M_50pct_high_lognormal_SE 100M_90pct_high_lognormal_SE; do
  "$BIN" --dataset "$D" --replicate 1 \
    --truth "$DATA/$D/ground_truth_labels.txt" \
    --input-fastq "$DATA/$D/reads.fastq.gz" \
    --deacon-kept "$PROD/deacon/$D/rep1/deacon.fastq.gz" \
    --cleanifier-kept "$PROD/cleanifier/$D/rep1/cleanifier_keep.fastq.gz" \
    --deacon-runtime-tsv "$PROD/metrics/$D.deacon.tsv" \
    --cleanifier-runtime-tsv "$PROD/metrics/$D.cleanifier.tsv" \
    --strategy verified-disagreement \
    --bowtie2 "$BOWTIE2" --bowtie2-index "$INDEX" \
    --work-dir "$WORK/$D" --threads 16 \
    --verifier-max-mapq 3 --verifier-min-nm 10 --output "$OUT"
done
