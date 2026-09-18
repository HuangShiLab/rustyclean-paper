#!/bin/bash
#SBATCH --job-name=fill_100m_comp_resume
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=yfz96@connect.hku.hk
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --time=24:00:00
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err

set -euo pipefail

PROJECT=/lustre1/g/aos_shihuang/rustyclean-paper
DATA=/scr/u/shihuang/rustyclean-paper/data/enhanced
KNEADDATA=/group/aos_shihuang/conda/envs/kneaddata/bin/kneaddata
KD_DB=/lustre1/g/aos_shihuang/databases/kneaddata/hg_39
HOSTILE=/home/shihuang/.local/bin/hostile
TRIMMOMATIC=/group/aos_shihuang/conda/envs/kneaddata/share/trimmomatic-0.40-0
TRF=/group/aos_shihuang/conda/envs/kneaddata/bin
ACC="python3 $PROJECT/scripts/hpc/fmh_accuracy.py"
OUT=/scr/u/shihuang/rustyclean-paper/fill_100m_comparators_v2

export PATH=/group/aos_shihuang/conda/envs/kneaddata/bin:/group/aos_shihuang/conda/envs/fastp/bin:/group/aos_shihuang/conda/envs/bowtie2/bin:$PATH

to_s() {
    python3 - "$1" <<'PY'
import sys
parts = [int(x) for x in sys.argv[1].split(':')]
while len(parts) < 3:
    parts.insert(0, 0)
h, m, s = parts
print(h * 3600 + m * 60 + s)
PY
}

append_result() {
    printf '%s,%s,%s,%s,%s,%s\n' "$1" "$2" "$3" "$4" "$5" "$6" >> "$OUT/fill_100m_comparators_metrics.csv"
}

max_kb() {
    local largest=0 value
    for value in "$@"; do
        [[ "$value" =~ ^[0-9]+$ ]] || continue
        if (( value > largest )); then
            largest=$value
        fi
    done
    echo "$largest"
}

finish_existing_kneaddata() {
    local dataset=$1; local run=$OUT/kneaddata/$dataset clean elapsed rss acc
    clean=$run/out/clean.fastq
    [[ -f "$clean" && -s "$clean" ]] || { echo "Expected completed KneadData output missing: $clean" >&2; return 1; }
    elapsed=$(to_s "$(awk -F': ' '/Elapsed \(wall clock\)/ {print $NF}' "$run/time.txt")")
    rss=$(awk -F': ' '/Maximum resident set size/ {print $NF}' "$run/time.txt")
    acc=$($ACC "$DATA/$dataset/ground_truth_labels.txt" "$clean")
    append_result kneaddata "$dataset" 1 "$elapsed" "$rss" "$acc"
    echo "    salvaged kneaddata $dataset: $acc"
    rm -rf "$run/out" "$run/acc"
}

run_kneaddata() {
    local dataset=$1; local run=$OUT/kneaddata/$dataset elapsed rss clean acc
    rm -rf "$run"
    mkdir -p "$run/out"
    echo "=== KneadData $dataset start $(date -Iseconds) ==="
    /usr/bin/time -v -o "$run/time.txt" "$KNEADDATA" \
        -un "$DATA/$dataset/reads.fastq.gz" -db "$KD_DB" \
        --output-prefix clean -o "$run/out" -t 8 \
        --trimmomatic "$TRIMMOMATIC" --trf "$TRF" \
        --remove-intermediate-output > "$run/run.log" 2>&1
    elapsed=$(to_s "$(awk -F': ' '/Elapsed \(wall clock\)/ {print $NF}' "$run/time.txt")")
    rss=$(awk -F': ' '/Maximum resident set size/ {print $NF}' "$run/time.txt")
    if [[ -f "$run/out/clean.fastq.gz" ]]; then
        clean=$run/out/clean.fastq.gz
    elif [[ -f "$run/out/clean.fastq" ]]; then
        clean=$run/out/clean.fastq
    else
        echo "ERROR: KneadData final output not found for $dataset" >&2
        return 1
    fi
    [[ -s "$clean" ]] || { echo "ERROR: empty KneadData output" >&2; return 1; }
    acc=$($ACC "$DATA/$dataset/ground_truth_labels.txt" "$clean")
    printf 'kneaddata\t%s\t1\t%s\t%s\n' "$dataset" "$elapsed" "$rss" >> "$OUT/timing_metrics.csv"
    append_result kneaddata "$dataset" 1 "$elapsed" "$rss" "$acc"
    echo "    kneaddata $dataset: $acc"
    rm -rf "$run/out" "$run/acc"
}

