#!/bin/bash
#SBATCH --job-name=hostile_100M
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=48:00:00
#SBATCH --output=/home/%u/hostile_100M_%j.out
#SBATCH --error=/home/%u/hostile_100M_%j.err

set -euo pipefail

source /group/aos_shihuang/conda/bin/activate hostile-centrifuge
# HOSTILE env has ancient samtools 0.1.19; override with modern samtools
export PATH=/home/shihuang/.conda/envs/samtools-only/bin:$PATH
which hostile || { echo "hostile not found"; exit 1; }
which bowtie2 || { echo "bowtie2 not found"; exit 1; }
which samtools || { echo "samtools not found"; exit 1; }

DATA=${SCRATCH_DIR:-/scr/u/$USER/rustyclean-paper}/data/enhanced
OUT=${SCRATCH_DIR:-/scr/u/$USER/rustyclean-paper}/results_100M_hostile
INDEX=${HOSTILE_INDEX:-$HOME/.local/share/hostile/human-t2t-hla}
THREADS=8
REPS=3

mkdir -p "$OUT"/metrics "$OUT"/logs

DATASETS=(
  100M_50pct_high_lognormal_SE
  100M_90pct_high_lognormal_SE
)

METRICS="$OUT/metrics/performance_100M_hostile.csv"
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
  for rep in $(seq 1 $REPS); do
    rep_dir="$OUT/results/$ds/rep_$rep"
    log="$OUT/logs/${ds}_rep${rep}.log"
    time_log="$OUT/logs/${ds}_rep${rep}.time"
    mkdir -p "$rep_dir"
    echo "=== $ds rep $rep ===" | tee -a "$log"

    /usr/bin/time -v -o "$time_log" \
      hostile clean --fastq1 "$DATA/$ds/reads.fastq.gz" \
        --aligner bowtie2 --index "$INDEX" --airplane \
        --output "$rep_dir" \
        --threads "$THREADS" \
        --force \
        >> "$log" 2>&1 || { echo "FAILED $ds rep $rep" >> "$log"; continue; }

    elapsed=$(grep "Elapsed (wall clock) time" "$time_log" | awk -F': ' '{print $2}')
    mem_kb=$(grep "Maximum resident set size" "$time_log" | awk -F': ' '{print $2}' | tr -d 'kB ')
    runtime_sec=$(parse_time "$elapsed")
    echo "hostile,$ds,$rep,$runtime_sec,$mem_kb,$(date -Iseconds)" >> "$METRICS"
  done
done

echo "All done. Metrics: $METRICS"
