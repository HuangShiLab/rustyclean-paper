#!/bin/bash
#SBATCH --job-name=k2_grch38_t2t
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=200G
#SBATCH --time=24:00:00
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err

set -e

source /group/aos_shihuang/conda/etc/profile.d/conda.sh
export PATH="/group/aos_shihuang/conda/envs/kraken2/bin:${PATH}"

DB_DIR="/lustre1/g/aos_shihuang/databases/rustyclean_human_grch38_t2t"
K2_DB="${DB_DIR}/kraken2/grch38_t2t"

GRCH38="/lustre1/g/aos_shihuang/databases/human/GCF_000001405.40_GRCh38.p14_genomic.fna.gz"
T2T="/lustre1/g/aos_shihuang/databases/fast2bM/human/GCF_009914755.1_T2T-CHM13v2.0_genomic.fna.gz"

if [ ! -f "${GRCH38}" ] || [ ! -f "${T2T}" ]; then
    echo "ERROR: Input FASTA not found" >&2
    exit 1
fi

mkdir -p "${K2_DB}"

echo "Job started at: $(date)"
echo "Building Kraken2 database: ${K2_DB}"

# 1. Download taxonomy
echo "[1/4] Downloading taxonomy..."
kraken2-build --download-taxonomy --db "${K2_DB}" --threads 8 2>&1 | tee "${K2_DB}/download_taxonomy.log"

# 2. Add GRCh38
echo "[2/4] Adding GRCh38 to library..."
kraken2-build --add-to-library "${GRCH38}" --db "${K2_DB}" --threads 8 2>&1 | tee -a "${K2_DB}/add_library.log"

# 3. Add T2T
echo "[3/4] Adding T2T-CHM13 to library..."
kraken2-build --add-to-library "${T2T}" --db "${K2_DB}" --threads 8 2>&1 | tee -a "${K2_DB}/add_library.log"

# 4. Build database
echo "[4/4] Building Kraken2 database..."
kraken2-build --build --db "${K2_DB}" --threads 8 --kmer-len 35 --minimizer-len 31 2>&1 | tee "${K2_DB}/build.log"

# Clean intermediate files to save space
kraken2-build --clean --db "${K2_DB}" 2>&1 | tee -a "${K2_DB}/build.log" || true

echo "Final database files:"
ls -lh "${K2_DB}/"
echo "Inspect:"
kraken2-inspect --db "${K2_DB}" | head -20
echo "Job finished at: $(date)"
