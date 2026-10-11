#!/bin/bash
#SBATCH --job-name=parallel_demo
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=04:00:00
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err

set -euo pipefail
export PATH="/lustre1/g/aos_shihuang/tools/samtools/samtools-1.21:/home/shihuang/.conda/envs/hostile-centrifuge/bin:/home/shihuang/.conda/envs/sketch-benchmark/bin:/group/aos_shihuang/conda/envs/fastp/bin:${PATH}"

REPO=/lustre1/g/aos_shihuang/rustyclean-paper
RUSTYCLEAN=/lustre1/g/aos_shihuang/rustyclean/target/release/rustyclean
READS=/lustre1/g/aos_shihuang/rustyclean-paper/scratch/data/parallel/reads
DEACON_INDEX=/lustre1/g/aos_shihuang/databases/deacon/panhuman-1.k31w15.idx
HOSTILE_INDEX=$HOME/.local/share/hostile/human-t2t-hla
RESULTS=/lustre1/g/aos_shihuang/rustyclean-paper/runs/parallel_demo
WORK=/tmp/parallel_demo_${SLURM_JOB_ID:-$$}
CPUS=16
WORKERS="1 8"

mkdir -p "$RESULTS/metrics" "$RESULTS/logs" "$WORK"
METRICS="$RESULTS/metrics/parallel_demo.csv"
if [[ ! -f "$METRICS" ]]; then
  echo "arm,workers,threads,n_samples,wall_s,user_s,sys_s,max_rss_kb,cgroup_cpu_s,timestamp" > "$METRICS"
fi

SAMPLES_TSV="$WORK/samples.tsv"
SAMPLES_LIST="$WORK/samples.txt"
: > "$SAMPLES_TSV"
: > "$SAMPLES_LIST"
for h in 01 05 10 50 70 90; do
  for r in 01 02 03 04; do
    sid="h${h}_r${r}"
    path="$READS/${sid}.fastq.gz"
    printf '%s\t%s\n' "$sid" "$path" >> "$SAMPLES_TSV"
    printf '%s\t%s\n' "$sid" "$path" >> "$SAMPLES_LIST"
  done
done
N_SAMPLES=$(wc -l < "$SAMPLES_LIST")

parse_runtime() {
  awk '/Elapsed \(wall clock\) time/ {print $NF; exit}' "$1"
}
parse_user() {
  awk '/User time \(seconds\)/ {print $NF; exit}' "$1"
}
parse_sys() {
  awk '/System time \(seconds\)/ {print $NF; exit}' "$1"
}
parse_mem() {
  awk '/Maximum resident set size/ {print $NF; exit}' "$1"
}
to_seconds() {
  awk -F: -v t="$1" 'BEGIN {n=split(t,a,":"); s=0; for(i=1;i<=n;i++) s=s*60+a[i]; printf "%.3f", s}'
}
cgroup_cpu() {
  local rel path
  rel=$(awk -F: '$1=="0"{print $3; exit}' /proc/self/cgroup 2>/dev/null || true)
  for path in /sys/fs/cgroup${rel}/cpu.stat /sys/fs/cgroup/cpu.stat /sys/fs/cgroup/cpuacct.usage; do
    [[ -r "$path" ]] || continue
    if [[ "$path" == *cpuacct.usage ]]; then
      awk '{printf "%.3f", $1/1000000}' "$path"
    else
      awk '$1=="usage_usec"{printf "%.3f", $2/1000000}' "$path"
    fi
    return
  done
  echo ""
}
cpu_delta() {
  python3 - "$1" "$2" <<'PY'
import sys

before = float(sys.argv[1]) if sys.argv[1] else 0.0
after = float(sys.argv[2]) if sys.argv[2] else 0.0
print(f"{max(after-before, 0.0):.3f}")
PY
}

