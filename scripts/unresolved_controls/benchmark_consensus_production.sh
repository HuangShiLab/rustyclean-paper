#!/bin/bash
set -euo pipefail

REPO_DIR="/lustre1/g/aos_shihuang/rustyclean-paper"
DATA_DIR="/scr/u/shihuang/rustyclean-paper/data/enhanced"
PROD="$REPO_DIR/runs/unresolved_controls/production_index_comparison"
OUT="$REPO_DIR/runs/unresolved_controls/summary/rustyclean_x_strategy_metrics.tsv"
BIN="$REPO_DIR/rustyclean-x/target/release/consensus_benchmark"

rm -f "$OUT"

DATASETS=(
  "5M_1pct_low_even_SE"
  "10M_10pct_med_even_SE"
  "30M_50pct_high_skewed_SE"
  "60M_90pct_high_lognormal_SE"
  "100M_50pct_high_lognormal_SE"
  "100M_90pct_high_lognormal_SE"
)

for DATASET in "${DATASETS[@]}"; do
  TRUTH="$DATA_DIR/${DATASET}/ground_truth_labels.txt"
  for REP in 1 2 3; do
    DEACON_KEPT="$PROD/deacon/${DATASET}/rep${REP}/deacon.fastq.gz"
    CLEANIFIER_KEPT="$PROD/cleanifier/${DATASET}/rep${REP}/cleanifier_keep.fastq.gz"
    "$BIN" \
      --dataset "$DATASET" \
      --replicate "$REP" \
      --truth "$TRUTH" \
      --deacon-kept "$DEACON_KEPT" \
      --cleanifier-kept "$CLEANIFIER_KEPT" \
      --deacon-runtime-tsv "$PROD/metrics/${DATASET}.deacon.tsv" \
      --cleanifier-runtime-tsv "$PROD/metrics/${DATASET}.cleanifier.tsv" \
      --strategy comparison \
      --output "$OUT"
  done
done
