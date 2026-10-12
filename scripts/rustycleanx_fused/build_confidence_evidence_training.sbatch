#!/bin/bash
#SBATCH --job-name=rcx_conf_evid
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH --time=08:00:00
#SBATCH --output=/lustre1/g/aos_shihuang/rustyclean-paper/logs/rcx_conf_evid-%j.out
#SBATCH --error=/lustre1/g/aos_shihuang/rustyclean-paper/logs/rcx_conf_evid-%j.err
set -euo pipefail
REPO=/lustre1/g/aos_shihuang/rustyclean-paper
BIN=$REPO/rustyclean-x/target/release/calibration_evidence
DATA=/scr/u/shihuang/rustyclean-paper/data/enhanced
PROD=$REPO/runs/unresolved_controls/production_index_comparison
INTERNAL=$REPO/runs/rustycleanx_fused/full_runs
CONF=$REPO/runs/rustycleanx_fused/confidence_sweep
OUT=$REPO/runs/rustycleanx_fused/confidence_evidence
mkdir -p "$OUT"
for D in 5M_1pct_low_even_SE 10M_10pct_med_even_SE 30M_50pct_high_skewed_SE; do
  "$BIN" --dataset "$D" \
    --report "$INTERNAL/$D/per_read_report.tsv.gz" \
    --deacon-kept "$PROD/deacon/$D/rep1/deacon.fastq.gz" \
    --cleanifier-kept "$PROD/cleanifier/$D/rep1/cleanifier_keep.fastq.gz" \
    --deacon-abs3-kept "$CONF/deacon_abs3/$D/deacon.fastq.gz" \
    --deacon-abs4-kept "$CONF/deacon_abs4/$D/deacon.fastq.gz" \
    --deacon-abs5-kept "$CONF/deacon_abs5/$D/deacon.fastq.gz" \
    --cleanifier-070-kept "$CONF/cleanifier_threshold_0_70/$D/cleanifier_keep.fastq.gz" \
    --cleanifier-090-kept "$CONF/cleanifier_threshold_0_90/$D/cleanifier_keep.fastq.gz" \
    --output "$OUT/$D.sample5.tsv.gz" --sample-every 5
done