run_hostile_fastp() {
    local dataset=$1; local run=$OUT/hostile_fastp/$dataset
    rm -rf "$run"
    mkdir -p "$run/out"
    echo "=== fastp + Hostile $dataset start $(date -Iseconds) ==="
    /usr/bin/time -v -o "$run/time_fastp.txt" fastp \
        -i "$DATA/$dataset/reads.fastq.gz" -o "$run/trimmed.fastq.gz" -w 8 \
        > "$run/fastp.log" 2>&1
    /usr/bin/time -v -o "$run/time_hostile.txt" "$HOSTILE" clean \
        --fastq1 "$run/trimmed.fastq.gz" --aligner bowtie2 --airplane \
        --threads 8 -o "$run/out" > "$run/hostile.log" 2>&1

    local fastp_elapsed hostile_elapsed fastp_rss hostile_rss elapsed rss clean acc
    fastp_elapsed=$(to_s "$(awk -F': ' '/Elapsed \(wall clock\)/ {print $NF}' "$run/time_fastp.txt")")
    hostile_elapsed=$(to_s "$(awk -F': ' '/Elapsed \(wall clock\)/ {print $NF}' "$run/time_hostile.txt")")
    fastp_rss=$(awk -F': ' '/Maximum resident set size/ {print $NF}' "$run/time_fastp.txt")
    hostile_rss=$(awk -F': ' '/Maximum resident set size/ {print $NF}' "$run/time_hostile.txt")
    elapsed=$(python3 - "$fastp_elapsed" "$hostile_elapsed" <<'PY'
import sys
print(int(sys.argv[1]) + int(sys.argv[2]))
PY
)
    rss=$(max_kb "$fastp_rss" "$hostile_rss")
    mapfile -t candidates < <(find "$run/out" -maxdepth 1 -type f -name '*.clean_*.fastq.gz' -size +0c -print)
    ((${#candidates[@]} > 0)) || { echo "ERROR: no Hostile cleaned FASTQ for $dataset" >&2; return 1; }
    clean=$(printf '%s\n' "${candidates[@]}" | xargs stat -c '%s %n' | sort -nr | head -1 | cut -d' ' -f3-)
    acc=$($ACC "$DATA/$dataset/ground_truth_labels.txt" "$clean")
    printf 'hostile_fastp\t%s\t1\t%s\t%s\n' "$dataset" "$elapsed" "$rss" >> "$OUT/timing_metrics.csv"
    append_result hostile_fastp "$dataset" 1 "$elapsed" "$rss" "$acc"
    echo "    hostile_fastp $dataset: $acc"
    rm -rf "$run/out" "$run/trimmed.fastq.gz"
}

D50=100M_50pct_high_lognormal_SE
D90=100M_90pct_high_lognormal_SE

finish_existing_kneaddata "$D50"
run_kneaddata "$D90"
run_hostile_fastp "$D50"
run_hostile_fastp "$D90"

mkdir -p "$PROJECT/results_auto_deacon/fill_100m_comparators_v2"
cp "$OUT/fill_100m_comparators_metrics.csv" "$PROJECT/results_auto_deacon/fill_100m_comparators_v2/"
cp "$OUT/timing_metrics.csv" "$PROJECT/results_auto_deacon/fill_100m_comparators_v2/"
echo "=== RESUME DONE at $(date -Iseconds) ==="
