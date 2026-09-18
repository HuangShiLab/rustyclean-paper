#!/bin/bash
#SBATCH --job-name=fill_100m_hostile
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=yfz96@connect.hku.hk
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --time=12:00:00
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err

set -euo pipefail

PROJECT=/lustre1/g/aos_shihuang/rustyclean-paper
DATA=/scr/u/shihuang/rustyclean-paper/data/enhanced
HOSTILE=/home/shihuang/.local/bin/hostile
ACC="python3 $PROJECT/scripts/hpc/fmh_accuracy.py"
OUT=/scr/u/shihuang/rustyclean-paper/fill_100m_comparators_v2

export PATH=/group/aos_shihuang/conda/envs/fastp/bin:/group/aos_shihuang/conda/envs/bowtie2/bin:$PATH

elapsed_from_time_file() {
    python3 - "$1" <<'PY'
import sys
from pathlib import Path
line = next(x for x in Path(sys.argv[1]).read_text().splitlines() if 'Elapsed (wall clock)' in x)
text = line.rsplit(': ', 1)[1].strip()
if '.' in text:
    text, frac = text.split('.', 1)
    frac = float('0.' + frac)
else:
    frac = 0.0
parts = [int(x) for x in text.split(':')]
while len(parts) < 3:
    parts.insert(0, 0)
h, m, s = parts
print(h * 3600 + m * 60 + s + frac)
PY
}

rss_from_time_file() {
    awk -F': ' '/Maximum resident set size/ {print $NF}' "$1"
}

append_result() {
    printf '%s,%s,%s,%s,%s,%s\n' "$1" "$2" "$3" "$4" "$5" "$6" >> "$OUT/fill_100m_comparators_metrics.csv"
}

finish_existing_hostile() {
    local dataset=$1
    local run=$OUT/hostile_fastp/$dataset
    local clean=$run/out/trimmed.clean.fastq.gz
    [[ -f "$clean" && -s "$clean" ]] || { echo "Expected Hostile output missing: $clean" >&2; return 1; }

    local fastp_elapsed hostile_elapsed fastp_rss hostile_rss elapsed rss acc
    fastp_elapsed=$(elapsed_from_time_file "$run/time_fastp.txt")
    hostile_elapsed=$(elapsed_from_time_file "$run/time_hostile.txt")
    fastp_rss=$(rss_from_time_file "$run/time_fastp.txt")
    hostile_rss=$(rss_from_time_file "$run/time_hostile.txt")
    elapsed=$(python3 - "$fastp_elapsed" "$hostile_elapsed" <<'PY'
import sys
print(float(sys.argv[1]) + float(sys.argv[2]))
PY
)
    rss=$(python3 - "$fastp_rss" "$hostile_rss" <<'PY'
import sys
print(max(int(x) for x in sys.argv[1:]))
PY
)
    acc=$($ACC "$DATA/$dataset/ground_truth_labels.txt" "$clean")
    printf 'hostile_fastp\t%s\t1\t%s\t%s\n' "$dataset" "$elapsed" "$rss" >> "$OUT/timing_metrics.csv"
    append_result hostile_fastp "$dataset" 1 "$elapsed" "$rss" "$acc"
    echo "salvaged hostile_fastp $dataset: $acc"
    rm -rf "$run/out" "$run/trimmed.fastq.gz"
}

run_hostile_fastp() {
    local dataset=$1
    local run=$OUT/hostile_fastp/$dataset
    rm -rf "$run"
    mkdir -p "$run/out"
    echo "=== fastp + Hostile $dataset start $(date -Iseconds) ==="

    /usr/bin/time -v -o "$run/time_fastp.txt" fastp \
        -i "$DATA/$dataset/reads.fastq.gz" \
        -o "$run/trimmed.fastq.gz" \
        -w 8 > "$run/fastp.log" 2>&1

    /usr/bin/time -v -o "$run/time_hostile.txt" "$HOSTILE" clean \
        --fastq1 "$run/trimmed.fastq.gz" \
        --aligner bowtie2 \
        --airplane \
        --threads 8 \
        -o "$run/out" > "$run/hostile.log" 2>&1

    local fastp_elapsed hostile_elapsed fastp_rss hostile_rss elapsed rss clean acc
    fastp_elapsed=$(elapsed_from_time_file "$run/time_fastp.txt")
    hostile_elapsed=$(elapsed_from_time_file "$run/time_hostile.txt")
    fastp_rss=$(rss_from_time_file "$run/time_fastp.txt")
    hostile_rss=$(rss_from_time_file "$run/time_hostile.txt")
    elapsed=$(python3 - "$fastp_elapsed" "$hostile_elapsed" <<'PY'
import sys
print(float(sys.argv[1]) + float(sys.argv[2]))
PY
)
    rss=$(python3 - "$fastp_rss" "$hostile_rss" <<'PY'
import sys
print(max(int(x) for x in sys.argv[1:]))
PY
)

    find "$run/out" -maxdepth 1 -type f -name '*.clean_*.fastq.gz' -size +0c -print | head -1 | grep -q . || {
        echo "ERROR: no Hostile cleaned FASTQ for $dataset" >&2
        return 1
    }
    clean=$(find "$run/out" -maxdepth 1 -type f -name '*.clean_*.fastq.gz' -size +0c -print | head -1)
    acc=$($ACC "$DATA/$dataset/ground_truth_labels.txt" "$clean")
    printf 'hostile_fastp\t%s\t1\t%s\t%s\n' "$dataset" "$elapsed" "$rss" >> "$OUT/timing_metrics.csv"
    append_result hostile_fastp "$dataset" 1 "$elapsed" "$rss" "$acc"
    echo "hostile_fastp $dataset: $acc"
    rm -rf "$run/out" "$run/trimmed.fastq.gz"
}

finish_existing_hostile 100M_50pct_high_lognormal_SE
run_hostile_fastp 100M_90pct_high_lognormal_SE

mkdir -p "$PROJECT/results_auto_deacon/fill_100m_comparators_v2"
cp "$OUT/fill_100m_comparators_metrics.csv" "$PROJECT/results_auto_deacon/fill_100m_comparators_v2/"
cp "$OUT/timing_metrics.csv" "$PROJECT/results_auto_deacon/fill_100m_comparators_v2/"
echo "=== HOSTILE RESUME DONE at $(date -Iseconds) ==="
