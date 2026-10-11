#!/bin/bash
#SBATCH --job-name=paired_trip
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --array=0-5
#SBATCH --output=logs/%x-%A_%a.out
#SBATCH --error=logs/%x-%A_%a.err

set -euo pipefail
export PATH="/lustre1/g/aos_shihuang/tools/samtools/samtools-1.21:/home/shihuang/.conda/envs/hostile-centrifuge/bin:/home/shihuang/.conda/envs/sketch-benchmark/bin:/group/aos_shihuang/conda/envs/fastp/bin:${PATH}"

REPO=/lustre1/g/aos_shihuang/rustyclean-paper
RUSTYCLEAN=/lustre1/g/aos_shihuang/rustyclean/target/release/rustyclean
DATA_DIR=/scr/u/shihuang/rustyclean-paper/data/enhanced
DEACON_INDEX=/lustre1/g/aos_shihuang/databases/deacon/panhuman-1.k31w15.idx
HOSTILE_INDEX=$HOME/.local/share/hostile/human-t2t-hla
RESULTS=/lustre1/g/aos_shihuang/rustyclean-paper/runs/paired_triplicate
THREADS=16
REPS=3

DATASETS=(
  5M_1pct_low_even_SE
  10M_10pct_med_even_SE
  30M_50pct_high_skewed_SE
  60M_90pct_high_lognormal_SE
  100M_50pct_high_lognormal_SE
  100M_90pct_high_lognormal_SE
)
DATASET=${DATASETS[$SLURM_ARRAY_TASK_ID]}
R1=${DATA_DIR}/${DATASET}/reads.fastq.gz
TRUTH=${DATA_DIR}/${DATASET}/ground_truth_labels.txt
OUT=${RESULTS}/${DATASET}
WORK=/tmp/paired_triplicate_${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}
SERVER_DIR=${WORK}/deacon_server

mkdir -p "$OUT/metrics" "$OUT/logs" "$WORK" "$SERVER_DIR"
METRICS=${OUT}/metrics/paired_runtime.csv
ACCURACY=${OUT}/metrics/paired_accuracy.csv
if [[ ! -f "$METRICS" ]]; then
  echo "dataset,rep,tool,order,runtime_s,max_rss_kb,timestamp" > "$METRICS"
fi
if [[ ! -f "$ACCURACY" ]]; then
  echo "dataset,rep,tool,accuracy,precision,recall,f1,tp,fp,tn,fn" > "$ACCURACY"
fi

parse_runtime() {
  awk '/Elapsed [(]wall clock[)] time/ {print $NF; exit}' "$1"
}
parse_mem() {
  awk '/Maximum resident set size/ {print $NF; exit}' "$1"
}
to_seconds() {
  awk -F: -v t="$1" 'BEGIN {n=split(t,a,":"); s=0; for(i=1;i<=n;i++) s=s*60+a[i]; printf "%.3f", s}'
}
emit_runtime() {
  echo "${DATASET},${1},${2},${3},${4},$(date -Iseconds)" >> "$METRICS"
}
have_metric() {
  awk -F, -v dataset="$DATASET" -v rep="$1" -v tool="$2" '
    NR > 1 && $1 == dataset && $2 == rep && $3 == tool { found = 1 }
    END { exit !found }
  ' "$METRICS"
}

# Warm the compressed input and both index types before any timed replicate.
cat "$R1" > /dev/null
cat "$DEACON_INDEX" > /dev/null
for index_file in "$HOSTILE_INDEX"*; do
  [[ -f "$index_file" ]] && cat "$index_file" > /dev/null || true
done

(
  cd "$SERVER_DIR"
  deacon server start -t "$THREADS" > server.log 2>&1
) &
server_pid=$!
for _ in $(seq 1 300); do
  [[ -S "$SERVER_DIR/deacon_server_socket" ]] && break
  kill -0 "$server_pid" 2>/dev/null || break
  sleep 0.2
done
[[ -S "$SERVER_DIR/deacon_server_socket" ]] || { echo "Deacon server failed" >&2; exit 1; }
cleanup() {
  (cd "$SERVER_DIR" && deacon --use-server server stop >/dev/null 2>&1) || true
  kill "$server_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
}
trap cleanup EXIT

