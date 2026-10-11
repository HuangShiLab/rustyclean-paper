#!/usr/bin/env python3
"""Plot optimized runtime and batch-parallel panels for the application note."""

import os
import sys

import matplotlib as mpl

mpl.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

SKILL_SCRIPTS = "/Users/macstudio/.agents/skills/nature-figure/scripts"
if SKILL_SCRIPTS not in sys.path:
    sys.path.append(SKILL_SCRIPTS)

from audit_panel_alignment import require_matplotlib_panel_alignment

mpl.rcParams.update({
    "font.family": "sans-serif",
    "font.sans-serif": ["Arial", "Helvetica", "DejaVu Sans", "sans-serif"],
    "font.size": 8,
    "axes.labelsize": 9,
    "axes.titlesize": 10,
    "xtick.labelsize": 7,
    "ytick.labelsize": 8,
    "legend.fontsize": 7,
    "axes.spines.right": False,
    "axes.spines.top": False,
    "axes.linewidth": 0.8,
    "legend.frameon": False,
    "figure.dpi": 300,
    "svg.fonttype": "none",
    "pdf.fonttype": 42,
})


def main() -> None:
    data_dir = sys.argv[1] if len(sys.argv) > 1 else "data"
    out_dir = sys.argv[2] if len(sys.argv) > 2 else "manuscript/bioinformatics_application_note/figures"
    os.makedirs(out_dir, exist_ok=True)

    io = pd.read_csv(os.path.join(data_dir, "main_figures/fig_io_optimized_runtime.csv"))
    demo = pd.read_csv(os.path.join(data_dir, "parallel_demo/parallel_demo_completed.csv"))
    demo = demo.groupby(["arm", "workers"], as_index=False)["wall_s"].mean()
    memory = pd.read_csv(os.path.join(data_dir, "parallel_demo/parallel_demo.csv"))
    memory = memory.groupby(["arm", "workers"], as_index=False)["max_rss_kb"].mean()
    labels = io["dataset_label"].tolist()
    x = np.arange(len(io))
    width = 0.28

    fig, axes = plt.subplots(2, 2, figsize=(8.6, 5.8))
    ax = axes[0, 0]
    ax.bar(x - width, io["hostile_fastp_s"] / 60, width,
           color="#C75B5B", label="Hostile + fastp", zorder=3)
    ax.bar(x, io["rustyclean_mean_all_s"] / 60, width,
           color="#8FC1D4", label="RustyClean, all reps", zorder=3)
    ax.bar(x + width, io["rustyclean_warm_mean_s"] / 60, width,
           color="#4A90A4", label="RustyClean, warm server", zorder=3)
    ax.set_xticks(x)
    ax.set_xticklabels(labels, rotation=25, ha="right")
    ax.set_ylabel("Wall time (min)")
    ax.set_title("a  I/O-optimized runtime")
    ax.legend(loc="upper left", fontsize=6)

    ax = axes[0, 1]
    arms = ["rustyclean", "hostile_fastp"]
    labels2 = ["RustyClean AUTO", "Hostile + fastp"]
    colors = ["#4A90A4", "#C75B5B"]
    xpos = np.arange(2)
    width2 = 0.32
    for i, (arm, label, color) in enumerate(zip(arms, labels2, colors)):
        values = [demo.loc[(demo.arm == arm) & (demo.workers == worker), "wall_s"].iloc[0] / 60
                  for worker in [1, 8]]
        ax.bar(xpos + (i - 0.5) * width2, values, width2, color=color,
               label=label, zorder=3)
        for xx, value in zip(xpos + (i - 0.5) * width2, values):
            ax.annotate(f"{value:.1f}", (xx, value), xytext=(0, 2),
                        textcoords="offset points", ha="center", fontsize=6)
    ax.set_xticks(xpos)
    ax.set_xticklabels(["W = 1", "W = 8"])
    ax.set_ylabel("24-sample wall time (min)")
    ax.set_title("b  Batch parallelization")
    ax.legend(loc="upper right", fontsize=6)

    ax = axes[1, 0]
    speedups = []
    for arm in arms:
        w1 = demo.loc[(demo.arm == arm) & (demo.workers == 1), "wall_s"].iloc[0]
        w8 = demo.loc[(demo.arm == arm) & (demo.workers == 8), "wall_s"].iloc[0]
        speedups.append(w1 / w8)
    bars = ax.bar(["RustyClean AUTO", "Hostile + fastp"], speedups, 0.45,
                  color=colors, zorder=3)
    for bar, value in zip(bars, speedups):
        ax.annotate(f"{value:.2f}×", (bar.get_x() + bar.get_width() / 2, value),
                    xytext=(0, 2), textcoords="offset points", ha="center", fontsize=7)
    ax.axhline(1, color="#666666", linewidth=0.8, linestyle="--", zorder=2)
    ax.set_ylabel("W = 8 speedup over same tool W = 1")
    ax.set_title("c  Scaling gain")
    ax.tick_params(axis="x", labelrotation=12)

    ax = axes[1, 1]
    mem_labels = ["RustyClean AUTO", "Hostile + fastp"]
    mem_colors = ["#4A90A4", "#C75B5B"]
    xpos = np.arange(2)
    width3 = 0.32
    for i, (arm, label, color) in enumerate(zip(arms, mem_labels, mem_colors)):
        values = []
        for worker in [1, 8]:
            subset = demo[(demo.arm == arm) & (demo.workers == worker)]
            memory_value = memory[(memory.arm == arm) & (memory.workers == worker)]["max_rss_kb"]
            values.append(memory_value.iloc[0] / 1024**2)
        ax.bar(xpos + (i - 0.5) * width3, values, width3, color=color,
               label=label, zorder=3)
        for xx, value in zip(xpos + (i - 0.5) * width3, values):
            ax.annotate(f"{value:.2f}", (xx, value), xytext=(0, 2),
                        textcoords="offset points", ha="center", fontsize=6)
    ax.set_xticks(xpos)
    ax.set_xticklabels(["W = 1", "W = 8"])
    ax.set_ylabel("Peak RSS, largest process (GiB)")
    ax.set_title("d  Peak process memory")
    ax.legend(loc="upper left", fontsize=6)
    ax.set_ylim(0, max(5.5, ax.get_ylim()[1] * 1.12))

    fig.tight_layout()
    require_matplotlib_panel_alignment(
        fig,
        json_out=os.path.join(out_dir, "fig2_io_parallel_memory.alignment.json"),
        overlay_svg=os.path.join(out_dir, "fig2_io_parallel_memory.alignment.svg"),
        tolerance_pt=1.5,
        gutter_tolerance_pt=1.5,
        strict=True,
    )
    for ext in ("png", "svg", "pdf"):
        fig.savefig(os.path.join(out_dir, f"fig2_io_parallel_memory.{ext}"), dpi=600,
                    bbox_inches="tight")
    plt.close(fig)
    print(f"Wrote fig2_io_parallel to {out_dir}")


if __name__ == "__main__":
    main()
