#!/usr/bin/env python3
"""Score retained reads using audited TP/FP/FN/TN count definitions.

TP=retained microbe, FP=retained host, FN=removed microbe, TN=removed host.
INPUT may be FASTQ file(s), comma-separated mate files, or a result directory.
"""
from __future__ import annotations

import csv
import gzip
import hashlib
import json
import sys
from pathlib import Path

FIELDS = [
    "tool", "condition", "dataset", "rep", "retained_fastqs",
    "tp", "fp", "fn", "tn", "unmapped_kept", "host_total", "microbe_total",
    "retained_total", "accuracy", "precision", "recall", "f1",
    "host_input_retention_pct", "microbial_loss_pct", "host_output_fraction_pct",
]


def stable_id(raw: str) -> int:
    token = raw.split()[0].split("/")[0].split("#")[0]
    ident = token[1:] if token.startswith("@") else token
    return int.from_bytes(hashlib.blake2b(ident.encode(), digest_size=8).digest(), "big")


def fastq_ids(path: Path) -> set[int]:
    opener = gzip.open if path.suffix == ".gz" else open
    ids: set[int] = set()
    with opener(path, "rt", encoding="utf-8", errors="ignore") as handle:
        for index, line in enumerate(handle):
            if index % 4 == 0:
                ids.add(stable_id(line))
    return ids


def truth_sets(path: Path) -> tuple[set[int], set[int]]:
    host: set[int] = set()
    microbe: set[int] = set()
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            if "\t" not in line:
                continue
            raw, label = line.rstrip("\n").split("\t", 1)
            (host if label.strip().lower() in {"host", "human"} else microbe).add(stable_id(raw))
    return host, microbe


def select_retained(directory: Path) -> list[Path]:
    patterns = ("*_clean_R1.fastq*", "*_clean_R2.fastq*", "*_clean.fastq*",
                "*_keep_1.fastq*", "*_keep_2.fastq*", "*_keep.fastq*",
                "*clean_1.fastq*", "*clean_2.fastq*", "*clean*.fastq*")
    found: set[Path] = set()
    for pattern in patterns:
        found.update(directory.rglob(pattern))
    bad = ("checkpoint", ".tmp", "filtered", "removed", "bowtie2.")
    candidates = [p for p in found if not any(x in p.as_posix().lower() for x in bad)]
    return sorted(candidates, key=lambda p: (len(p.name), p.name))


def resolve_input(value: str) -> list[Path]:
    path = Path(value)
    if path.is_dir():
        selected = select_retained(path)
        if not selected:
            raise FileNotFoundError(f"no retained FASTQ under {path}")
        return selected
    paths = [Path(item) for item in value.split(",") if item]
    missing = [p for p in paths if not p.is_file()]
    if missing:
        raise FileNotFoundError(f"missing FASTQ inputs: {missing}")
    return paths


def main() -> None:
    if len(sys.argv) != 8:
        raise SystemExit("usage: TOOL CONDITION DATASET REP TRUTH INPUT OUTPUT")
    tool, condition, dataset, rep, truth_value, input_value, output_value = sys.argv[1:]
    host, microbe = truth_sets(Path(truth_value))
    files = resolve_input(input_value)
    kept: set[int] = set()
    for path in files:
        kept.update(fastq_ids(path))
    tp = len(kept & microbe)
    fp = len(kept & host)
    fn = len(microbe - kept)
    tn = len(host - kept)
    precision = tp / (tp + fp) if tp + fp else 1.0
    recall = tp / (tp + fn) if tp + fn else 1.0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    total = tp + fp + fn + tn
    row = {
        "tool": tool, "condition": condition, "dataset": dataset, "rep": rep,
        "retained_fastqs": ";".join(p.as_posix() for p in files),
        "tp": tp, "fp": fp, "fn": fn, "tn": tn,
        "unmapped_kept": len(kept - host - microbe),
        "host_total": len(host), "microbe_total": len(microbe),
        "retained_total": len(kept),
        "accuracy": f"{(tp + tn) / total:.9f}" if total else "0.000000000",
        "precision": f"{precision:.9f}", "recall": f"{recall:.9f}", "f1": f"{f1:.9f}",
        "host_input_retention_pct": f"{100 * fp / len(host):.6f}" if host else "0.000000",
        "microbial_loss_pct": f"{100 * fn / len(microbe):.6f}" if microbe else "0.000000",
        "host_output_fraction_pct": f"{100 * fp / len(kept):.6f}" if kept else "0.000000",
    }
    output = Path(output_value)
    output.parent.mkdir(parents=True, exist_ok=True)
    is_new = not output.exists() or output.stat().st_size == 0
    with output.open("a", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS, lineterminator="\n")
        if is_new:
            writer.writeheader()
        writer.writerow(row)
    print(json.dumps(row, sort_keys=True))


if __name__ == "__main__":
    main()
