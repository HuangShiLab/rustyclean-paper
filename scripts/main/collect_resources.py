#!/usr/bin/env python3
"""Merge per-task benchmark metrics and summarise runtime and peak memory.

Each benchmark runs as a SLURM job array, one task per dataset, and every task
writes its own ``<name>.taskN.csv`` so that concurrent appends cannot interleave.
This script merges those parts back into ``<name>.csv`` and then flattens every
experiment into one table, so runtime and peak memory for the whole panel can be
read in one place rather than assembled by hand from a dozen files.

The per-experiment CSVs do not share a schema: some name the tool column ``tool``
and others ``mode``, some name the dataset ``dataset`` and others ``sample``.
Rather than rewrite eight scripts to agree, the columns are normalised here.

Usage:
    collect_resources.py [--roots DIR ...] [--out DIR]
"""

import argparse
import csv
import glob
import os
import re
import subprocess
import sys
from collections import defaultdict

TASK_RE = re.compile(r"^(?P<base>.+)\.task\d+\.csv$")

# The column that holds the tool/mode, in preference order, and likewise the
# column that holds the dataset. Different experiments chose different names.
TOOL_KEYS = ("tool", "mode", "backend")
DATASET_KEYS = ("dataset", "sample")


def merge_task_parts(roots):
    """Concatenate <name>.taskN.csv into <name>.csv, keeping one header."""
    groups = defaultdict(list)
    for root in roots:
        if not os.path.isdir(root):
            continue
        for path in glob.glob(os.path.join(root, "**", "*.task*.csv"), recursive=True):
            m = TASK_RE.match(os.path.basename(path))
            if m:
                merged = os.path.join(os.path.dirname(path), m.group("base") + ".csv")
                groups[merged].append(path)

    for merged, parts in sorted(groups.items()):
        parts.sort()
        header, rows = None, []
        for part in parts:
            with open(part, newline="") as fh:
                lines = list(csv.reader(fh))
            if not lines:
                continue
            # A part may be header-only if its task exited before doing work.
            if header is None:
                header = lines[0]
            rows.extend(lines[1:])
        if header is None:
            continue
        with open(merged, "w", newline="") as fh:
            w = csv.writer(fh)
            w.writerow(header)
            w.writerows(rows)
        print(f"  merged {len(parts):>2} parts, {len(rows):>4} rows -> {merged}")
    return len(groups)


def pick(row, keys):
    for k in keys:
        if row.get(k):
            return row[k]
    return ""


def hms(seconds):
    try:
        s = float(seconds)
    except (TypeError, ValueError):
        return ""
    h, rem = divmod(int(s), 3600)
    m, sec = divmod(rem, 60)
    return f"{h:d}:{m:02d}:{sec:02d}"


def collect(roots, out_dir):
    """Flatten every metrics CSV into one normalised resource table."""
    records = []
    seen = set()
    for root in roots:
        if not os.path.isdir(root):
            continue
        for path in glob.glob(os.path.join(root, "**", "*.csv"), recursive=True):
            if TASK_RE.match(os.path.basename(path)):
                continue  # a part; its merged parent is read instead
            # This script's own output lands under RUNS_DIR, so a second run
            # would read the previous summary back in and count everything twice.
            if os.path.basename(path) == "resources.csv":
                continue
            real = os.path.realpath(path)
            if real in seen:
                continue
            seen.add(real)
            with open(path, newline="") as fh:
                try:
                    reader = csv.DictReader(fh)
                    if not reader.fieldnames:
                        continue
                    # Only files that actually carry resource measurements.
                    if "runtime_seconds" not in reader.fieldnames:
                        continue
                    for row in reader:
                        rt = row.get("runtime_seconds", "")
                        mem = row.get("max_memory_kb", "")
                        records.append({
                            "experiment": os.path.splitext(os.path.basename(path))[0],
                            "tool": pick(row, TOOL_KEYS),
                            "dataset": pick(row, DATASET_KEYS),
                            "rep": row.get("rep", ""),
                            "runtime_seconds": rt,
                            "runtime_hms": hms(rt),
                            "max_memory_kb": mem,
                            "max_memory_gb": (f"{float(mem)/1048576:.2f}"
                                              if mem.replace(".", "", 1).isdigit() else ""),
                            "timestamp": row.get("timestamp", ""),
                            "source": os.path.relpath(path, out_dir) if out_dir else path,
                        })
                except (csv.Error, UnicodeDecodeError):
                    continue
    return records


