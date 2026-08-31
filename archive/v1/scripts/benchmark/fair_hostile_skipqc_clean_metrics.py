#!/usr/bin/env python3
"""
Clean the raw metrics CSV produced by run_benchmark.sh.

RustyClean's colourised logs leave ANSI escape sequences in the
`backend` and `estimated_host_pct` fields. This script strips them
and writes a tidy CSV.

Usage:
    python clean_metrics.py rc_auto_skipqc_hostile_metrics.csv clean_metrics.csv
"""

import re
import sys
import pandas as pd

ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")


def strip_ansi(s: str) -> str:
    if pd.isna(s):
        return s
    return ANSI_RE.sub("", str(s))


def extract_field(text: str, field: str) -> str:
    """Extract the value of `field="value"` from a possibly noisy log line."""
    text = strip_ansi(text)
    # Remove ANSI codes and any timestamp/log-level noise by focusing on the field pattern
    pattern = rf"{field}\s*=\s*\"([^\"]+)\""
    m = re.search(pattern, text)
    if m:
        return m.group(1)
    # Fallback: if the cell is already a plain value, return it
    text = text.strip()
    if text and "=" not in text:
        return text
    return "unknown"


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)

    infile, outfile = sys.argv[1:3]
    df = pd.read_csv(infile)

    if "backend" in df.columns:
        df["backend"] = df["backend"].apply(lambda x: extract_field(x, "chosen_backend"))
    if "estimated_host_pct" in df.columns:
        df["estimated_host_pct"] = df["estimated_host_pct"].apply(lambda x: extract_field(x, "estimated_host_pct"))

    # Make sure runtime is numeric
    for col in ["runtime_seconds", "max_memory_kb", "output_size_bytes"]:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce")

    df.to_csv(outfile, index=False)
    print(f"Cleaned metrics written to {outfile}")


if __name__ == "__main__":
    main()
