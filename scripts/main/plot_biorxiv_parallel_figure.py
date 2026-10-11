#!/usr/bin/env python3
"""Create the bioRxiv parallel-scaling and batch-comparison figure."""

import os
import sys

import matplotlib as mpl

mpl.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

mpl.rcParams.update({
    "font.family": "sans-serif",
    "font.sans-serif": ["Arial", "Helvetica", "DejaVu Sans", "Liberation Sans"],
    "font.size": 7,
    "axes.labelsize": 7.5,
    "axes.titlesize": 7.5,
    "xtick.labelsize": 6.5,
    "ytick.labelsize": 6.5,
    "legend.fontsize": 6,
    "axes.linewidth": 0.6,
    "xtick.major.width": 0.6,
    "ytick.major.width": 0.6,
    "axes.spines.right": False,
    "axes.spines.top": False,
    "legend.frameon": False,
    "figure.dpi": 600,
    "svg.fonttype": "none",
    "pdf.fonttype": 42,
})

COLOR_RC = "#4C78A8"
COLOR_HOSTILE = "#C44E52"
COLOR_IDEAL = "#777777"


def main() -> None:
    scaling_path = sys.argv[1] if len(sys.argv) > 1 else "data/deacon_panel/parallel_scaling_deacon.csv"
    batch_path = sys.argv[2] if len(sys.argv) > 2 else "data/parallel_demo/parallel_demo_completed.csv"
    out_dir = sys.argv[3] if len(sys.argv) > 3 else "manuscript/bioinformatics_biorxiv/figures"
    os.makedirs(out_dir, exist_ok=True)

    scaling = pd.read_csv(scaling_path).sort_values("workers")
    batch = pd.read_csv(batch_path).groupby(["arm", "workers"], as_index=False)["wall_s"].mean()

    def batch_value(arm: str, workers: int) -> float:
        return float(batch.loc[(batch.arm == arm) & (batch.workers == workers), "wall_s"].iloc[0])

    rc_backend_workers = scaling["workers"].astype(int).to_numpy()
    rc_backend_speedup = scaling["speedup_vs_w1"].astype(float).to_numpy()

    workers = np.array([1, 8])
    rc_full = np.array([batch_value("rustyclean", worker) / 60 for worker in workers])
    hostile_full = np.array([batch_value("hostile_fastp", worker) / 60 for worker in workers])
    scaling_values = np.array([
        scaling.loc[scaling.workers == 8, "speedup_vs_w1"].iloc[0],
        1027.14 / 140.67,
        1002.15 / 265.62,
    ])
    scaling_labels = ["Deacon backend\n(16 × 10M)", "RustyClean AUTO\n(24 × 1M)", "Hostile + fastp\n(24 × 1M)"]

    fig, axes = plt.subplots(1, 3, figsize=(7.2, 2.25), constrained_layout=True)
    panel_labels = ["a", "b", "c"]

    ax = axes[0]
    ax.plot(workers, workers, "--", color=COLOR_IDEAL, linewidth=0.8,
            label="Ideal", zorder=2)
    ax.plot(rc_backend_workers, rc_backend_speedup, "o-", color=COLOR_RC,
            linewidth=1.0, markersize=3, label="RustyClean backend", zorder=3)
    for worker, value in zip(rc_backend_workers, rc_backend_speedup):
        ax.annotate(f"{value:.2f}×", (worker, value), xytext=(0, 3),
                    textcoords="offset points", ha="center", fontsize=5.5)
    ax.set_xticks(workers)
    ax.set_xlabel("Concurrent workers")
    ax.set_ylabel("Speedup vs W = 1")
    ax.set_title("a  Deacon backend scaling")
    ax.set_ylim(0, 9.5)
    ax.legend(loc="upper left", fontsize=5.5)

    ax = axes[1]
    xpos = np.arange(2)
    width = 0.32
    series = [
        ("RustyClean AUTO", rc_full, COLOR_RC),
        ("Hostile + fastp", hostile_full, COLOR_HOSTILE),
    ]
    for i, (label, values, color) in enumerate(series):
        ax.bar(xpos + (i - 0.5) * width, values, width, color=color,
               label=label, zorder=3)
        for xx, value in zip(xpos + (i - 0.5) * width, values):
            ax.annotate(f"{value:.1f}", (xx, value), xytext=(0, 1.5),
                        textcoords="offset points", ha="center", fontsize=5.5)
    ax.set_xticks(xpos)
    ax.set_xticklabels(["W = 1", "W = 8"])
    ax.set_ylabel("24-sample wall time (min)")
    ax.set_title("b  Full-pipeline batch time")
    ax.set_ylim(0, max(hostile_full.max(), rc_full.max()) * 1.18)
    ax.legend(loc="upper right", fontsize=5.5)

    ax = axes[2]
    bars = ax.bar(np.arange(3), scaling_values, 0.52,
                  color=[COLOR_RC, COLOR_RC, COLOR_HOSTILE], zorder=3)
    ax.axhline(8, color=COLOR_IDEAL, linewidth=0.8, linestyle="--", zorder=2)
    ax.annotate("Ideal W = 8", (2.42, 8.12), ha="right", fontsize=5.5,
                color=COLOR_IDEAL)
    for bar, value in zip(bars, scaling_values):
        ax.annotate(f"{value:.2f}×", (bar.get_x() + bar.get_width() / 2, value),
                    xytext=(0, 1.5), textcoords="offset points", ha="center",
                    fontsize=5.5)
    ax.set_xticks(np.arange(3))
    ax.set_xticklabels(scaling_labels, fontsize=5.5)
    ax.set_ylabel("W = 8 scaling factor")
    ax.set_title("c  Scaling comparison")
    ax.set_ylim(0, 9.3)

    for ax, label in zip(axes, panel_labels):
        ax.text(-0.16, 1.08, label, transform=ax.transAxes,
                fontsize=8, fontweight="bold", va="top", ha="left")

    for extension in ("png", "svg", "pdf"):
        fig.savefig(os.path.join(out_dir, f"fig4_parallel_scaling_hostile.{extension}"),
                    dpi=600, bbox_inches="tight")
    plt.close(fig)
    print(f"Wrote fig4_parallel_scaling_hostile to {out_dir}")


if __name__ == "__main__":
    main()
