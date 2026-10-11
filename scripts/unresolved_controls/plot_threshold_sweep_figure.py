#!/usr/bin/env python3
"""Plot Supplementary Figure S3 from threshold_sweep_compact.csv."""
from __future__ import annotations

import argparse
import csv
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output-stem", type=Path, required=True)
    parser.add_argument("--default-threshold", type=float, default=0.30)
    args = parser.parse_args()

    with args.input.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    threshold = [float(row["threshold"]) for row in rows]
    series = {
        "f1_mean": "Retained-microbe F1",
        "host_retention_pct": "Host input retained (%)",
        "microbial_loss_pct": "Microbial loss (%)",
        "recheck_rate": "Bowtie2 recheck rate",
    }
    fig, axes = plt.subplots(1, 4, figsize=(10.2, 2.5), constrained_layout=True)
    for ax, (metric, label) in zip(axes, series.items()):
        values = [float(row[metric]) for row in rows]
        ax.plot(threshold, values, color="#4A90A4", marker="o", markersize=3.2, linewidth=1.1)
        ax.axvline(args.default_threshold, color="#C75B5B", linewidth=0.8, linestyle="--", label="Default 0.30")
        ax.set_xlabel("Bowtie2 recheck threshold", fontsize=7)
        ax.set_title(label, fontsize=7)
        ax.tick_params(labelsize=6)
        ax.spines[["top", "right"]].set_visible(False)
    axes[0].set_ylim(min(float(r["f1_mean"]) for r in rows) - 0.00008,
                     max(float(r["f1_mean"]) for r in rows) + 0.00008)
    axes[1].set_yscale("log")
    axes[1].set_ylabel("% of true host input", fontsize=6)
    axes[3].set_ylim(-0.04, 1.04)
    axes[0].legend(frameon=False, fontsize=5.5, loc="lower right")
    args.output_stem.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(args.output_stem.with_suffix(".png"), dpi=300)
    fig.savefig(args.output_stem.with_suffix(".svg"))
    fig.savefig(args.output_stem.with_suffix(".pdf"))


if __name__ == "__main__":
    main()
