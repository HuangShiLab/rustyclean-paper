#!/bin/bash
#SBATCH --job-name=rc_baseline_k2
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=128G
#SBATCH --time=24:00:00
#SBATCH --output=/home/%u/rc_baseline_k2_%j.out
#SBATCH --error=/home/%u/rc_baseline_k2_%j.err

set -e
source ~/.cargo/env 2>/dev/null || true
source /group/aos_shihuang/conda/etc/profile.d/conda.sh
conda activate /lustre1/g/aos_shihuang/rustyclean-paper/.conda_envs/rustyclean-benchmark

export PATH="/group/aos_shihuang/conda/envs/fastp/bin:/group/aos_shihuang/conda/envs/bowtie2/bin:/group/aos_shihuang/conda/envs/kraken2/bin:/lustre1/g/aos_shihuang/tools/samtools/samtools-1.21:${PATH}"

RC=/lustre1/g/aos_shihuang/rustyclean/target/release/rustyclean
PROJECT=/lustre1/g/aos_shihuang/rustyclean-paper/baseline_kraken2_memmap
DATA=${SCRATCH_DIR:-/scr/u/$USER/rustyclean-paper}/data/enhanced
OUT=$PROJECT/results
METRICS=$PROJECT/metrics/performance_baseline_kraken2_memmap.csv
KRAKEN_DB_SRC="${KRAKEN2_DB:-/lustre1/g/aos_shihuang/databases/rustyclean_human_t2t_only/kraken2/t2t_only}"
HOST_INDEX="${BOWTIE2_INDEX:-/lustre1/g/aos_shihuang/databases/rustyclean_human_t2t_only/bowtie2/t2t_hla}"

mkdir -p "$OUT"
mkdir -p "$(dirname "$METRICS")"

# Copy essential Kraken2 DB files to node-local /tmp
KRAKEN_DB="/tmp/kraken16_$$"
echo "Copying essential Kraken2 DB files to node-local storage: $KRAKEN_DB ..."
mkdir -p "$KRAKEN_DB"
start_copy=$(date +%s)
for f in hash.k2d opts.k2d taxo.k2d seqid2taxid.map names.dmp nodes.dmp ktaxonomy.tsv; do
    if [ -f "$KRAKEN_DB_SRC/$f" ]; then
        cp "$KRAKEN_DB_SRC/$f" "$KRAKEN_DB/"
    fi
done
end_copy=$(date +%s)
echo "DB copy complete in $((end_copy - start_copy))s"
ls -lh "$KRAKEN_DB"

cleanup_db() {
    rm -rf "$KRAKEN_DB"
    echo "Cleaned up node-local DB: $KRAKEN_DB"
}
trap cleanup_db EXIT

DATASETS=(
    "30M_50pct_high_skewed_SE"
    "60M_90pct_high_lognormal_SE"
    "100M_50pct_high_lognormal_SE"
    "100M_90pct_high_lognormal_SE"
)

parse_time() {
    local t="$1"
    local s=0
    if [[ "$t" == *:* ]]; then
        local n
        n=$(echo "$t" | awk -F: '{print NF}')
        if [ "$n" -eq 2 ]; then
            s=$(echo "$t" | awk -F: '{print ($1*60)+$2}')
        elif [ "$n" -eq 3 ]; then
            s=$(echo "$t" | awk -F: '{print ($1*3600)+($2*60)+$3}')
        fi
    else
        s="$t"
    fi
    printf "%.2f" "$s"
}

printf "tool,dataset,rep,runtime_seconds,max_memory_kb,timestamp\n" > "$METRICS"

for dataset in "${DATASETS[@]}"; do
    R1="$DATA/$dataset/reads.fastq.gz"
    if [ ! -f "$R1" ]; then
        echo "WARNING: $R1 not found, skipping $dataset"
        continue
    fi
    for rep in 1 2 3; do
        ds_out="$OUT/$dataset/rep_$rep"
        rm -rf "$ds_out"
        mkdir -p "$ds_out"
        log="$ds_out/run.log"
        time_log="$ds_out/time.log"
        echo "=== $dataset rep $rep ===" | tee -a "$log"
        /usr/bin/time -v "$RC" \
            --r1 "$R1" \
            --host-removal-mode auto \
            --kraken2-db "$KRAKEN_DB" \
            --host-index "$HOST_INDEX" \
            --auto-survey \
            --kraken2-memory-mapping \
            --checkpoint-dir "$ds_out/.checkpoints" \
            -o "$ds_out" \
            -t 8 \
            --clean \
            > "$log" 2> "$time_log"
        rt=$(awk -F": " '/Elapsed \(wall clock\) time/ {print $NF}' "$time_log")
        [ -z "$rt" ] && rt="0:0"
        mem=$(awk '/Maximum resident set size/ {print $NF}' "$time_log")
        [ -z "$mem" ] && mem="0"
        rt_sec=$(parse_time "$rt")
        ts=$(date -Iseconds)
        printf "rustyclean_baseline_k2_memmap,%s,%s,%s,%s,%s\n" "$dataset" "$rep" "$rt_sec" "$mem" "$ts" >> "$METRICS"
        echo "  runtime=${rt_sec}s memory=${mem}kb" | tee -a "$log"
    done
done

echo "Benchmark complete. Metrics: $METRICS"
