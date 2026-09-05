#!/bin/bash
# =============================================================================
# Parallel-scaling experiment — submit both stages in order
# =============================================================================
#   bash scripts/run_parallel_scaling.sh              # simulate, then benchmark
#   bash scripts/run_parallel_scaling.sh --dry-run    # print the plan only
#   bash scripts/run_parallel_scaling.sh --from 2     # data already simulated
#   bash scripts/run_parallel_scaling.sh --from 2 --after 4012345
#
# Stage 1  generate_parallel_data.sh      20 array tasks, ~1 h each
#          120 samples x 1,000,000 reads at 1/5/10/50/70/90 % host, ~12 GB
# Stage 2  benchmark_parallel_scaling.sh   5 array tasks, up to ~8 h each
#          five arms per task at W = 1, 2, 4, 8, 16 workers on 16 cores
#
# 25 array tasks in total, inside this cluster's MaxSubmitJobPerUser of 50, so
# this can run alongside a normal panel. It still retries on the submit limit,
# because whatever else is queued counts too.
#
# Separate from run_all.sh on purpose: this panel answers a throughput question
# and has its own data, so folding it into the accuracy rerun would couple two
# experiments that fail for unrelated reasons.
# =============================================================================

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
export REPO_DIR="$REPO"
source "$REPO/scripts/hpc/config.sh"

DRY_RUN=0
FROM_STAGE=0
AFTER_JOB=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --from)    FROM_STAGE="$2"; shift 2 ;;
        --after)   AFTER_JOB="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 1 ;;
    esac
done

mkdir -p "$LOG_DIR" || { echo "ERROR: cannot create $LOG_DIR" >&2; exit 1; }

# A dependency on a job SLURM has already purged is refused with an opaque
# "Job dependency problem", so check the id before building a plan around it.
if [ -n "$AFTER_JOB" ] && [ "$DRY_RUN" -eq 0 ] && command -v sacct >/dev/null 2>&1; then
    for _j in ${AFTER_JOB//:/ }; do
        sacct -n -j "${_j%%_*}" --format=JobID 2>/dev/null | grep -q . || {
            echo "ERROR: --after names job $_j, which SLURM no longer knows." >&2
            echo "       If its output is already on disk, drop --after." >&2
            exit 1; }
    done
fi

submit() {
    local stage="$1" label="$2" script="$3" dep="${4:-}"
    if [ "$stage" -lt "$FROM_STAGE" ]; then
        echo "  [stage $stage] $label — SKIPPED (--from $FROM_STAGE)" >&2
        echo ""; return
    fi
    [ -f "$REPO/$script" ] || { echo "  [stage $stage] MISSING: $script" >&2; echo ""; return; }

    local depflag=""
    [ -n "$dep" ] && depflag="--dependency=afterok:$dep"
    # The #SBATCH directives use a relative "logs/" path, which only lands in the
    # right place when sbatch runs from the repository root. Passing the absolute
    # path overrides them so this works from any directory.
    local pat="%x-%j"
    grep -qE '^#SBATCH[[:space:]]+(--array|-a)[= ]' "$REPO/$script" && pat="%x-%A_%a"
    local logflags="--output=$LOG_DIR/$pat.out --error=$LOG_DIR/$pat.err"

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "  [stage $stage] $label" >&2
        echo "      sbatch $depflag $logflags $script" >&2
        echo "DRYRUN$stage"; return
    fi

    local jid="" out="" attempt=0
    while :; do
        if out=$(sbatch --parsable $depflag $logflags "$REPO/$script" 2>&1); then
            jid="${out%%;*}"; break
        fi
        case "$out" in
            *QOSMaxSubmitJobPerUserLimit*|*AssocMaxSubmitJobLimit*|*"job submit limit"*)
                attempt=$((attempt + 1))
                [ "$attempt" -eq 1 ] && echo "  [stage $stage] at the QOS submit limit; retrying every ${SUBMIT_RETRY_SECONDS:-300}s" >&2
                if [ "$attempt" -gt "${SUBMIT_MAX_RETRIES:-288}" ]; then
                    echo "  [stage $stage] $label — GAVE UP after $attempt attempts" >&2
                    echo ""; return
                fi
                sleep "${SUBMIT_RETRY_SECONDS:-300}" ;;
            *)  echo "  [stage $stage] $label — sbatch failed: $out" >&2; echo ""; return ;;
        esac
    done
    echo "  [stage $stage] $label -> job $jid${dep:+ (after $dep)}" >&2
    echo "$jid"
}

echo "RustyClean parallel-scaling experiment" >&2
echo "  repo    : $REPO" >&2
echo "  data    : $PARALLEL_DATA_DIR" >&2
echo "  runs    : $PARALLEL_RUNS_DIR" >&2
echo "  panel   : $(wc -w <<< "$PARALLEL_HOST_PCTS") host fractions x $PARALLEL_N_REPS replicates" >&2
echo "            = $(( $(wc -w <<< "$PARALLEL_HOST_PCTS") * PARALLEL_N_REPS )) samples of $PARALLEL_READS_PER_SAMPLE reads" >&2
echo >&2

# Stage 1 also needs the Bowtie2 index the benchmark aligns against. It is built
# by run_all.sh stage 1; refuse rather than queue five benchmark tasks that will
# each discover the missing index an hour into their allocation.
if [ "$FROM_STAGE" -le 2 ] && [ "$DRY_RUN" -eq 0 ]; then
    if [ ! -e "${BOWTIE2_INDEX}.1.bt2" ] && [ ! -e "${BOWTIE2_INDEX}.1.bt2l" ]; then
        echo "ERROR: no Bowtie2 index at $BOWTIE2_INDEX" >&2
        echo "       Build it first:  sbatch scripts/main/build_bowtie2_t2t_only.sh" >&2
        exit 1
    fi
fi

echo "Stage 1 — simulate the 120-sample panel" >&2
J_GEN=$(submit 1 "generate parallel panel (ISS, 20 array tasks)" \
        scripts/main/generate_parallel_data.sh)
echo >&2

DEP2="${AFTER_JOB:-}"
[ -n "${J_GEN:-}" ] && DEP2="${DEP2:+$DEP2:}$J_GEN"

echo "Stage 2 — scaling benchmark" >&2
J_BENCH=$(submit 2 "parallel scaling, W = 1 2 4 8 16 (5 array tasks)" \
          scripts/main/benchmark_parallel_scaling.sh "$DEP2")
echo >&2

echo "Submitted." >&2
echo >&2
echo "Watch:      squeue -u \$USER" >&2
echo "Analyse:    python3 scripts/main/analyze_parallel_scaling.py" >&2
echo "            (source scripts/hpc/config.sh first, or pass --runs $PARALLEL_RUNS_DIR)" >&2
if [ "$DRY_RUN" -eq 0 ] && [ -n "${J_BENCH:-}" ]; then
    echo >&2
    echo "Before trusting a 24-hour array, prove the wiring on six samples:" >&2
    echo "  PARALLEL_DRY_RUN=1 bash scripts/main/benchmark_parallel_scaling.sh" >&2
    echo "  PARALLEL_LIMIT=6 sbatch --array=2 scripts/main/benchmark_parallel_scaling.sh" >&2
fi
