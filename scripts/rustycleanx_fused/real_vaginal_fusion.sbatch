#!/bin/bash
#SBATCH --job-name=rcx_real_vag
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=160G
#SBATCH --time=24:00:00
#SBATCH --output=/lustre1/g/aos_shihuang/rustyclean-paper/logs/rcx_real_vaginal-%j.out
#SBATCH --error=/lustre1/g/aos_shihuang/rustyclean-paper/logs/rcx_real_vaginal-%j.err

set -euo pipefail
REPO=/lustre1/g/aos_shihuang/rustyclean-paper
CLEANIFIER=$REPO/.conda_envs/cleanifier/bin/cleanifier
DEACON=/home/shihuang/.conda/envs/sketch-benchmark/bin/deacon
CLEANIFIER_INDEX=$REPO/databases/cleanifier/t2t_pangenome_hla_variants_cdna_cleanifier_index_k29_w33
DEACON_INDEX=/lustre1/g/aos_shihuang/databases/deacon/panhuman-1.k31w15.idx
INPUT=$REPO/real_data/vaginal_swab/reads.fastq.gz
OUT=$REPO/runs/rustycleanx_fused/real_vaginal_swab
WITNESS=$REPO/runs/rustycleanx_fused/indices/microbial.witness.hashes
mkdir -p "$OUT/deacon" "$OUT/cleanifier"

export PATH="$(dirname "$CLEANIFIER"):$(dirname "$DEACON"):${PATH}"
"$CLEANIFIER" filter --index "$CLEANIFIER_INDEX" --fastq "$INPUT" \
  --out "$OUT/cleanifier/cleanifier" --threads 16 --compression gz \
  --compression-level 1 --threshold 0.5
CLEANIFIER_KEPT=$(find "$OUT/cleanifier" -maxdepth 1 -type f -name '*keep*.fastq*' | head -n1)

"$DEACON" filter "$DEACON_INDEX" "$INPUT" --output "$OUT/deacon/deacon.fastq.gz" \
  --threads 16 --compression-level 1 --summary "$OUT/deacon/deacon_summary.json" --quiet
DEACON_KEPT=$OUT/deacon/deacon.fastq.gz

"$REPO/rustyclean-x/target/release/production_fusion" \
  --dataset real_vaginal_swab \
  --r1 "$INPUT" \
  --deacon-kept "$DEACON_KEPT" \
  --cleanifier-kept "$CLEANIFIER_KEPT" \
  --witness-index "$WITNESS" \
  --outdir "$OUT/fusion" \
  --microbe-witness-fraction 0.30 \
  --microbe-score-rescue 0.30
