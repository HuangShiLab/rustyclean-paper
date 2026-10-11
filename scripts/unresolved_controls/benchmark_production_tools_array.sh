#!/bin/bash
#SBATCH --job-name=rcx_prod_compare
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=96G
#SBATCH --time=12:00:00
#SBATCH --array=0-5
#SBATCH --output=logs/rcx_prod_compare_%A_%a.out
#SBATCH --error=logs/rcx_prod_compare_%A_%a.err

set -euo pipefail

REPO_DIR="/lustre1/g/aos_shihuang/rustyclean-paper"
DATA_DIR="/scr/u/shihuang/rustyclean-paper/data/enhanced"
CLEANIFIER="$REPO_DIR/.conda_envs/cleanifier/bin/cleanifier"
DEACON="/home/shihuang/.conda/envs/sketch-benchmark/bin/deacon"
CLEANIFIER_INDEX="$REPO_DIR/databases/cleanifier/t2t_pangenome_hla_variants_cdna_cleanifier_index_k29_w33"
DEACON_INDEX="/lustre1/g/aos_shihuang/databases/deacon/panhuman-1.k31w15.idx"
RESULTS="$REPO_DIR/runs/unresolved_controls/production_index_comparison"
mkdir -p "$RESULTS/logs" "$RESULTS/metrics" "$RESULTS/cleanifier" "$RESULTS/deacon"

export PATH="$(dirname "$CLEANIFIER"):/home/shihuang/.conda/envs/sketch-benchmark/bin:${PATH}"
DATASETS=(
  "5M_1pct_low_even_SE"
  "10M_10pct_med_even_SE"
  "30M_50pct_high_skewed_SE"
  "60M_90pct_high_lognormal_SE"
  "100M_50pct_high_lognormal_SE"
  "100M_90pct_high_lognormal_SE"
)
DATASET="${DATASETS[$SLURM_ARRAY_TASK_ID]}"
DATASET_DIR="$DATA_DIR/${DATASET}"
R1="$DATASET_DIR/reads.fastq.gz"
TRUTH="$DATASET_DIR/ground_truth_labels.txt"
test -s "$R1"
test -s "$TRUTH"
test -s "${CLEANIFIER_INDEX}.filter"
test -s "${DEACON_INDEX}"

# Fresh output table per array task; all three replicates append to it.
CLEAN_METRICS="$RESULTS/metrics/${DATASET}.cleanifier.tsv"
DEACON_METRICS="$RESULTS/metrics/${DATASET}.deacon.tsv"
rm -f "$CLEAN_METRICS" "$DEACON_METRICS"

for REP in 1 2 3; do
    # Cleanifier production index, default threshold, 16 worker threads.
    C_OUT="$RESULTS/cleanifier/${DATASET}/rep${REP}"
    mkdir -p "$C_OUT"
    C_TIME="$RESULTS/logs/${DATASET}.cleanifier.rep${REP}.time"
    C_LOG="$RESULTS/logs/${DATASET}.cleanifier.rep${REP}.log"
    /usr/bin/time -v -o "$C_TIME" "$CLEANIFIER" filter \
      --index "$CLEANIFIER_INDEX" \
      --fastq "$R1" \
      --out "$C_OUT/cleanifier" \
      --threads 16 --compression gz --compression-level 1 --threshold 0.5 \
      >"$C_LOG" 2>&1
    C_FASTQ=$(find "$C_OUT" -maxdepth 1 -type f -name '*keep*.fastq*' | head -n1)
    C_RUNTIME=$(awk '/Elapsed \(wall clock\) time/ {print $NF}' "$C_TIME")
    C_HR_SEC=$(awk '/Elapsed \(wall clock\) time/ {n=split($NF,a,":"); if(n==3) print a[1]*3600+a[2]*60+a[3]; else print a[1]*60+a[2]}' "$C_TIME")
    C_RSS=$(awk '/Maximum resident set size/ {print $NF}' "$C_TIME")
    "$REPO_DIR/scripts/unresolved_controls/compute_production_accuracy.py" \
      --tool cleanifier --dataset "$DATASET" --replicate "$REP" \
      --truth "$TRUTH" --fastq "$C_FASTQ" \
      --runtime-s "$C_HR_SEC" --max-rss-kb "$C_RSS" \
      --output "$CLEAN_METRICS"

    # Deacon production index, deplete host matches, 16 threads.
    D_OUT="$RESULTS/deacon/${DATASET}/rep${REP}"
    mkdir -p "$D_OUT"
    D_TIME="$RESULTS/logs/${DATASET}.deacon.rep${REP}.time"
    D_LOG="$RESULTS/logs/${DATASET}.deacon.rep${REP}.log"
    /usr/bin/time -v -o "$D_TIME" "$DEACON" filter \
      "$DEACON_INDEX" "$R1" \
      --deplete \
      --output "$D_OUT/deacon.fastq.gz" \
      --threads 16 --compression-level 1 \
      --summary "$D_OUT/deacon_summary.json" \
      >"$D_LOG" 2>&1
    D_FASTQ="$D_OUT/deacon.fastq.gz"
    D_RUNTIME=$(awk '/Elapsed \(wall clock\) time/ {print $NF}' "$D_TIME")
    D_HR_SEC=$(awk '/Elapsed \(wall clock\) time/ {n=split($NF,a,":"); if(n==3) print a[1]*3600+a[2]*60+a[3]; else print a[1]*60+a[2]}' "$D_TIME")
    D_RSS=$(awk '/Maximum resident set size/ {print $NF}' "$D_TIME")
    "$REPO_DIR/scripts/unresolved_controls/compute_production_accuracy.py" \
      --tool deacon --dataset "$DATASET" --replicate "$REP" \
      --truth "$TRUTH" --fastq "$D_FASTQ" \
      --runtime-s "$D_HR_SEC" --max-rss-kb "$D_RSS" \
      --output "$DEACON_METRICS"
done

# Copy metrics beside the canonical summary.
mkdir -p "$REPO_DIR/runs/unresolved_controls/summary/production_index_comparison"
cp "$CLEAN_METRICS" "$REPO_DIR/runs/unresolved_controls/summary/production_index_comparison/${DATASET}.cleanifier.tsv"
cp "$DEACON_METRICS" "$REPO_DIR/runs/unresolved_controls/summary/production_index_comparison/${DATASET}.deacon.tsv"
