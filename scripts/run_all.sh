#!/bin/bash
# =============================================================================
# RustyClean benchmark — full rerun driver
# =============================================================================
# Submits every stage of a from-scratch rerun in dependency order, so each stage
# starts only after the one it needs has succeeded. Nothing runs on the login
# node; every stage is a SLURM job.
#
#   bash scripts/run_all.sh              # submit everything
#   bash scripts/run_all.sh --dry-run    # print the plan without submitting
#   bash scripts/run_all.sh --from 3     # resume from stage 3
#
# See RUN_ALL.md for what each stage costs and produces.
# =============================================================================

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# Exported so each sbatch job can find config.sh; SLURM propagates the environment.
export REPO_DIR="$REPO"
source "$REPO/scripts/hpc/config.sh"

DRY_RUN=0
FROM_STAGE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --from)    FROM_STAGE="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 1 ;;
    esac
done

# submit <stage> <label> <script> [dependency_job_id]
# Echoes the job id so later stages can depend on it.
submit() {
    local stage="$1" label="$2" script="$3" dep="${4:-}"
    if [ "$stage" -lt "$FROM_STAGE" ]; then
        echo "  [stage $stage] $label — SKIPPED (--from $FROM_STAGE)" >&2
        echo ""
        return
    fi
    if [ ! -f "$REPO/$script" ]; then
        echo "  [stage $stage] $label — MISSING SCRIPT: $script" >&2
        echo ""
        return
    fi
    local depflag=""
    [ -n "$dep" ] && depflag="--dependency=afterok:$dep"
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "  [stage $stage] $label" >&2
        echo "      sbatch $depflag $script" >&2
        echo "DRYRUN$stage"
        return
    fi
    local jid
    jid=$(sbatch --parsable $depflag "$REPO/$script")
    echo "  [stage $stage] $label -> job $jid${dep:+ (after $dep)}" >&2
    echo "$jid"
}

echo "RustyClean full rerun" >&2
echo "  repo      : $REPO" >&2
echo "  databases : $DB_ROOT" >&2
echo "  data      : $DATA_DIR" >&2
echo "  results   : $RESULTS_DIR" >&2
echo >&2

# --- Stage 1: references and indexes ----------------------------------------
echo "Stage 1 — references and indexes" >&2
J_K2=$(submit   1 "Kraken2 human-only index"        scripts/main/build_kraken2_t2t_only.sh)
J_BT2=$(submit  1 "Bowtie2 T2T-only index"          scripts/main/build_bowtie2_t2t_only.sh)
J_AUX=$(submit  1 "minimap2 / sylph / centrifuge"   scripts/main/build_aux_indexes.sh)
echo >&2

# --- Stage 2: simulated data -------------------------------------------------
# Host reads are simulated from GRCh38 while depletion runs against T2T, so the
# benchmark measures real assembly divergence rather than a self-match.
echo "Stage 2 — simulated datasets" >&2
J_DATA=$(submit 2 "generate 19 simulated datasets" scripts/hpc/generate_data_sequential_slurm.sh)
echo >&2

# --- Stage 3: main comparisons ----------------------------------------------
DEP3="${J_DATA:+$J_DATA}"
[ -n "${J_K2:-}" ] && DEP3="${DEP3:+$DEP3:}$J_K2"
echo "Stage 3 — main comparisons" >&2
J_KD=$(submit    3 "RustyClean auto vs KneadData"   scripts/benchmark/run_benchmark.sh "$DEP3")
J_HOST=$(submit  3 "RustyClean --skip-qc vs Hostile" scripts/benchmark/fair_hostile_skipqc_run_benchmark.sh "$DEP3")
J_BACK=$(submit  3 "backend comparison"             scripts/main/benchmark_backend_runtime.sh "$DEP3")
echo >&2

# --- Stage 4: verification pass and index ablation ---------------------------
echo "Stage 4 — verification pass and index ablation" >&2
J_BASE=$(submit  4 "Kraken2 baseline (no recheck)"  scripts/benchmark/benchmark_baseline_kraken2_memmap.sh "$DEP3")
J_RECH=$(submit  4 "Kraken2 + Bowtie2 recheck"      scripts/benchmark/benchmark_bowtie2_recheck_v2.sh "$DEP3")
J_ABL=$(submit   4 "index ablation (human-only)"    scripts/benchmark/benchmark_k2_index_ablation.sh "$DEP3")
echo >&2

# --- Stage 5: gaps the published results never covered -----------------------
echo "Stage 5 — previously unmeasured" >&2
J_BOUND=$(submit 5 "auto decision boundary"         scripts/main/benchmark_auto_decision_boundary.sh "$DEP3")
J_PE=$(submit    5 "paired-end panel"               scripts/main/benchmark_t2t_only_pe_panel.sh "$DEP3")
echo >&2

# --- Stage 6: accuracy -------------------------------------------------------
echo "Stage 6 — accuracy" >&2
ALL_RUNS=$(printf "%s\n" "$J_KD" "$J_HOST" "$J_BASE" "$J_RECH" "$J_ABL" \
    | { grep -v '^$' || true; } | paste -sd: -)
submit 6 "accuracy, all tools"        scripts/benchmark/run_compute_accuracy.sh          "$ALL_RUNS" >/dev/null
submit 6 "accuracy, recheck arms"     scripts/benchmark/run_accuracy_bowtie2_recheck_v2.sh "$ALL_RUNS" >/dev/null
submit 6 "accuracy, index ablation"   scripts/benchmark/run_accuracy_k2_index_ablation.sh  "$ALL_RUNS" >/dev/null
echo >&2

echo "Submitted. Watch with: squeue -u \$USER" >&2
echo "Then collect results with the analysis scripts listed in RUN_ALL.md." >&2
