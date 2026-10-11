#!/usr/bin/env python3
"""Summarize the paired RustyClean/Hostile parallel-demo benchmark."""

import argparse
import csv
import statistics
from collections import defaultdict
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("metrics_csv")
    parser.add_argument("output_csv")
    parser.add_argument("--output-markdown")
    args = parser.parse_args()

    rows = []
    with open(args.metrics_csv, newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            rows.append(row)

    grouped = defaultdict(list)
    for row in rows:
        grouped[(row["arm"], int(row["workers"]))].append(float(row["wall_s"]))
    summary = {
        key: {"mean": statistics.mean(values), "sd": statistics.stdev(values) if len(values) > 1 else 0.0}
        for key, values in grouped.items()
    }

    workers = sorted({worker for _, worker in grouped})
    baseline_workers = workers[0]
    output_fields = [
        "arm",
        "workers",
        "n",
        "mean_wall_s",
        "sd_wall_s",
        "speedup_vs_own_w1",
        "parallel_efficiency",
        "hostile_at_same_workers_s",
        "rustyclean_speedup_vs_hostile",
    ]
    output_rows = []
    for arm in ["rustyclean", "hostile_fastp"]:
        for worker in workers:
            key = (arm, worker)
            baseline_key = (arm, baseline_workers)
            mean = summary[key]["mean"]
            baseline = summary[baseline_key]["mean"]
            hostile_mean = summary[("hostile_fastp", worker)]["mean"]
            rustyclean_mean = summary[("rustyclean", worker)]["mean"]
            denominator = baseline * baseline_workers
            output_rows.append({
                "arm": arm,
                "workers": worker,
                "n": len(grouped[key]),
                "mean_wall_s": f"{mean:.3f}",
                "sd_wall_s": f"{summary[key]['sd']:.3f}",
                "speedup_vs_own_w1": f"{baseline / mean:.2f}",
                "parallel_efficiency": f"{(baseline / mean) * baseline_workers / worker:.2f}",
                "hostile_at_same_workers_s": f"{hostile_mean:.3f}",
                "rustyclean_speedup_vs_hostile": f"{hostile_mean / rustyclean_mean:.2f}" if arm == "rustyclean" else "",
            })

    with open(args.output_csv, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=output_fields)
        writer.writeheader()
        writer.writerows(output_rows)

    if args.output_markdown:
        with open(args.output_markdown, "w", encoding="utf-8") as handle:
            handle.write("| Tool | Workers | Mean wall (s) | Speedup vs own W=1 | Parallel efficiency | Hostile same W (s) | RC vs Hostile |\n")
            handle.write("|---|---:|---:|---:|---:|---:|---:|\n")
            for row in output_rows:
                handle.write(
                    f"| {row['arm']} | {row['workers']} | {row['mean_wall_s']} | "
                    f"{row['speedup_vs_own_w1']} | {row['parallel_efficiency']} | "
                    f"{row['hostile_at_same_workers_s']} | {row['rustyclean_speedup_vs_hostile'] or '—'} |\n"
                )


if __name__ == "__main__":
    main()
