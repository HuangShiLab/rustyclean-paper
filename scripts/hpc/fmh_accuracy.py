#!/usr/bin/env python3
"""Accuracy of a rustyclean fmh output dir against ground truth labels."""
import gzip, sys
from pathlib import Path

def read_fastq_ids(path):
    ids = set()
    opener = (lambda: gzip.open(path, "rt", encoding="utf-8", errors="ignore")) \
        if str(path).endswith(".gz") else (lambda: open(path, "r", encoding="utf-8", errors="ignore"))
    with opener() as fh:
        for i, line in enumerate(fh):
            if i % 4 == 0:
                rid = line.split()[0][1:]
                ids.add(rid.split("/")[0].split("#")[0])
    return ids

gt_path, outdir = Path(sys.argv[1]), Path(sys.argv[2])
host_ids, microbe_ids = set(), set()
with open(gt_path) as fh:
    for line in fh:
        line = line.strip()
        if not line or "\t" not in line:
            continue
        rid, label = line.split("\t", 1)
        (host_ids if label.lower() == "host" else microbe_ids).add(rid)

# Accept either an explicit FASTQ file or a directory containing cleaned reads.
def choose_fastq(path):
    path = Path(path)
    if path.is_file():
        return path
    candidates = (
        list(path.rglob("*_clean.fastq.gz"))
        + list(path.rglob("*_clean_R1.fastq.gz"))
        + list(path.glob("clean.fastq.gz"))
        + list(path.glob("clean.fastq"))
    )
    candidates = [c for c in candidates if c.is_file() and c.stat().st_size > 0]
    if not candidates:
        print("ERROR: no clean fastq in", path, file=sys.stderr)
        sys.exit(1)
    return max(candidates, key=lambda p: p.stat().st_size)

kept = read_fastq_ids(choose_fastq(outdir))
tp = len(kept & microbe_ids); fp = len(kept & host_ids)
fn = len(microbe_ids - kept); tn = len(host_ids - kept)
acc = (tp+tn)/(tp+tn+fp+fn) if tp+tn+fp+fn else 0
prec = tp/(tp+fp) if tp+fp else 0
rec = tp/(tp+fn) if tp+fn else 0
f1 = 2*prec*rec/(prec+rec) if prec+rec else 0
microbial_loss_pct = 100*fn/len(microbe_ids) if microbe_ids else 0
host_carry_pct = 100*fp/len(host_ids) if host_ids else 0
print(f"{acc:.6f},{prec:.6f},{rec:.6f},{f1:.6f},{microbial_loss_pct:.4f},{host_carry_pct:.4f},{tp},{fp},{fn},{tn}")
