#!/bin/bash
#SBATCH --job-name=k2_t2t_only
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=200G
#SBATCH --time=12:00:00
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err

set -e

# This script used to hardcode every path, which put it out of step with the
# rest of the build: its T2T FASTA came from a different directory than the one
# config.sh names and preflight validates, so the Kraken2 database could be
# built from a different file than the Bowtie2, minimap2, sylph and centrifuge
# indexes -- and the provenance stamps would have recorded the wrong source.
# Locate the repository (SLURM copies the batch script to a spool directory).
if [ -z "${REPO_DIR:-}" ]; then
    for _cand in "${SLURM_SUBMIT_DIR:-}" \
                 "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)" \
                 /lustre1/g/aos_shihuang/rustyclean-paper; do
        if [ -n "$_cand" ] && [ -f "$_cand/scripts/hpc/config.sh" ]; then
            REPO_DIR="$_cand"; break
        fi
    done
fi
[ -n "${REPO_DIR:-}" ] || { echo "ERROR: cannot locate the repository. Set REPO_DIR." >&2; exit 1; }
source "$REPO_DIR/scripts/hpc/config.sh"
activate_conda
export PATH="$CONDA_BASE/envs/kraken2/bin:${PATH}"

K2_DB="$KRAKEN2_DB_T2T_ONLY"
T2T="$T2T_FASTA"
SOURCE_TAX="$SOURCE_TAXONOMY"

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
# awk rather than head: this script now sources config.sh, which enables
# pipefail, and head exiting first makes kraken2-inspect take SIGPIPE. The
# pipeline then returns 141 and set -e kills the job -- after the database has
# already been built and cleaned. awk reads to the end, and the inspect is only
# diagnostic, so it must not be able to fail the build.
kraken2-inspect --db "${K2_DB}" 2>/dev/null | awk 'NR<=30' || true
echo "Job finished at: $(date)"
