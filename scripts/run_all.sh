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
#   bash scripts/run_all.sh --from 4 --after 3975213:3975210 \
#       --after-runs 3975214:3975215:3975216
#                                        # resume: --after is what every stage
#                                        # needs (data, indexes); --after-runs is
#                                        # extra prerequisites for stage 6 only
#
# Each array task counts against the cluster's MaxSubmitJobPerUser limit, and
# the full panel exceeds it. Submission therefore blocks and retries until room
# appears, so run it detached:
#   nohup bash scripts/run_all.sh > logs/submit.log 2>&1 &
#
# See RUN_ALL.md for what each stage costs and produces.
# =============================================================================

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# Exported so each sbatch job can find config.sh; SLURM propagates the environment.
export REPO_DIR="$REPO"
source "$REPO/scripts/hpc/config.sh"

# A missing log directory makes SLURM fail each job at launch, with no log to
# say why. Create it before queueing anything.
if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
    echo "ERROR: cannot create the log directory: $LOG_DIR" >&2
    exit 1
fi

DRY_RUN=0
FROM_STAGE=0
AFTER_JOB=""
AFTER_RUNS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --from)    FROM_STAGE="$2"; shift 2 ;;
        --after)   AFTER_JOB="$2"; shift 2 ;;
        --after-runs) AFTER_RUNS="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 1 ;;
    esac
done

# Resuming past stage 2 skips the jobs the later stages depend on, so without an
# explicit --after they would be submitted with no dependency at all and start
# before the data exists. Refuse rather than launch them against missing input.
if [ "$FROM_STAGE" -gt 2 ] && [ -z "$AFTER_JOB" ] && [ "$DRY_RUN" -eq 0 ]; then
    if [ ! -d "$DATA_DIR" ] || [ -z "$(ls -A "$DATA_DIR" 2>/dev/null)" ]; then
        echo "ERROR: --from $FROM_STAGE skips the stages that build the indexes and data," >&2
        echo "       and $DATA_DIR is empty. Pass --after <jobid> to wait for the" >&2
        echo "       running data job, or wait for it to finish first." >&2
        exit 1
    fi
fi

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

    # The #SBATCH directives inside each script use a relative "logs/" path,
    # which only lands in the right place when sbatch is run from the repo root.
    # Passing the absolute path here overrides them, so run_all.sh works from
    # any directory. Array jobs keep the %A_%a pattern so tasks stay grouped.
    local pat="%x-%j"
    grep -qE '^#SBATCH[[:space:]]+(--array|-a)[= ]' "$REPO/$script" && pat="%x-%A_%a"
    local logflags="--output=$LOG_DIR/$pat.out --error=$LOG_DIR/$pat.err"

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "  [stage $stage] $label" >&2
        echo "      sbatch $depflag $logflags $script" >&2
        echo "DRYRUN$stage"
        return
    fi
    # Each array task counts against MaxSubmitJobPerUser, so a panel of this
    # size reaches the cap partway through and every later sbatch is refused.
    # Wait for room instead of dropping the rest of the plan on the floor.
    local jid="" out="" attempt=0
    while :; do
        if out=$(sbatch --parsable $depflag $logflags "$REPO/$script" 2>&1); then
            jid="${out%%;*}"
            break
        fi
        case "$out" in
            *QOSMaxSubmitJobPerUserLimit*|*AssocMaxSubmitJobLimit*|*"job submit limit"*)
                attempt=$((attempt + 1))
                if [ "$attempt" -eq 1 ]; then
                    echo "  [stage $stage] $label — queue is at the QOS submit limit;" >&2
                    echo "      retrying every ${SUBMIT_RETRY_SECONDS:-300}s until there is room" >&2
                fi
                if [ "$attempt" -gt "${SUBMIT_MAX_RETRIES:-288}" ]; then
                    echo "  [stage $stage] $label — GAVE UP after $attempt attempts" >&2
                    echo ""; return
                fi
                sleep "${SUBMIT_RETRY_SECONDS:-300}"
                ;;
            *)
                echo "  [stage $stage] $label — sbatch failed: $out" >&2
                echo ""; return
                ;;
        esac
    done
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
J_DATA=$(submit 2 "generate 18 simulated datasets (ISS, job array)" scripts/hpc/generate_data_slurm.sh)
echo >&2

# --- Stage 3: main comparisons ----------------------------------------------
DEP3="${AFTER_JOB:-}"
[ -n "${J_DATA:-}" ] && DEP3="${DEP3:+$DEP3:}$J_DATA"
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
# AFTER_JOB (indexes and data) applies to every stage. AFTER_RUNS names
# benchmark jobs submitted by an earlier invocation and applies to stage 6
# ALONE: putting them in AFTER_JOB would hold stages 4 and 5 behind benchmarks
# they do not need, which on the long 60M datasets costs hours.
ALL_RUNS=$(printf "%s\n" "$AFTER_JOB" "$AFTER_RUNS" "$J_KD" "$J_HOST" "$J_BASE" "$J_RECH" "$J_ABL" \
    | { grep -v '^$' || true; } | paste -sd: -)
submit 6 "accuracy, all tools"        scripts/benchmark/run_compute_accuracy.sh          "$ALL_RUNS" >/dev/null
submit 6 "accuracy, recheck arms"     scripts/benchmark/run_accuracy_bowtie2_recheck_v2.sh "$ALL_RUNS" >/dev/null
submit 6 "accuracy, index ablation"   scripts/benchmark/run_accuracy_k2_index_ablation.sh  "$ALL_RUNS" >/dev/null

# The resource summary reads output from every benchmark, including the three
# that ALL_RUNS leaves out, so it needs its own dependency list.
EVERY_RUN=$(printf "%s\n" "$AFTER_JOB" "$AFTER_RUNS" "$J_KD" "$J_HOST" "$J_BACK" "$J_BASE" "$J_RECH" \
    "$J_ABL" "$J_BOUND" "$J_PE" | { grep -v '^$' || true; } | paste -sd: -)
submit 6 "runtime and memory summary" scripts/benchmark/run_collect_resources.sh "$EVERY_RUN" >/dev/null
echo >&2

echo "Submitted. Watch with: squeue -u \$USER" >&2
echo >&2
echo "Runtime and peak memory land in $RUNS_DIR/summary/resources.csv once the" >&2
echo "last job finishes. To see partial results at any time, run:" >&2
echo "    python3 $REPO/scripts/main/collect_resources.py" >&2
