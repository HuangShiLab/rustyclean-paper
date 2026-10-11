#!/usr/bin/env python3
"""Create the compact Bioinformatics Application Note figures.

Figure 1 contains the six-dataset runtime and memory comparison.
Figure 2 combines legacy Deacon scaling with full-pipeline batch
parallelization and peak process memory.
"""

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
    "axes.labelsize": 8.5,
    "axes.titlesize": 9.5,
    "xtick.labelsize": 7,
    "ytick.labelsize": 7.5,
    "legend.fontsize": 6.5,
    "axes.spines.right": False,
    "axes.spines.top": False,
    "axes.linewidth": 0.75,
    "legend.frameon": False,
    "figure.dpi": 300,
    "svg.fonttype": "none",
    "pdf.fonttype": 42,
})

TOOLS = [
    "kneaddata", "hostile_fastp", "deacon_skipqc",
    "rc_auto_deacon", "rc_auto_deacon_norecheck",
]
TOOL_LABELS = {
    "kneaddata": "KneadData",
    "hostile_fastp": "Hostile + fastp",
    "deacon_skipqc": "Deacon only",
    "rc_auto_deacon": "RustyClean AUTO",
    "rc_auto_deacon_norecheck": "RustyClean AUTO without recheck",
}
TOOL_COLORS = {
    "kneaddata": "#D4A373",
    "hostile_fastp": "#C75B5B",
    "deacon_skipqc": "#7EB5A6",
    "rc_auto_deacon": "#4A90A4",
    "rc_auto_deacon_norecheck": "#E17054",
}
DATASETS = [
    "5M_1pct_low_even_SE", "10M_10pct_med_even_SE",
    "30M_50pct_high_skewed_SE", "60M_90pct_high_lognormal_SE",
    "100M_50pct_high_lognormal_SE", "100M_90pct_high_lognormal_SE",
]
DATASET_LABELS = [
    "5M / 1%", "10M / 10%", "30M / 50%",
    "60M / 90%", "100M / 50%", "100M / 90%",
]
BAR_WIDTH = 0.18


def save(fig, out_dir, stem):
    require_matplotlib_panel_alignment(
        fig,
        json_out=os.path.join(out_dir, f"{stem}.alignment.json"),
        overlay_svg=os.path.join(out_dir, f"{stem}.alignment.svg"),
        tolerance_pt=1.5,
        gutter_tolerance_pt=1.5,
        strict=True,
    )
    for ext in ("png", "svg", "pdf"):
        fig.savefig(os.path.join(out_dir, f"{stem}.{ext}"), dpi=600,
                    bbox_inches="tight")
    plt.close(fig)


def plot_performance(data_dir, out_dir):
    perf_path = data_dir
    perf = pd.read_csv(perf_path)
    perf = perf.set_index(["tool", "dataset"])
    x = np.arange(len(DATASETS))
    width = BAR_WIDTH
    fig, axes = plt.subplots(1, 2, figsize=(7.0, 2.9))

    for i, tool in enumerate(TOOLS):
        offset = (i - (len(TOOLS) - 1) / 2) * width
        for j, dataset in enumerate(DATASETS):
            row = perf.loc[(tool, dataset)]
            axes[0].bar(x[j] + offset, row["runtime_s"] / 60, width,
                        color=TOOL_COLORS[tool], zorder=3)
            axes[1].bar(x[j] + offset, row["memory_gib"], width,
                        color=TOOL_COLORS[tool], zorder=3)

    axes[0].set_title("a  Runtime")
    axes[0].set_ylabel("Runtime (min, log scale)")
    axes[0].set_yscale("log")
    axes[0].set_ylim(0.05, 400)
    axes[1].set_title("b  Peak memory")
    axes[1].set_ylabel("Peak memory (GiB)")
    axes[1].set_ylim(0, 6)
    for ax in axes:
        ax.set_xticks(x)
        ax.set_xticklabels(DATASET_LABELS, rotation=25, ha="right")

    fig.tight_layout()
    save(fig, out_dir, "fig1_performance")


