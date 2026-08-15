#!/bin/bash
#SBATCH --job-name=rustyclean_sylph_std
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=32
#SBATCH --mem=128G
#SBATCH --time=8:00:00
#SBATCH --output=/home/shihuang/rustyclean_sylph_std_%j.out
#SBATCH --error=/home/shihuang/rustyclean_sylph_std_%j.err

set -euo pipefail

source /group/aos_shihuang/conda/etc/profile.d/conda.sh
conda activate /group/aos_shihuang/conda/envs/kneaddata
export PATH=/group/aos_shihuang/conda/envs/sylph/bin:$PATH

RUSTYCLEAN=/lustre1/g/aos_shihuang/rustyclean/target/release/rustyclean
DATA=/scr/u/shihuang/rustyclean-paper/data/enhanced
OUT=/scr/u/shihuang/rustyclean-paper/results_sylph_standard
SYLPH_DB=/lustre1/g/aos_shihuang/databases/rustyclean_human_t2t_only/sylph/human_t2t.syldb
BT2_INDEX=/home/shihuang/.local/share/hostile/human-t2t-hla
THREADS=8
REPS=3

mkdir -p "$OUT"/metrics "$OUT"/logs

DATASETS=(
  5M_1pct_low_even_SE
  10M_10pct_med_even_SE
  30M_50pct_high_skewed_SE
  60M_90pct_high_lognormal_SE
)

METRICS="$OUT/metrics/performance_sylph_standard.csv"
echo "tool,dataset,rep,runtime_seconds,max_memory_kb,timestamp" > "$METRICS"

for ds in "${DATASETS[@]}"; do
  for rep in $(seq 1 $REPS); do
    rep_dir="$OUT/results/$ds/rep_$rep"
    log="$OUT/logs/${ds}_rep${rep}.log"
    time_log="$OUT/logs/${ds}_rep${rep}.time"
    mkdir -p "$rep_dir"
    echo "=== $ds rep $rep ===" | tee -a "$log"
    /usr/bin/time -v -o "$time_log" \
      "$RUSTYCLEAN" \
        --r1 "$DATA/$ds/reads.fastq.gz" \
        --output "$rep_dir" \
        --host-removal-mode sylph \
        --sylph-db "$SYLPH_DB" \
        --host-index "$BT2_INDEX" \
        --threads "$THREADS" \
        --skip-qc \
        --checkpoint-dir "$rep_dir/checkpoints" \
        >> "$log" 2>&1 || { echo "FAILED $ds rep $rep" >> "$log"; continue; }
    elapsed=$(grep "Elapsed (wall clock) time" "$time_log" | awk -F': ' '{print $2}')
    mem_kb=$(grep "Maximum resident set size" "$time_log" | awk -F': ' '{print $2}' | tr -d 'kB ')
    runtime_sec=$(echo "$elapsed" | awk -F: '{if(NF==2){print $1*60+$2}else{print $1*3600+$2*60+$3}}')
    echo "rustyclean_sylph,$ds,$rep,$runtime_sec,$mem_kb,$(date -Iseconds)" >> "$METRICS"
  done
done
