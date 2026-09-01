#!/bin/bash
#SBATCH --job-name=build_aux_idx
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=128G
#SBATCH --time=12:00:00
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err

# =============================================================================
# Build the minimap2, sylph and centrifuge indexes
# =============================================================================
# These three backends had no build script, so their indexes could not be
# reproduced. All three derive from the same T2T + HLA FASTA that the Bowtie2
# index is built from, which keeps the backend comparison an honest test of the
# algorithms rather than of differing reference content.
#
# Run after prepare_grch38_t2t_fasta.sh has produced the combined FASTA.
# =============================================================================

set -euo pipefail

# Locate the repository. SLURM copies the batch script to a spool directory, so
# $0 does not point into the repo under sbatch, and config.sh cannot be found via
# a variable that config.sh itself defines.
if [ -z "${REPO_DIR:-}" ]; then
    for _cand in "${SLURM_SUBMIT_DIR:-}" \
                 "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)" \
                 /lustre1/g/aos_shihuang/rustyclean-paper; do
        if [ -n "$_cand" ] && [ -f "$_cand/scripts/hpc/config.sh" ]; then
            REPO_DIR="$_cand"; break
        fi
    done
fi
if [ -z "${REPO_DIR:-}" ]; then
    echo "ERROR: cannot locate the repository. Set REPO_DIR to its path." >&2
    exit 1
fi
source "$REPO_DIR/scripts/hpc/config.sh"
activate_conda
export PATH="/group/aos_shihuang/conda/envs/minimap2/bin:/group/aos_shihuang/conda/envs/sylph/bin:/group/aos_shihuang/conda/envs/centrifuge/bin:${PATH}"

# Combined human reference: T2T-CHM13v2.0 plus IPD-IMGT/HLA, matching the
# Bowtie2 index and Hostile's human-t2t-hla.
FASTA="${AUX_FASTA:-$T2T_FASTA}"

if [ ! -f "$FASTA" ]; then
    echo "ERROR: combined reference FASTA not found: $FASTA" >&2
    echo "Set AUX_FASTA, or check T2T_FASTA in scripts/hpc/config.sh" >&2
    exit 1
fi

echo "Job started at: $(date)"
echo "Reference: $FASTA ($(du -h "$FASTA" | cut -f1))"

# --- minimap2 ---------------------------------------------------------------
if ! command -v minimap2 >/dev/null 2>&1; then
    echo "[1/3] minimap2 not available, skipping the minimap2 index"
elif [ -f "$MINIMAP2_INDEX" ] && index_up_to_date "${MINIMAP2_INDEX}.source" "$FASTA"; then
    echo "[1/3] minimap2 index already built from $FASTA, skipping"
else
    echo "[1/3] Building minimap2 index (short-read preset)..."
    mkdir -p "$(dirname "$MINIMAP2_INDEX")"
    minimap2 -x sr -t "$N_THREADS" -d "$MINIMAP2_INDEX" "$FASTA"
    index_stamp_write "${MINIMAP2_INDEX}.source" "$FASTA"
    ls -lh "$MINIMAP2_INDEX"
fi

# --- sylph ------------------------------------------------------------------
if [ -f "$SYLPH_DB" ] && index_up_to_date "${SYLPH_DB}.source" "$FASTA"; then
    echo "[2/3] sylph database already built from $FASTA, skipping"
else
    echo "[2/3] Building sylph sketch database..."
    mkdir -p "$(dirname "$SYLPH_DB")"
    # -g: sketch as genomes; -o takes the path without the .syldb suffix
    sylph sketch -g "$FASTA" -t "$N_THREADS" -o "${SYLPH_DB%.syldb}"
    index_stamp_write "${SYLPH_DB}.source" "$FASTA"
    ls -lh "$SYLPH_DB"
fi

# --- centrifuge -------------------------------------------------------------
if ! command -v centrifuge-build >/dev/null 2>&1; then
    echo "[3/3] centrifuge-build not available, skipping the centrifuge index"
elif [ -f "${CENTRIFUGE_INDEX}.1.cf" ] && index_up_to_date "${CENTRIFUGE_INDEX}.source" "$FASTA"; then
    echo "[3/3] centrifuge index already built from $FASTA, skipping"
else
    echo "[3/3] Building centrifuge index..."
    mkdir -p "$(dirname "$CENTRIFUGE_INDEX")"
    CF_TMP="$(dirname "$CENTRIFUGE_INDEX")/build_tmp"
    mkdir -p "$CF_TMP"
    # Every sequence in the reference is human, so map them all to taxid 9606.
    grep '^>' "$FASTA" | sed 's/^>//' | awk '{print $1"\t9606"}' > "$CF_TMP/seqid2taxid.map"
    # Minimal taxonomy covering the human lineage.
    if [ -f "$KRAKEN2_DB_T2T_ONLY/taxonomy/nodes.dmp" ]; then
        cp "$KRAKEN2_DB_T2T_ONLY/taxonomy/nodes.dmp" "$CF_TMP/nodes.dmp"
        cp "$KRAKEN2_DB_T2T_ONLY/taxonomy/names.dmp" "$CF_TMP/names.dmp"
    else
        echo "ERROR: no NCBI taxonomy available for the centrifuge build" >&2
        echo "Expected $KRAKEN2_DB_T2T_ONLY/taxonomy/{nodes,names}.dmp" >&2
        exit 1
    fi
    centrifuge-build -p "$N_THREADS" \
        --conversion-table "$CF_TMP/seqid2taxid.map" \
        --taxonomy-tree "$CF_TMP/nodes.dmp" \
        --name-table "$CF_TMP/names.dmp" \
        "$FASTA" "$CENTRIFUGE_INDEX"
    index_stamp_write "${CENTRIFUGE_INDEX}.source" "$FASTA"
    ls -lh "${CENTRIFUGE_INDEX}"*.cf
fi

echo
echo "All auxiliary indexes built."
echo "  minimap2   : $MINIMAP2_INDEX"
echo "  sylph      : $SYLPH_DB"
echo "  centrifuge : $CENTRIFUGE_INDEX"
echo "Job finished at: $(date)"