def plot_parallel_resource(data_dir, out_dir):
    scaling = pd.read_csv(os.path.join(data_dir, "fig4_parallel_scaling.csv"))
    demo_completed = pd.read_csv("data/parallel_demo/parallel_demo_completed.csv")
    demo_all = pd.read_csv("data/parallel_demo/parallel_demo.csv")

    workers = scaling["workers"].astype(int)
    wall = scaling["wall_s"].astype(float)
    speedup = scaling["speedup_vs_w1"].astype(float)

    demo = demo_completed.groupby(["arm", "workers"], as_index=False)["wall_s"].mean()
    memory_all = demo_all.groupby(["arm", "workers"], as_index=False)["max_rss_kb"].mean()

    fig, axes = plt.subplots(2, 2, figsize=(7.2, 5.8))

    ax = axes[0, 0]
    bars = ax.bar([str(w) for w in workers], wall, BAR_WIDTH, color="#4A90A4", zorder=3)
    for bar, value in zip(bars, wall):
        minute, second = int(value // 60), int(value % 60)
        ax.annotate(f"{minute}m{second:02d}s",
                    (bar.get_x() + bar.get_width() / 2, value), xytext=(0, 2),
                    textcoords="offset points", ha="center", fontsize=6)
    ax.set_title("a  Deacon backend throughput")
    ax.set_ylabel("16-sample wall time (s)")
    ax.set_xlabel("Concurrent workers")

    ax = axes[0, 1]
    ax.plot(workers, speedup, "o-", color="#4A90A4", label="RustyClean backend",
            zorder=3)
    ax.plot(workers, workers, "--", color="#8C8C8C", label="Ideal", zorder=2)
    for worker, value in zip(workers, speedup):
        ax.annotate(f"{value:.2f}×", (worker, value), xytext=(0, 4),
                    textcoords="offset points", ha="center", fontsize=6)
    ax.set_title("b  Deacon backend efficiency")
    ax.set_ylabel("Speedup vs W = 1")
    ax.set_xlabel("Concurrent workers")
    ax.set_xticks(workers)
    ax.set_ylim(0, max(workers) * 1.15)
    ax.legend(loc="upper left")

    ax = axes[1, 0]
    xpos = np.arange(2)
    width = BAR_WIDTH
    arms = [("rustyclean", "RustyClean AUTO", "#4A90A4"),
            ("hostile_fastp", "Hostile + fastp", "#C75B5B")]
    scaling_notes = {"rustyclean": "7.30×", "hostile_fastp": "3.77×"}
    for i, (arm, label, color) in enumerate(arms):
        values = [demo.loc[(demo.arm == arm) & (demo.workers == worker), "wall_s"].iloc[0] / 60
                  for worker in (1, 8)]
        ax.bar(xpos + (i - 0.5) * width, values, width, color=color,
               label=label, zorder=3)
        for xx, value in zip(xpos + (i - 0.5) * width, values):
            ax.annotate(f"{value:.1f}", (xx, value), xytext=(0, 2),
                        textcoords="offset points", ha="center", fontsize=6)
        center = xpos[-1] + (i - 0.5) * width
        ax.annotate(scaling_notes[arm], (center, 4.5), ha="center",
                    fontsize=6, color=color)
    ax.set_xticks(xpos)
    ax.set_xticklabels(["W = 1", "W = 8"])
    ax.set_ylabel("24-sample wall time (min)")
    ax.set_title("c  Full-pipeline batch scaling")
    ax.set_ylim(0, 5.3)
    ax.legend(loc="upper right")

    ax = axes[1, 1]
    width = BAR_WIDTH
    for i, (arm, label, color) in enumerate(arms):
        values = []
        for worker in (1, 8):
            rows = memory_all[(memory_all.arm == arm) &
                              (memory_all.workers == worker)]["max_rss_kb"]
            if arm == "rustyclean" and worker == 1:
                completed_time = demo_completed[(demo_completed.arm == arm) &
                                                 (demo_completed.workers == worker)]["timestamp"].max()
                all_rows = demo_all[(demo_all.arm == arm) &
                                    (demo_all.workers == worker)]
                rows = all_rows[all_rows.timestamp == completed_time]["max_rss_kb"]
            values.append(rows.mean() / 1024**2)
        ax.bar(xpos + (i - 0.5) * width, values, width, color=color,
               label=label, zorder=3)
        for xx, value in zip(xpos + (i - 0.5) * width, values):
            ax.annotate(f"{value:.2f}", (xx, value), xytext=(0, 2),
                        textcoords="offset points", ha="center", fontsize=6)
    ax.set_xticks(xpos)
    ax.set_xticklabels(["W = 1", "W = 8"])
    ax.set_ylabel("Peak process memory (GiB)")
    ax.set_title("d  Peak process memory")
    ax.set_ylim(0, 5.5)
    ax.legend(loc="upper left")

    fig.tight_layout()
    save(fig, out_dir, "fig2_parallel_resource")


def main():
    data_dir = sys.argv[1] if len(sys.argv) > 1 else "data/main_figures"
    out_dir = sys.argv[2] if len(sys.argv) > 2 else "manuscript/bioinformatics_application_note/figures"
    os.makedirs(out_dir, exist_ok=True)
    app_source = "manuscript/bioinformatics_application_note/source_data"
    perf_source = os.path.join(app_source, "fig1_five_way_runtime_memory.csv")
    plot_performance(perf_source, out_dir)
    plot_parallel_resource(data_dir, out_dir)
    print(f"Wrote fig1_performance and fig2_parallel_resource to {out_dir}")


if __name__ == "__main__":
    main()