# Read every input and index once, untimed, so both worker counts and both
# tools start with the same warm page cache.
while IFS=$'\t' read -r _ path; do cat "$path" > /dev/null; done < "$SAMPLES_LIST"
cat "$DEACON_INDEX" > /dev/null
for index_file in "$HOSTILE_INDEX"*; do
  [[ -f "$index_file" ]] && cat "$index_file" > /dev/null || true
done

hostile_worker() {
  local worker=$1
  cat > "$worker" <<'EOF'
#!/bin/bash
set -euo pipefail
sid="$1"
r1="$2"
threads="${THREADS:?THREADS must be set}"
out="${ARM_OUT:?ARM_OUT must be set}"
tmp="${HOSTILE_TMP:?HOSTILE_TMP must be set}"
mkdir -p "$out/$sid" "$tmp/$sid"
trimmed="$tmp/$sid/trimmed.fastq.gz"
fastp --in1 "$r1" --out1 "$trimmed" \
  --thread "$threads" --compression 1 \
  --cut_front --cut_tail \
  --qualified_quality_phred 20 --length_required 50 \
  > "$tmp/$sid/fastp.log" 2>&1
hostile clean --fastq1 "$trimmed" \
  --aligner bowtie2 --index "$HOSTILE_INDEX" \
  --airplane --force --output "$out/$sid" --threads "$threads" \
  > "$tmp/$sid/hostile.log" 2>&1
EOF
}

for workers in $WORKERS; do
  threads=$((CPUS / workers))
  arm_out="$WORK/${workers}_workers"
  arm_log="$RESULTS/logs/${workers}_workers"
  rm -rf "$arm_out"
  mkdir -p "$arm_out" "$arm_log"

  # RustyClean: one batch process with W worker tasks.
  timefile="$arm_log/rustyclean.time"
  rc_cpu_before=$(cgroup_cpu)
  /usr/bin/time -v -o "$timefile" "$RUSTYCLEAN" \
    --samples "$SAMPLES_TSV" \
    --deacon-index "$DEACON_INDEX" \
    --host-index "$HOSTILE_INDEX" \
    --max-contamination 100.0 \
    --fastp-compression 1 \
    --deacon-compression-level 2 \
    -o "$arm_out/rustyclean" \
    --workers "$workers" --threads "$threads" \
    --checkpoint-dir "$arm_log/rustyclean_checkpoints" \
  --clean > "$arm_log/rustyclean.log" 2>&1
  rc_wall=$(to_seconds "$(parse_runtime "$timefile")")
  rc_cpu=$(cpu_delta "$rc_cpu_before" "$(cgroup_cpu)")
  echo "rustyclean,$workers,$threads,$N_SAMPLES,$rc_wall,$(parse_user "$timefile"),$(parse_sys "$timefile"),$(parse_mem "$timefile"),$rc_cpu,$(date -Iseconds)" >> "$METRICS"

  # Hostile+fastp: W independent shell pipelines, matching the W x T budget.
  worker="$arm_log/hostile_worker.sh"
  hostile_worker "$worker"
  chmod +x "$worker"
  timefile="$arm_log/hostile.time"
  hostile_cpu_before=$(cgroup_cpu)
  HOSTILE_INDEX="$HOSTILE_INDEX" THREADS="$threads" ARM_OUT="$arm_out/hostile" HOSTILE_TMP="$WORK/hostile_tmp" \
  /usr/bin/time -v -o "$timefile" bash -c \
    "xargs -a '$SAMPLES_LIST' -P $workers -n 2 bash '$worker' > '$arm_log/hostile.xargs.log' 2>&1"
  hs_wall=$(to_seconds "$(parse_runtime "$timefile")")
  hostile_cpu=$(cpu_delta "$hostile_cpu_before" "$(cgroup_cpu)")
  echo "hostile_fastp,$workers,$threads,$N_SAMPLES,$hs_wall,$(parse_user "$timefile"),$(parse_sys "$timefile"),$(parse_mem "$timefile"),$hostile_cpu,$(date -Iseconds)" >> "$METRICS"
done

rm -rf "$WORK"
echo "Benchmark complete: $METRICS"
