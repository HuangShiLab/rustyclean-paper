#!/usr/bin/env python3
"""Plot full-pipeline batch parallelization against Hostile + fastp."""

import os
import sys

import matplotlib as mpl

mpl.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

mpl.rcParams.update({
    "font.family": "sans-serif",
    "font.sans-serif": ["Arial", "Helvetica", "DejaVu Sans", "sans-serif"],
    "font.size": 9,
    "axes.labelsize": 10,
    "axes.titlesize": 11,
    "xtick.labelsize": 9,
    "ytick.labelsize": 9,
    "legend.fontsize": 8,
    "axes.spines.right": False,
    "axes.spines.top": False,
    "axes.linewidth": 0.8,
    "legend.frameon": False,
    "figure.dpi": 300,
    "svg.fonttype": "none",
    "pdf.fonttype": 42,
})


def main() -> None:
    input_csv = sys.argv[1] if len(sys.argv) > 1 else "data/parallel_demo/parallel_demo_completed.csv"
    out_dir = sys.argv[2] if len(sys.argv) > 2 else "figures"
    os.makedirs(out_dir, exist_ok=True)
    demo = pd.read_csv(input_csv).groupby(["arm", "workers"], as_index=False)["wall_s"].mean()
    fig, axes = plt.subplots(1, 2, figsize=(7.2, 3.0), gridspec_kw={"wspace": 0.3})

    ax = axes[0]
    xpos = np.arange(2)
    width = 0.32
    arms = [("rustyclean", "RustyClean AUTO", "#4A90A4"),
            ("hostile_fastp", "Hostile + fastp", "#C75B5B")]
    for i, (arm, label, color) in enumerate(arms):
        values = [demo.loc[(demo.arm == arm) & (demo.workers == worker), "wall_s"].iloc[0] / 60
                  for worker in (1, 8)]
        ax.bar(xpos + (i - 0.5) * width, values, width, color=color, label=label,
               zorder=3)
        for xx, value in zip(xpos + (i - 0.5) * width, values):
            ax.annotate(f"{value:.1f}", (xx, value), xytext=(0, 2),
                        textcoords="offset points", ha="center", fontsize=7)
    ax.set_xticks(xpos)
    ax.set_xticklabels(["W = 1", "W = 8"])
    ax.set_ylabel("24-sample wall time (min)")
    ax.set_title("a  Batch wall time")
    ax.legend(loc="upper right")

    ax = axes[1]
    speedups = []
    for arm, label, color in arms:
        w1 = demo.loc[(demo.arm == arm) & (demo.workers == 1), "wall_s"].iloc[0]
        w8 = demo.loc[(demo.arm == arm) & (demo.workers == 8), "wall_s"].iloc[0]
        speedups.append(w1 / w8)
    bars = ax.bar(["RustyClean AUTO", "Hostile + fastp"], speedups, 0.45,
                  color=[color for _, _, color in arms], zorder=3)
    for bar, value in zip(bars, speedups):
        ax.annotate(f"{value:.2f}×", (bar.get_x() + bar.get_width() / 2, value),
                    xytext=(0, 2), textcoords="offset points", ha="center",
                    fontsize=8)
    ax.axhline(1, color="#666666", linewidth=0.8, linestyle="--", zorder=2)
    ax.set_ylabel("W = 8 speedup over same tool W = 1")
    ax.set_title("b  Scaling gain")
    ax.tick_params(axis="x", labelrotation=10)

    fig.tight_layout()
    for ext in ("png", "svg", "pdf"):
        fig.savefig(os.path.join(out_dir, f"figS3_parallel_demo.{ext}"),
                    dpi=300, bbox_inches="tight")
    plt.close(fig)
    print(f"Wrote figS3_parallel_demo to {out_dir}")


if __name__ == "__main__":
    main()
