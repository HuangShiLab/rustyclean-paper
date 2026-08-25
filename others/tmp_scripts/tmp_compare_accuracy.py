#!/usr/bin/env python3
"""
Compare host-removal accuracy against ground-truth labels.

Usage:
    python compare_accuracy.py <data_dir> <results_dir> <dataset1> [<dataset2> ...]

Expects:
    <data_dir>/<dataset>/ground_truth_labels.txt
    <results_dir>/<tool>/<dataset>/...*.fastq.gz

Tools detected from subdirectories of <results_dir>.
"""

import gzip
import os
import sys
from pathlib import Path


def normalize_read_id(raw: str) -> str:
    rid = raw.split()[0]
    rid = rid.lstrip("@")
    if rid.endswith("/1") or rid.endswith("/2"):
        rid = rid[:-2]
    return rid


def read_ground_truth(gt_path: Path):
    truth = {}
    with open(gt_path) as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line or "\t" not in line:
                continue
            rid, label = line.split("\t", 1)
            truth[normalize_read_id(rid)] = label.lower().startswith("host")
    return truth


def collect_output_ids(out_dir: Path):
    ids = set()
    for fq in out_dir.rglob("*.fastq.gz"):
        # Skip empty / temp files
        if fq.stat().st_size == 0:
            continue
        with gzip.open(fq, "rt", encoding="utf-8", errors="replace") as fh:
            for i, line in enumerate(fh):
                if i % 4 != 0:
                    continue
                if not line:
                    continue
                ids.add(normalize_read_id(line))
    return ids


def evaluate(truth: dict, output_ids: set):
    tp = fp = tn = fn = 0
    for rid, is_host in truth.items():
        predicted_host = rid not in output_ids
        if is_host and predicted_host:
            tp += 1
        elif is_host and not predicted_host:
            fn += 1
        elif not is_host and predicted_host:
            fp += 1
        else:
            tn += 1

    precision = tp / (tp + fp) if (tp + fp) else 0.0
    recall = tp / (tp + fn) if (tp + fn) else 0.0
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) else 0.0
    accuracy = (tp + tn) / (tp + tn + fp + fn) if (tp + tn + fp + fn) else 0.0
    return {
        "total": len(truth),
        "tp": tp,
        "fp": fp,
        "tn": tn,
        "fn": fn,
        "precision": precision,
        "recall": recall,
        "f1": f1,
        "accuracy": accuracy,
    }


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        sys.exit(1)

    data_dir = Path(sys.argv[1])
    results_dir = Path(sys.argv[2])
    datasets = sys.argv[3:]

    # Auto-detect tools from results_dir subdirectories
    tools = sorted([
        p.name for p in results_dir.iterdir()
        if p.is_dir() and not p.name.startswith(".") and p.name != "metrics" and p.name != "logs"
    ])
    if not tools:
        print(f"No tool directories found in {results_dir}", file=sys.stderr)
        sys.exit(1)
    print(f"Detected tools: {tools}")

    rows = []
    for dataset in datasets:
        gt_path = data_dir / dataset / "ground_truth_labels.txt"
        if not gt_path.exists():
            print(f"Warning: ground truth not found: {gt_path}", file=sys.stderr)
            continue
        truth = read_ground_truth(gt_path)
        for tool in tools:
            tool_dir = results_dir / tool / dataset
            if not tool_dir.exists():
                continue
            output_ids = collect_output_ids(tool_dir)
            metrics = evaluate(truth, output_ids)
            rows.append({"dataset": dataset, "tool": tool, **metrics})

    if not rows:
        print("No results to report.")
        return

    out_csv = results_dir / "metrics" / "accuracy.csv"
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    with open(out_csv, "w") as fh:
        header = ["dataset", "tool", "total", "tp", "fp", "tn", "fn",
                  "precision", "recall", "f1", "accuracy"]
        fh.write(",".join(header) + "\n")
        for r in rows:
            fh.write(",".join(str(r[h]) for h in header) + "\n")

    print(f"Wrote accuracy metrics to {out_csv}")
    for r in rows:
        print(f"{r['dataset']:40s} {r['tool']:20s} "
              f"F1={r['f1']:.4f} Acc={r['accuracy']:.4f} "
              f"Prec={r['precision']:.4f} Rec={r['recall']:.4f}")


if __name__ == "__main__":
    main()
