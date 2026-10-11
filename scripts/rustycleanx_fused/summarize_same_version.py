#!/usr/bin/env python3
"""Collate fused full-run and existing same-data comparator metrics."""
import argparse
import csv
import statistics
from collections import defaultdict
from pathlib import Path


def fmean(values):
    return statistics.fmean(values) if values else float("nan")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--fused-root", required=True)
    parser.add_argument("--production-metrics", required=True)
    parser.add_argument("--combined-accuracy", required=True)
    parser.add_argument("--combined-performance", required=True)
    parser.add_argument("--datasets", nargs="+", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    tools = defaultdict(lambda: defaultdict(list))
    for dataset in args.datasets:
        fused_path = Path(args.fused_root) / dataset / "metrics.tsv"
        with fused_path.open() as handle:
            for row in csv.DictReader(handle, delimiter="\t"):
                tools["rustycleanx_fused"]["runtime_s"].append(float(row["seconds"]))
                tools["rustycleanx_fused"]["host_retention_pct"].append(float(row["host_retention_pct"]))
                tools["rustycleanx_fused"]["microbial_loss_pct"].append(float(row["microbial_loss_pct"]))
                tools["rustycleanx_fused"]["f1"].append(float(row["f1"]))

        for tool in ("deacon", "cleanifier"):
            path = Path(args.production_metrics) / f"{dataset}.{tool}.tsv"
            with path.open() as handle:
                for row in csv.DictReader(handle):
                    tools[tool]["runtime_s"].append(float(row["runtime_s"]))
                    tools[tool]["host_retention_pct"].append(float(row["host_input_retention_pct"]))
                    tools[tool]["microbial_loss_pct"].append(float(row["microbial_loss_pct"]))
                    tools[tool]["f1"].append(float(row["f1"]))

    with Path(args.combined_accuracy).open() as handle:
        for row in csv.DictReader(handle):
            if row["dataset"] not in args.datasets:
                continue
            if row["tool"] == "fastp_hostile":
                tools["fastp_hostile"]["host_retention_pct"].append(float(row["host_input_retention_pct"]))
                tools["fastp_hostile"]["microbial_loss_pct"].append(float(row["microbial_loss_pct"]))
                tools["fastp_hostile"]["f1"].append(float(row["f1"]))
            if row["tool"] == "kneaddata":
                tools["kneaddata"]["host_retention_pct"].append(float(row["host_input_retention_pct"]))
                tools["kneaddata"]["microbial_loss_pct"].append(float(row["microbial_loss_pct"]))
                tools["kneaddata"]["f1"].append(float(row["f1"]))

    with Path(args.combined_performance).open() as handle:
        for row in csv.DictReader(handle):
            if row["dataset"] not in args.datasets:
                continue
            if row["tool"] == "fastp_hostile":
                tools["fastp_hostile"]["runtime_s"].append(float(row["runtime_s"]))
            if row["tool"] == "kneaddata":
                tools["kneaddata"]["runtime_s"].append(float(row["runtime_s"]))

    fields = ["tool", "runs", "runtime_s_mean", "host_retention_pct_mean",
              "microbial_loss_pct_mean", "f1_mean"]
    with Path(args.output).open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t")
        writer.writeheader()
        for tool in ("rustycleanx_fused", "deacon", "cleanifier", "fastp_hostile", "kneaddata"):
            values = tools[tool]
            writer.writerow({
                "tool": tool,
                "runs": len(values["f1"]),
                "runtime_s_mean": fmean(values["runtime_s"]),
                "host_retention_pct_mean": fmean(values["host_retention_pct"]),
                "microbial_loss_pct_mean": fmean(values["microbial_loss_pct"]),
                "f1_mean": fmean(values["f1"]),
            })


if __name__ == "__main__":
    main()
