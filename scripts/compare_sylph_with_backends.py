#!/usr/bin/env python3
"""Compare sylph backend runtime/memory/accuracy against existing backends."""
import csv
import sys
from pathlib import Path
from statistics import mean, stdev

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np


RESULTS_DIR = Path(__file__).resolve().parent.parent
OUT_DIR = RESULTS_DIR / "results_sylph_standard" / "metrics"
OUT_DIR.mkdir(parents=True, exist_ok=True)


def read_csv(path):
    with open(path, newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def summarize(rows, value_key):
    vals = [float(r[value_key]) for r in rows]
    if len(vals) == 1:
        return vals[0], 0.0
    return mean(vals), stdev(vals)


def dataset_host_pct(name):
    mapping = {
        "5M_1pct_low_even_SE": 1,
        "10M_10pct_med_even_SE": 10,
        "30M_50pct_high_skewed_SE": 50,
        "60M_90pct_high_lognormal_SE": 90,
    }
    return mapping.get(name, name)


def main():
    datasets = [
        "5M_1pct_low_even_SE",
        "10M_10pct_med_even_SE",
        "30M_50pct_high_skewed_SE",
        "60M_90pct_high_lognormal_SE",
    ]

    # Load sylph results
    sylph_perf = read_csv(RESULTS_DIR / "results_sylph_standard" / "metrics" / "performance_sylph_standard.csv")
    sylph_acc = read_csv(RESULTS_DIR / "results_sylph_standard" / "metrics" / "accuracy_sylph_standard.csv")

    # Load existing accuracy
    acc_all = read_csv(RESULTS_DIR / "benchmark" / "results" / "accuracy_comparison.csv")

    # Load existing performance
    perf_auto_kd = read_csv(RESULTS_DIR / "benchmark" / "results" / "auto_vs_kneaddata_metrics.csv")
    perf_hostile = read_csv(RESULTS_DIR / "benchmark" / "results" / "fair_hostile_skipqc_results.csv")

    summary_rows = []
    for ds in datasets:
        host_pct = dataset_host_pct(ds)

        # Sylph
        sp = [r for r in sylph_perf if r["dataset"] == ds]
        rt_mean, rt_sd = summarize(sp, "runtime_seconds")
        mem_mean, mem_sd = summarize(sp, "max_memory_kb")
        mem_mean = mem_mean / 1024.0  # KB -> MB

        sa = [r for r in sylph_acc if r["dataset"] == ds]
        f1_mean = mean([float(r["f1"]) for r in sa])

        # RustyClean auto skip-qc
        rc = [r for r in perf_hostile if r["dataset"] == ds and r["tool"] == "rustyclean_auto_skipqc"]
        rc_rt = float(rc[0]["runtime_seconds"]) if rc else None
        rc_mem = float(rc[0]["max_memory_kb"]) / 1024 / 1024 if rc else None

        # Hostile raw
        ho = [r for r in perf_hostile if r["dataset"] == ds and r["tool"] == "hostile_raw"]
        ho_rt = float(ho[0]["runtime_seconds"]) if ho else None
        ho_mem = float(ho[0]["max_memory_kb"]) / 1024 / 1024 if ho else None

        # KneadData
        kd = [r for r in perf_auto_kd if r["dataset"] == ds and r["tool"] == "kneaddata"]
        kd_rt = float(kd[0]["runtime_seconds"]) if kd else None
        kd_mem = float(kd[0]["max_memory_kb"]) / 1024 / 1024 if kd else None

        # Accuracy from accuracy_comparison.csv
        acc_map = {}
        for r in acc_all:
            if r["dataset"] == ds:
                acc_map[r["tool"]] = float(r["f1"])

        summary_rows.append({
            "dataset": ds,
            "host_pct": host_pct,
            "sylph_runtime_mean": rt_mean,
            "sylph_runtime_sd": rt_sd,
            "sylph_memory_gb": mem_mean / 1024,
            "sylph_f1": f1_mean,
            "rc_auto_skipqc_runtime": rc_rt,
            "rc_auto_skipqc_memory_gb": rc_mem,
            "rc_auto_skipqc_f1": acc_map.get("rustyclean_auto_skipqc"),
            "hostile_runtime": ho_rt,
            "hostile_memory_gb": ho_mem,
            "hostile_f1": acc_map.get("hostile_raw"),
            "kneaddata_runtime": kd_rt,
            "kneaddata_memory_gb": kd_mem,
            "kneaddata_f1": acc_map.get("kneaddata"),
        })

    # Write summary CSV
    out_csv = OUT_DIR / "sylph_backend_comparison_summary.csv"
    fieldnames = [
        "dataset", "host_pct",
        "sylph_runtime_mean", "sylph_runtime_sd", "sylph_memory_gb", "sylph_f1",
        "rc_auto_skipqc_runtime", "rc_auto_skipqc_memory_gb", "rc_auto_skipqc_f1",
        "hostile_runtime", "hostile_memory_gb", "hostile_f1",
        "kneaddata_runtime", "kneaddata_memory_gb", "kneaddata_f1",
    ]
    with open(out_csv, "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(summary_rows)
    print(f"Wrote {out_csv}")

    # Plot
    x = np.arange(len(datasets))
    width = 0.2
    fig, axes = plt.subplots(1, 3, figsize=(14, 4))

    tools = ["sylph", "rc_auto_skipqc", "hostile", "kneaddata"]
    colors = {"sylph": "#9467bd", "rc_auto_skipqc": "#4A90A4", "hostile": "#2ca02c", "kneaddata": "#C75B5B"}

    # Runtime
    ax = axes[0]
    runtime_cols = {
        "sylph": "sylph_runtime_mean",
        "rc_auto_skipqc": "rc_auto_skipqc_runtime",
        "hostile": "hostile_runtime",
        "kneaddata": "kneaddata_runtime",
    }
    for i, tool in enumerate(tools):
        vals = [r[runtime_cols[tool]] for r in summary_rows]
        ax.bar(x + (i - 1.5) * width, vals, width, label=tool, color=colors[tool])
    ax.set_ylabel("Runtime (s)")
    ax.set_xticks(x)
    ax.set_xticklabels([dataset_host_pct(d) for d in datasets])
    ax.set_xlabel("Host %")
    ax.set_title("Runtime comparison")
    ax.legend(frameon=False)

    # Memory
    ax = axes[1]
    memory_cols = {
        "sylph": "sylph_memory_gb",
        "rc_auto_skipqc": "rc_auto_skipqc_memory_gb",
        "hostile": "hostile_memory_gb",
        "kneaddata": "kneaddata_memory_gb",
    }
    for i, tool in enumerate(tools):
        vals = [r[memory_cols[tool]] for r in summary_rows]
        ax.bar(x + (i - 1.5) * width, vals, width, label=tool, color=colors[tool])
    ax.set_ylabel("Memory (GB)")
    ax.set_xticks(x)
    ax.set_xticklabels([dataset_host_pct(d) for d in datasets])
    ax.set_xlabel("Host %")
    ax.set_title("Memory comparison")
    ax.legend(frameon=False)

    # F1
    ax = axes[2]
    f1_cols = {
        "sylph": "sylph_f1",
        "rc_auto_skipqc": "rc_auto_skipqc_f1",
        "hostile": "hostile_f1",
        "kneaddata": "kneaddata_f1",
    }
    for i, tool in enumerate(tools):
        vals = [r[f1_cols[tool]] for r in summary_rows]
        ax.bar(x + (i - 1.5) * width, vals, width, label=tool, color=colors[tool])
    ax.set_ylabel("F1 score")
    ax.set_ylim(0.92, 1.005)
    ax.set_xticks(x)
    ax.set_xticklabels([dataset_host_pct(d) for d in datasets])
    ax.set_xlabel("Host %")
    ax.set_title("F1 comparison")
    ax.legend(frameon=False)

    plt.tight_layout()
    out_fig = OUT_DIR / "sylph_backend_comparison.png"
    plt.savefig(out_fig, dpi=300)
    print(f"Wrote {out_fig}")


if __name__ == "__main__":
    main()
