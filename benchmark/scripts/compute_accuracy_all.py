#!/usr/bin/env python3
"""Compute accuracy metrics for RustyClean, Hostile and KneadData outputs.

Reads ground_truth_labels.txt for each dataset and compares it to the read IDs
retained in each tool's cleaned output. Outputs a CSV with accuracy, precision,
recall, F1 and raw counts.

Run on HPC:
    python compute_accuracy_all.py /scr/u/shihuang/rustyclean-paper \
        /scr/u/shihuang/rustyclean-paper/accuracy_comparison.csv
"""

import csv
import gzip
import os
import re
import subprocess
import sys
from pathlib import Path

DATASETS = [
    "5M_1pct_low_even_SE",
    "10M_10pct_med_even_SE",
    "30M_50pct_high_skewed_SE",
    "60M_90pct_high_lognormal_SE",
]


def find_clean_file(outdir: Path, tool: str) -> Path:
    """Locate the final cleaned FASTQ file for a tool."""
    if not outdir.exists():
        raise FileNotFoundError(f"Output directory not found: {outdir}")

    if tool.startswith("rustyclean"):
        patterns = ["*_clean_R1.fastq.gz", "*_clean.fastq.gz"]
    elif tool == "hostile_raw":
        patterns = ["*.fastq.gz"]
    elif tool == "kneaddata":
        # Prefer *clean*.fastq; fall back to any non-intermediate .fastq
        clean = list(outdir.rglob("*clean*.fastq"))
        if clean:
            return max(clean, key=lambda p: p.stat().st_size)
        patterns = ["*.fastq"]
    else:
        patterns = ["*.fastq.gz", "*.fastq"]

    for pattern in patterns:
        matches = list(outdir.rglob(pattern))
        if matches:
            # For Hostile, exclude anything that looks intermediate/contam
            if tool == "hostile_raw":
                matches = [
                    m for m in matches
                    if "contam" not in m.name and "trimmed" not in m.name and "repeats" not in m.name
                ]
            if matches:
                return max(matches, key=lambda p: p.stat().st_size)
    raise FileNotFoundError(f"No cleaned FASTQ found in {outdir}")


def read_fastq_ids(path: Path) -> set:
    """Return set of read IDs from a FASTQ file (gzipped or plain)."""
    ids = set()
    if str(path).endswith(".gz"):
        opener = lambda: gzip.open(path, "rt", encoding="utf-8", errors="ignore")
    else:
        opener = lambda: open(path, "r", encoding="utf-8", errors="ignore")

    with opener() as fh:
        for i, line in enumerate(fh):
            if i % 4 == 0:
                # @read_id/1 or @read_id
                rid = line.split()[0][1:].split("/")[0]
                ids.add(rid)
    return ids


def read_ground_truth(gt_path: Path) -> tuple:
    """Return (host_ids, microbe_ids)."""
    host_ids = set()
    microbe_ids = set()
    with open(gt_path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or "\t" not in line:
                continue
            rid, label = line.split("\t", 1)
            if label.lower() == "host":
                host_ids.add(rid)
            else:
                microbe_ids.add(rid)
    return host_ids, microbe_ids


def compute_metrics(host_ids: set, microbe_ids: set, kept_ids: set) -> dict:
    tp = len(kept_ids & microbe_ids)
    fp = len(kept_ids & host_ids)
    fn = len(microbe_ids - kept_ids)
    tn = len(host_ids - kept_ids)

    accuracy = (tp + tn) / (tp + tn + fp + fn) if (tp + tn + fp + fn) else 0
    precision = tp / (tp + fp) if (tp + fp) else 0
    recall = tp / (tp + fn) if (tp + fn) else 0
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) else 0

    return {
        "accuracy": accuracy,
        "precision": precision,
        "recall": recall,
        "f1": f1,
        "tp": tp,
        "fp": fp,
        "tn": tn,
        "fn": fn,
    }


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <project_dir> <output_csv>", file=sys.stderr)
        sys.exit(1)

    project_dir = Path(sys.argv[1])
    out_csv = Path(sys.argv[2])

    data_dir = project_dir / "data" / "enhanced"
    fair_dir = project_dir / "rc_auto_skipqc_hostile_v2"
    auto_dir = project_dir / "auto_vs_kneaddata"

    tool_dirs = {
        "rustyclean_auto_skipqc": (fair_dir, "{dataset}/rc_auto_skipqc"),
        "hostile_raw": (fair_dir, "{dataset}/hostile_raw"),
        "rustyclean_auto": (auto_dir, "{dataset}/rc_auto"),
        "kneaddata": (auto_dir, "{dataset}/kneaddata"),
    }

    rows = []
    for dataset in DATASETS:
        gt_path = data_dir / dataset / "ground_truth_labels.txt"
        if not gt_path.exists():
            print(f"Warning: ground truth missing for {dataset}", file=sys.stderr)
            continue

        print(f"Loading ground truth for {dataset} ...")
        host_ids, microbe_ids = read_ground_truth(gt_path)
        all_ids = host_ids | microbe_ids
        print(f"  host={len(host_ids)}, microbe={len(microbe_ids)}")

        for tool, (base_dir, rel_pattern) in tool_dirs.items():
            outdir = base_dir / rel_pattern.format(dataset=dataset)
            try:
                clean_file = find_clean_file(outdir, tool)
            except FileNotFoundError as e:
                print(f"  [{tool}] skip: {e}", file=sys.stderr)
                continue

            print(f"  [{tool}] reading {clean_file.name} ...")
            kept_ids = read_fastq_ids(clean_file)
            print(f"  [{tool}] kept={len(kept_ids)}")

            metrics = compute_metrics(host_ids, microbe_ids, kept_ids)
            rows.append({
                "dataset": dataset,
                "tool": tool,
                "accuracy": f"{metrics['accuracy']:.6f}",
                "precision": f"{metrics['precision']:.6f}",
                "recall": f"{metrics['recall']:.6f}",
                "f1": f"{metrics['f1']:.6f}",
                "tp": metrics["tp"],
                "fp": metrics["fp"],
                "tn": metrics["tn"],
                "fn": metrics["fn"],
            })

    with open(out_csv, "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=[
            "dataset", "tool", "accuracy", "precision", "recall", "f1",
            "tp", "fp", "tn", "fn"
        ])
        writer.writeheader()
        writer.writerows(rows)

    print(f"Wrote {len(rows)} rows to {out_csv}")


if __name__ == "__main__":
    main()
