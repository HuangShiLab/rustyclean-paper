#!/usr/bin/env python3
"""
Compare RustyClean T2T-only Kraken2 + T2T+HLA Bowtie2 recheck
against Hostile and KneadData on the matched n=4 panel.
"""

from pathlib import Path
import pandas as pd


PANEL_DATASETS = [
    "30M_50pct_high_skewed_SE",
    "60M_90pct_high_lognormal_SE",
    "100M_50pct_high_lognormal_SE",
    "100M_90pct_high_lognormal_SE",
]


def load_accuracy():
    # RustyClean T2T-only
    rc = pd.read_csv("/lustre1/g/aos_shihuang/rustyclean-paper/rustyclean_t2t_only_matched/analysis/accuracy_skipqc_matched.csv")
    rc = rc[rc["dataset"].isin(PANEL_DATASETS)].copy()
    rc = rc.rename(columns={"dataset": "Dataset", "tool": "Tool", "f1": "F1", "accuracy": "Accuracy", "precision": "Precision", "recall": "Recall"})

    # Hostile 30M/60M
    h1 = pd.read_csv("/lustre1/g/aos_shihuang/rustyclean-paper/analysis_hostile_accuracy/accuracy.csv")
    h1 = h1[(h1["Dataset"].isin(PANEL_DATASETS)) & (h1["Tool"] == "hostile")].copy()
    # Hostile 100M
    h2 = pd.read_csv("/lustre1/g/aos_shihuang/rustyclean-paper/analysis_hostile_100M_accuracy/accuracy.csv")
    h2 = h2[(h2["Dataset"].isin(PANEL_DATASETS)) & (h2["Tool"] == "hostile")].copy()
    hostile = pd.concat([h1, h2], ignore_index=True)
    hostile["rep"] = 1

    # KneadData 30M/60M
    k1 = pd.read_csv("/lustre1/g/aos_shihuang/rustyclean-paper/analysis_hostile_accuracy/accuracy.csv")
    k1 = k1[(k1["Dataset"].isin(PANEL_DATASETS)) & (k1["Tool"] == "kneaddata")].copy()
    # KneadData 100M
    k2 = pd.read_csv("/lustre1/g/aos_shihuang/rustyclean-paper/analysis_kneaddata_100M_accuracy/accuracy.csv")
    k2 = k2[(k2["Dataset"].isin(PANEL_DATASETS)) & (k2["Tool"] == "kneaddata")].copy()
    kneaddata = pd.concat([k1, k2], ignore_index=True)
    kneaddata["rep"] = 1

    return pd.concat([rc, hostile, kneaddata], ignore_index=True)[["Dataset", "Tool", "rep", "Accuracy", "Precision", "Recall", "F1"]]


def load_performance():
    # RustyClean T2T-only
    rc = pd.read_csv("/lustre1/g/aos_shihuang/rustyclean-paper/rustyclean_t2t_only_matched/metrics/performance.csv")
    rc = rc[rc["dataset"].isin(PANEL_DATASETS)].copy()
    rc["runtime_min"] = rc["runtime_seconds"] / 60.0
    rc["memory_gb"] = rc["max_memory_kb"] / 1024.0 / 1024.0

    # Hostile
    h1 = pd.read_csv("/lustre1/g/aos_shihuang/rustyclean-paper/results_hostile_centrifuge/metrics/performance.csv")
    h1 = h1[(h1["dataset"].isin(PANEL_DATASETS)) & (h1["tool"] == "hostile")].copy()
    h2 = pd.read_csv("/lustre1/g/aos_shihuang/rustyclean-paper/hostile_100M_matched/metrics/performance.csv")
    h2 = h2[(h2["dataset"].isin(PANEL_DATASETS)) & (h2["tool"] == "hostile")].copy()
    hostile = pd.concat([h1, h2], ignore_index=True)
    hostile["runtime_min"] = hostile["runtime_seconds"] / 60.0
    hostile["memory_gb"] = hostile["max_memory_kb"] / 1024.0 / 1024.0

    # KneadData
    k1 = pd.read_csv("/lustre1/g/aos_shihuang/rustyclean-paper/results_hostile_centrifuge/metrics/performance.csv")
    k1 = k1[(k1["dataset"].isin(PANEL_DATASETS)) & (k1["tool"] == "kneaddata")].copy()
    k2 = pd.read_csv("/lustre1/g/aos_shihuang/rustyclean-paper/kneaddata_100M_matched/metrics/performance.csv")
    k2 = k2[(k2["dataset"].isin(PANEL_DATASETS)) & (k2["tool"] == "kneaddata")].copy()
    kneaddata = pd.concat([k1, k2], ignore_index=True)
    kneaddata["runtime_min"] = kneaddata["runtime_seconds"] / 60.0
    kneaddata["memory_gb"] = kneaddata["max_memory_kb"] / 1024.0 / 1024.0

    return pd.concat([rc, hostile, kneaddata], ignore_index=True)


def main():
    out_dir = Path("/lustre1/g/aos_shihuang/rustyclean-paper/analysis_t2t_only_panel")
    out_dir.mkdir(parents=True, exist_ok=True)

    acc = load_accuracy()
    acc.to_csv(out_dir / "accuracy_t2t_only_panel.csv", index=False)
    acc_summary = acc.groupby(["Dataset", "Tool"]).agg(
        Accuracy_mean=("Accuracy", "mean"),
        Accuracy_std=("Accuracy", "std"),
        Precision_mean=("Precision", "mean"),
        Precision_std=("Precision", "std"),
        Recall_mean=("Recall", "mean"),
        Recall_std=("Recall", "std"),
        F1_mean=("F1", "mean"),
        F1_std=("F1", "std"),
    ).reset_index()
    acc_summary.to_csv(out_dir / "accuracy_summary_t2t_only_panel.csv", index=False)

    perf = load_performance()
    perf.to_csv(out_dir / "performance_t2t_only_panel.csv", index=False)
    perf_summary = perf.groupby(["dataset", "tool"]).agg(
        runtime_min_mean=("runtime_min", "mean"),
        runtime_min_std=("runtime_min", "std"),
        memory_gb_mean=("memory_gb", "mean"),
        memory_gb_std=("memory_gb", "std"),
    ).reset_index()
    perf_summary.to_csv(out_dir / "performance_summary_t2t_only_panel.csv", index=False)

    print(f"Wrote T2T-only panel comparison to {out_dir}")
    print("\nAccuracy summary:")
    print(acc_summary.round(4).to_string(index=False))
    print("\nPerformance summary:")
    print(perf_summary.round(2).to_string(index=False))


if __name__ == "__main__":
    main()
