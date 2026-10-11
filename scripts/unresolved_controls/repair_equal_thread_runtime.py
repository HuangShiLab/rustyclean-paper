#!/usr/bin/env python3
"""Repair fastp+Hostile wall time from GNU time logs.

The original inline parser retained only the terminal seconds field. This
script recomputes runtime as fastp wall time plus Hostile wall time, verifies
counts, and writes a timestamped CSV backup before modifying performance.csv.
"""
from __future__ import annotations

import csv
import shutil
import time
from pathlib import Path


def elapsed_seconds(path: Path) -> float:
    for raw in path.read_text(encoding="utf-8").splitlines():
        if "Elapsed (wall clock) time" not in raw:
            continue
        value = raw.split()[-1].strip()
        return sum(float(part) * 60**i for i, part in enumerate(reversed(value.split(":"))))
    raise ValueError(f"missing elapsed time: {path}")


def main() -> None:
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--panel-root", required=True, type=Path)
    args = parser.parse_args()
    performance = args.panel_root / "metrics" / "performance.csv"
    logs = args.panel_root / "logs"
    with performance.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
        fields = list(rows[0]) if rows else []
    repaired = 0
    for row in rows:
        if row["tool"] != "fastp_hostile":
            continue
        fastp_log = logs / f"{row['dataset']}_hostile_fastp_rep{row['rep']}.time"
        hostile_log = logs / f"{row['dataset']}_hostile_rep{row['rep']}.time"
        old = float(row["runtime_s"])
        new = elapsed_seconds(fastp_log) + elapsed_seconds(hostile_log)
        row["runtime_s"] = f"{new:.3f}"
        row["extra"] = (
            '{"runtime_repaired":true,"wall_rule":"sum sequential stages",'
            f'"previous_runtime_s":{old:.3f}}}'
        )
        repaired += 1
    backup = performance.with_name(
        "performance.before_runtime_repair." + time.strftime("%Y%m%d_%H%M%S") + ".csv"
    )
    shutil.copy2(performance, backup)
    with performance.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    print(f"repaired_rows={repaired} backup={backup}")


if __name__ == "__main__":
    main()
