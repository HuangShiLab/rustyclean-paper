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

# When a reference is missing, look for it and print candidates rather than
# leaving the user to guess the path.
suggest() {
    local label="$1" pattern="$2"; shift 2
    local found=""
    for root in "$@"; do
        [ -d "$root" ] || continue
        found="$found$(find "$root" -maxdepth 4 -name "$pattern" -size +1M 2>/dev/null | head -4)
"
    done
    found=$(printf "%s" "$found" | grep -v '^$')
    if [ -n "$found" ]; then
        printf "       candidates for %s:\n" "$label"
        printf "%s\n" "$found" | sed 's/^/         /'
    else
        printf "       no candidate found for %s (searched: %s)\n" "$label" "$*"
    fi
}
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

# A proxy pointing at a loopback port is an SSH tunnel; if it is down, every
# conda or pip install fails with a ProxyError even though direct access works.
_pv="${https_proxy:-${http_proxy:-}}"
case "$_pv" in
    *127.0.0.1*|*localhost*)
        _pp=$(printf "%s" "$_pv" | sed 's#.*:##; s#/.*##')
        if ! timeout 3 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/$_pp" 2>/dev/null; then
            warn "proxy points at a dead tunnel" "127.0.0.1:$_pp — installs will fail"
            note "unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY"
        fi ;;
esac

echo "[3] Tools on PATH"
need_file "conda profile"           "$CONDA_BASE/etc/profile.d/conda.sh"

# Mirror the PATH the job scripts build, plus any env created under the project.
for _e in "$CONDA_BASE"/envs/*/bin "$PROJECT_DIR"/.conda_envs/*/bin; do
    [ -d "$_e" ] && PATH="$_e:$PATH"
done
export PATH

MISSING_PKGS=""
# executable -> conda package, since several differ (art_illumina is "art",
# and the *-build tools ship with their parent package)
pkg_for() {
    case "$1" in
        art_illumina)              echo art ;;
        kraken2|kraken2-build)     echo kraken2 ;;
        bowtie2|bowtie2-build)     echo bowtie2 ;;
        centrifuge|centrifuge-build) echo centrifuge ;;
        python3)                   echo python ;;
        *)                         echo "$1" ;;
    esac
}
have() {  # have <label> <exe> <required|optional> [why]
    if command -v "$2" >/dev/null 2>&1; then ok "$1 ($(command -v "$2"))"; return; fi
    if [ "$3" = "required" ]; then bad "$1" "$2 not on PATH${4:+ — $4}"
    else warn "$1" "$2 not on PATH${4:+ — $4}"; fi
    local pkg; pkg=$(pkg_for "$2")
    case " $MISSING_PKGS " in *" $pkg "*) ;; *) MISSING_PKGS="$MISSING_PKGS $pkg" ;; esac
}
have "fastp"          fastp            required "quality control"
have "kraken2"        kraken2          required "classification path"
have "kraken2-build"  kraken2-build    required "stage 1 index build"
have "bowtie2"        bowtie2          required "alignment path and the survey"
have "bowtie2-build"  bowtie2-build    required "stage 1 index build"
have "samtools"       samtools         required "alignment output handling"
have "seqtk"          seqtk            required "auto-mode subsampling"
have "InSilicoSeq"    iss              required "stage 2 read simulation (the driver uses ISS)"
have "art_illumina"   art_illumina     optional "only for the alternative ART generator"

# Stage 2 refuses to run unseeded, and an invalid model name fails all 18 array
# tasks at once. Both are one --help call away, so check rather than discover it
# after the jobs are queued.
if command -v iss >/dev/null 2>&1; then
    _iss_help=$(iss generate --help 2>&1 || true)
    if printf '%s' "$_iss_help" | grep -q -- '--seed'; then
        ok "ISS supports --seed (simulation is reproducible)"
    else
        bad "ISS has no --seed" "stage 2 will refuse to run; ISS_ALLOW_UNSEEDED=1 overrides"
    fi
    # --help does not reliably enumerate the built-in error models, so a
    # non-match here proves nothing and must not block a run. Measured directly
    # on this cluster: miseq 301 bp, novaseq 151 bp, hiseq 126 bp.
    if printf '%s' "$_iss_help" | grep -qi -- "${ISS_MODEL:-novaseq}"; then
        ok "ISS model '${ISS_MODEL:-novaseq}' listed in --help"
    else
        note "ISS model '${ISS_MODEL:-novaseq}' is not named in --help; that is expected,"
        note "the models are not enumerated there. Confirm the read length with:"
        note "  iss generate --genomes G --model ${ISS_MODEL:-novaseq} --n_reads 1000 --output /tmp/m --cpus 4"
    fi
