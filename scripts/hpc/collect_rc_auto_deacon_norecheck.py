#!/usr/bin/env python3
"""Collect performance and per-read accuracy for AUTO with verification disabled."""
from __future__ import annotations

import csv
import gzip
import sys
from pathlib import Path

DATASETS = [
    "5M_1pct_low_even_SE",
    "10M_10pct_med_even_SE",
    "30M_50pct_high_skewed_SE",
    "60M_90pct_high_lognormal_SE",
    "100M_50pct_high_lognormal_SE",
    "100M_90pct_high_lognormal_SE",
]


def fastq_ids(path: Path) -> set[str]:
    opener = gzip.open if path.suffix == ".gz" else open
    ids: set[str] = set()
    with opener(path, "rt", encoding="utf-8", errors="ignore") as handle:
        for index, line in enumerate(handle):
            if index % 4 == 0:
                read_id = line.split()[0][1:]
                read_id = read_id.split("/")[0].split("#")[0]
                ids.add(read_id)
    return ids


def clean_fastq(output_dir: Path) -> Path | None:
    candidates: list[Path] = []
    for pattern in ("*_clean_R1.fastq.gz", "*_clean.fastq.gz", "*clean*.fastq*"):
        candidates.extend(output_dir.rglob(pattern))
    candidates = [
        path for path in candidates
        if "checkpoint" not in path.relative_to(output_dir).as_posix().lower()
        and "trimmed_" not in path.name.lower()
        and "bowtie2." not in path.name.lower()
    ]
    return max(candidates, key=lambda path: path.stat().st_size) if candidates else None


def ground_truth(path: Path) -> tuple[set[str], set[str]]:
    host: set[str] = set()
    microbe: set[str] = set()
    with path.open() as handle:
        for line in handle:
            if "\t" not in line:
                continue
            read_id, label = line.strip().split("\t", 1)
            read_id = read_id.split("/")[0].split("#")[0]
            (host if label.lower() == "host" else microbe).add(read_id)
    return host, microbe


def main(data_dir: Path, results_dir: Path, output_csv: Path) -> None:
    performance: dict[tuple[str, int], tuple[float, float]] = {}
    performance_path = results_dir / "metrics" / "performance.csv"
    with performance_path.open(newline="") as handle:
        for row in csv.DictReader(handle):
            try:
                performance[(row["dataset"], int(row["rep"]))] = (
                    float(row["runtime_seconds"]),
                    float(row["max_memory_kb"]) / 1024 / 1024,
                )
            except (KeyError, ValueError):
                continue

    output_csv.parent.mkdir(parents=True, exist_ok=True)
    fields = [
        "dataset", "rep", "runtime_s", "memory_gib", "tp", "fp", "fn", "tn",
        "accuracy", "precision", "recall", "f1", "microbial_loss_pct",
        "host_carry_pct",
    ]
    with output_csv.open("w", newline="") as out_handle:
        writer = csv.DictWriter(out_handle, fieldnames=fields)
        writer.writeheader()
        for dataset in DATASETS:
            gt_host, gt_microbe = ground_truth(data_dir / dataset / "ground_truth_labels.txt")
            for rep in (1, 2, 3):
                row = {field: "" for field in fields}
                row.update(dataset=dataset, rep=rep)
                if (dataset, rep) in performance:
                    runtime, memory = performance[(dataset, rep)]
                    row.update(runtime_s=f"{runtime:.2f}", memory_gib=f"{memory:.4f}")
                output_dir = results_dir / "rustyclean_auto_deacon_norecheck" / dataset / f"rep_{rep}"
                clean = clean_fastq(output_dir)
                if clean is None:
                    writer.writerow(row)
                    continue
                kept = fastq_ids(clean)
                tp = len(kept & gt_microbe)
                fp = len(kept & gt_host)
                fn = len(gt_microbe - kept)
                tn = len(gt_host - kept)
                precision = tp / (tp + fp) if tp + fp else 0.0
                recall = tp / (tp + fn) if tp + fn else 0.0
                f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
                row.update(
                    tp=tp, fp=fp, fn=fn, tn=tn,
                    accuracy=f"{(tp + tn) / (tp + tn + fp + fn):.6f}",
                    precision=f"{precision:.6f}",
                    recall=f"{recall:.6f}",
                    f1=f"{f1:.6f}",
                    microbial_loss_pct=f"{fp / (fp + tn) * 100:.4f}" if fp + tn else "0.0000",
                    host_carry_pct=f"{fn / (tp + fp) * 100:.4f}" if tp + fp else "0.0000",
                )
                writer.writerow(row)
    print(output_csv)


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit(f"Usage: {sys.argv[0]} <data_dir> <results_dir> <output_csv>")
    main(Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]))
