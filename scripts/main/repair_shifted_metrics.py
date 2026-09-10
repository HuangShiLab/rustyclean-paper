#!/usr/bin/env python3
"""Realign metric CSVs that carry one stray field after max_memory_kb.

fair_hostile_skipqc_run_benchmark.sh read parse_time_log's "<seconds>,<kb>"
with a bare `read` instead of `IFS=, read`, so the whole string landed in the
first variable -- contributing two CSV fields -- and the second variable was
emitted empty. Every column after max_memory_kb therefore sat one place to the
right of its header.

Runtime and peak memory were unaffected, because they are the two halves of
that first string and land where the header expects them. Everything after was
wrong, which mattered little while the trailing columns were output size and
backend, and matters a great deal now that cgroup CPU and memory sit there.

The script only touches rows whose shape matches the bug exactly: one field too
many, and the field after max_memory_kb empty. Anything else is left alone and
reported, so a file broken some other way is not quietly rewritten.

    repair_shifted_metrics.py <file-or-directory>...
"""

import csv
import os
import sys


def repair(path):
    with open(path, newline="") as fh:
        rows = list(csv.reader(fh))
    if not rows:
        return 0, 0, "empty"
    header = rows[0]
    want = len(header)
    try:
        drop_at = header.index("max_memory_kb") + 1
    except ValueError:
        return 0, 0, "no max_memory_kb column"

    fixed, skipped, out = 0, 0, [header]
    for row in rows[1:]:
        if len(row) == want:
            out.append(row)
        elif len(row) == want + 1 and row[drop_at] == "":
            out.append(row[:drop_at] + row[drop_at + 1:])
            fixed += 1
        else:
            out.append(row)
            skipped += 1
    if fixed:
        tmp = path + ".tmp"
        with open(tmp, "w", newline="") as fh:
            csv.writer(fh).writerows(out)
        os.replace(tmp, path)     # atomic: a half-written metrics file is worse
    return fixed, skipped, ""


def main(argv):
    targets = []
    for arg in argv:
        if os.path.isdir(arg):
            for root, _, files in os.walk(arg):
                targets += [os.path.join(root, f) for f in files if f.endswith(".csv")]
        else:
            targets.append(arg)
    if not targets:
        print("usage: repair_shifted_metrics.py <file-or-directory>...", file=sys.stderr)
        return 2

    total_fixed = total_odd = 0
    for path in sorted(targets):
        fixed, skipped, note = repair(path)
        if note:
            continue
        total_fixed += fixed
        total_odd += skipped
        if fixed or skipped:
            print(f"  {fixed:>4} realigned, {skipped:>3} left alone  {path}")
    print(f"\n  {total_fixed} row(s) realigned")
    if total_odd:
        print(f"  {total_odd} row(s) had an unexpected shape and were left as they are",
              file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
