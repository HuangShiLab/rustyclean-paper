#!/bin/bash
# Reparse time.log files for bowtie2-recheck benchmark and regenerate performance CSV.

PROJECT=/lustre1/g/aos_shihuang/rustyclean-paper/bowtie2_recheck_v2
OUT=$PROJECT/results
METRICS=$PROJECT/metrics/performance_bowtie2_recheck.csv

parse_time() {
    local t="$1"
    local s=0
    if [[ "$t" == *:* ]]; then
        local n
        n=$(echo "$t" | awk -F: '{print NF}')
        if [ "$n" -eq 2 ]; then
            s=$(echo "$t" | awk -F: '{print ($1*60)+$2}')
        elif [ "$n" -eq 3 ]; then
            s=$(echo "$t" | awk -F: '{print ($1*3600)+($2*60)+$3}')
        fi
    else
        s="$t"
    fi
    printf "%.2f" "$s"
}

printf "tool,dataset,rep,runtime_seconds,max_memory_kb,timestamp\n" > "$METRICS"

for dataset_dir in "$OUT"/*; do
    [ -d "$dataset_dir" ] || continue
    dataset=$(basename "$dataset_dir")
    for rep_dir in "$dataset_dir"/rep_*; do
        [ -d "$rep_dir" ] || continue
        rep=$(basename "$rep_dir" | sed 's/rep_//')
        time_log="$rep_dir/time.log"
        if [ ! -s "$time_log" ]; then
            echo "Warning: $time_log missing or empty"
            continue
        fi
        rt=$(awk -F": " '/Elapsed \(wall clock\) time/ {print $NF}' "$time_log")
        mem=$(awk '/Maximum resident set size/ {print $NF}' "$time_log")
        rt_sec=$(parse_time "$rt")
        ts=$(date -Iseconds -r "$time_log" 2>/dev/null || date -Iseconds)
        printf "rustyclean_bt2recheck,%s,%s,%s,%s,%s\n" "$dataset" "$rep" "$rt_sec" "$mem" "$ts" >> "$METRICS"
        echo "$dataset rep_$rep: runtime=${rt_sec}s memory=${mem}kb"
    done
done

echo "Reparsed metrics: $METRICS"
