#!/bin/bash
#SBATCH --job-name=k2_t2t_only
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=200G
#SBATCH --time=12:00:00
#SBATCH --output=/home/shihuang/k2_t2t_only_%j.out
#SBATCH --error=/home/shihuang/k2_t2t_only_%j.err

set -e

source /group/aos_shihuang/conda/etc/profile.d/conda.sh
export PATH="/group/aos_shihuang/conda/envs/kraken2/bin:${PATH}"

DB_DIR="/lustre1/g/aos_shihuang/databases/rustyclean_human_t2t_only"
K2_DB="${DB_DIR}/kraken2/t2t_only"

T2T="/lustre1/g/aos_shihuang/databases/fast2bM/human/GCF_009914755.1_T2T-CHM13v2.0_genomic.fna.gz"

# Full NCBI taxonomy from existing standard kraken2 db
SOURCE_TAX="/lustre1/g/aos_shihuang/tools/kraken2-standard-db/kraken_database/taxonomy"

if [ ! -f "${T2T}" ]; then
    echo "ERROR: T2T FASTA not found" >&2
    exit 1
fi

if [ ! -f "${SOURCE_TAX}/names.dmp" ] || [ ! -f "${SOURCE_TAX}/nucl_gb.accession2taxid" ]; then
    echo "ERROR: Source taxonomy not found in ${SOURCE_TAX}" >&2
    exit 1
fi

# Clean and recreate
rm -rf "${K2_DB}"
mkdir -p "${K2_DB}/taxonomy"
mkdir -p "${K2_DB}/library"

echo "Job started at: $(date)"
echo "Building T2T-only Kraken2 database: ${K2_DB}"

# Symlink full taxonomy
ln -s "${SOURCE_TAX}/names.dmp" "${K2_DB}/taxonomy/names.dmp"
ln -s "${SOURCE_TAX}/nodes.dmp" "${K2_DB}/taxonomy/nodes.dmp"
ln -s "${SOURCE_TAX}/nucl_gb.accession2taxid" "${K2_DB}/taxonomy/nucl_gb.accession2taxid"
ln -s "${SOURCE_TAX}/nucl_wgs.accession2taxid" "${K2_DB}/taxonomy/nucl_wgs.accession2taxid"
ln -s "${SOURCE_TAX}/merged.dmp" "${K2_DB}/taxonomy/merged.dmp" || true
ln -s "${SOURCE_TAX}/citations.dmp" "${K2_DB}/taxonomy/citations.dmp" || true
ln -s "${SOURCE_TAX}/delnodes.dmp" "${K2_DB}/taxonomy/delnodes.dmp" || true

# Decompress T2T FASTA
echo "Decompressing T2T..."
zcat "${T2T}" > "${K2_DB}/library/t2t.fna"

# Add T2T to library
echo "[1/2] Adding T2T-CHM13 to library..."
kraken2-build --add-to-library "${K2_DB}/library/t2t.fna" --db "${K2_DB}" --threads 8 2>&1 | tee "${K2_DB}/add_library.log"

# Build database
echo "[2/2] Building Kraken2 database..."
kraken2-build --build --db "${K2_DB}" --threads 8 --kmer-len 35 --minimizer-len 31 2>&1 | tee "${K2_DB}/build.log"

# Clean intermediate files
kraken2-build --clean --db "${K2_DB}" 2>&1 | tee -a "${K2_DB}/build.log" || true

echo "Final database files:"
ls -lh "${K2_DB}/"
echo "Inspect:"
kraken2-inspect --db "${K2_DB}" | head -30
echo "Job finished at: $(date)"
