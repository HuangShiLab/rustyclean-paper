#!/bin/bash
# =============================================================================
# RustyClean Benchmark — HPC Configuration
# =============================================================================
# Source this file in all HPC job scripts to keep paths consistent.
# Edit the values below for your cluster environment.

set -euo pipefail

# ---------------------------------------------------------------------------
# Project paths (on shared filesystem visible to compute nodes)
# ---------------------------------------------------------------------------
export PROJECT_DIR="${PROJECT_DIR:-/lustre1/g/aos_shihuang/rustyclean-paper}"

# Simulated reads and run outputs both live on the project filesystem. The user
# scratch on this cluster is 500 GB with ~154 GB free, which is short of the
# ~265 GB a full panel needs; the lustre group quota has several TB spare.
# Override either variable to move the trees elsewhere.
export SCRATCH_DIR="${SCRATCH_DIR:-$PROJECT_DIR/scratch}"
export DATA_DIR="${DATA_DIR:-$SCRATCH_DIR/data/enhanced}"
export RESULTS_DIR="${RESULTS_DIR:-$SCRATCH_DIR/results}"
export ANALYSIS_DIR="${ANALYSIS_DIR:-$SCRATCH_DIR/analysis}"

# Per-experiment run directories. Kept out of the repository tree by .gitignore
# so that hundreds of GB of output never reach git status. Point RUNS_DIR at a
# filesystem with room; the project directory is the fallback when the user
# scratch is too small.
export RUNS_DIR="${RUNS_DIR:-$PROJECT_DIR/runs}"
# SLURM .out/.err files. #SBATCH directives cannot reference this variable --
# SLURM parses those lines literally, before any shell runs -- so the directives
# use the relative path "logs/", which resolves here when a job is submitted
# from the repository root. run_all.sh additionally passes the absolute path on
# the sbatch command line, which overrides the directive and works from any
# directory.
export LOG_DIR="${LOG_DIR:-$PROJECT_DIR/logs}"

# ---------------------------------------------------------------------------
# Tool paths
# ---------------------------------------------------------------------------
# If you use a conda environment, set CONDA_ENV and CONDA_BASE.
export CONDA_ENV="${CONDA_ENV:-rustyclean-benchmark}"
export CONDA_BASE="${CONDA_BASE:-/group/aos_shihuang/conda}"

# Explicit binary paths (optional; will be resolved from conda if empty)
export RUSTYCLEAN="${RUSTYCLEAN:-/lustre1/g/aos_shihuang/rustyclean/target/release/rustyclean}"
export KNEADDATA="${KNEADDATA:-}"
export KRAKEN2="${KRAKEN2:-}"
export FASTP="${FASTP:-}"
export ISS="${ISS:-}"

# ---------------------------------------------------------------------------
# Database paths
# ---------------------------------------------------------------------------
# Root under which every index built by this project lives.
export DB_ROOT="${DB_ROOT:-/lustre1/g/aos_shihuang/databases}"

# --- Reference FASTAs -------------------------------------------------------
# T2T is the depletion reference. GRCh38 is the genome host reads are SIMULATED
# from; keeping the two different is deliberate, so that host removal has real
# assembly divergence to detect rather than matching the reads it came from.
export T2T_FASTA="${T2T_FASTA:-/lustre1/g/aos_shihuang/databases/kraken2/kraken16/genomes/GCF_009914755.1_T2T-CHM13v2.0_genomic.fna.gz}"
# No IPD-IMGT/HLA FASTA is present on this system, so every RustyClean index is
# built from T2T alone. Hostile's default index adds HLA; that difference is
# reported rather than worked around.
export HLA_FASTA="${HLA_FASTA:-}"
# Reference the auxiliary backends (minimap2, sylph, centrifuge) are built from.
export AUX_FASTA="${AUX_FASTA:-$T2T_FASTA}"
# Versioned RefSeq GRCh38.p14, so the Methods can state exactly what host
# reads were simulated from.
export HUMAN_GENOME="${HUMAN_GENOME:-/lustre1/g/aos_shihuang/databases/kraken2/kraken16/genomes/GCF_000001405.40_GRCh38.p14_genomic.fna.gz}"
export GENOME_DIR="${GENOME_DIR:-$PROJECT_DIR/genomes}"
# Directory of microbial genome FASTAs the simulated communities are drawn from.
# Accepts .fasta/.fa/.fna, gzipped or not. Needs at least 100 genomes for the
# high-complexity datasets, or genomes get reused and the community contains
# duplicate sequence.
#
# Pool the simulated microbial communities are drawn from. GTDB r202 reference
# genomes are used rather than the two larger collections on this cluster:
#   - GTDBr226_reference_genome (732k) is genome-level, not species-level, so a
#     random draw is dominated by over-sequenced species and a "100-species"
#     community would really contain many strains of the same few organisms.
#   - kraken2/kraken16/genomes is the source of the MIXED Kraken2 database and
#     contains the human genome; drawing "microbial" genomes from it would both
#     put host sequence in the ground truth and make the index ablation circular.
export MICROBIAL_GENOME_DIR="${MICROBIAL_GENOME_DIR:-$DB_ROOT/GTDB/GTDBr202/GTDBr202_reference_genome}"

