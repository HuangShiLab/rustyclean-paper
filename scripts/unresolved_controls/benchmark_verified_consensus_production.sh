#!/bin/bash
set -euo pipefail

REPO_DIR="/lustre1/g/aos_shihuang/rustyclean-paper"
DATA_DIR="/scr/u/shihuang/rustyclean-paper/data/enhanced"
PROD="$REPO_DIR/runs/unresolved_controls/production_index_comparison"
OUT="$REPO_DIR/runs/unresolved_controls/summary/rustyclean_x_verified_clean_metrics.tsv"
WORK_ROOT="$REPO_DIR/runs/unresolved_controls/verified_consensus_work"
BIN="$REPO_DIR/rustyclean-x/target/release/consensus_benchmark"
HOSTILE_INDEX="${HOSTILE_INDEX:-$HOME/.local/share/hostile/human-t2t-hla}"
BOWTIE2="${BOWTIE2:-$HOME/.conda/envs/hostile-centrifuge/bin/bowtie2}"
MINIMAP2="${MINIMAP2:-$HOME/.conda/envs/sketch-benchmark/bin/minimap2}"
GTDB_DIR="${GTDB_DIR:-/lustre1/g/aos_shihuang/databases/GTDB/GTDBr202/GTDBr202_reference_genome}"
WORK_ROOT="$REPO_DIR/runs/unresolved_controls/verified_consensus_work"
MICROBE_PANEL="$WORK_ROOT/gtdb_r202_first100_panel.fna"


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
  DIR="$DATA_DIR/${DATASET}"
  TRUTH="$DIR/ground_truth_labels.txt"
  INPUT="$DIR/reads.fastq.gz"
  for REP in 1 2 3; do
    WORK="$WORK_ROOT/${DATASET}/rep${REP}"
    "$BIN" \
      --dataset "$DATASET" \
      --replicate "$REP" \
      --truth "$TRUTH" \
      --input-fastq "$INPUT" \
      --deacon-kept "$PROD/deacon/${DATASET}/rep${REP}/deacon.fastq.gz" \
      --cleanifier-kept "$PROD/cleanifier/${DATASET}/rep${REP}/cleanifier_keep.fastq.gz" \
      --deacon-runtime-tsv "$PROD/metrics/${DATASET}.deacon.tsv" \
      --cleanifier-runtime-tsv "$PROD/metrics/${DATASET}.cleanifier.tsv" \
      --strategy verified-clean \
      --bowtie2 "$BOWTIE2" \
      --bowtie2-index "$HOSTILE_INDEX" \
      --work-dir "$WORK" \
      --threads 16 \
      --output "$OUT"
  done
done
