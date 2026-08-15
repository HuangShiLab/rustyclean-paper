#!/bin/bash
#SBATCH --job-name=rustyclean_sylph_full
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=128G
#SBATCH --time=12:00:00
#SBATCH --output=/home/shihuang/rustyclean_sylph_full_%j.out
#SBATCH --error=/home/shihuang/rustyclean_sylph_full_%j.err

set -euo pipefail

source /group/aos_shihuang/conda/etc/profile.d/conda.sh
conda activate /group/aos_shihuang/conda/envs/kneaddata
export PATH=/group/aos_shihuang/conda/envs/sylph/bin:$PATH

RUSTYCLEAN=/lustre1/g/aos_shihuang/rustyclean/target/release/rustyclean
DATA=/scr/u/shihuang/rustyclean-paper/data/enhanced
OUT=/scr/u/shihuang/rustyclean-paper/results_sylph_full
SYLPH_DB=/lustre1/g/aos_shihuang/databases/rustyclean_human_t2t_only/sylph/human_t2t.syldb
BT2_INDEX=/home/shihuang/.local/share/hostile/human-t2t-hla
THREADS=8
REPS=3

mkdir -p "$OUT"/metrics "$OUT"/logs

METRICS="$OUT/metrics/performance_sylph_full.csv"
echo "tool,dataset,rep,runtime_seconds,max_memory_kb,timestamp" > "$METRICS"

for ds_path in "$DATA"/*; do
  [ -d "$ds_path" ] || continue
  ds=$(basename "$ds_path")
  r1="$ds_path/reads_R1.fastq.gz"
  r2="$ds_path/reads_R2.fastq.gz"
  se="$ds_path/reads.fastq.gz"
  input_args=()
  if [ -f "$r1" ]; then
    input_args=(--r1 "$r1" --r2 "$r2")
  elif [ -f "$se" ]; then
    input_args=(--r1 "$se")
  else
    echo "Skip $ds: no reads file found" | tee -a "$OUT/logs/skip.log"
    continue
  fi

  for rep in $(seq 1 $REPS); do
    rep_dir="$OUT/results/$ds/rep_$rep"
    log="$OUT/logs/${ds}_rep${rep}.log"
    time_log="$OUT/logs/${ds}_rep${rep}.time"
    mkdir -p "$rep_dir"
    echo "=== $ds rep $rep ===" | tee -a "$log"
    /usr/bin/time -v -o "$time_log" \
      "$RUSTYCLEAN" \
        "${input_args[@]}" \
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
