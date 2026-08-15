#!/usr/bin/env python3
"""Compute accuracy for RustyClean sylph+bowtie2 outputs in parallel."""
import csv
import gzip
import sys
from pathlib import Path
from multiprocessing import Pool, cpu_count


def read_fastq_ids(path: Path) -> set:
    ids = set()
    if str(path).endswith(".gz"):
        opener = lambda: gzip.open(path, "rt", encoding="utf-8", errors="ignore")
    else:
        opener = lambda: open(path, "r", encoding="utf-8", errors="ignore")
    with opener() as fh:
        for i, line in enumerate(fh):
            if i % 4 == 0:
                rid = line.split()[0][1:]
                rid = rid.split("/")[0]
                rid = rid.split("#")[0]
                ids.add(rid)
    return ids


def read_ground_truth(gt_path: Path) -> tuple:
    host_ids = set()
    microbe_ids = set()
    with open(gt_path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or "\t" not in line:
                continue
            rid, label = line.split("\t", 1)
            rid = rid.split("/")[0]
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
    total = tp + tn + fp + fn
    accuracy = (tp + tn) / total if total else 0
    precision = tp / (tp + fp) if (tp + fp) else 0
    recall = tp / (tp + fn) if (tp + fn) else 0
    if (tp + fp) == 0 and (tp + fn) == 0:
        # No microbes to recover and none predicted: perfect negative prediction.
        f1 = 1.0
    else:
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


def find_clean_file(outdir: Path) -> Path:
    patterns = ["*_clean_R1.fastq.gz", "*_clean.fastq.gz"]
    for pattern in patterns:
        matches = list(outdir.rglob(pattern))
        if matches:
            return max(matches, key=lambda p: p.stat().st_size)
    raise FileNotFoundError(f"No cleaned FASTQ found in {outdir}")


def process_dataset(args):
    data_dir, project_dir, dataset = args
    gt_path = data_dir / dataset / "ground_truth_labels.txt"
    if not gt_path.exists():
        print(f"Warning: ground truth missing for {dataset}", file=sys.stderr)
        return []

    host_ids, microbe_ids = read_ground_truth(gt_path)
    rows = []
    out_base = project_dir / "results" / dataset
    for rep_dir in sorted(out_base.glob("rep_*")):
        rep = rep_dir.name.split("_")[-1]
        try:
            clean_file = find_clean_file(rep_dir)
        except FileNotFoundError as e:
            print(f"  [{dataset} rep{rep}] skip: {e}", file=sys.stderr)
            continue
        kept_ids = read_fastq_ids(clean_file)
        metrics = compute_metrics(host_ids, microbe_ids, kept_ids)
        rows.append({
            "dataset": dataset,
            "rep": rep,
            "tool": "rustyclean_sylph",
            "accuracy": f"{metrics['accuracy']:.6f}",
            "precision": f"{metrics['precision']:.6f}",
            "recall": f"{metrics['recall']:.6f}",
            "f1": f"{metrics['f1']:.6f}",
            "tp": metrics["tp"],
            "fp": metrics["fp"],
            "tn": metrics["tn"],
            "fn": metrics["fn"],
        })
        print(f"{dataset} rep{rep}: f1={metrics['f1']:.4f} precision={metrics['precision']:.4f} recall={metrics['recall']:.4f}")
    return rows


def main():
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <data_dir> <project_dir> <output_csv>", file=sys.stderr)
        sys.exit(1)

    data_dir = Path(sys.argv[1])
    project_dir = Path(sys.argv[2])
    out_csv = Path(sys.argv[3])
    out_base = project_dir / "results"

    datasets = sorted([d.name for d in out_base.iterdir() if d.is_dir()])
    print(f"Processing {len(datasets)} datasets using up to {cpu_count()} cores")

    args = [(data_dir, project_dir, ds) for ds in datasets]
    n_workers = min(len(datasets), cpu_count())

    rows = []
    with Pool(processes=n_workers) as pool:
        for result in pool.imap_unordered(process_dataset, args):
            rows.extend(result)

    rows.sort(key=lambda r: (r["dataset"], int(r["rep"])))

    with open(out_csv, "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=[
            "dataset", "rep", "tool", "accuracy", "precision", "recall", "f1",
            "tp", "fp", "tn", "fn"
        ])
        writer.writeheader()
        writer.writerows(rows)

    print(f"Wrote {len(rows)} rows to {out_csv}")


if __name__ == "__main__":
    main()