run_rustyclean() {
  local rep=$1
  local out=${WORK}/rc/rep${rep}
  local work=${WORK}/rc_work/rep${rep}
  rm -rf "$out" "$work"
  mkdir -p "$out" "$work"
  local timefile=${OUT}/logs/rustyclean_rep${rep}.time
  local logfile=${OUT}/logs/rustyclean_rep${rep}.log
  /usr/bin/time -v -o "$timefile" "$RUSTYCLEAN" \
    --r1 "$R1" \
    --deacon-index "$DEACON_INDEX" \
    --host-index "$HOSTILE_INDEX" \
    --max-contamination 100.0 \
    --fastp-compression 1 \
    --deacon-compression-level 2 \
    --use-deacon-server \
    --deacon-server-dir "$SERVER_DIR" \
    --work-dir "$work" \
    --checkpoint-dir "$out/.checkpoints" \
    --clean -o "$out" -t "$THREADS" \
    > "$logfile" 2>&1
  local final
  final=$(find "$out" -name '*_clean_R1.fastq.gz' -print -quit)
  [[ -n "$final" ]] || { echo "RustyClean output missing for rep $rep" >&2; return 1; }
  emit_runtime "$rep" rustyclean "$(to_seconds "$(parse_runtime "$timefile")")" "$(parse_mem "$timefile")"
  python3 "$REPO/scripts/main/compute_accuracy_one.py" \
    rustyclean "$DATASET" "$rep" "$TRUTH" "$final" "$ACCURACY"
}

run_hostile() {
  local rep=$1
  local out=${WORK}/hostile/rep${rep}
  rm -rf "$out"
  mkdir -p "$out"
  local fastp_time=${OUT}/logs/hostile_fastp_rep${rep}.time
  local fastp_log=${OUT}/logs/hostile_fastp_rep${rep}.log
  local hostile_time=${OUT}/logs/hostile_rep${rep}.time
  local hostile_log=${OUT}/logs/hostile_rep${rep}.log
  local trimmed=${WORK}/hostile_trimmed_rep${rep}.fastq.gz

  /usr/bin/time -v -o "$fastp_time" fastp \
    --in1 "$R1" --out1 "$trimmed" \
    --json "$out/fastp.json" --html "$out/fastp.html" \
    --thread "$THREADS" --compression 1 \
    --cut_front --cut_tail \
    --qualified_quality_phred 20 --length_required 50 \
    > "$fastp_log" 2>&1
  /usr/bin/time -v -o "$hostile_time" hostile clean \
    --fastq1 "$trimmed" \
    --aligner bowtie2 \
    --index "$HOSTILE_INDEX" \
    --airplane --force \
    --output "$out" --threads "$THREADS" \
    > "$hostile_log" 2>&1

  local clean
  clean=$(find "$out" -name '*.clean.fastq.gz' -o -name '*clean*.fastq.gz' | head -1)
  [[ -n "$clean" ]] || { echo "Hostile output missing for rep $rep" >&2; return 1; }
  local total
  total=$(python3 - "$fastp_time" "$hostile_time" <<'PY'
import sys

def seconds(path):
    for line in open(path):
        if line.strip().startswith('Elapsed (wall clock) time'):
            value = line.strip().rsplit(':', 1)[1].strip()
            parts = [float(x) for x in value.split(':')]
            return sum(x * 60 ** i for i, x in enumerate(reversed(parts)))
    raise SystemExit(f'elapsed time missing in {path}')

print(f'{seconds(sys.argv[1]) + seconds(sys.argv[2]):.3f}')
PY
)
  emit_runtime "$rep" hostile_fastp "$total" "$(parse_mem "$hostile_time")"
  python3 "$REPO/scripts/main/compute_accuracy_one.py" \
    hostile_fastp "$DATASET" "$rep" "$TRUTH" "$clean" "$ACCURACY"
  rm -f "$trimmed"
}

for rep in $(seq 1 "$REPS"); do
  if have_metric "$rep" rustyclean && have_metric "$rep" hostile_fastp; then
    echo "skip $DATASET rep $rep: both paired measurements already exist"
    continue
  fi

  if (( rep % 2 == 1 )); then
    if ! have_metric "$rep" rustyclean; then run_rustyclean "$rep"; fi
    if ! have_metric "$rep" hostile_fastp; then run_hostile "$rep"; fi
    order=resume
  else
    if ! have_metric "$rep" hostile_fastp; then run_hostile "$rep"; fi
    if ! have_metric "$rep" rustyclean; then run_rustyclean "$rep"; fi
    order=resume
  fi
  echo "completed $DATASET rep $rep order=$order"
done

rm -rf "$WORK"
