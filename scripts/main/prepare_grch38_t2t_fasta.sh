#!/bin/bash
#SBATCH --job-name=prep_grch38_t2t
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=01:00:00
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err

set -e

DB_DIR="/lustre1/g/aos_shihuang/databases/rustyclean_human_grch38_t2t"
mkdir -p "${DB_DIR}/fasta"

GRCH38="/lustre1/g/aos_shihuang/databases/human/GCF_000001405.40_GRCh38.p14_genomic.fna.gz"
T2T="/lustre1/g/aos_shihuang/databases/fast2bM/human/GCF_009914755.1_T2T-CHM13v2.0_genomic.fna.gz"
MERGED="${DB_DIR}/fasta/grch38_t2t_merged_genomic.fna.gz"

if [ ! -f "${GRCH38}" ]; then
    echo "ERROR: GRCh38 not found: ${GRCH38}" >&2
    exit 1
fi

if [ ! -f "${T2T}" ]; then
    echo "ERROR: T2T not found: ${T2T}" >&2
    exit 1
fi

echo "Job started at: $(date)"
echo "Merging GRCh38 + T2T into ${MERGED}..."

# Concatenate while preserving original sequence IDs; decompress on the fly
# Add prefix to sequence IDs to avoid any potential collisions
cat <(zcat "${GRCH38}" | awk '/^>/{print ">grch38|" substr($0,2); next}{print}') \
    <(zcat "${T2T}" | awk '/^>/{print ">t2t|" substr($0,2); next}{print}') | \
    pigz -p 4 > "${MERGED}"

echo "Merged FASTA: ${MERGED}"
echo "Size: $(du -sh ${MERGED})"
echo "Sequences: $(zcat ${MERGED} | grep -c '^>')"
echo "Job finished at: $(date)"