fi
have "python3"        python3          required "accuracy and analysis"
have "KneadData"      kneaddata        required "comparator"
have "Hostile"        hostile          required "comparator"
have "minimap2"       minimap2         optional "minimap2 backend only"
have "sylph"          sylph            optional "sylph backend only"
have "centrifuge"     centrifuge       optional "centrifuge backend only"
have "centrifuge-build" centrifuge-build optional "centrifuge index build only"

if [ -n "$MISSING_PKGS" ]; then
    echo
    note "install what is missing into an environment on a filesystem with room:"
    echo
    echo "         conda create -p $PROJECT_DIR/.conda_envs/rustyclean-benchmark \\"
    echo "             -c conda-forge -c bioconda -y$MISSING_PKGS"
    echo
    note "do NOT install into the base env: /group is at 100% of its quota,"
    note "which is why 'mamba install' fails with Permission denied."
    note "activate_conda puts \$PROJECT_DIR/.conda_envs/*/bin on PATH automatically."
fi
echo

echo "[4] Reference FASTAs  (inputs to stage 1)"
if [ -f "$T2T_FASTA" ]; then ok "T2T-CHM13v2.0 (depletion reference)"; else
    bad "T2T-CHM13v2.0 (depletion reference)" "$T2T_FASTA"
    suggest "T2T" "*T2T-CHM13*genomic.fna*" "$DB_ROOT" /lustre1/g/aos_shihuang
    suggest "T2T (alt naming)" "*chm13*.fa*" "$DB_ROOT" /lustre1/g/aos_shihuang
fi
if [ -n "$HLA_FASTA" ] && [ -f "$HLA_FASTA" ]; then ok "IPD-IMGT/HLA (optional)"
else note "no IPD-IMGT/HLA: RustyClean indexes are built from T2T alone (Hostile's default adds HLA)"; fi
if [ -f "$AUX_FASTA" ]; then ok "reference for minimap2/sylph/centrifuge"; else bad "reference for minimap2/sylph/centrifuge" "$AUX_FASTA"; fi
if [ -f "$HUMAN_GENOME" ]; then ok "GRCh38 (host reads are SIMULATED from this)"; else
    bad "GRCh38 (host reads are SIMULATED from this)" "$HUMAN_GENOME"
    note "without it generate_enhanced_data.sh silently falls back to chr1 only"
    suggest "GRCh38" "*GRCh38*.fa*" "$DB_ROOT" /lustre1/g/aos_shihuang
    suggest "GRCh38 (RefSeq naming)" "GCF_000001405*genomic.fna*" "$DB_ROOT" /lustre1/g/aos_shihuang
fi
need_dir  "NCBI taxonomy (kraken2 + centrifuge)" "$SOURCE_TAXONOMY"

# The simulated communities are drawn from this collection; without it every
# stage-2 array task fails immediately.
_mg="${MICROBIAL_GENOME_DIR:-$GENOME_DIR/genomes_fasta}"
if [ -d "$_mg" ]; then
    _n=$(find "$_mg" -maxdepth 1 \( -name '*.fasta' -o -name '*.fa' -o -name '*.fna' \
            -o -name '*.fasta.gz' -o -name '*.fa.gz' -o -name '*.fna.gz' \) 2>/dev/null | wc -l)
    if   [ "$_n" -ge 100 ]; then ok "microbial genomes ($_n found)"
    elif [ "$_n" -gt 0 ];   then warn "microbial genomes: only $_n" "high-complexity sets need 100; fewer means genomes are reused and the community contains duplicates"
    else bad "microbial genomes: directory is empty" "$_mg"
    fi
else
    bad "microbial genome collection" "$_mg"
    note "stage 2 cannot build any community without it; set MICROBIAL_GENOME_DIR"
    for _c in "$DB_ROOT"/GTDB/*/[Gg]*reference_genome "$DB_ROOT"/kraken2/*/genomes "$DB_ROOT"/genomes; do
        [ -d "$_c" ] || continue
        _cn=$(find "$_c" -maxdepth 1 \( -name '*.fna*' -o -name '*.fa*' \) 2>/dev/null | wc -l)
        [ "$_cn" -gt 10 ] && printf "         candidate: %-64s (%s genomes)\n" "$_c" "$_cn"
    done
fi
echo

# ISS throughput was measured at ~4386 reads/s with 16 cpus on this cluster. A
# stage-2 walltime under the largest dataset's estimate kills that task, and the
# afterok dependency then cancels every later stage, so check it here.
_gen="$REPO_DIR/scripts/hpc/generate_data_slurm.sh"
if [ -f "$_gen" ]; then
    _tl=$(grep -m1 -oE '^#SBATCH --time=[0-9:]+' "$_gen" | cut -d= -f2)
    _hours=$(printf '%s' "$_tl" | awk -F: '{print $1 + $2/60}')
    _maxreads=$(sed -n '/^DATASETS=(/,/^)/p' "$_gen" | grep -oE '"[^"]+"' | tr -d '"' \
                | cut -d: -f2 | sort -n | tail -1)
    _need=$(awk -v r="$_maxreads" 'BEGIN{printf "%.1f", r/4386/3600}')
    if awk -v h="$_hours" -v n="$_need" 'BEGIN{exit !(h > n * 1.5)}'; then
        ok "stage 2 walltime $_tl covers the largest dataset (~${_need} h)"
    else
        bad "stage 2 walltime $_tl is too tight" "largest dataset needs ~${_need} h at 16 cpus"
    fi
