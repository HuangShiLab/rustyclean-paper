#!/bin/bash
#SBATCH --job-name=bt2_grch38_t2t_v2
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=12:00:00
#SBATCH --output=/home/shihuang/bt2_grch38_t2t_v2_%j.out
#SBATCH --error=/home/shihuang/bt2_grch38_t2t_v2_%j.err

set -e

source /group/aos_shihuang/conda/etc/profile.d/conda.sh
export PATH="/group/aos_shihuang/conda/envs/bowtie2/bin:${PATH}"

DB_DIR="/lustre1/g/aos_shihuang/databases/rustyclean_human_grch38_t2t"
FASTA="${DB_DIR}/fasta/grch38_t2t_merged_genomic.fna.gz"
OUT_PREFIX="${DB_DIR}/bowtie2/grch38_t2t"

if [ ! -f "${FASTA}" ]; then
    echo "ERROR: Merged FASTA not found: ${FASTA}" >&2
    exit 1
fi

mkdir -p "${DB_DIR}/bowtie2"
rm -f "${OUT_PREFIX}"*.bt2 "${OUT_PREFIX}"*.bt2l

echo "Job started at: $(date)"
echo "Building bowtie2 large index: ${OUT_PREFIX}"

TMP_FA="${DB_DIR}/fasta/grch38_t2t_merged_genomic.fna"
zcat "${FASTA}" > "${TMP_FA}"

bowtie2-build --large-index --threads 8 "${TMP_FA}" "${OUT_PREFIX}" 2>&1 | tee "${DB_DIR}/bowtie2/build_v2.log"

rm -f "${TMP_FA}"

echo "Index files:"
ls -lh "${DB_DIR}/bowtie2/"
echo "Job finished at: $(date)"
