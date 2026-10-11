#!/usr/bin/env python3
"""Plot the optimized fastp -> Deacon runtime benchmark versus Hostile."""

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
    "xtick.labelsize": 8,
    "ytick.labelsize": 9,
    "legend.fontsize": 8,
    "axes.spines.right": False,
    "axes.spines.top": False,
    "axes.linewidth": 0.8,
    "figure.dpi": 300,
    "svg.fonttype": "none",
    "pdf.fonttype": 42,
})


def main() -> None:
    data_dir = sys.argv[1] if len(sys.argv) > 1 else "data/main_figures"
    out_dir = sys.argv[2] if len(sys.argv) > 2 else "figures"
    os.makedirs(out_dir, exist_ok=True)
    df = pd.read_csv(os.path.join(data_dir, "fig_io_optimized_runtime.csv"))
    labels = df["dataset_label"].tolist()
    x = np.arange(len(df))
    width = 0.26

    fig, axes = plt.subplots(1, 2, figsize=(7.2, 3.3), gridspec_kw={"wspace": 0.28})

    ax = axes[0]
    ax.bar(x - width, df["hostile_fastp_s"] / 60, width,
           color="#C75B5B", label="Hostile + fastp", zorder=3)
    ax.bar(x, df["rustyclean_mean_all_s"] / 60, width,
           color="#8FC1D4", label="RustyClean AUTO, all reps", zorder=3)
    ax.bar(x + width, df["rustyclean_warm_mean_s"] / 60, width,
           color="#4A90A4", label="RustyClean AUTO, warm server", zorder=3)
    ax.errorbar(x, df["rustyclean_mean_all_s"] / 60,
                yerr=df["rustyclean_sd_all_s"] / 60, fmt="none",
                ecolor="#333333", elinewidth=0.7, capsize=2, zorder=4)
    for xpos, value in zip(x - width, df["hostile_fastp_s"] / 60):
        ax.annotate(f"{value:.0f}", (xpos, value), xytext=(0, 2),
                    textcoords="offset points", ha="center", fontsize=6)
    for xpos, value in zip(x + width, df["rustyclean_warm_mean_s"] / 60):
        ax.annotate(f"{value:.0f}", (xpos, value), xytext=(0, 2),
                    textcoords="offset points", ha="center", fontsize=6)
    ax.set_xticks(x)
    ax.set_xticklabels(labels, rotation=25, ha="right")
    ax.set_ylabel("Wall time (min)")
    ax.set_title("a  End-to-end runtime")
    ax.legend(loc="upper left", fontsize=7)
    ax.set_ylim(0, max(df["hostile_fastp_s"] / 60) * 1.16)

    ax = axes[1]
    ax.bar(x - width / 2, df["speedup_all_reps"], width,
           color="#8FC1D4", label="All reps", zorder=3)
    ax.bar(x + width / 2, df["speedup_warm"], width,
           color="#4A90A4", label="Warm server", zorder=3)
    for xpos, value in zip(x - width / 2, df["speedup_all_reps"]):
        ax.annotate(f"{value:.2f}×", (xpos, value), xytext=(0, 2),
                    textcoords="offset points", ha="center", fontsize=6)
    for xpos, value in zip(x + width / 2, df["speedup_warm"]):
        ax.annotate(f"{value:.2f}×", (xpos, value), xytext=(0, 2),
                    textcoords="offset points", ha="center", fontsize=6)
    ax.axhline(1, color="#666666", linewidth=0.8, linestyle="--", zorder=2)
    ax.set_xticks(x)
    ax.set_xticklabels(labels, rotation=25, ha="right")
    ax.set_ylabel("RustyClean speedup over Hostile + fastp")
    ax.set_title("b  Runtime speedup")
    ax.legend(loc="upper left", fontsize=7)
    ax.set_ylim(0, max(df["speedup_warm"].max(), df["speedup_all_reps"].max()) * 1.18)

    fig.tight_layout()
    for ext in ("png", "svg", "pdf"):
        fig.savefig(os.path.join(out_dir, f"fig_io_optimized_runtime.{ext}"),
                    dpi=300, bbox_inches="tight")
    plt.close(fig)
    print(f"Wrote fig_io_optimized_runtime to {out_dir}")


if __name__ == "__main__":
    main()
