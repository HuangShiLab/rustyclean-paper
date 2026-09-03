#!/bin/bash
#SBATCH --job-name=bt2_t2t_only
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=12:00:00
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err

# =============================================================================
# Bowtie2 index from T2T-CHM13v2.0 alone
# =============================================================================
# Replaces build_bowtie2_grch38_t2t_v2.sh for the benchmark. That script builds
# from GRCh38 and T2T merged, but host reads are simulated FROM GRCh38, so a
# reference containing GRCh38 would hold the exact source of every host read and
# make depletion trivially easy. Keeping the depletion reference to T2T alone
# leaves real assembly divergence for the tools to find, and matches the
# human-only Kraken2 index so RustyClean's two paths use the same reference
# content.
#
# Note that Hostile's default index adds IPD-IMGT/HLA to T2T. That difference is
# a property of the comparison and is reported, not something to paper over by
# changing Hostile's defaults.
# =============================================================================

set -euo pipefail

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
export PATH="$CONDA_BASE/envs/bowtie2/bin:${PATH}"

OUT_PREFIX="$BOWTIE2_INDEX"
WORK="$(dirname "$OUT_PREFIX")"
mkdir -p "$WORK"

if [ ! -f "$T2T_FASTA" ]; then
    echo "ERROR: T2T FASTA not found: $T2T_FASTA" >&2
    exit 1
fi

STAMP="${OUT_PREFIX}.source"
if [ -f "${OUT_PREFIX}.1.bt2" ] || [ -f "${OUT_PREFIX}.1.bt2l" ]; then
    if index_up_to_date "$STAMP" "$T2T_FASTA"; then
        echo "Bowtie2 index already built from $T2T_FASTA, skipping: $OUT_PREFIX"
        exit 0
    fi
    echo "Bowtie2 index present but NOT stamped as built from $T2T_FASTA."
    echo "Rebuilding rather than reusing an index of unknown provenance."
    rm -f "${OUT_PREFIX}".*.bt2 "${OUT_PREFIX}".*.bt2l
fi

echo "Job started at: $(date)"
echo "Reference: $T2T_FASTA"
echo "Output prefix: $OUT_PREFIX"

TMP_FA="$WORK/t2t.fna"
echo "Decompressing..."
zcat "$T2T_FASTA" > "$TMP_FA"

echo "Building Bowtie2 index..."
# No --large-index. That flag is inherited from the GRCh38+T2T merged builder,
# where it is required because the merged reference is about 6.2 Gbp and passes
# Bowtie2's 4 Gbp (2^32) limit for the small format. T2T alone is about 3.1 Gbp,
# so the small format applies, and Bowtie2 switches formats on its own if a
# reference ever does exceed the limit.
#
# The format is not cosmetic here: .bt2l stores 64-bit offsets and so is larger
# than the equivalent .bt2, and index size is both a reported figure and the
# input to RustyClean's own database-size estimate. Forcing the large format
# would overstate RustyClean's footprint against the .bt2 indexes KneadData and
# Hostile ship, as an artefact of a flag rather than of the method.
bowtie2-build --threads "${N_THREADS:-16}" "$TMP_FA" "$OUT_PREFIX" \
    2>&1 | tee "$WORK/build.log"

rm -f "$TMP_FA"
ls -lh "${OUT_PREFIX}"*
echo "Job finished at: $(date)"

index_stamp_write "$STAMP" "$T2T_FASTA"
echo "Stamped: $STAMP"
