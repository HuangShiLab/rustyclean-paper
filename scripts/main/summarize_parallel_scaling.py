#!/usr/bin/env python3
"""Summarize legacy W-by-T parallel scaling runs."""

import csv
import glob
from collections import defaultdict
from pathlib import Path


def main() -> None:
    rows = []
    for path in glob.glob("data/parallel_scaling_legacy/*.csv"):
        with open(path, newline="", encoding="utf-8") as handle:
            rows.extend(csv.DictReader(handle))
    grouped = {(row["arm"], int(row["workers"])): float(row["wall_seconds"]) for row in rows}
    output_path = Path("data/parallel_scaling_legacy/summary.csv")
    fields = [
        "arm", "workers", "wall_s", "speedup_vs_own_w1",
        "parallel_efficiency", "rustyclean_speedup_vs_hostile",
    ]
    with output_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for arm in ["rustyclean_batch", "rustyclean_batch_skipqc", "hostile"]:
            baseline = grouped[(arm, 1)]
            for workers in [1, 2, 4, 8, 16]:
                wall = grouped[(arm, workers)]
                speedup = baseline / wall
                efficiency = speedup / workers
                ratio = ""
                if arm.startswith("rustyclean"):
                    ratio = f"{grouped[('hostile', workers)] / wall:.2f}"
                writer.writerow({
                    "arm": arm,
                    "workers": workers,
                    "wall_s": f"{wall:.2f}",
                    "speedup_vs_own_w1": f"{speedup:.2f}",
                    "parallel_efficiency": f"{efficiency:.2f}",
                    "rustyclean_speedup_vs_hostile": ratio,
                })


if __name__ == "__main__":
    main()