# --- Indexes built by scripts/main/build_*.sh -------------------------------
export DB_T2T="${DB_T2T:-$DB_ROOT/rustyclean_human_t2t_only}"
# Kraken2, human-only. THE DEFAULT. Every experiment should use this unless it
# is explicitly testing index content.
export KRAKEN2_DB_T2T_ONLY="${KRAKEN2_DB_T2T_ONLY:-$DB_T2T/kraken2/t2t_only}"
# Kraken2, human-only plus IPD-IMGT/HLA. Index-content control for the ablation.
export KRAKEN2_DB_T2T_HLA="${KRAKEN2_DB_T2T_HLA:-$DB_T2T/kraken2/t2t_hla}"
# Kraken2, mixed multi-taxon library. Ablation arm A only; NOT a default.
# With a mixed library Kraken2 can assign a host read to an ancestor of
# Homo sapiens, which host detection must account for.
export KRAKEN2_DB_MIXED="${KRAKEN2_DB_MIXED:-$DB_ROOT/kraken2/kraken16}"
export BOWTIE2_INDEX="${BOWTIE2_INDEX:-$DB_T2T/bowtie2/t2t_only}"
export MINIMAP2_INDEX="${MINIMAP2_INDEX:-$DB_T2T/minimap2/t2t_only.mmi}"
export SYLPH_DB="${SYLPH_DB:-$DB_T2T/sylph/t2t.syldb}"
export CENTRIFUGE_INDEX="${CENTRIFUGE_INDEX:-$DB_T2T/centrifuge/t2t_only}"

# --- Comparator defaults (their own, unmodified) ----------------------------
# KneadData Homo_sapiens_hg39_T2T_Bowtie2_v0.1 (GCF_009914755.1, no HLA).
export KNEADDATA_DB="${KNEADDATA_DB:-$DB_ROOT/kneaddata/hg_39}"
# Hostile human-t2t-hla (T2T-CHM13v2.0 + IPD-IMGT/HLA), fetched by hostile itself.
export HOSTILE_INDEX="${HOSTILE_INDEX:-$HOME/.local/share/hostile/human-t2t-hla}"

# Active Kraken2 database. Human-only by default.
export KRAKEN2_DB="${KRAKEN2_DB:-$KRAKEN2_DB_T2T_ONLY}"

# --- Simulation parameters --------------------------------------------------
# The driver simulates with InSilicoSeq. The art_illumina scripts are kept for
# reference only. Do not mix the two: their error models differ, so datasets
# from one are not comparable with datasets from the other.
#
# ISS_MODEL selects the ISS error model, and the model -- not READ_LENGTH --
# determines read length. Check what the installed ISS produces before running
# the panel, and make READ_LENGTH agree with it; the Methods quotes READ_LENGTH.
export ISS_MODEL="${ISS_MODEL:-miseq}"
export READ_LENGTH="${READ_LENGTH:-150}"
# Passed to ISS so a rerun reproduces the same reads. Each array task offsets it
# by its task id, so datasets are independent but still deterministic.
export SIM_SEED="${SIM_SEED:-42}"
# art_illumina only; unused by the ISS path.
export ART_MODEL="${ART_MODEL:-HS25}"
export PE_FRAG_MEAN="${PE_FRAG_MEAN:-300}"
export PE_FRAG_SD="${PE_FRAG_SD:-30}"

# ---------------------------------------------------------------------------
# Compute settings
# ---------------------------------------------------------------------------
export N_THREADS="${N_THREADS:-16}"
export N_REPLICATES="${N_REPLICATES:-3}"

# ---------------------------------------------------------------------------
# Local scratch (highly recommended for I/O-heavy steps)
# ---------------------------------------------------------------------------
# Use node-local scratch if available; fall back to /tmp or DATA_DIR.
export LOCAL_SCRATCH="${LOCAL_SCRATCH:-}"
if [ -z "$LOCAL_SCRATCH" ]; then
    JOB_ID="${SLURM_JOB_ID:-$$}"
    if [ -n "${TMPDIR:-}" ]; then
        export LOCAL_SCRATCH="$TMPDIR/rustyclean_$JOB_ID"
    elif [ -d /tmp ]; then
        export LOCAL_SCRATCH="/tmp/rustyclean_$JOB_ID"
    else
        export LOCAL_SCRATCH="$DATA_DIR/.scratch_$JOB_ID"
    fi
fi

