#!/bin/bash
# =============================================================================
# Preflight — check everything run_all.sh needs before submitting 60-80 h of jobs
# =============================================================================
#   bash scripts/preflight.sh
#
# Exits non-zero if anything REQUIRED is missing. Items marked OPTIONAL only
# disable the experiment that needs them.
# =============================================================================

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$REPO_DIR/scripts/hpc/config.sh" 2>/dev/null || {
    echo "FATAL: cannot source $REPO_DIR/scripts/hpc/config.sh"; exit 1; }
set +euo pipefail

FAIL=0; WARN=0
ok()   { printf "  \033[32m OK \033[0m %s\n" "$1"; }
bad()  { printf "  \033[31mMISS\033[0m %-52s %s\n" "$1" "$2"; FAIL=$((FAIL+1)); }
warn() { printf "  \033[33mWARN\033[0m %-52s %s\n" "$1" "$2"; WARN=$((WARN+1)); }
note() { printf "  \033[36mNOTE\033[0m %s\n" "$1"; }

need_dir()  { [ -d "$2" ] && ok "$1" || bad "$1" "$2"; }
need_file() { [ -f "$2" ] && ok "$1" || bad "$1" "$2"; }
need_exec() { [ -x "$2" ] && ok "$1" || bad "$1" "$2"; }
opt_dir()   { [ -d "$2" ] && ok "$1" || warn "$1" "$2"; }
opt_file()  { [ -f "$2" ] && ok "$1" || warn "$1" "$2"; }
# a kraken2 db is a directory holding hash.k2d
need_k2()   { [ -f "$2/hash.k2d" ] && ok "$1" || bad "$1" "$2/hash.k2d"; }
opt_k2()    { [ -f "$2/hash.k2d" ] && ok "$1" || warn "$1" "$2/hash.k2d"; }
# a bowtie2 index is a prefix with {prefix}.1.bt2
need_bt2()  { { [ -f "$2.1.bt2" ] || [ -f "$2.1.bt2l" ]; } && ok "$1" || bad "$1" "$2.1.bt2"; }
opt_bt2()   { { [ -f "$2.1.bt2" ] || [ -f "$2.1.bt2l" ]; } && ok "$1" || warn "$1" "$2.1.bt2"; }

echo "Preflight for a full rerun"
echo "  REPO_DIR = $REPO_DIR"
echo

echo "[1] Repository and driver"
need_file "run_all.sh"              "$REPO_DIR/scripts/run_all.sh"
need_file "config.sh"               "$REPO_DIR/scripts/hpc/config.sh"
need_file "RUN_ALL.md"              "$REPO_DIR/RUN_ALL.md"
[ -w "$REPO_DIR" ] && ok "repository is writable" || warn "repository is NOT writable" "$REPO_DIR"
echo

echo "[2] RustyClean binary  (must be rebuilt: --bowtie2-recheck now takes a path)"
need_exec "rustyclean binary"       "$RUSTYCLEAN"
if [ -x "$RUSTYCLEAN" ]; then
    if "$RUSTYCLEAN" --help 2>&1 | grep -q -- "--bowtie2-recheck <"; then
        ok "binary accepts --bowtie2-recheck <PREFIX>"
    else
        bad "binary is STALE" "rebuild: cd $(dirname "$(dirname "$(dirname "$RUSTYCLEAN")")") && cargo build --release"
    fi
fi
echo

echo "[3] Conda and tools"
need_file "conda profile"           "$CONDA_BASE/etc/profile.d/conda.sh"
opt_dir   "benchmark env"           "$REPO_DIR/.conda_envs/rustyclean-benchmark"
for t in fastp bowtie2 kraken2 minimap2 sylph centrifuge seqtk kneaddata; do
    opt_dir "conda env: $t"         "$CONDA_BASE/envs/$t/bin"
done
opt_dir   "samtools"                "/lustre1/g/aos_shihuang/tools/samtools/samtools-1.21"
command -v hostile >/dev/null 2>&1 && ok "hostile on PATH" || warn "hostile not on PATH" "needed by stage 3"
echo

echo "[4] Reference FASTAs  (inputs to stage 1)"
need_file "T2T-CHM13v2.0 (depletion reference)" "$T2T_FASTA"
opt_file  "IPD-IMGT/HLA"            "$HLA_FASTA"
opt_file  "GRCh38 (host reads are SIMULATED from this)" "$HUMAN_GENOME"
need_dir  "NCBI taxonomy for kraken2-build" "/lustre1/g/aos_shihuang/tools/kraken2-standard-db/kraken_database/taxonomy"
echo

echo "[5] Indexes  (stage 1 BUILDS these; present = will be reused/overwritten)"
opt_k2    "Kraken2 human-only  [DEFAULT]" "$KRAKEN2_DB_T2T_ONLY"
opt_bt2   "Bowtie2 T2T+HLA"         "$BOWTIE2_INDEX"
opt_file  "minimap2 index"          "$MINIMAP2_INDEX"
opt_file  "sylph database"          "$SYLPH_DB"
opt_k2    "Kraken2 mixed [ablation only]" "$KRAKEN2_DB_MIXED"
echo

echo "[6] Comparator databases  (NOT built by stage 1 - install separately)"
need_bt2  "KneadData hg39_T2T"      "$KNEADDATA_DB"
opt_bt2   "Hostile human-t2t-hla"   "$HOSTILE_INDEX"
echo

echo "[7] Scratch and output space"
need_dir  "scratch root"            "$SCRATCH_DIR"
[ -w "$SCRATCH_DIR" ] && ok "scratch is writable" || bad "scratch NOT writable" "$SCRATCH_DIR"
opt_dir   "simulated data (stage 2 creates)" "$DATA_DIR"
need_dir  "SLURM log destination"   "$HOME"
avail=$(df -Pk "$SCRATCH_DIR" 2>/dev/null | awk 'NR==2{print int($4/1048576)}')
if [ -n "$avail" ]; then
    [ "$avail" -ge 500 ] && ok "free space on scratch: ${avail} GB (need ~500)" \
                         || warn "free space on scratch: ${avail} GB" "a full rerun needs ~500 GB"
fi
echo

echo "[8] Stage-6 accuracy scripts"
need_file "compute_accuracy_all.py"              "$REPO_DIR/scripts/benchmark/compute_accuracy_all.py"
need_file "compute_accuracy_bowtie2_recheck_v2.py" "$REPO_DIR/scripts/benchmark/compute_accuracy_bowtie2_recheck_v2.py"
need_file "compare_k2_index_ablation.py"         "$REPO_DIR/scripts/benchmark/compare_k2_index_ablation.py"
echo

echo "-------------------------------------------------------------"
if [ "$FAIL" -gt 0 ]; then
    echo "  $FAIL required item(s) missing, $WARN warning(s). Fix the MISS lines first."
    exit 1
fi
echo "  All required items present ($WARN warning(s))."
note "WARN on an index under [5] just means stage 1 will build it."
note "WARN on the mixed Kraken2 db only disables the stage-4 ablation."
echo "  Next:  bash scripts/run_all.sh --dry-run"
exit 0
