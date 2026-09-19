#!/bin/bash
#SBATCH --job-name=rc_deacon_norecheck
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --time=08:00:00
#SBATCH --array=0-5
#SBATCH --output=logs/%x-%A_%a.out
#SBATCH --error=logs/%x-%A_%a.err

set -euo pipefail

export PATH="/home/shihuang/.conda/envs/sketch-benchmark/bin:/group/aos_shihuang/conda/envs/fastp/bin:/group/aos_shihuang/conda/envs/bowtie2/bin:${PATH}"

DATA_DIR="/scr/u/shihuang/rustyclean-paper/data/enhanced"
RESULTS_DIR="/lustre1/g/aos_shihuang/rustyclean-paper/runs/deacon_auto_norecheck"
METRICS_DIR="${RESULTS_DIR}/metrics"
LOGS_DIR="${RESULTS_DIR}/logs"
RUSTYCLEAN="/lustre1/g/aos_shihuang/rustyclean/target/release/rustyclean"
DEACON_INDEX="/lustre1/g/aos_shihuang/databases/deacon/panhuman-1.k31w15.idx"
HOST_INDEX="/home/shihuang/.local/share/hostile/human-t2t-hla"
THREADS=16
REPS=3

# 7ab1a4b exposes the threshold but not the later --no-bowtie2-recheck alias.
# A threshold above 1 disables the conditional Bowtie2 verification stage while
# retaining the full fastp -> Deacon AUTO workflow.
RECHECK_THRESHOLD=1.01

DATASETS=(
  "5M_1pct_low_even_SE"
  "10M_10pct_med_even_SE"
  "30M_50pct_high_skewed_SE"
  "60M_90pct_high_lognormal_SE"
  "100M_50pct_high_lognormal_SE"
  "100M_90pct_high_lognormal_SE"
)
DATASET="${DATASETS[$SLURM_ARRAY_TASK_ID]}"
R1="${DATA_DIR}/${DATASET}/reads.fastq.gz"

mkdir -p "${METRICS_DIR}" "${LOGS_DIR}"
METRICS="${METRICS_DIR}/performance.csv"
if [ ! -f "${METRICS}" ]; then
  echo "tool,dataset,rep,runtime_seconds,max_memory_kb,timestamp" > "${METRICS}"
fi

for REP in $(seq 1 "${REPS}"); do
  OUT="${RESULTS_DIR}/rustyclean_auto_deacon_norecheck/${DATASET}/rep_${REP}"
  rm -rf "${OUT}"
  mkdir -p "${OUT}"
  TIMEFILE="${LOGS_DIR}/${DATASET}_rep${REP}.time"
  RUNLOG="${LOGS_DIR}/${DATASET}_rep${REP}.run.log"

  /usr/bin/time -v -o "${TIMEFILE}" \
    "${RUSTYCLEAN}" \
      --mode auto \
      --r1 "${R1}" \
      --deacon-index "${DEACON_INDEX}" \
      --host-index "${HOST_INDEX}" \
      --recheck-threshold "${RECHECK_THRESHOLD}" \
      --max-contamination 100.0 \
      --checkpoint-dir "${OUT}/.checkpoints" \
      --clean \
      -o "${OUT}" \
      -t "${THREADS}" \
      > "${RUNLOG}" 2>&1

  ELAPSED=$(awk -F': ' '/Elapsed \(wall clock\) time/ {print $NF; exit}' "${TIMEFILE}")
  MAXMEM=$(awk '/Maximum resident set size/ {print $NF; exit}' "${TIMEFILE}")
  RUNTIME=$(awk -F: -v t="${ELAPSED}" 'BEGIN {n=split(t,a,":"); s=0; for(i=1;i<=n;i++) s=s*60+a[i]; printf "%.2f", s}')
  echo "rustyclean_auto_deacon_norecheck,${DATASET},${REP},${RUNTIME},${MAXMEM},$(date -Iseconds)" >> "${METRICS}"
done
