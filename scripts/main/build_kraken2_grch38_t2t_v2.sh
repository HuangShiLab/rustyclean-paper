#!/bin/bash
#SBATCH --job-name=k2_grch38_t2t_v2
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=200G
#SBATCH --time=24:00:00
#SBATCH --output=/home/%u/k2_grch38_t2t_v2_%j.out
#SBATCH --error=/home/%u/k2_grch38_t2t_v2_%j.err

set -e

source /group/aos_shihuang/conda/etc/profile.d/conda.sh
export PATH="/group/aos_shihuang/conda/envs/kraken2/bin:${PATH}"

DB_DIR="/lustre1/g/aos_shihuang/databases/rustyclean_human_grch38_t2t"
K2_DB="${DB_DIR}/kraken2/grch38_t2t"

GRCH38="/lustre1/g/aos_shihuang/databases/human/GCF_000001405.40_GRCh38.p14_genomic.fna.gz"
T2T="/lustre1/g/aos_shihuang/databases/fast2bM/human/GCF_009914755.1_T2T-CHM13v2.0_genomic.fna.gz"

# Source taxonomy from existing kraken2 db (kraken16)
SOURCE_K2="/lustre1/g/aos_shihuang/databases/kraken2/kraken16"

if [ ! -f "${GRCH38}" ] || [ ! -f "${T2T}" ]; then
    echo "ERROR: Input FASTA not found" >&2
    exit 1
fi

if [ ! -f "${SOURCE_K2}/names.dmp" ] || [ ! -f "${SOURCE_K2}/nodes.dmp" ]; then
    echo "ERROR: Source taxonomy not found in ${SOURCE_K2}" >&2
    exit 1
fi

# Clean and recreate
rm -rf "${K2_DB}"
mkdir -p "${K2_DB}/taxonomy"
mkdir -p "${K2_DB}/library/added"

echo "Job started at: $(date)"
echo "Building Kraken2 database: ${K2_DB}"

# Copy taxonomy
cp "${SOURCE_K2}/names.dmp" "${K2_DB}/taxonomy/"
cp "${SOURCE_K2}/nodes.dmp" "${K2_DB}/taxonomy/"

# Add GRCh38 to library and create prelim_map
LIB_DIR="${K2_DB}/library/added"
echo "[1/3] Adding GRCh38 to library..."
zcat "${GRCH38}" > "${LIB_DIR}/grch38.fna"
awk '/^>/{sub(/^>/, ""); id=$1; print id "\t9606"}' "${LIB_DIR}/grch38.fna" > "${LIB_DIR}/prelim_map_grch38.txt"

# Add T2T to library and create prelim_map
echo "[2/3] Adding T2T-CHM13 to library..."
zcat "${T2T}" > "${LIB_DIR}/t2t.fna"
awk '/^>/{sub(/^>/, ""); id=$1; print id "\t9606"}' "${LIB_DIR}/t2t.fna" > "${LIB_DIR}/prelim_map_t2t.txt"

# Build database
echo "[3/3] Building Kraken2 database..."
kraken2-build --build --db "${K2_DB}" --threads 8 --kmer-len 35 --minimizer-len 31 2>&1 | tee "${K2_DB}/build_v2.log"

# Clean intermediate files
kraken2-build --clean --db "${K2_DB}" 2>&1 | tee -a "${K2_DB}/build_v2.log" || true

echo "Final database files:"
ls -lh "${K2_DB}/"
echo "Inspect:"
kraken2-inspect --db "${K2_DB}" | head -20
echo "Job finished at: $(date)"
