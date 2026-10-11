#!/usr/bin/env python3
"""Compute ground-truth accuracy for one cleaned FASTQ."""

import csv
import gzip
import sys
from pathlib import Path


def read_ids(path: str) -> set[str]:
    opener = gzip.open if path.endswith(".gz") else open
    ids = set()
    with opener(path, "rt", encoding="utf-8", errors="ignore") as handle:
        for index, line in enumerate(handle):
            if index % 4:
                continue
            read_id = line.split()[0][1:].split("/")[0].split("#")[0]
            ids.add(read_id)
    return ids


def read_ground_truth(path: str) -> tuple[set[str], set[str]]:
    host_ids = set()
    microbe_ids = set()
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if "\t" not in line:
                continue
            read_id, label = line.strip().split("\t", 1)
            read_id = read_id.split("/")[0].split("#")[0]
            if label.lower() == "host":
                host_ids.add(read_id)
            else:
                microbe_ids.add(read_id)
    return host_ids, microbe_ids


def main() -> None:
    if len(sys.argv) != 7:
        raise SystemExit(
            "usage: compute_accuracy_one.py TOOL DATASET REP GROUND_TRUTH CLEAN_FASTQ OUTPUT_CSV"
        )
    tool, dataset, rep, truth_path, clean_path, output_csv = sys.argv[1:]
    host_ids, microbe_ids = read_ground_truth(truth_path)
    kept_ids = read_ids(clean_path)
    tp = len(kept_ids & microbe_ids)
    fp = len(kept_ids & host_ids)
    fn = len(microbe_ids - kept_ids)
    tn = len(host_ids - kept_ids)
    precision = tp / (tp + fp) if tp + fp else 1.0
    recall = tp / (tp + fn) if tp + fn else 1.0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    accuracy = (tp + tn) / (tp + tn + fp + fn)
    row = {
        "tool": tool,
        "dataset": dataset,
        "rep": rep,
        "accuracy": f"{accuracy:.6f}",
        "precision": f"{precision:.6f}",
        "recall": f"{recall:.6f}",
        "f1": f"{f1:.6f}",
        "tp": tp,
        "fp": fp,
        "tn": tn,
        "fn": fn,
    }
    output = Path(output_csv)
    output.parent.mkdir(parents=True, exist_ok=True)
    is_new = not output.exists()
    with output.open("a", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(row))
        if is_new:
            writer.writeheader()
        writer.writerow(row)


if __name__ == "__main__":
    main()
