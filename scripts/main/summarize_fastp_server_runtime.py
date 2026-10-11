#!/usr/bin/env python3
"""Summarize the iterative fastp -> Deacon server runtime benchmark."""

import csv
import statistics
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
INPUT_ROOT = ROOT / "data" / "fastp_deacon_io"
OUTPUT = INPUT_ROOT / "runtime_summary.csv"

FILES = {
    "5M_1pct_low_even_SE": INPUT_ROOT / "small_server_rep3.csv",
    "10M_10pct_med_even_SE": INPUT_ROOT / "small_server_rep3.csv",
    "30M_50pct_high_skewed_SE": INPUT_ROOT / "serverrep3_30M_50pct_high_skewed_SE.csv",
    "60M_90pct_high_lognormal_SE": INPUT_ROOT / "serverrep3_60M_90pct_high_lognormal_SE.csv",
    "100M_50pct_high_lognormal_SE": INPUT_ROOT / "serverrep3_100M_50pct_high_lognormal_SE.csv",
    "100M_90pct_high_lognormal_SE": INPUT_ROOT / "serverrep3_100M_90pct_high_lognormal_SE.csv",
}

# Published single-measurement comparator from
# manuscript/bioinformatics_application_note/source_data/hostile_runtime_components.csv.
HOSTILE_FASTP_S = {
    "5M_1pct_low_even_SE": 186.62,
    "10M_10pct_med_even_SE": 326.46,
    "30M_50pct_high_skewed_SE": 840.31,
    "60M_90pct_high_lognormal_SE": 1456.40,
    "100M_50pct_high_lognormal_SE": 1284.92,
    "100M_90pct_high_lognormal_SE": 1860.70,
}


def main() -> None:
    rows = []
    for dataset, path in FILES.items():
        with path.open(newline="", encoding="utf-8") as handle:
            matches = [row for row in csv.DictReader(handle) if row["dataset"] == dataset]
        if not matches:
            raise RuntimeError(f"no rows for {dataset} in {path}")
        runtimes = [float(row["wall_s"]) for row in matches if row["status"] == "ok"]
        warm_runtimes = runtimes[1:] if len(runtimes) > 2 else runtimes
        hostile = HOSTILE_FASTP_S[dataset]
        rows.append({
            "dataset": dataset,
            "reps": len(runtimes),
            "rustyclean_mean_all_s": round(statistics.mean(runtimes), 2),
            "rustyclean_sd_all_s": round(statistics.stdev(runtimes), 2) if len(runtimes) > 1 else 0,
            "rustyclean_warm_mean_s": round(statistics.mean(warm_runtimes), 2),
            "hostile_fastp_s": hostile,
            "speedup_all_reps": round(hostile / statistics.mean(runtimes), 2),
            "speedup_warm": round(hostile / statistics.mean(warm_runtimes), 2),
        })

    with OUTPUT.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

    print(f"wrote {OUTPUT}")


if __name__ == "__main__":
    main()