fi
echo

echo "[5] Indexes  (stage 1 BUILDS these)"
opt_k2    "Kraken2 human-only  [DEFAULT]" "$KRAKEN2_DB_T2T_ONLY"
opt_bt2   "Bowtie2 T2T-only"        "$BOWTIE2_INDEX"
opt_file  "minimap2 index"          "$MINIMAP2_INDEX"
opt_file  "sylph database"          "$SYLPH_DB"
opt_k2    "Kraken2 mixed [ablation only]" "$KRAKEN2_DB_MIXED"

# An index existing says nothing about which reference built it. Report the
# stamp so a stale index is visible here rather than silently reused.
provenance() {
    local label="$1" stamp="$2" src="$3"
    if index_up_to_date "$stamp" "$src"; then
        printf '       %-28s reuse (stamped: %s)\n' "$label" "$(basename "$src")"
    elif [ -f "$stamp" ]; then
        printf '       %-28s REBUILD (stamped from a different reference)\n' "$label"
    else
        printf '       %-28s REBUILD (no provenance stamp)\n' "$label"
    fi
}
echo "   stage 1 will:"
printf '       %-28s REBUILD (always: the builder wipes the db first)\n' "Kraken2 human-only"
provenance "Bowtie2 T2T-only"   "${BOWTIE2_INDEX}.source"     "$T2T_FASTA"
provenance "minimap2 index"     "${MINIMAP2_INDEX}.source"    "$AUX_FASTA"
provenance "sylph database"     "${SYLPH_DB}.source"          "$AUX_FASTA"
provenance "centrifuge index"   "${CENTRIFUGE_INDEX}.source"  "$AUX_FASTA"
note "an index is reused only when stamped as built from the reference above;"
note "set FORCE_REBUILD=1 to rebuild regardless."
echo

echo "[6] Comparator databases  (NOT built by stage 1 - install separately)"
need_bt2  "KneadData hg39_T2T"      "$KNEADDATA_DB"
opt_bt2   "Hostile human-t2t-hla"   "$HOSTILE_INDEX"
echo

echo "[7] Output locations and space"
printf "       simulated reads -> %s\n" "$DATA_DIR"
printf "       run outputs     -> %s\n" "$RUNS_DIR"
for pair in "SCRATCH_DIR:$SCRATCH_DIR" "RUNS_DIR:$RUNS_DIR"; do
    lbl="${pair%%:*}"; dir="${pair#*:}"
    parent="$dir"; while [ ! -d "$parent" ] && [ "$parent" != "/" ]; do parent=$(dirname "$parent"); done
    if [ -w "$parent" ]; then ok "$lbl writable ($parent)"; else bad "$lbl NOT writable" "$parent"; fi
done
# SLURM writes the .out/.err file at job launch. If the directory is missing the
# job dies immediately and the reason has nowhere to be recorded, so this is
# checked rather than left to fail silently across a whole array.
if [ -d "$LOG_DIR" ] && [ -w "$LOG_DIR" ]; then
    ok "SLURM log directory ($LOG_DIR)"
elif [ -d "$LOG_DIR" ]; then
    bad "SLURM log directory NOT writable" "$LOG_DIR"
else
    bad "SLURM log directory missing" "mkdir -p $LOG_DIR"
fi

# Space is what matters, wherever the two trees actually live.
space_for() {
    local lbl="$1" dir="$2" need="$3"
    local parent="$dir"; while [ ! -d "$parent" ] && [ "$parent" != "/" ]; do parent=$(dirname "$parent"); done
    local avail; avail=$(df -Pk "$parent" 2>/dev/null | awk 'NR==2{print int($4/1048576)}')
    [ -z "$avail" ] && { warn "$lbl free space unknown" "$parent"; return; }
    if   [ "$avail" -ge "$need" ]; then ok   "$lbl free: ${avail} GB on $(df -Pk "$parent" | awk 'NR==2{print $6}') (need ~${need})"
    elif [ "$avail" -ge $((need/3)) ]; then warn "$lbl free: ${avail} GB" "need ~${need} GB; trim the panel or set the dir elsewhere"
    else                                bad  "$lbl free: ${avail} GB" "need ~${need} GB; see RUN_ALL.md"
    fi
}
# reads ~65 GB, outputs ~200 GB; if both land on one filesystem df reports it once
space_for "reads   " "$DATA_DIR" 80
space_for "outputs " "$RUNS_DIR" 250
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
