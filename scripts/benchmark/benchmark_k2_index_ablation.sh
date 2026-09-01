#!/bin/bash
#SBATCH --job-name=rc_k2_index_ablation
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=128G
#SBATCH --time=24:00:00
#SBATCH --output=/home/%u/rc_k2_index_ablation_%j.out
#SBATCH --error=/home/%u/rc_k2_index_ablation_%j.err

# =============================================================================
# Kraken2 index ablation: mixed database vs human-only database
# =============================================================================
# Single-variable comparison against the existing bowtie2-recheck results.
#
#   arm A (already measured) : kraken16  -- mixed: bacteria/archaea/viral/human
#                              data/benchmark_results/{accuracy,performance}_bowtie2_recheck.csv
#   arm B (this script)      : t2t_only  -- human-only, T2T-CHM13v2.0
#
# EVERYTHING ELSE IS HELD IDENTICAL to benchmark_bowtie2_recheck_v2.sh:
# same datasets, same host index (hg_39), same flags, same thread count, 3 reps.
# Only --kraken2-db changes, so any difference is attributable to the index.
#
# Motivation: Kraken2 assigns the LCA of a read's k-mer hits. With a mixed
# database a host read sharing k-mers with other taxa is assigned to an ancestor
# of Homo sapiens rather than to 9606 itself. Arm A measured 1.41% host
# carry-over; this quantifies how much of that is the index rather than the
# method.
# =============================================================================

set -e
source ~/.cargo/env 2>/dev/null || true
source /group/aos_shihuang/conda/etc/profile.d/conda.sh
conda activate /lustre1/g/aos_shihuang/rustyclean-paper/.conda_envs/rustyclean-benchmark

export PATH="/group/aos_shihuang/conda/envs/fastp/bin:/group/aos_shihuang/conda/envs/bowtie2/bin:/group/aos_shihuang/conda/envs/kraken2/bin:/lustre1/g/aos_shihuang/tools/samtools/samtools-1.21:${PATH}"

RC=/lustre1/g/aos_shihuang/rustyclean/target/release/rustyclean
PROJECT=/lustre1/g/aos_shihuang/rustyclean-paper/k2_index_ablation
DATA=${SCRATCH_DIR:-/scr/u/$USER/rustyclean-paper}/data/enhanced
OUT=$PROJECT/results
METRICS=$PROJECT/metrics/performance_k2_mixed.csv

# --- the only variable under test -------------------------------------------
KRAKEN_DB_SRC="${KRAKEN2_DB_MIXED:-/lustre1/g/aos_shihuang/databases/kraken2/kraken16}"
# --- held identical to the kraken16 arm -------------------------------------
HOST_INDEX="${BOWTIE2_INDEX:-/lustre1/g/aos_shihuang/databases/rustyclean_human_t2t_only/bowtie2/t2t_hla}"
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
    "100M_50pct_high_lognormal_SE"
    "100M_90pct_high_lognormal_SE"
)

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
        echo "=== $dataset rep $rep (t2t_only) ===" | tee -a "$log"
        /usr/bin/time -v "$RC" \
            --r1 "$R1" \
            --host-removal-mode auto \
            --kraken2-db "$KRAKEN_DB" \
            --host-index "$HOST_INDEX" \
            --auto-survey \
            --bowtie2-recheck "$HOST_INDEX" \
            --kraken2-memory-mapping \
            --checkpoint-dir "$ds_out/.checkpoints" \
            -o "$ds_out" \
            -t "$THREADS" \
            --clean \
            > "$log" 2> "$time_log"
        rt=$(awk -F": " '/Elapsed \(wall clock\) time/ {print $NF}' "$time_log"); [ -z "$rt" ] && rt="0:0"
        mem=$(awk '/Maximum resident set size/ {print $NF}' "$time_log"); [ -z "$mem" ] && mem="0"
        printf "rustyclean_k2_mixed,%s,%s,%s,%s,%s\n" \
            "$dataset" "$rep" "$(parse_time "$rt")" "$mem" "$(date -Iseconds)" >> "$METRICS"
        echo "  runtime=$(parse_time "$rt")s memory=${mem}kb" | tee -a "$log"
    done
done

echo
echo "Ablation arm B complete. Metrics: $METRICS"
echo "Next: compute accuracy with"
echo "  sbatch scripts/benchmark/run_accuracy_k2_index_ablation.sh"
