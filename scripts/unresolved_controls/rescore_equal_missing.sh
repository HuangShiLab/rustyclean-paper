#!/bin/bash
set -euo pipefail
BASE=/lustre1/g/aos_shihuang/rustyclean-paper
DATA=/scr/u/shihuang/rustyclean-paper/data/enhanced
ACC="$BASE/runs/unresolved_controls/equal_thread_panel/metrics/accuracy.csv"
OUT="$BASE/runs/unresolved_controls/equal_thread_panel/outputs"
PY="$BASE/scripts/unresolved_controls/score_retained_reads.py"
python3 "$PY" rustyclean_auto auto_deacon_default 100M_90pct_high_lognormal_SE 1 \
  "$DATA/100M_90pct_high_lognormal_SE/ground_truth_labels.txt" \
  "$OUT/100M_90pct_high_lognormal_SE/rustyclean/rep1" "$ACC"
for dataset in \
  5M_1pct_low_even_SE 10M_10pct_med_even_SE 30M_50pct_high_skewed_SE \
  60M_90pct_high_lognormal_SE 100M_50pct_high_lognormal_SE 100M_90pct_high_lognormal_SE; do
  python3 "$PY" fastp_hostile fastp_plus_hostile "$dataset" 1 \
    "$DATA/$dataset/ground_truth_labels.txt" \
    "$OUT/$dataset/hostile/rep1" "$ACC"
done
python3 - <<'PY'
import shutil
from pathlib import Path
p = Path('/lustre1/g/aos_shihuang/rustyclean-paper/runs/unresolved_controls/equal_thread_panel/outputs')
if p.exists():
    shutil.rmtree(p)
PY
