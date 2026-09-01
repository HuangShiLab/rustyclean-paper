#!/usr/bin/env python3
"""
Re-collect fair benchmark results from per-dataset time logs and output files.

The aggregated CSV written by run_benchmark.sh can be corrupted because
RustyClean's colourised logs contain commas and ANSI escape sequences.
This script walks the output directory, reads each tool's GNU time log,
finds the cleaned FASTQ, and writes a clean CSV.

Usage:
    python collect_results.py $SCRATCH_DIR/rc_auto_skipqc_hostile_v2 results.csv
"""

import re
import sys
import os
import glob
from datetime import datetime
from pathlib import Path


def parse_gnu_time_log(path: str):
    """Parse GNU /usr/bin/time -v output."""
    runtime_seconds = None
    max_memory_kb = None
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line.startswith("Elapsed (wall clock) time"):
                # Line format: "Elapsed (wall clock) time (h:mm:ss or m:ss): 1:46.30"
                # The actual time is the last colon-separated token.
                val = line.split(":")[-1].strip()
                # Reconstruct the full time from the preceding tokens.
                # Split on all colons; the last three tokens form h:m:s or m:s.
                tokens = line.split(":")
                # tokens are like ["Elapsed (wall clock) time (h", "mm", "ss or m", "ss)", " 1", "46.30"]
                # The numeric time is the last non-empty numeric tokens before the description.
                # Easier: match a time pattern at the end of the line.
                m = re.search(r"(\d+):(\d+(?:\.\d+)?)(?::(\d+(?:\.\d+)?))?\s*$", line)
                if m:
                    groups = m.groups()
                    if groups[2] is None:
                        # m:ss
                        runtime_seconds = int(float(groups[0]) * 60 + float(groups[1]))
                    else:
                        # h:mm:ss
                        runtime_seconds = int(float(groups[0]) * 3600 + float(groups[1]) * 60 + float(groups[2]))
            elif line.startswith("Maximum resident set size"):
                max_memory_kb = int(line.split()[-1])
    return runtime_seconds, max_memory_kb


def find_output_size(ds_path: Path, tool: str):
    """Find the first cleaned FASTQ and return its size in bytes."""
    if tool == "rustyclean_auto_skipqc":
        pattern = str(ds_path / "rc_auto_skipqc" / "**" / "*_clean_R1.fastq.gz")
    elif tool == "hostile_raw":
        pattern = str(ds_path / "hostile_raw" / "**" / "*.fastq.gz")
    else:
        return None
    files = glob.glob(pattern, recursive=True)
    if files:
        return os.path.getsize(files[0])
    return None


def parse_rustyclean_log(ds_path: Path):
    """Extract backend and estimated host pct from RustyClean log."""
    log_path = ds_path / "rc_auto_skipqc.log"
    backend = "unknown"
    host_pct = "unknown"
    if not log_path.exists():
        return backend, host_pct

    ansi_re = re.compile(r"\x1b\[[0-9;]*m")
    with open(log_path) as f:
        for line in f:
            clean = ansi_re.sub("", line)
            if 'chosen_backend=' in clean:
                m = re.search(r'chosen_backend="([^"]+)"', clean)
                if m:
                    backend = m.group(1)
            if 'estimated_host_pct=' in clean:
                m = re.search(r'estimated_host_pct="([^"]+)"', clean)
                if m:
                    host_pct = m.group(1)
    return backend, host_pct


def collect(outdir: str, outfile: str):
    outdir = Path(outdir)
    rows = []
    datasets = sorted([d for d in outdir.iterdir() if d.is_dir()])

    for ds in datasets:
        dataset = ds.name
        ts = datetime.now().isoformat()

        # RustyClean
        rc_time = ds / "rc_auto_skipqc.time.log"
        if rc_time.exists():
            runtime, mem = parse_gnu_time_log(str(rc_time))
            size = find_output_size(ds, "rustyclean_auto_skipqc")
            backend, host_pct = parse_rustyclean_log(ds)
            rows.append({
                "dataset": dataset,
                "tool": "rustyclean_auto_skipqc",
                "runtime_seconds": runtime,
                "max_memory_kb": mem,
                "output_size_bytes": size,
                "backend": backend,
                "estimated_host_pct": host_pct,
                "timestamp": ts,
            })

        # Hostile
        hs_time = ds / "hostile_raw.time.log"
        if hs_time.exists():
            runtime, mem = parse_gnu_time_log(str(hs_time))
            size = find_output_size(ds, "hostile_raw")
            rows.append({
                "dataset": dataset,
                "tool": "hostile_raw",
                "runtime_seconds": runtime,
                "max_memory_kb": mem,
                "output_size_bytes": size,
                "backend": "bowtie2",
                "estimated_host_pct": "NA",
                "timestamp": ts,
            })

    import pandas as pd
    df = pd.DataFrame(rows)
    df.to_csv(outfile, index=False)
    print(f"Wrote {len(df)} rows to {outfile}")
    print(df.to_string(index=False))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    collect(sys.argv[1], sys.argv[2])