# ---------------------------------------------------------------------------
# Helper: activate conda environment
# ---------------------------------------------------------------------------
activate_conda() {
    # Environments created under the project take precedence, so tools missing
    # from the shared install can be added without write access to /group.
    for _e in "$PROJECT_DIR"/.conda_envs/*/bin; do
        [ -d "$_e" ] && export PATH="$_e:$PATH"
    done
    if [ -f "$CONDA_BASE/etc/profile.d/conda.sh" ]; then
        source "$CONDA_BASE/etc/profile.d/conda.sh"
    else
        export PATH="$CONDA_BASE/bin:$PATH"
    fi
    # Use combined activation helper if available (adds tool envs to PATH)
    if [ -f "$PROJECT_DIR/.conda_envs/activate_benchmark.sh" ]; then
        source "$PROJECT_DIR/.conda_envs/activate_benchmark.sh"
    else
        # Fallback: prefix-based env only
        CONDA_PREFIX="$PROJECT_DIR/.conda_envs/$CONDA_ENV"
        if [ -d "$CONDA_PREFIX" ]; then
            conda activate "$CONDA_PREFIX"
        elif conda env list 2>/dev/null | grep -q "^$CONDA_ENV[[:space:]]"; then
            conda activate "$CONDA_ENV"
        else
            echo "WARNING: conda env '$CONDA_ENV' not found; continuing with the" >&2
            echo "         current environment. Tool paths are set explicitly by" >&2
            echo "         each script, so this is usually survivable." >&2
        fi
    fi
}

# ---------------------------------------------------------------------------
# Helper: resolve tool path (conda env or explicit)
# ---------------------------------------------------------------------------
resolve_tool() {
    local explicit="$1"
    local name="$2"
    if [ -n "$explicit" ] && [ -x "$explicit" ]; then
        echo "$explicit"
    elif command -v "$name" >/dev/null 2>&1; then
        command -v "$name"
    else
        echo "ERROR: $name not found" >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Helper: robust GNU time parsing
# ---------------------------------------------------------------------------
parse_gnu_time() {
    local timefile="$1"
    local runtime="unknown"
    local max_mem="unknown"

    if [ -f "$timefile" ]; then
        runtime=$(grep "Elapsed (wall clock) time" "$timefile" | sed -n 's/.*Elapsed (wall clock) time.*: //p' || echo "unknown")
        max_mem=$(grep "Maximum resident set size" "$timefile" | sed -n 's/.*Maximum resident set size (kbytes): //p' || echo "unknown")
    fi

    echo "$runtime,$max_mem"
}

# ---------------------------------------------------------------------------
# Helper: parse runtime string (H:MM:SS / M:SS / SS.SS) to seconds
# ---------------------------------------------------------------------------
parse_runtime_to_seconds() {
    local t="$1"
    if [ -z "$t" ] || [ "$t" = "unknown" ]; then
        echo "nan"
        return
    fi
    python3 - "$t" <<'PYEOF'
import sys
t = sys.argv[1]
parts = t.split(':')
if len(parts) == 3:
    print(int(parts[0])*3600 + int(parts[1])*60 + float(parts[2]))
elif len(parts) == 2:
    print(int(parts[0])*60 + float(parts[1]))
else:
    try:
        print(float(parts[0]))
    except ValueError:
        print('nan')
PYEOF
}

# ---------------------------------------------------------------------------
# Index provenance
#
# An index file sitting at the expected path does not prove it was built from
# the reference this rerun uses -- the v1 indexes lived at similar paths and
# were built from GRCh38, so a plain "does the file exist" check would silently
# reuse the wrong reference and reproduce the very bug the rerun exists to fix.
# Each builder therefore stamps the index with the source it was built from and
# skips only when that stamp still matches. No stamps exist yet, so the first
# run after this change rebuilds everything. FORCE_REBUILD=1 rebuilds anyway.
export FORCE_REBUILD="${FORCE_REBUILD:-0}"

_index_stamp_value() {
    local src="$1"
    local abs size
    abs="$(cd "$(dirname "$src")" && pwd)/$(basename "$src")"
    size="$(stat -c %s "$src" 2>/dev/null || stat -f %z "$src" 2>/dev/null || echo '?')"
    printf '%s\t%s\n' "$abs" "$size"
}

# index_up_to_date <stamp_path> <source_fasta> -> 0 when the build can be skipped
index_up_to_date() {
    local stamp="$1" src="$2"
    if [ "${FORCE_REBUILD:-0}" = "1" ]; then return 1; fi
    if [ ! -f "$stamp" ]; then return 1; fi
    [ "$(cat "$stamp")" = "$(_index_stamp_value "$src")" ]
}

index_stamp_write() {
    local stamp="$1" src="$2"
    mkdir -p "$(dirname "$stamp")"
    _index_stamp_value "$src" > "$stamp"
}