def drop_superseded(records):
    """Keep only the latest measurement for each (experiment, tool, dataset, rep).

    A benchmark that appended to its previous CSV leaves two runs in one file,
    and pooling them averages a fixed configuration with the one that replaced
    it. Report what was dropped rather than doing it quietly.
    """
    latest = {}
    for r in records:
        key = (r["experiment"], r["tool"], r["dataset"], r["rep"])
        prev = latest.get(key)
        if prev is None or r.get("timestamp", "") > prev.get("timestamp", ""):
            latest[key] = r
    dropped = len(records) - len(latest)
    if dropped:
        print(f"  {dropped} superseded measurement(s) dropped: an earlier run of the "
              f"same tool and dataset was still in the file")
    return list(latest.values())


def write_summary(records, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    out_csv = os.path.join(out_dir, "resources.csv")
    cols = ["experiment", "tool", "dataset", "rep", "runtime_seconds",
            "runtime_hms", "max_memory_kb", "max_memory_gb", "timestamp", "source"]
    with open(out_csv, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader()
        w.writerows(records)
    print(f"\n  {len(records)} measurements -> {out_csv}")

    # A failed run records FAILED rather than a number; keep those visible as a
    # count instead of silently dropping them from the summary.
    ok = [r for r in records
          if r["runtime_seconds"].replace(".", "", 1).isdigit()]
    failed = len(records) - len(ok)

    by_tool = defaultdict(list)
    for r in ok:
        by_tool[(r["experiment"], r["tool"])].append(r)

    print(f"\n{'experiment':<38} {'tool':<22} {'n':>3} "
          f"{'median time':>12} {'max time':>12} {'peak mem':>10}")
    print("-" * 102)
    for (exp, tool), rs in sorted(by_tool.items()):
        times = sorted(float(r["runtime_seconds"]) for r in rs)
        mems = [float(r["max_memory_kb"]) for r in rs
                if r["max_memory_kb"].replace(".", "", 1).isdigit()]
        med = times[len(times) // 2]
        print(f"{exp:<38.38} {tool:<22.22} {len(rs):>3} "
              f"{hms(med):>12} {hms(times[-1]):>12} "
              f"{(max(mems)/1048576 if mems else 0):>9.1f}G")
    if failed:
        print(f"\n  {failed} run(s) recorded as FAILED; see {out_csv}")


def sacct_snapshot(out_dir, days):
    """SLURM's own accounting, as an independent check on /usr/bin/time.

    GNU time reports the peak RSS of the process it launched and the children it
    waited for, which can undercount when a tool forks helpers that outlive the
    wait. sacct measures the whole cgroup, so a large disagreement is worth
    investigating before a memory number is published.
    """
    out = os.path.join(out_dir, "sacct.txt")
    cmd = ["sacct", f"--starttime=now-{days}days", "--units=G",
           "--format=JobID%20,JobName%34,Elapsed,MaxRSS,ReqMem,State%14"]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        print("  sacct unavailable; skipping the accounting cross-check")
        return
    if res.returncode != 0:
        print(f"  sacct failed: {res.stderr.strip()[:200]}")
        return
    with open(out, "w") as fh:
        fh.write(res.stdout)
    print(f"  SLURM accounting -> {out}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--roots", nargs="*", default=None,
                    help="directories to search (default: the project output trees)")
    ap.add_argument("--out", default=None, help="where to write the summary")
    ap.add_argument("--sacct-days", type=int, default=14)
    args = ap.parse_args()

    env = os.environ.get
    roots = args.roots or [p for p in (
        env("RESULTS_DIR"), env("SCRATCH_DIR"), env("RUNS_DIR"),
        os.path.join(env("PROJECT_DIR", ""), "metrics") if env("PROJECT_DIR") else None,
    ) if p]
    if not roots:
        print("No output roots. Source scripts/hpc/config.sh or pass --roots.",
              file=sys.stderr)
        return 1

    out_dir = args.out or os.path.join(env("RUNS_DIR", "."), "summary")

    # Roots that nest inside one another make the recursive glob find the same
    # file more than once, and every measurement is then counted twice. The
    # default roots do nest -- RESULTS_DIR sits inside SCRATCH_DIR -- so drop
    # duplicates and any root contained in another before searching.
    resolved = sorted({os.path.realpath(r) for r in roots})
    roots = [r for r in resolved
             if not any(r != other and r.startswith(other + os.sep) for other in resolved)]

    print("Merging per-task metric files")
    merge_task_parts(roots)

    print("\nCollecting resource measurements")
    records = collect(roots, out_dir)
    if not records:
        print("  no metrics found; did the benchmarks run?", file=sys.stderr)
        return 1
    records = drop_superseded(records)
    write_summary(records, out_dir)
    sacct_snapshot(out_dir, args.sacct_days)
    return 0


if __name__ == "__main__":
    sys.exit(main())
