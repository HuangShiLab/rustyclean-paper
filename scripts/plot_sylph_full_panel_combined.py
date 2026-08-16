#!/usr/bin/env python3
"""Generate a publication-quality combined figure for sylph full panel."""
import csv
import re
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np


RESULTS_DIR = Path(__file__).resolve().parent.parent / "results_sylph_full"
SUMMARY = RESULTS_DIR / "metrics" / "sylph_full_summary.csv"
OUT_FIG = RESULTS_DIR / "figures" / "sylph_full_combined.png"


def read_summary():
    with open(SUMMARY, newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def parse_dataset(name):
    m = re.match(r"^(\d+M)_(\d+)pct_(\w+)_(\w+)_(SE|PE)$", name)
    if not m:
        return None
    reads, host_pct, complexity, abundance, mode = m.groups()
    return {
        "reads_m": int(reads.replace("M", "")),
        "host_pct": int(host_pct),
        "mode": mode,
    }


def main():
    rows = read_summary()

    fig, axes = plt.subplots(1, 2, figsize=(9, 4))

    # Panel A: F1 vs host %
    ax = axes[0]
    for mode, marker in [("SE", "o"), ("PE", "s")]:
        subset = [r for r in rows if parse_dataset(r["dataset"])["mode"] == mode]
        ax.scatter(
            [parse_dataset(r["dataset"])["host_pct"] for r in subset],
            [float(r["f1_mean"]) for r in subset],
            s=[parse_dataset(r["dataset"])["reads_m"] * 2.5 for r in subset],
            marker=marker,
            alpha=0.75,
            edgecolors="k",
            linewidths=0.5,
            label=mode,
        )
    ax.set_xlabel("Host contamination (%)")
    ax.set_ylabel("F1 score")
    ax.set_ylim(0.94, 1.005)
    ax.set_title("(a) Accuracy across full panel")
    ax.legend(title="Layout", frameon=False)
    ax.grid(True, alpha=0.3)

    # Panel B: Runtime vs reads, colored by host %
    ax = axes[1]
    host_pcts = sorted({parse_dataset(r["dataset"])["host_pct"] for r in rows})
    cmap = plt.cm.Spectral
    colors = {pct: cmap(i / max(1, len(host_pcts) - 1)) for i, pct in enumerate(host_pcts)}

    for pct in host_pcts:
        subset = [r for r in rows if parse_dataset(r["dataset"])["host_pct"] == pct]
        ax.scatter(
            [parse_dataset(r["dataset"])["reads_m"] for r in subset],
            [float(r["runtime_mean"]) / 60 for r in subset],
            color=colors[pct],
            s=50,
            alpha=0.85,
            edgecolors="k",
            linewidths=0.5,
            label=f"{pct}%",
        )
    ax.set_xlabel("Reads (millions)")
    ax.set_ylabel("Runtime (minutes)")
    ax.set_title("(b) Runtime scaling")
    ax.legend(title="Host %", frameon=False, bbox_to_anchor=(1.02, 1), loc="upper left")
    ax.grid(True, alpha=0.3)

    plt.tight_layout()
    OUT_FIG.parent.mkdir(parents=True, exist_ok=True)
    plt.savefig(OUT_FIG, dpi=300, bbox_inches="tight")
    print(f"Wrote {OUT_FIG}")


if __name__ == "__main__":
    main()
