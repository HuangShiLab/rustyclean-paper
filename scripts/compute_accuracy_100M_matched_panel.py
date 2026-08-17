#!/usr/bin/env python3
"""Compute accuracy for 100M matched panel: RustyClean auto/sylph, KneadData, Hostile.

Directory layout:
  rustyclean_auto_sylph_100M_matched/rustyclean_auto_sylph/{dataset}/rep_{1,2,3}
  kneaddata_100M_matched/kneaddata/{dataset}/
  hostile_100M_matched/hostile/{dataset}/
"""
import csv
import gzip
import sys
from multiprocessing import Pool, cpu_count
from pathlib import Path


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


def find_clean_files(outdir: Path, tool: str) -> list[Path]:
    candidates = []
    if tool == "kneaddata":
        patterns = ["*clean*.fastq*"]
    elif tool == "hostile":
        patterns = ["*clean*.fastq*", "*.fastq.gz"]
    else:  # rustyclean
        patterns = ["*_clean_R1.fastq.gz", "*_clean.fastq.gz"]

    for pattern in patterns:
        candidates.extend(outdir.rglob(pattern))

    filtered = []
    for p in candidates:
        rel = str(p.relative_to(outdir)).lower()
        if any(skip in rel for skip in [".checkpoints", "checkpoints", "work/", "trimmed_", "bowtie2.", "kraken2.", "minimap2.", "classified.", "unclassified.", "contam"]):
            continue
        filtered.append(p)

    if not filtered:
        return []
    for pattern in ["*_clean_R1.fastq.gz", "*_clean.fastq.gz", "*clean*.fastq*"]:
        matches = [p for p in filtered if p.match(pattern)]
        if matches:
            return matches
    return [max(filtered, key=lambda p: p.stat().st_size)]


def process_item(args):
    data_dir, tool, dataset, rep, results_base = args
    if tool == "rustyclean_auto_sylph":
        outdir = results_base / "rustyclean_auto_sylph_100M_matched" / "rustyclean_auto_sylph" / dataset / f"rep_{rep}"
    elif tool == "kneaddata":
        outdir = results_base / "kneaddata_100M_matched" / "kneaddata" / dataset
    elif tool == "hostile":
        outdir = results_base / "hostile_100M_matched" / "hostile" / dataset
    else:
        return []

    gt_path = data_dir / dataset / "ground_truth_labels.txt"
    if not gt_path.exists():
        print(f"Warning: ground truth missing for {dataset}", file=sys.stderr)
        return []

    host_ids, microbe_ids = read_ground_truth(gt_path)
    clean_files = find_clean_files(outdir, tool)
    if not clean_files:
        print(f"  [{tool} {dataset} rep{rep}] skip: no clean FASTQ in {outdir}", file=sys.stderr)
        return []

    kept_ids = set()
    for f in clean_files:
        kept_ids.update(read_fastq_ids(f))

    metrics = compute_metrics(host_ids, microbe_ids, kept_ids)
    print(f"{tool} {dataset} rep{rep}: f1={metrics['f1']:.4f} precision={metrics['precision']:.4f} recall={metrics['recall']:.4f}")
    return [{
        "dataset": dataset,
        "rep": rep,
        "tool": tool,
        "accuracy": f"{metrics['accuracy']:.6f}",
        "precision": f"{metrics['precision']:.6f}",
        "recall": f"{metrics['recall']:.6f}",
        "f1": f"{metrics['f1']:.6f}",
        "tp": metrics["tp"],
        "fp": metrics["fp"],
        "tn": metrics["tn"],
        "fn": metrics["fn"],
    }]


def main():
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <data_dir> <results_base_dir> <output_csv>", file=sys.stderr)
        sys.exit(1)

    data_dir = Path(sys.argv[1])
    results_base = Path(sys.argv[2])
    out_csv = Path(sys.argv[3])
    out_csv.parent.mkdir(parents=True, exist_ok=True)

    datasets = ["100M_50pct_high_lognormal_SE", "100M_90pct_high_lognormal_SE"]
    tools = ["rustyclean_auto_sylph", "kneaddata", "hostile"]
    reps = [1, 2, 3]

    args = [(data_dir, tool, ds, rep, results_base) for ds in datasets for tool in tools for rep in reps]
    print(f"Processing {len(args)} combinations using up to {cpu_count()} cores")

    rows = []
    with Pool(processes=min(len(args), cpu_count())) as pool:
        for result in pool.imap_unordered(process_item, args):
            rows.extend(result)

    rows.sort(key=lambda r: (r["dataset"], r["tool"], int(r["rep"])))

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
