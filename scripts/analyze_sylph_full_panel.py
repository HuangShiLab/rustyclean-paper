#!/usr/bin/env python3
"""Analyze RustyClean sylph backend on full enhanced panel.

Input:
    results_sylph_full/metrics/performance_sylph_full.csv
    results_sylph_full/metrics/accuracy_sylph_full.csv

Output:
    results_sylph_full/metrics/sylph_full_summary.csv
    results_sylph_full/figures/sylph_full_*.png
"""
import csv
import re
import sys
from pathlib import Path
from statistics import mean, stdev

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np


RESULTS_DIR = Path(__file__).resolve().parent.parent / "results_sylph_full"
METRICS_DIR = RESULTS_DIR / "metrics"
FIGURES_DIR = RESULTS_DIR / "figures"


def read_csv(path):
    with open(path, newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def parse_dataset(name):
    """Parse dataset name like '100M_90pct_high_lognormal_SE'."""
    m = re.match(r"^(\d+M)_(\d+)pct_(\w+)_(\w+)_(SE|PE)$", name)
    if not m:
        return None
    reads_str, host_pct, complexity, abundance, mode = m.groups()
    reads = int(reads_str.replace("M", "")) * 1_000_000
    return {
        "name": name,
        "reads": reads,
        "host_pct": int(host_pct),
        "complexity": complexity,
        "abundance": abundance,
        "mode": mode,
    }


def summarize(rows, key):
    vals = [float(r[key]) for r in rows]
    if len(vals) == 1:
        return vals[0], 0.0
    return mean(vals), stdev(vals)


def main():
    perf_path = METRICS_DIR / "performance_sylph_full.csv"
    acc_path = METRICS_DIR / "accuracy_sylph_full.csv"

    if not perf_path.exists():
        print(f"Missing {perf_path}", file=sys.stderr)
        sys.exit(1)
    if not acc_path.exists():
        print(f"Missing {acc_path}", file=sys.stderr)
        sys.exit(1)

    FIGURES_DIR.mkdir(parents=True, exist_ok=True)

    perf = read_csv(perf_path)
    acc = read_csv(acc_path)

    # Build summary per dataset
    datasets = sorted({r["dataset"] for r in perf} | {r["dataset"] for r in acc})
    summary = []
    for ds in datasets:
        info = parse_dataset(ds)
        if not info:
            print(f"Warning: cannot parse {ds}", file=sys.stderr)
            continue

        p_rows = [r for r in perf if r["dataset"] == ds]
        a_rows = [r for r in acc if r["dataset"] == ds]

        rt_mean, rt_sd = summarize(p_rows, "runtime_seconds")
        mem_mean, mem_sd = summarize(p_rows, "max_memory_kb")
        mem_gb = mem_mean / 1024 / 1024

        f1_mean, f1_sd = summarize(a_rows, "f1")
        precision_mean, _ = summarize(a_rows, "precision")
        recall_mean, _ = summarize(a_rows, "recall")

        summary.append({
            "dataset": ds,
            "reads_m": info["reads"] / 1_000_000,
            "host_pct": info["host_pct"],
            "complexity": info["complexity"],
            "abundance": info["abundance"],
            "mode": info["mode"],
            "runtime_mean": rt_mean,
            "runtime_sd": rt_sd,
            "memory_gb": mem_gb,
            "memory_sd_mb": mem_sd / 1024,
            "f1_mean": f1_mean,
            "f1_sd": f1_sd,
            "precision_mean": precision_mean,
            "recall_mean": recall_mean,
            "throughput_mreads_per_min": (info["reads"] / 1_000_000) / (rt_mean / 60),
        })

    # Write summary CSV
    summary_path = METRICS_DIR / "sylph_full_summary.csv"
    fieldnames = [
        "dataset", "reads_m", "host_pct", "complexity", "abundance", "mode",
        "runtime_mean", "runtime_sd", "memory_gb", "memory_sd_mb",
        "f1_mean", "f1_sd", "precision_mean", "recall_mean",
        "throughput_mreads_per_min",
    ]
    with open(summary_path, "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(summary)
    print(f"Wrote {summary_path}")

    # Plots
    df = sorted(summary, key=lambda r: (r["reads_m"], r["host_pct"]))
    x = np.arange(len(df))

    # Color by host_pct
    host_pcts = sorted({r["host_pct"] for r in df})
    cmap = plt.cm.Spectral
    colors = {pct: cmap(i / max(1, len(host_pcts) - 1)) for i, pct in enumerate(host_pcts)}

    # Figure 1: F1 vs host_pct, colored by mode
    fig, ax = plt.subplots(figsize=(8, 5))
    for mode in ["SE", "PE"]:
        subset = [r for r in df if r["mode"] == mode]
        ax.scatter(
            [r["host_pct"] for r in subset],
            [r["f1_mean"] for r in subset],
            label=mode,
            alpha=0.8,
            s=[r["reads_m"] * 3 for r in subset],
        )
    ax.set_xlabel("Host contamination (%)")
    ax.set_ylabel("F1 score")
    ax.set_ylim(0.94, 1.005)
    ax.set_title("Sylph backend accuracy across full panel")
    ax.legend(title="Mode", frameon=False)
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    fig.savefig(FIGURES_DIR / "sylph_full_f1_vs_hostpct.png", dpi=300)
    plt.close(fig)
    print(f"Wrote {FIGURES_DIR / 'sylph_full_f1_vs_hostpct.png'}")

    # Figure 2: Runtime vs reads, colored by host_pct
    fig, ax = plt.subplots(figsize=(8, 5))
    for pct in host_pcts:
        subset = [r for r in df if r["host_pct"] == pct]
        ax.scatter(
            [r["reads_m"] for r in subset],
            [r["runtime_mean"] / 60 for r in subset],
            color=colors[pct],
            label=f"{pct}%",
            alpha=0.8,
            s=60,
        )
    ax.set_xlabel("Reads (millions)")
    ax.set_ylabel("Runtime (minutes)")
    ax.set_title("Sylph backend runtime scaling")
    ax.legend(title="Host %", frameon=False, bbox_to_anchor=(1.02, 1), loc="upper left")
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    fig.savefig(FIGURES_DIR / "sylph_full_runtime_vs_reads.png", dpi=300)
    plt.close(fig)
    print(f"Wrote {FIGURES_DIR / 'sylph_full_runtime_vs_reads.png'}")

    # Figure 3: Memory vs reads
    fig, ax = plt.subplots(figsize=(8, 5))
    for pct in host_pcts:
        subset = [r for r in df if r["host_pct"] == pct]
        ax.scatter(
            [r["reads_m"] for r in subset],
            [r["memory_gb"] for r in subset],
            color=colors[pct],
            label=f"{pct}%",
            alpha=0.8,
            s=60,
        )
    ax.set_xlabel("Reads (millions)")
    ax.set_ylabel("Peak memory (GB)")
    ax.set_title("Sylph backend memory scaling")
    ax.legend(title="Host %", frameon=False, bbox_to_anchor=(1.02, 1), loc="upper left")
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    fig.savefig(FIGURES_DIR / "sylph_full_memory_vs_reads.png", dpi=300)
    plt.close(fig)
    print(f"Wrote {FIGURES_DIR / 'sylph_full_memory_vs_reads.png'}")

    # Figure 4: Throughput vs host_pct
    fig, ax = plt.subplots(figsize=(8, 5))
    for mode in ["SE", "PE"]:
        subset = [r for r in df if r["mode"] == mode]
        ax.scatter(
            [r["host_pct"] for r in subset],
            [r["throughput_mreads_per_min"] for r in subset],
            label=mode,
            alpha=0.8,
            s=[r["reads_m"] * 3 for r in subset],
        )
    ax.set_xlabel("Host contamination (%)")
    ax.set_ylabel("Throughput (M reads / min)")
    ax.set_title("Sylph backend throughput")
    ax.legend(title="Mode", frameon=False)
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    fig.savefig(FIGURES_DIR / "sylph_full_throughput.png", dpi=300)
    plt.close(fig)
    print(f"Wrote {FIGURES_DIR / 'sylph_full_throughput.png'}")

    # Print key findings
    print("\n=== Key findings ===")
    print(f"Datasets: {len(summary)}")
    print(f"F1 range: {min(r['f1_mean'] for r in summary):.4f} - {max(r['f1_mean'] for r in summary):.4f}")
    print(f"Memory range: {min(r['memory_gb'] for r in summary):.2f} - {max(r['memory_gb'] for r in summary):.2f} GB")
    print(f"Runtime range: {min(r['runtime_mean'] for r in summary):.1f} - {max(r['runtime_mean'] for r in summary):.1f} s")

    zero_host = [r for r in summary if r["host_pct"] == 0]
    if zero_host:
        print(f"\n0% host sample: F1={zero_host[0]['f1_mean']:.4f}, runtime={zero_host[0]['runtime_mean']:.1f}s, memory={zero_host[0]['memory_gb']:.2f}GB")


if __name__ == "__main__":
    main()
