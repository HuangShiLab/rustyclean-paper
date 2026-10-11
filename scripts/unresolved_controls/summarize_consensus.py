#!/usr/bin/env python3
"""Summarize RustyClean-X production-evidence consensus against both arms."""

import csv
import statistics
import sys
from collections import defaultdict
from pathlib import Path


METRIC_COLUMNS = (
    "runtime_s",
    "f1",
    "host_input_retention_pct",
    "microbial_loss_pct",
    "host_output_fraction_pct",
)


def read_tsv(path):
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle, delimiter="\t"))


def read_csv(path):
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def read_production_arm(metrics_dir, tool):
    rows = []
    for path in sorted(metrics_dir.glob(f"*.{tool}.tsv")):
        dataset = path.name.removesuffix(f".{tool}.tsv")
        for row in read_csv(path):
            row["dataset"] = dataset
            rows.append(row)
    if not rows:
        raise FileNotFoundError(f"no production metrics for {tool} in {metrics_dir}")
    return rows


def summarize(rows):
    by_dataset = defaultdict(list)
    for row in rows:
        by_dataset[row["dataset"]].append(row)

    dataset_means = []
    for dataset, dataset_rows in sorted(by_dataset.items()):
        values = {
            column: statistics.mean(
                [float(row[column]) for row in dataset_rows]
            )
            for column in METRIC_COLUMNS
        }
        values["dataset"] = dataset
        values["replicates"] = len(dataset_rows)
        dataset_means.append(values)

    summary = {
        "datasets": len(dataset_means),
        "replicates_per_dataset": sorted({row["replicates"] for row in dataset_means}),
    }
    for column in METRIC_COLUMNS:
        summary[f"{column}_median_of_dataset_means"] = statistics.median(
            [row[column] for row in dataset_means]
        )
        summary[f"{column}_sd_across_datasets"] = (
            statistics.stdev(row[column] for row in dataset_means)
            if len(dataset_means) > 1
            else 0.0
        )
    return summary


def main():
    if len(sys.argv) != 4:
        raise SystemExit(
            "usage: summarize_consensus.py CONSENSUS_TSV PRODUCTION_METRICS_DIR OUTPUT_TSV"
        )

    consensus_path = Path(sys.argv[1])
    metrics_dir = Path(sys.argv[2]) / "metrics"
    output_path = Path(sys.argv[3])
    def normalized_consensus(strategy):
        normalized = []
        for row in read_tsv(consensus_path):
            if row["strategy"] != f"rustyclean_x_{strategy}":
                continue
            normalized.append(
                {
                    "dataset": row["dataset"],
                    "runtime_s": row["consensus_runtime_s"],
                    "f1": row["f1"],
                    "host_input_retention_pct": row["host_retention_pct"],
                    "microbial_loss_pct": row["microbial_loss_pct"],
                    "host_output_fraction_pct": row["host_output_fraction_pct"],
                }
            )
        if not normalized:
            raise ValueError(f"no consensus rows for strategy {strategy}")
        return normalized

    tool_rows = {
        "deacon": read_production_arm(metrics_dir, "deacon"),
        "cleanifier": read_production_arm(metrics_dir, "cleanifier"),
        "rustyclean_x_both_remove": normalized_consensus("both_remove"),
        "rustyclean_x_either_remove": normalized_consensus("either_remove"),
    }

    summaries = {tool: summarize(rows) for tool, rows in tool_rows.items()}
    output_path.parent.mkdir(parents=True, exist_ok=True)
    columns = ["tool"] + list(summaries["deacon"].keys())
    with output_path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, delimiter="\t")
        writer.writeheader()
        for tool in (
            "deacon",
            "cleanifier",
            "rustyclean_x_both_remove",
            "rustyclean_x_either_remove",
        ):
            writer.writerow({"tool": tool, **summaries[tool]})


if __name__ == "__main__":
    main()
