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

# Runtime outputs go to user scratch (/scr/u/shihuang) because the project
# directory on /lustre1 is near the user quota limit.
export SCRATCH_DIR="${SCRATCH_DIR:-/scr/u/shihuang/rustyclean-paper}"
export DATA_DIR="${DATA_DIR:-$SCRATCH_DIR/data/enhanced}"
export RESULTS_DIR="${RESULTS_DIR:-$SCRATCH_DIR/results}"
export ANALYSIS_DIR="${ANALYSIS_DIR:-$SCRATCH_DIR/analysis}"
export LOG_DIR="${LOG_DIR:-$SCRATCH_DIR/logs}"

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
export T2T_FASTA="${T2T_FASTA:-$DB_ROOT/fast2bM/human/GCF_009914755.1_T2T-CHM13v2.0_genomic.fna.gz}"
export HLA_FASTA="${HLA_FASTA:-$DB_ROOT/rustyclean_human_t2t_only/hla/ipd_imgt_hla.fna}"
export HUMAN_GENOME="${HUMAN_GENOME:-$PROJECT_DIR/databases/GRCh38.fa.gz}"
export GENOME_DIR="${GENOME_DIR:-$PROJECT_DIR/genomes}"

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
export BOWTIE2_INDEX="${BOWTIE2_INDEX:-$DB_T2T/bowtie2/t2t_hla}"
export MINIMAP2_INDEX="${MINIMAP2_INDEX:-$DB_T2T/minimap2/t2t_hla.mmi}"
export SYLPH_DB="${SYLPH_DB:-$DB_T2T/sylph/t2t.syldb}"
export CENTRIFUGE_INDEX="${CENTRIFUGE_INDEX:-$DB_T2T/centrifuge/t2t_hla}"

# --- Comparator defaults (their own, unmodified) ----------------------------
# KneadData Homo_sapiens_hg39_T2T_Bowtie2_v0.1 (GCF_009914755.1, no HLA).
export KNEADDATA_DB="${KNEADDATA_DB:-$DB_ROOT/kneaddata/hg_39}"
# Hostile human-t2t-hla (T2T-CHM13v2.0 + IPD-IMGT/HLA), fetched by hostile itself.
export HOSTILE_INDEX="${HOSTILE_INDEX:-$HOME/.local/share/hostile/human-t2t-hla}"

# Active Kraken2 database. Human-only by default.
export KRAKEN2_DB="${KRAKEN2_DB:-$KRAKEN2_DB_T2T_ONLY}"

# --- Simulation parameters --------------------------------------------------
export ISS_MODEL="${ISS_MODEL:-miseq}"
export READ_LENGTH="${READ_LENGTH:-150}"
export ISS_SEED="${ISS_SEED:-42}"

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
        else
            conda activate "$CONDA_ENV"
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
