#!/usr/bin/env python3
"""Count retained-read TP/FP/FN/TN against a two-column ground-truth file."""
from __future__ import annotations

import argparse
import csv
import gzip
import json
from pathlib import Path


def open_text(path: str):
    if path.endswith(".gz"):
        return gzip.open(path, "rt")
    return open(path, "rt")


def fastq_ids(path: str) -> set[str]:
    ids = set()
    with open_text(path) as handle:
        for line_number, line in enumerate(handle, 1):
            if line_number % 4 == 1:
                ids.add(line[1:].split()[0])
    return ids


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tool", required=True)
    parser.add_argument("--dataset", required=True)
    parser.add_argument("--replicate", required=True, type=int)
    parser.add_argument("--truth", required=True)
    parser.add_argument("--fastq", required=True)
    parser.add_argument("--runtime-s", type=float, required=True)
    parser.add_argument("--max-rss-kb", type=float, default=0.0)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    host = set()
    microbe = set()
    with open_text(args.truth) as handle:
        for line in handle:
            if not line.strip():
                continue
            read_id, label = line.rstrip("\n").split("\t", 1)
            if label.strip().lower() in {"host", "human"}:
                host.add(read_id.split()[0])
            else:
                microbe.add(read_id.split()[0])

    retained = fastq_ids(args.fastq)
    tp = len(retained & microbe)
    fp = len(retained & host)
    fn = len(microbe - retained)
    tn = len(host - retained)
    host_total = fp + tn
    microbe_total = tp + fn
    retained_total = tp + fp
    precision = tp / (tp + fp) if tp + fp else 1.0
    recall = tp / (tp + fn) if tp + fn else 1.0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0

    row = {
        "tool": args.tool,
        "dataset": args.dataset,
        "replicate": args.replicate,
        "runtime_s": args.runtime_s,
        "max_rss_kb": args.max_rss_kb,
        "tp": tp,
        "fp": fp,
        "fn": fn,
        "tn": tn,
        "host_total": host_total,
        "microbe_total": microbe_total,
        "retained_total": retained_total,
        "precision": precision,
        "recall": recall,
        "f1": f1,
        "host_input_retention_pct": 100 * fp / host_total if host_total else 0.0,
        "microbial_loss_pct": 100 * fn / microbe_total if microbe_total else 0.0,
        "host_output_fraction_pct": 100 * fp / retained_total if retained_total else 0.0,
    }
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    is_new = not output.exists() or output.stat().st_size == 0
    with output.open("a", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(row), lineterminator="\n")
        if is_new:
            writer.writeheader()
        writer.writerow(row)
    print(json.dumps(row, sort_keys=True))


if __name__ == "__main__":
    main()
