#!/usr/bin/env python3
"""Compare sylph backend with T2T-only vs Hostile T2T+HLA Bowtie2 index."""
import csv
from pathlib import Path
from statistics import mean, stdev

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np


RESULTS_DIR = Path(__file__).resolve().parent.parent
OUT_DIR = RESULTS_DIR / "results_sylph_t2t_only" / "metrics"
OUT_DIR.mkdir(parents=True, exist_ok=True)


def read_csv(path):
    with open(path, newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def summarize(rows, value_key):
    vals = [float(r[value_key]) for r in rows]
    if len(vals) == 1:
        return vals[0], 0.0
    return mean(vals), stdev(vals)


def main():
    datasets = [
        "5M_1pct_low_even_SE",
        "10M_10pct_med_even_SE",
        "30M_50pct_high_skewed_SE",
        "60M_90pct_high_lognormal_SE",
    ]
    host_pcts = [1, 10, 50, 90]

    std_perf = read_csv(RESULTS_DIR / "results_sylph_standard" / "metrics" / "performance_sylph_standard.csv")
    std_acc = read_csv(RESULTS_DIR / "results_sylph_standard" / "metrics" / "accuracy_sylph_standard.csv")
    t2t_perf = read_csv(RESULTS_DIR / "results_sylph_t2t_only" / "metrics" / "performance_sylph_t2t_only.csv")
    t2t_acc = read_csv(RESULTS_DIR / "results_sylph_t2t_only" / "metrics" / "accuracy_sylph_t2t_only.csv")

    summary_rows = []
    warm_rows = []
    for ds, hp in zip(datasets, host_pcts):
        sp = [r for r in std_perf if r["dataset"] == ds]
        sa = [r for r in std_acc if r["dataset"] == ds]
        tp = [r for r in t2t_perf if r["dataset"] == ds]
        ta = [r for r in t2t_acc if r["dataset"] == ds]

        std_rt, _ = summarize(sp, "runtime_seconds")
        std_mem, _ = summarize(sp, "max_memory_kb")
        std_f1 = mean([float(r["f1"]) for r in sa])

        t2t_rt, _ = summarize(tp, "runtime_seconds")
        t2t_mem, _ = summarize(tp, "max_memory_kb")
        t2t_f1 = mean([float(r["f1"]) for r in ta])

        # Warm-run summary: exclude rep 1 to reduce first-run index-cache noise.
        sp_warm = [r for r in sp if int(r["rep"]) > 1]
        tp_warm = [r for r in tp if int(r["rep"]) > 1]
        std_rt_warm, _ = summarize(sp_warm, "runtime_seconds") if sp_warm else (std_rt, 0.0)
        t2t_rt_warm, _ = summarize(tp_warm, "runtime_seconds") if tp_warm else (t2t_rt, 0.0)

        summary_rows.append({
            "dataset": ds,
            "host_pct": hp,
            "hostile_index_runtime": std_rt,
            "hostile_index_memory_gb": std_mem / 1024 / 1024,
            "hostile_index_f1": std_f1,
            "t2t_only_runtime": t2t_rt,
            "t2t_only_memory_gb": t2t_mem / 1024 / 1024,
            "t2t_only_f1": t2t_f1,
        })
        warm_rows.append({
            "dataset": ds,
            "host_pct": hp,
            "hostile_index_runtime_warm": std_rt_warm,
            "t2t_only_runtime_warm": t2t_rt_warm,
        })

    out_csv = OUT_DIR / "sylph_t2t_only_vs_hostile_index.csv"
    fieldnames = [
        "dataset", "host_pct",
        "hostile_index_runtime", "hostile_index_memory_gb", "hostile_index_f1",
        "t2t_only_runtime", "t2t_only_memory_gb", "t2t_only_f1",
    ]
    with open(out_csv, "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(summary_rows)
    print(f"Wrote {out_csv}")

    warm_csv = OUT_DIR / "sylph_t2t_only_vs_hostile_index_warm.csv"
    with open(warm_csv, "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=["dataset", "host_pct", "hostile_index_runtime_warm", "t2t_only_runtime_warm"])
        writer.writeheader()
        writer.writerows(warm_rows)
    print(f"Wrote {warm_csv}")

    # Plot
    x = np.arange(len(datasets))
    width = 0.35
    fig, axes = plt.subplots(1, 4, figsize=(16, 4))

    def bar_pair(ax, vals_a, vals_b, title, ylabel, ylim=None):
        ax.bar(x - width/2, vals_a, width, label="Hostile T2T+HLA", color="#2ca02c")
        ax.bar(x + width/2, vals_b, width, label="T2T-only", color="#9467bd")
        ax.set_ylabel(ylabel)
        ax.set_xticks(x)
        ax.set_xticklabels(host_pcts)
        ax.set_xlabel("Host %")
        ax.set_title(title)
        if ylim:
            ax.set_ylim(ylim)
        ax.legend(frameon=False)

    # Runtime (all reps)
    bar_pair(axes[0],
             [r["hostile_index_runtime"] for r in summary_rows],
             [r["t2t_only_runtime"] for r in summary_rows],
             "Runtime (all reps)", "Runtime (s)")

    # Runtime (warm reps, rep >= 2)
    bar_pair(axes[1],
             [r["hostile_index_runtime_warm"] for r in warm_rows],
             [r["t2t_only_runtime_warm"] for r in warm_rows],
             "Runtime (warm reps)", "Runtime (s)")

    # Memory
    bar_pair(axes[2],
             [r["hostile_index_memory_gb"] for r in summary_rows],
             [r["t2t_only_memory_gb"] for r in summary_rows],
             "Memory", "Memory (GB)")

    # F1
    bar_pair(axes[3],
             [r["hostile_index_f1"] for r in summary_rows],
             [r["t2t_only_f1"] for r in summary_rows],
             "F1 score", "F1", (0.99, 1.0005))

    plt.tight_layout()
    out_fig = OUT_DIR / "sylph_t2t_only_vs_hostile_index.png"
    plt.savefig(out_fig, dpi=300)
    print(f"Wrote {out_fig}")


if __name__ == "__main__":
    main()
