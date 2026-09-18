#!/bin/bash
# Fill the missing 100M KneadData and fastp + Hostile comparator cells.
# AUTO/deacon results are intentionally not rerun here.

#SBATCH --job-name=fill_100m_comparators
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
REPO=/lustre1/g/aos_shihuang/rustyclean
DATA=/scr/u/shihuang/rustyclean-paper/data/enhanced
KNEADDATA=/group/aos_shihuang/conda/envs/kneaddata/bin/kneaddata
KD_DB=/lustre1/g/aos_shihuang/databases/kneaddata/hg_39
HOSTILE=/home/shihuang/.local/bin/hostile
TRIMMOMATIC=/group/aos_shihuang/conda/envs/kneaddata/share/trimmomatic-0.40-0
TRF=/group/aos_shihuang/conda/envs/kneaddata/bin
ACC="python3 $PROJECT/scripts/hpc/fmh_accuracy.py"

# Fresh output tree; the failed AUTO fill output remains untouched.
OUT=/scr/u/shihuang/rustyclean-paper/fill_100m_comparators_v2
mkdir -p "$OUT" "$PROJECT/logs"

export PATH=$PROJECT/tools/deacon-build/bin:/group/aos_shihuang/conda/envs/kneaddata/bin:/group/aos_shihuang/conda/envs/fastp/bin:/group/aos_shihuang/conda/envs/bowtie2/bin:$PATH
export RUST_BACKTRACE=1

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

timing_csv=$OUT/timing_metrics.csv
metrics_csv=$OUT/fill_100m_comparators_metrics.csv
printf 'tool\tdataset\trep\telapsed_s\tmax_rss_kb\n' > "$timing_csv"
echo "tool,dataset,rep,elapsed_s,max_rss_kb,accuracy,precision,recall,f1,microbial_loss_pct,host_carry_pct" > "$metrics_csv"

append_timing() {
    printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$timing_csv"
}

append_result() {
    printf '%s,%s,%s,%s,%s,%s\n' "$1" "$2" "$3" "$4" "$5" "$6" >> "$metrics_csv"
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

run_kneaddata() {
    local dataset=$1
    local run=$OUT/kneaddata/$dataset
    rm -rf "$run"
    mkdir -p "$run/out"

    echo "=== KneadData $dataset start $(date -Iseconds) ==="
    /usr/bin/time -v -o "$run/time.txt" "$KNEADDATA" \
        -un "$DATA/$dataset/reads.fastq.gz" \
        -db "$KD_DB" \
        --output-prefix clean \
        -o "$run/out" \
        -t 8 \
        --trimmomatic "$TRIMMOMATIC" \
        --trf "$TRF" \
        --remove-intermediate-output \
        > "$run/run.log" 2>&1

    local elapsed rss clean acc
    elapsed=$(to_s "$(awk -F': ' '/Elapsed \(wall clock\)/ {print $NF}' "$run/time.txt")")
    rss=$(awk -F': ' '/Maximum resident set size/ {print $NF}' "$run/time.txt")

    # Explicitly select the final retained-read output.  Do not glob, because
    # KneadData also writes a separate *_contam.fastq discarded-reads file.
    if [[ -f "$run/out/clean.fastq.gz" ]]; then
        clean=$run/out/clean.fastq.gz
    elif [[ -f "$run/out/clean.fastq" ]]; then
        clean=$run/out/clean.fastq
    else
        echo "ERROR: KneadData final output not found for $dataset" >&2
        find "$run/out" -maxdepth 1 -type f -printf '%s %f\n' >&2
        return 1
    fi
    [[ -s "$clean" ]] || { echo "ERROR: empty KneadData output: $clean" >&2; return 1; }

    append_timing kneaddata "$dataset" 1 "$elapsed" "$rss"
    # fmh_accuracy.py chooses gzip/plain from the actual path suffix.
    acc=$($ACC "$DATA/$dataset/ground_truth_labels.txt" "$clean")
    append_result kneaddata "$dataset" 1 "$elapsed" "$rss" "$acc"
    echo "    kneaddata $dataset: $acc"
    rm -rf "$run/out" "$run/acc"
}

run_hostile_fastp() {
    local dataset=$1
    local run=$OUT/hostile_fastp/$dataset
    rm -rf "$run"
    mkdir -p "$run/out"

    echo "=== fastp + Hostile $dataset start $(date -Iseconds) ==="
    /usr/bin/time -v -o "$run/time_fastp.txt" \
        fastp -i "$DATA/$dataset/reads.fastq.gz" \
              -o "$run/trimmed.fastq.gz" \
              -w 8 \
        > "$run/fastp.log" 2>&1

    /usr/bin/time -v -o "$run/time_hostile.txt" \
        "$HOSTILE" clean \
            --fastq1 "$run/trimmed.fastq.gz" \
            --aligner bowtie2 \
            --airplane \
            --threads 8 \
            -o "$run/out" \
        > "$run/hostile.log" 2>&1

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
    if ((${#candidates[@]} == 0)); then
        echo "ERROR: Hostile cleaned FASTQ not found for $dataset" >&2
        find "$run/out" -maxdepth 1 -type f -printf '%s %f\n' >&2
        return 1
    fi
    clean=$(printf '%s\n' "${candidates[@]}" | xargs stat -c '%s %n' | sort -nr | head -1 | cut -d' ' -f3-)

    append_timing hostile_fastp "$dataset" 1 "$elapsed" "$rss"
    acc=$($ACC "$DATA/$dataset/ground_truth_labels.txt" "$clean")
    append_result hostile_fastp "$dataset" 1 "$elapsed" "$rss" "$acc"
    echo "    hostile_fastp $dataset: $acc"
    rm -rf "$run/out" "$run/trimmed.fastq.gz"
}

D50=100M_50pct_high_lognormal_SE
D90=100M_90pct_high_lognormal_SE

run_kneaddata "$D50"
run_kneaddata "$D90"
run_hostile_fastp "$D50"
run_hostile_fastp "$D90"

mkdir -p "$PROJECT/results_auto_deacon/fill_100m_comparators_v2"
cp "$metrics_csv" "$PROJECT/results_auto_deacon/fill_100m_comparators_v2/"
cp "$timing_csv" "$PROJECT/results_auto_deacon/fill_100m_comparators_v2/"
echo "=== ALL DONE at $(date -Iseconds) ==="
