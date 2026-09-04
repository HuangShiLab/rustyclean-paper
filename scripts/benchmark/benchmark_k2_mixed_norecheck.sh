#!/bin/bash
#SBATCH --job-name=rc_k2_mixed_norecheck
#SBATCH --array=0-4
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=128G
#SBATCH --time=24:00:00
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err

# =============================================================================
# Mixed Kraken2 library, verification pass OFF
# =============================================================================
# The configuration the recheck pass was originally added to compensate for:
# host removal against the mixed multi-taxon library kraken16, with nothing
# after it. It is the reference the rewritten pass has to beat -- if the pass
# now costs runtime without improving on this, it is not worth keeping.
#
# Only --kraken2-db and the presence of --bowtie2-recheck differ from the other
# arms, so any difference is attributable to those two choices.
# =============================================================================

set -e

# Each dataset runs as its own SLURM array task, so they execute concurrently on
# different nodes instead of one after another inside a single job. Metrics go
# to a per-task file because concurrent appends to one CSV interleave; the
# stage-6 collector merges them. Running this script directly, with no array,
# processes the whole list and writes the unsuffixed file, as before.
ARRAY_TAG=""
[ -n "${SLURM_ARRAY_TASK_ID:-}" ] && ARRAY_TAG=".task${SLURM_ARRAY_TASK_ID}"

source ~/.cargo/env 2>/dev/null || true
source /group/aos_shihuang/conda/etc/profile.d/conda.sh
conda activate /lustre1/g/aos_shihuang/rustyclean-paper/.conda_envs/rustyclean-benchmark

export PATH="/group/aos_shihuang/conda/envs/fastp/bin:/group/aos_shihuang/conda/envs/bowtie2/bin:/group/aos_shihuang/conda/envs/kraken2/bin:/lustre1/g/aos_shihuang/tools/samtools/samtools-1.21:${PATH}"

RC=/lustre1/g/aos_shihuang/rustyclean/target/release/rustyclean
PROJECT="${RUNS_DIR:-/lustre1/g/aos_shihuang/rustyclean-paper/runs}/k2_mixed_norecheck"
DATA=${SCRATCH_DIR:-/scr/u/$USER/rustyclean-paper}/data/enhanced
OUT=$PROJECT/results
METRICS=$PROJECT/metrics/performance_k2_mixed_norecheck${ARRAY_TAG}.csv

# --- the only variable under test -------------------------------------------
KRAKEN_DB_SRC="${KRAKEN2_DB_MIXED:-/lustre1/g/aos_shihuang/databases/kraken2/kraken16}"
# --- held identical to the kraken16 arm -------------------------------------
HOST_INDEX="${BOWTIE2_INDEX:?BOWTIE2_INDEX is not set; source scripts/hpc/config.sh}"
THREADS=8
REPS=3

mkdir -p "$OUT" "$(dirname "$METRICS")"

if [ ! -f "$KRAKEN_DB_SRC/hash.k2d" ]; then
    echo "ERROR: Kraken2 database not found at $KRAKEN_DB_SRC" >&2
    exit 1
fi

# Stage the database on node-local storage: mmap over Lustre is pathologically
# slow because every page fault is a network round trip.
KRAKEN_DB="/tmp/k2_mixed_$$"
echo "Staging mixed Kraken2 DB to node-local storage: $KRAKEN_DB"
mkdir -p "$KRAKEN_DB"
start_copy=$(date +%s)
for f in hash.k2d opts.k2d taxo.k2d seqid2taxid.map names.dmp nodes.dmp ktaxonomy.tsv; do
    [ -f "$KRAKEN_DB_SRC/$f" ] && cp "$KRAKEN_DB_SRC/$f" "$KRAKEN_DB/"
done
# nodes.dmp / seqid2taxid.map are what let RustyClean resolve ancestor taxa of
# the host; warn loudly if the database does not ship them.
for f in nodes.dmp seqid2taxid.map; do
    [ -f "$KRAKEN_DB/$f" ] || echo "WARNING: $f absent - host detection will fall back to an exact taxid match"
done
echo "DB staged in $(( $(date +%s) - start_copy ))s"
ls -lh "$KRAKEN_DB"

cleanup_db() { rm -rf "$KRAKEN_DB"; echo "Cleaned up $KRAKEN_DB"; }
trap cleanup_db EXIT

DATASETS=(
    "30M_50pct_high_skewed_SE"
    "60M_90pct_high_lognormal_SE"
    "60M_99pct_med_lognormal_SE"
    "100M_50pct_high_lognormal_SE"
    "100M_90pct_high_lognormal_SE"
)

if [ -n "${SLURM_ARRAY_TASK_ID:-}" ]; then
    if [ "$SLURM_ARRAY_TASK_ID" -ge "${#DATASETS[@]}" ]; then
        echo "array task $SLURM_ARRAY_TASK_ID is past the end of ${#DATASETS[@]} datasets; nothing to do"
        exit 0
    fi
    DATASETS=( "${DATASETS[$SLURM_ARRAY_TASK_ID]}" )
    echo "array task $SLURM_ARRAY_TASK_ID -> ${DATASETS[0]}"
fi

parse_time() {
    local t="$1" s=0
    if [[ "$t" == *:* ]]; then
        local n; n=$(echo "$t" | awk -F: '{print NF}')
        if [ "$n" -eq 2 ]; then s=$(echo "$t" | awk -F: '{print ($1*60)+$2}')
        elif [ "$n" -eq 3 ]; then s=$(echo "$t" | awk -F: '{print ($1*3600)+($2*60)+$3}'); fi
    else s="$t"; fi
    printf "%.2f" "$s"
}

printf "tool,dataset,rep,runtime_seconds,max_memory_kb,timestamp\n" > "$METRICS"

for dataset in "${DATASETS[@]}"; do
    R1="$DATA/$dataset/reads.fastq.gz"
    if [ ! -f "$R1" ]; then
        echo "WARNING: $R1 not found, skipping $dataset"
        continue
    fi
    for rep in $(seq 1 $REPS); do
        ds_out="$OUT/$dataset/rep_$rep"
        rm -rf "$ds_out"; mkdir -p "$ds_out"
        log="$ds_out/run.log"; time_log="$ds_out/time.log"
        echo "=== $dataset rep $rep (mixed, no recheck) ===" | tee -a "$log"
        /usr/bin/time -v "$RC" \
            --r1 "$R1" \
            --host-removal-mode auto \
            --kraken2-db "$KRAKEN_DB" \
            --host-index "$HOST_INDEX" \
            --auto-survey \
            --kraken2-memory-mapping \
            --checkpoint-dir "$ds_out/.checkpoints" \
            -o "$ds_out" \
            -t "$THREADS" \
            --clean \
            > "$log" 2> "$time_log"
        rt=$(awk -F": " '/Elapsed \(wall clock\) time/ {print $NF}' "$time_log"); [ -z "$rt" ] && rt="0:0"
        mem=$(awk '/Maximum resident set size/ {print $NF}' "$time_log"); [ -z "$mem" ] && mem="0"
        printf "rustyclean_k2_mixed_norecheck,%s,%s,%s,%s,%s\n" \
            "$dataset" "$rep" "$(parse_time "$rt")" "$mem" "$(date -Iseconds)" >> "$METRICS"
        echo "  runtime=$(parse_time "$rt")s memory=${mem}kb" | tee -a "$log"
    done
done

echo
echo "Ablation arm B complete. Metrics: $METRICS"
echo "Next: compute accuracy with"
echo "  sbatch scripts/benchmark/run_accuracy_k2_mixed_norecheck.sh"
