#!/bin/bash
#SBATCH --job-name=rc_100M_sylph_auto
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=12:00:00
#SBATCH --output=/home/shihuang/rc_100M_sylph_auto_%j.out
#SBATCH --error=/home/shihuang/rc_100M_sylph_auto_%j.err

set -euo pipefail

source /group/aos_shihuang/conda/etc/profile.d/conda.sh
conda activate /group/aos_shihuang/conda/envs/kneaddata
export PATH=/group/aos_shihuang/conda/envs/sylph/bin:$PATH

RUSTYCLEAN=/lustre1/g/aos_shihuang/rustyclean/target/release/rustyclean
DATA=/scr/u/shihuang/rustyclean-paper/data/enhanced
OUT=/scr/u/shihuang/rustyclean-paper/results_100M_sylph_auto
SYLPH_DB=/lustre1/g/aos_shihuang/databases/rustyclean_human_t2t_only/sylph/human_t2t.syldb
BT2_INDEX=/home/shihuang/.local/share/hostile/human-t2t-hla
THREADS=8
REPS=3

mkdir -p "$OUT"/metrics "$OUT"/logs

DATASETS=(
  100M_50pct_high_lognormal_SE
  100M_90pct_high_lognormal_SE
)

METRICS="$OUT/metrics/performance_100M_sylph_auto.csv"
echo "tool,dataset,rep,runtime_seconds,max_memory_kb,timestamp" > "$METRICS"

parse_time() {
  local t=$1
  echo "$t" | awk -F':' '{
    if (NF == 3) print $1*3600 + $2*60 + $3;
    else if (NF == 2) print $1*60 + $2;
    else print $1;
  }'
}

for ds in "${DATASETS[@]}"; do
  for mode in auto sylph; do
    for rep in $(seq 1 $REPS); do
      rep_dir="$OUT/results_${mode}/$ds/rep_$rep"
      log="$OUT/logs/${mode}_${ds}_rep${rep}.log"
      time_log="$OUT/logs/${mode}_${ds}_rep${rep}.time"
      mkdir -p "$rep_dir"
      echo "=== $mode $ds rep $rep ===" | tee -a "$log"

      if [ "$mode" == "auto" ]; then
        mode_arg="auto"
        extra_args="--auto-survey"
      else
        mode_arg="sylph"
        extra_args=""
      fi

      /usr/bin/time -v -o "$time_log" \
        "$RUSTYCLEAN" \
          --r1 "$DATA/$ds/reads.fastq.gz" \
          --output "$rep_dir" \
          --host-removal-mode "$mode_arg" \
          --sylph-db "$SYLPH_DB" \
          --host-index "$BT2_INDEX" \
          --threads "$THREADS" \
          --skip-qc \
          $extra_args \
          --checkpoint-dir "$rep_dir/checkpoints" \
          >> "$log" 2>&1 || { echo "FAILED $mode $ds rep $rep" >> "$log"; continue; }

      elapsed=$(grep "Elapsed (wall clock) time" "$time_log" | awk -F': ' '{print $2}')
      mem_kb=$(grep "Maximum resident set size" "$time_log" | awk -F': ' '{print $2}' | tr -d 'kB ')
      runtime_sec=$(parse_time "$elapsed")
      echo "rustyclean_${mode},$ds,$rep,$runtime_sec,$mem_kb,$(date -Iseconds)" >> "$METRICS"
    done
  done
done

echo "All done. Metrics: $METRICS"
