#!/usr/bin/env python3
"""Validate that scored accuracy rows contain audited count/rate invariants."""
from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("accuracy_csv", type=Path)
    parser.add_argument("--tolerance", type=float, default=1e-5)
    args = parser.parse_args()
    checked = 0
    with args.accuracy_csv.open(newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            tp, fp, fn, tn = (float(row[k]) for k in ("tp", "fp", "fn", "tn"))
            host = fp + tn
            microbe = tp + fn
            retained = tp + fp
            checks = {
                "f1": float(row["f1"]),
                "host_retention": float(row["host_input_retention_pct"]),
                "microbe_loss": float(row["microbial_loss_pct"]),
                "host_output": float(row["host_output_fraction_pct"]),
            }
            expected = {
                "f1": 2 * tp / (2 * tp + fp + fn) if 2 * tp + fp + fn else 0.0,
                "host_retention": 100 * fp / host if host else 0.0,
                "microbe_loss": 100 * fn / microbe if microbe else 0.0,
                "host_output": 100 * fp / retained if retained else 0.0,
            }
            for key, value in expected.items():
                if not math.isclose(checks[key], value, rel_tol=0, abs_tol=args.tolerance):
                    raise SystemExit(f"invariant failed at row {checked + 1}: {key}")
            checked += 1
    print(f"validated_rows={checked}")


if __name__ == "__main__":
    main()
