#!/usr/bin/env python3
"""Generate comparison figures for RustyClean vs Hostile / KneadData.

Inputs:
    benchmark/results/fair_hostile_skipqc_results.csv
    benchmark/results/auto_vs_kneaddata_metrics.csv
    benchmark/results/accuracy_comparison.csv (optional)

Outputs:
    benchmark/figures/rc_hostile_kneaddata_comparison.{png,svg,pdf}
"""

import csv
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np


RC_COLOR = "#4A90A4"
HOSTILE_COLOR = "#C75B5B"
KNEADDATA_COLOR = "#D4A373"


def load_metrics(csv_path: Path) -> list:
    rows = []
    with open(csv_path, "r", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            # Convert numeric fields
            for key in ["runtime_seconds", "max_memory_kb", "output_size_bytes"]:
                if key in row:
                    try:
                        row[key] = float(row[key])
                    except (ValueError, TypeError):
                        row[key] = np.nan
            rows.append(row)
    return rows


def load_accuracy(csv_path: Path) -> dict:
    """Return {(dataset, tool): {accuracy, precision, recall, f1}}."""
    acc = {}
    if not csv_path.exists():
        return acc
    with open(csv_path, "r", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            key = (row["dataset"], row["tool"])
            acc[key] = {k: float(row[k]) for k in ["accuracy", "precision", "recall", "f1"]}
    return acc


def mb_from_kb(kb: float) -> float:
    return kb / 1024


def plot_comparison(outdir: Path, fair_rows: list, auto_rows: list, accuracy: dict):
    datasets = [
        "5M_1pct_low_even_SE",
        "10M_10pct_med_even_SE",
        "30M_50pct_high_skewed_SE",
        "60M_90pct_high_lognormal_SE",
    ]
    short_labels = ["5M\n1%", "10M\n10%", "30M\n50%", "60M\n90%"]

    # Prepare data structures
    fair_rc = {r["dataset"]: r for r in fair_rows if r["tool"] == "rustyclean_auto_skipqc"}
    fair_hs = {r["dataset"]: r for r in fair_rows if r["tool"] == "hostile_raw"}
    auto_rc = {r["dataset"]: r for r in auto_rows if r["tool"] == "rustyclean_auto"}
    auto_kd = {r["dataset"]: r for r in auto_rows if r["tool"] == "kneaddata"}

    fig, axes = plt.subplots(2, 3, figsize=(14, 8))
    fig.suptitle("RustyClean vs Hostile / KneadData on simulated metagenomes", fontsize=13)

    x = np.arange(len(datasets))
    width = 0.35

    def autolabel(ax, rects, fmt="{:.0f}"):
        for rect in rects:
            height = rect.get_height()
            if not np.isfinite(height) or height == 0:
                continue
            ax.annotate(fmt.format(height),
                        xy=(rect.get_x() + rect.get_width() / 2, height),
                        xytext=(0, 3), textcoords="offset points",
                        ha="center", va="bottom", fontsize=6)

    # Row 0: fair comparison with Hostile (no QC)
    ax = axes[0, 0]
    rc_times = [fair_rc[d]["runtime_seconds"] / 60 for d in datasets]
    hs_times = [fair_hs[d]["runtime_seconds"] / 60 for d in datasets]
    bars1 = ax.bar(x - width/2, rc_times, width, label="RustyClean AUTO --skip-qc", color=RC_COLOR)
    bars2 = ax.bar(x + width/2, hs_times, width, label="Hostile", color=HOSTILE_COLOR)
    ax.set_ylabel("Runtime (min)")
    ax.set_title("(a) Runtime (no-QC fair)")
    ax.set_xticks(x)
    ax.set_xticklabels(short_labels)
    ax.legend(frameon=False, fontsize=7)
    autolabel(ax, bars1, "{:.1f}")
    autolabel(ax, bars2, "{:.1f}")
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)

    ax = axes[0, 1]
    rc_mem = [mb_from_kb(fair_rc[d]["max_memory_kb"]) for d in datasets]
    hs_mem = [mb_from_kb(fair_hs[d]["max_memory_kb"]) for d in datasets]
    bars1 = ax.bar(x - width/2, rc_mem, width, label="RustyClean", color=RC_COLOR)
    bars2 = ax.bar(x + width/2, hs_mem, width, label="Hostile", color=HOSTILE_COLOR)
    ax.set_ylabel("Peak memory (MB)")
    ax.set_title("(b) Memory (no-QC fair)")
    ax.set_xticks(x)
    ax.set_xticklabels(short_labels)
    ax.legend(frameon=False, fontsize=7)
    autolabel(ax, bars1, "{:.0f}")
    autolabel(ax, bars2, "{:.0f}")
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)

    ax = axes[0, 2]
    if accuracy:
        rc_f1 = [accuracy.get((d, "rustyclean_auto_skipqc"), {}).get("f1", np.nan) for d in datasets]
        hs_f1 = [accuracy.get((d, "hostile_raw"), {}).get("f1", np.nan) for d in datasets]
        bars1 = ax.bar(x - width/2, rc_f1, width, label="RustyClean", color=RC_COLOR)
        bars2 = ax.bar(x + width/2, hs_f1, width, label="Hostile", color=HOSTILE_COLOR)
        ax.set_ylim(0.95, 1.001)
        ax.set_ylabel("F1-score")
        ax.set_title("(c) F1-score (no-QC fair)")
        ax.set_xticks(x)
        ax.set_xticklabels(short_labels)
        ax.legend(frameon=False, fontsize=7)
        autolabel(ax, bars1, "{:.4f}")
        autolabel(ax, bars2, "{:.4f}")
    else:
        ax.text(0.5, 0.5, "Accuracy data not available",
                ha="center", va="center", transform=ax.transAxes)
        ax.set_title("(c) F1-score (no-QC fair)")
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)

    # Row 1: full comparison with KneadData (with QC)
    ax = axes[1, 0]
    rc_times = [auto_rc[d]["runtime_seconds"] / 60 for d in datasets]
    kd_times = [auto_kd[d]["runtime_seconds"] / 60 for d in datasets]
    bars1 = ax.bar(x - width/2, rc_times, width, label="RustyClean AUTO", color=RC_COLOR)
    bars2 = ax.bar(x + width/2, kd_times, width, label="KneadData", color=KNEADDATA_COLOR)
    ax.set_ylabel("Runtime (min)")
    ax.set_title("(d) Runtime (full pipeline)")
    ax.set_xticks(x)
    ax.set_xticklabels(short_labels)
    ax.legend(frameon=False, fontsize=7)
    autolabel(ax, bars1, "{:.1f}")
    autolabel(ax, bars2, "{:.1f}")
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)

    ax = axes[1, 1]
    rc_mem = [mb_from_kb(auto_rc[d]["max_memory_kb"]) for d in datasets]
    kd_mem = [mb_from_kb(auto_kd[d]["max_memory_kb"]) for d in datasets]
    bars1 = ax.bar(x - width/2, rc_mem, width, label="RustyClean", color=RC_COLOR)
    bars2 = ax.bar(x + width/2, kd_mem, width, label="KneadData", color=KNEADDATA_COLOR)
    ax.set_ylabel("Peak memory (MB)")
    ax.set_title("(e) Memory (full pipeline)")
    ax.set_xticks(x)
    ax.set_xticklabels(short_labels)
    ax.legend(frameon=False, fontsize=7)
    autolabel(ax, bars1, "{:.0f}")
    autolabel(ax, bars2, "{:.0f}")
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)

    ax = axes[1, 2]
    if accuracy:
        rc_f1 = [accuracy.get((d, "rustyclean_auto"), {}).get("f1", np.nan) for d in datasets]
        kd_f1 = [accuracy.get((d, "kneaddata"), {}).get("f1", np.nan) for d in datasets]
        bars1 = ax.bar(x - width/2, rc_f1, width, label="RustyClean", color=RC_COLOR)
        bars2 = ax.bar(x + width/2, kd_f1, width, label="KneadData", color=KNEADDATA_COLOR)
        ax.set_ylim(0.95, 1.001)
        ax.set_ylabel("F1-score")
        ax.set_title("(f) F1-score (full pipeline)")
        ax.set_xticks(x)
        ax.set_xticklabels(short_labels)
        ax.legend(frameon=False, fontsize=7)
        autolabel(ax, bars1, "{:.4f}")
        autolabel(ax, bars2, "{:.4f}")
    else:
        ax.text(0.5, 0.5, "Accuracy data not available",
                ha="center", va="center", transform=ax.transAxes)
        ax.set_title("(f) F1-score (full pipeline)")
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)

    plt.tight_layout(rect=[0, 0, 1, 0.96])

    outdir.mkdir(parents=True, exist_ok=True)
    for ext in ["png", "svg", "pdf"]:
        out_path = outdir / f"rc_hostile_kneaddata_comparison.{ext}"
        fig.savefig(out_path, dpi=300 if ext == "png" else None, bbox_inches="tight")
        print(f"Saved {out_path}")

    plt.close(fig)


def main():
    repo_root = Path(__file__).resolve().parents[2]
    results_dir = repo_root / "benchmark" / "results"
    figures_dir = repo_root / "benchmark" / "figures"

    fair_csv = results_dir / "fair_hostile_skipqc_results.csv"
    auto_csv = results_dir / "auto_vs_kneaddata_metrics.csv"
    acc_csv = results_dir / "accuracy_comparison.csv"

    if not fair_csv.exists() or not auto_csv.exists():
        print(f"Missing required metrics files: {fair_csv} or {auto_csv}", file=sys.stderr)
        sys.exit(1)

    fair_rows = load_metrics(fair_csv)
    auto_rows = load_metrics(auto_csv)
    accuracy = load_accuracy(acc_csv)

    plot_comparison(figures_dir, fair_rows, auto_rows, accuracy)


if __name__ == "__main__":
    main()
