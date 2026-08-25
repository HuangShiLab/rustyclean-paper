#!/bin/bash
#SBATCH --job-name=rc_postprocess
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=4:00:00
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err

set -e

source /group/aos_shihuang/conda/etc/profile.d/conda.sh
conda activate /lustre1/g/aos_shihuang/rustyclean-paper/.conda_envs/rustyclean-benchmark

export PATH="/group/aos_shihuang/conda/envs/fastp/bin:/group/aos_shihuang/conda/envs/kraken2/bin:${PATH}"

SCRIPT_DIR="/lustre1/g/aos_shihuang/rustyclean-paper/scripts"
DATA_DIR="/scr/u/shihuang/rustyclean-paper/data/enhanced"
CROSS_DATA_DIR="/scr/u/shihuang/rustyclean-paper/data/cross_species"
ANALYSIS_DIR="/lustre1/g/aos_shihuang/rustyclean-paper/results_analysis"

mkdir -p "${ANALYSIS_DIR}"

log() { echo "[$(date +%H:%M:%S)] $*"; }

# ---------------------------------------------------------------------------
# Human 4 datasets: accuracy comparison
# ---------------------------------------------------------------------------
HUMAN4_DATASETS=(
    "5M_1pct_low_even_SE"
    "10M_10pct_med_even_SE"
    "30M_50pct_high_skewed_SE"
    "60M_90pct_high_lognormal_SE"
)

log "=== Human4 accuracy comparison ==="
python3 "${SCRIPT_DIR}/compare_accuracy.py" \
    "/scr/u/shihuang/rustyclean-paper/data/enhanced" \
    "/lustre1/g/aos_shihuang/rustyclean-paper/results_hostile_centrifuge" \
    "${HUMAN4_DATASETS[@]}" \
    > "${ANALYSIS_DIR}/human4_accuracy.log" 2>&1

# ---------------------------------------------------------------------------
# RustyClean mode comparison: decision boundary
# ---------------------------------------------------------------------------
log "=== Mode decision boundary analysis ==="
python3 "${SCRIPT_DIR}/analyze_decision_boundary.py" \
    "/scr/u/shihuang/rustyclean-paper/data/enhanced" \
    "/lustre1/g/aos_shihuang/rustyclean-paper/results_rc_modes" \
    "${ANALYSIS_DIR}" \
    > "${ANALYSIS_DIR}/mode_decision_boundary.log" 2>&1

# ---------------------------------------------------------------------------
# AUTO scaling summary
# ---------------------------------------------------------------------------
log "=== AUTO scaling summary ==="
python3 /dev/stdin << 'PYEOF'
import json
from pathlib import Path
import pandas as pd

metrics_dir = Path("/lustre1/g/aos_shihuang/rustyclean-paper/results_auto_scale/metrics")
analysis_dir = Path("/lustre1/g/aos_shihuang/rustyclean-paper/results_analysis")
analysis_dir.mkdir(parents=True, exist_ok=True)

csv_path = metrics_dir / "auto_scale.csv"
if csv_path.exists():
    df = pd.read_csv(csv_path)
    summary = []
    for _, row in df.iterrows():
        summary.append({
            "scale": int(row["scale"]),
            "n_samples": int(row["n_samples"]),
            "runtime_seconds": float(row["runtime_seconds"]),
            "runtime_hours": float(row["runtime_seconds"]) / 3600,
            "max_memory_gb": float(row["max_memory_kb"]) / 1024 / 1024,
            "chosen_bowtie2": int(row["chosen_bowtie2"]),
            "chosen_kraken2": int(row["chosen_kraken2"]),
            "branch_correct": row["branch_correct"],
        })
    with open(analysis_dir / "auto_scaling_summary.json", "w") as fh:
        json.dump(summary, fh, indent=2)
    print(json.dumps(summary, indent=2))
else:
    print("auto_scale.csv not found")
PYEOF

# ---------------------------------------------------------------------------
# Cross-species accuracy comparison (if data exists)
# ---------------------------------------------------------------------------
if [ -d "${CROSS_DATA_DIR}" ]; then
    log "=== Cross-species accuracy comparison ==="
    CROSS_DATASETS=$(ls "${CROSS_DATA_DIR}" | grep -E "^human_|^mouse_|^rat_|^pig_|^rice_|^monkey_" | sort)
    if [ -n "${CROSS_DATASETS}" ]; then
        python3 "${SCRIPT_DIR}/compare_accuracy.py" \
            "${CROSS_DATA_DIR}" \
            "/lustre1/g/aos_shihuang/rustyclean-paper/results_cross_species" \
            ${CROSS_DATASETS} \
            > "${ANALYSIS_DIR}/cross_species_accuracy.log" 2>&1
    else
        log "No cross-species datasets found yet"
    fi
else
    log "Cross-species data dir not found, skipping"
fi

log "Post-processing complete. Results in ${ANALYSIS_DIR}"
