#!/usr/bin/env python3
"""
Aggregate matched panel n=4 results for RustyClean (skip-qc + auto-survey),
Hostile, and KneadData across 4 datasets:
  30M_50pct_high_skewed_SE
  60M_90pct_high_lognormal_SE
  100M_50pct_high_lognormal_SE
  100M_90pct_high_lognormal_SE
"""

import sys
from pathlib import Path
import pandas as pd


PANEL_DATASETS = [
    "30M_50pct_high_skewed_SE",
    "60M_90pct_high_lognormal_SE",
    "100M_50pct_high_lognormal_SE",
    "100M_90pct_high_lognormal_SE",
]


def load_rc_accuracy():
    path = Path("/lustre1/g/aos_shihuang/rustyclean-paper/rustyclean_auto_skipqc_survey_matched/analysis/accuracy_skipqc_matched.csv")
    df = pd.read_csv(path)
    df = df[df["dataset"].isin(PANEL_DATASETS)].copy()
    df = df.rename(columns={"dataset": "Dataset", "tool": "Tool", "f1": "F1", "accuracy": "Accuracy", "precision": "Precision", "recall": "Recall"})
    return df[["Dataset", "Tool", "rep", "Accuracy", "Precision", "Recall", "F1"]]


def load_hostile_accuracy():
    # 30M/60M
    df1 = pd.read_csv("/lustre1/g/aos_shihuang/rustyclean-paper/analysis_hostile_accuracy/accuracy.csv")
    df1 = df1[(df1["Dataset"].isin(PANEL_DATASETS)) & (df1["Tool"] == "hostile")].copy()
    # 100M
    df2 = pd.read_csv("/lustre1/g/aos_shihuang/rustyclean-paper/analysis_hostile_100M_accuracy/accuracy.csv")
    df2 = df2[(df2["Dataset"].isin(PANEL_DATASETS)) & (df2["Tool"] == "hostile")].copy()
    df = pd.concat([df1, df2], ignore_index=True)
    df["rep"] = 1
    return df[["Dataset", "Tool", "rep", "Accuracy", "Precision", "Recall", "F1"]]


def load_kneaddata_accuracy():
    # 30M/60M
    df1 = pd.read_csv("/lustre1/g/aos_shihuang/rustyclean-paper/analysis_hostile_accuracy/accuracy.csv")
    df1 = df1[(df1["Dataset"].isin(PANEL_DATASETS)) & (df1["Tool"] == "kneaddata")].copy()
    # 100M
    df2 = pd.read_csv("/lustre1/g/aos_shihuang/rustyclean-paper/analysis_kneaddata_100M_accuracy/accuracy.csv")
    df2 = df2[(df2["Dataset"].isin(PANEL_DATASETS)) & (df2["Tool"] == "kneaddata")].copy()
    df = pd.concat([df1, df2], ignore_index=True)
    df["rep"] = 1
    return df[["Dataset", "Tool", "rep", "Accuracy", "Precision", "Recall", "F1"]]


def load_rc_performance():
    path = Path("/lustre1/g/aos_shihuang/rustyclean-paper/rustyclean_auto_skipqc_survey_matched/metrics/performance.csv")
    df = pd.read_csv(path)
    df = df[df["dataset"].isin(PANEL_DATASETS)].copy()
    df["runtime_min"] = df["runtime_seconds"] / 60.0
    df["memory_gb"] = df["max_memory_kb"] / 1024.0 / 1024.0
    return df


def load_hostile_performance():
    df1 = pd.read_csv("/lustre1/g/aos_shihuang/rustyclean-paper/results_hostile_centrifuge/metrics/performance.csv")
    df1 = df1[(df1["dataset"].isin(PANEL_DATASETS)) & (df1["tool"] == "hostile")].copy()
    df2 = pd.read_csv("/lustre1/g/aos_shihuang/rustyclean-paper/hostile_100M_matched/metrics/performance.csv")
    df2 = df2[(df2["dataset"].isin(PANEL_DATASETS)) & (df2["tool"] == "hostile")].copy()
    df = pd.concat([df1, df2], ignore_index=True)
    df["runtime_min"] = df["runtime_seconds"] / 60.0
    df["memory_gb"] = df["max_memory_kb"] / 1024.0 / 1024.0
    return df


def load_kneaddata_performance():
    df1 = pd.read_csv("/lustre1/g/aos_shihuang/rustyclean-paper/results_hostile_centrifuge/metrics/performance.csv")
    df1 = df1[(df1["dataset"].isin(PANEL_DATASETS)) & (df1["tool"] == "kneaddata")].copy()
    df2 = pd.read_csv("/lustre1/g/aos_shihuang/rustyclean-paper/kneaddata_100M_matched/metrics/performance.csv")
    df2 = df2[(df2["dataset"].isin(PANEL_DATASETS)) & (df2["tool"] == "kneaddata")].copy()
    df = pd.concat([df1, df2], ignore_index=True)
    df["runtime_min"] = df["runtime_seconds"] / 60.0
    df["memory_gb"] = df["max_memory_kb"] / 1024.0 / 1024.0
    return df


def summarize_accuracy(df):
    summary = df.groupby(["Dataset", "Tool"]).agg(
        Accuracy_mean=("Accuracy", "mean"),
        Accuracy_std=("Accuracy", "std"),
        Precision_mean=("Precision", "mean"),
        Precision_std=("Precision", "std"),
        Recall_mean=("Recall", "mean"),
        Recall_std=("Recall", "std"),
        F1_mean=("F1", "mean"),
        F1_std=("F1", "std"),
    ).reset_index()
    return summary


def summarize_performance(df):
    summary = df.groupby(["dataset", "tool"]).agg(
        runtime_min_mean=("runtime_min", "mean"),
        runtime_min_std=("runtime_min", "std"),
        memory_gb_mean=("memory_gb", "mean"),
        memory_gb_std=("memory_gb", "std"),
    ).reset_index()
    return summary


def main():
    out_dir = Path("/lustre1/g/aos_shihuang/rustyclean-paper/analysis_matched_panel_n4")
    out_dir.mkdir(parents=True, exist_ok=True)

    # Accuracy
    rc_acc = load_rc_accuracy()
    hostile_acc = load_hostile_accuracy()
    kneaddata_acc = load_kneaddata_accuracy()
    acc_all = pd.concat([rc_acc, hostile_acc, kneaddata_acc], ignore_index=True)
    acc_all.to_csv(out_dir / "accuracy_matched_panel_n4.csv", index=False)
    acc_summary = summarize_accuracy(acc_all)
    acc_summary.to_csv(out_dir / "accuracy_summary_matched_panel_n4.csv", index=False)

    # Performance
    rc_perf = load_rc_performance()
    hostile_perf = load_hostile_performance()
    kneaddata_perf = load_kneaddata_performance()
    perf_all = pd.concat([rc_perf, hostile_perf, kneaddata_perf], ignore_index=True)
    perf_all.to_csv(out_dir / "performance_matched_panel_n4.csv", index=False)
    perf_summary = summarize_performance(perf_all)
    perf_summary.to_csv(out_dir / "performance_summary_matched_panel_n4.csv", index=False)

    print(f"Wrote matched panel n=4 results to {out_dir}")
    print("\nAccuracy summary:")
    print(acc_summary.round(4).to_string(index=False))
    print("\nPerformance summary:")
    print(perf_summary.round(2).to_string(index=False))


if __name__ == "__main__":
    main()
