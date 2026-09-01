#!/usr/bin/env python3
"""Re-collect benchmark metrics from per-dataset GNU time logs.

Use this if the main CSV was corrupted (e.g. ANSI escapes or partial writes).
The script scans OUTDIR/<dataset>/ for *.time.log files and rebuilds a clean
metrics table.
"""

import csv
import os
import re
import sys
from pathlib import Path


OUTDIR = Path(os.environ.get("SCRATCH_DIR", f"/scr/u/{os.environ.get('USER','')}/rustyclean-paper") + "/auto_vs_kneaddata")

DATASETS = [
    "5M_1pct_low_even_SE",
    "10M_10pct_med_even_SE",
    "30M_50pct_high_skewed_SE",
    "60M_90pct_high_lognormal_SE",
]

TIME_RE = re.compile(r"Elapsed \(wall clock\) time \(h:mm:ss or m:ss\):\s*(.+)")
MEM_RE = re.compile(r"Maximum resident set size \(kbytes\):\s*(\d+)")


def parse_elapsed(s: str) -> float:
    parts = s.strip().split(":")
    if len(parts) == 2:
        m, sec = parts
        return float(m) * 60 + float(sec)
    if len(parts) == 3:
        h, m, sec = parts
        return float(h) * 3600 + float(m) * 60 + float(sec)
    return float(s)


def parse_time_log(path: Path) -> tuple:
    text = path.read_text(encoding="utf-8", errors="ignore")
    elapsed = TIME_RE.search(text)
    mem = MEM_RE.search(text)
    runtime = parse_elapsed(elapsed.group(1)) if elapsed else "unknown"
    max_mem = mem.group(1) if mem else "unknown"
    return runtime, max_mem


def find_output_size(ds_path: Path, tool: str) -> int:
    if tool == "rustyclean_auto":
        for pattern in ("*_clean_R1.fastq.gz", "*_clean.fastq.gz"):
            matches = list(ds_path.rglob(pattern))
            if matches:
                return matches[0].stat().st_size
    else:  # kneaddata
        clean_candidates = [p for p in ds_path.iterdir() if p.is_file() and "clean" in p.name and p.suffix == ".fastq"]
        if clean_candidates:
            return max(p.stat().st_size for p in clean_candidates)
        candidates = [
            p for p in ds_path.iterdir()
            if p.is_file() and p.suffix == ".fastq"
            and "contam" not in p.name
            and "trimmed" not in p.name
            and "repeats" not in p.name
        ]
        if candidates:
            return max(p.stat().st_size for p in candidates)
    return "unknown"


ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")


def parse_backend(log_path: Path) -> str:
    if not log_path.exists():
        return "unknown"
    text = ANSI_RE.sub("", log_path.read_text(encoding="utf-8", errors="ignore"))
    m = re.search(r"chosen_backend[=:]\"?([^\"\s]+)\"?", text)
    return m.group(1) if m else "unknown"


def parse_hostpct(log_path: Path) -> str:
    if not log_path.exists():
        return "unknown"
    text = ANSI_RE.sub("", log_path.read_text(encoding="utf-8", errors="ignore"))
    m = re.search(r"estimated_host_pct[=:]\"?([^\"\s]+)\"?", text)
    return m.group(1) if m else "unknown"


def main():
    rows = []
    for dataset in DATASETS:
        ds_path = OUTDIR / dataset
        if not ds_path.exists():
            continue

        # RustyClean
        rc_time = ds_path / "rc_auto.time.log"
        if rc_time.exists():
            rt, mem = parse_time_log(rc_time)
            log = ds_path / "rc_auto.log"
            backend = parse_backend(log)
            hostpct = parse_hostpct(log)
            size = find_output_size(ds_path / "rc_auto", "rustyclean_auto")
            rows.append([dataset, "rustyclean_auto", rt, mem, size, backend, hostpct])

        # KneadData
        kd_time = ds_path / "kneaddata.time.log"
        if kd_time.exists():
            rt, mem = parse_time_log(kd_time)
            size = find_output_size(ds_path / "kneaddata", "kneaddata")
            rows.append([dataset, "kneaddata", rt, mem, size, "bowtie2", "NA"])

    out_csv = sys.argv[1] if len(sys.argv) > 1 else str(OUTDIR / "auto_vs_kneaddata_metrics_rebuilt.csv")
    with open(out_csv, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["dataset", "tool", "runtime_seconds", "max_memory_kb",
                         "output_size_bytes", "backend", "estimated_host_pct"])
        writer.writerows(rows)

    print(f"Wrote {len(rows)} rows to {out_csv}")


if __name__ == "__main__":
    main()
