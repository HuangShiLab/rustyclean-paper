#!/usr/bin/env python3
# =============================================================================
# RustyClean Benchmark - Comprehensive Publication Figures (v2)
# =============================================================================
# Generates six publication-quality figures for the HPC benchmark paper,
# combining results from the human multi-tool comparison, RustyClean mode
# decision-boundary analysis, AUTO scalability, cross-species validation,
# and real-data validation.
#
# Usage:
#     python scripts/generate_publication_figures_v2.py [output_dir]
#
# The optional output_dir defaults to:
#     /lustre1/g/aos_shihuang/rustyclean-paper/results_analysis/figures
# =============================================================================

import json
import os
import re
import sys

import matplotlib as mpl

mpl.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import seaborn as sns

# -----------------------------------------------------------------------------
# Base directory on the HPC filesystem.  Can be overridden via environment
# variable so the same script can be tested outside the production path.
# -----------------------------------------------------------------------------
BASE_DIR = os.environ.get(
    "RUSTYCLEAN_PAPER_DIR", "/lustre1/g/aos_shihuang/rustyclean-paper"
)
DEFAULT_OUTPUT_DIR = os.path.join(BASE_DIR, "analysis_final_v3", "figures")

# -----------------------------------------------------------------------------
# Matplotlib rcParams - Nature/Cell style
# -----------------------------------------------------------------------------
mpl.rcParams.update(
    {
        "font.family": "sans-serif",
        "font.sans-serif": ["Arial", "Helvetica", "DejaVu Sans", "sans-serif"],
        "font.size": 7,
        "axes.labelsize": 8,
        "axes.titlesize": 9,
        "xtick.labelsize": 7,
        "ytick.labelsize": 7,
        "legend.fontsize": 7,
        "axes.spines.right": False,
        "axes.spines.top": False,
        "axes.linewidth": 0.8,
        "xtick.major.width": 0.8,
        "ytick.major.width": 0.8,
        "xtick.major.size": 3,
        "ytick.major.size": 3,
        "legend.frameon": False,
        "figure.dpi": 300,
        "svg.fonttype": "none",
        "pdf.fonttype": 42,
    }
)

# -----------------------------------------------------------------------------
# Color palette
# -----------------------------------------------------------------------------
COLORS = {
    "rustyclean": "#4A90A4",
    "kneaddata": "#C75B5B",
    "hostile": "#E8A838",
    "centrifuge": "#8FA876",
    "bowtie2": "#5B9A6D",
    "kraken2": "#C75B5B",
    "auto": "#4A90A4",
    "neutral": "#7F8C8D",
}


def tool_color(tool_name: str) -> str:
    """Return the publication color for a tool / mode name."""
    t = str(tool_name).lower().replace("-", "_").strip()
    mapping = {
        "rustyclean_k2": COLORS["rustyclean"],
        "rustyclean_cf": COLORS["centrifuge"],
        "rustyclean_bt2": COLORS["bowtie2"],
        "rustyclean_auto": COLORS["auto"],
        "kneaddata": COLORS["kneaddata"],
        "hostile": COLORS["hostile"],
        "centrifuge": COLORS["centrifuge"],
        "kraken2": COLORS["kraken2"],
        "bowtie2": COLORS["bowtie2"],
        "auto": COLORS["auto"],
    }
    return mapping.get(t, COLORS["neutral"])


def tool_label(tool_name: str) -> str:
    """Return a human-readable label for a tool / mode name."""
    t = str(tool_name).lower().replace("-", "_").strip()
    mapping = {
        "rustyclean_k2": "RustyClean (K2)",
        "rustyclean_cf": "RustyClean (CF)",
        "rustyclean_bt2": "RustyClean (BT2)",
        "rustyclean_auto": "RustyClean (AUTO)",
        "kneaddata": "KneadData",
        "hostile": "Hostile",
        "centrifuge": "Centrifuge",
        "kraken2": "Kraken2",
        "bowtie2": "Bowtie2",
        "auto": "AUTO",
    }
    return mapping.get(t, str(tool_name))


# -----------------------------------------------------------------------------
# Constants describing the expected experimental layout
# -----------------------------------------------------------------------------
HUMAN_DATASETS = [
    "5M_1pct_low_even_SE",
    "10M_10pct_med_even_SE",
    "30M_50pct_high_skewed_SE",
    "60M_90pct_high_lognormal_SE",
]

HUMAN_TOOLS = ["rustyclean_k2", "rustyclean_cf", "kneaddata", "hostile"]
REAL_SAMPLES = ["oral_saliva", "vaginal_swab", "breast_cancer_stool"]
REAL_TOOLS = [
    "rustyclean_k2",
    "rustyclean_bt2",
    "rustyclean_auto",
    "kneaddata",
    "hostile",
    "centrifuge",
]
CROSS_SPECIES_ORDER = ["human", "mouse", "rat", "pig", "rice", "monkey"]
RC_MODES = ["kraken2", "bowtie2", "auto"]


# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
def parse_time_to_seconds(value):
    """Parse GNU time elapsed strings (m:ss, h:mm:ss) to seconds."""
    if isinstance(value, (int, float)):
        return float(value)
    if value is None or pd.isna(value):
        return np.nan
    s = str(value).strip()
    if s.lower() in ("", "unknown", "na", "nan"):
        return np.nan
    parts = s.split(":")
    try:
        if len(parts) == 3:
            return int(parts[0]) * 3600 + int(parts[1]) * 60 + float(parts[2])
        if len(parts) == 2:
            return int(parts[0]) * 60 + float(parts[1])
        return float(parts[0])
    except (ValueError, TypeError):
        return np.nan


def read_csv(path: str):
    """Read a CSV if it exists, otherwise return None."""
    if not path or not os.path.exists(path):
        return None
    try:
        return pd.read_csv(path)
    except Exception as exc:
        print(f"Warning: could not read {path}: {exc}")
        return None


def read_json(path: str):
    """Read a JSON file if it exists, otherwise return None."""
    if not path or not os.path.exists(path):
        return None
    try:
        with open(path) as fh:
            return json.load(fh)
    except Exception as exc:
        print(f"Warning: could not read {path}: {exc}")
        return None


def prepare_performance(df: pd.DataFrame) -> pd.DataFrame:
    """Normalize a performance DataFrame: parse runtime and add memory units."""
    df = df.copy()
    if "runtime_seconds" in df.columns:
        df["runtime_seconds"] = df["runtime_seconds"].apply(parse_time_to_seconds)
    for col in ("max_memory_kb", "memory_kb"):
        if col in df.columns:
            df["memory_mb"] = pd.to_numeric(df[col], errors="coerce") / 1024
            df["memory_gb"] = df["memory_mb"] / 1024
            break
    # Standardise column names that may vary across result sets.
    df = df.rename(columns={"sample": "dataset"})
    if "tool" in df.columns:
        df["tool"] = df["tool"].str.lower().str.strip()
    if "dataset" in df.columns:
        df["dataset"] = df["dataset"].str.strip()
    return df


def extract_host_pct(name: str) -> float:
    """Extract host percentage from a dataset name such as '10M_10pct_*'."""
    m = re.search(r"_(\d+)pct_", str(name))
    if m:
        return float(m.group(1)) / 100.0
    return np.nan


def extract_species(name: str) -> str:
    """Extract species token from dataset names such as 'human_5M_1pct'."""
    return str(name).split("_")[0].lower()


def save_figure(fig, name: str, output_dir: str):
    """Save a figure in SVG, PDF, PNG (300 dpi) and TIFF (600 dpi)."""
    os.makedirs(output_dir, exist_ok=True)
    base = os.path.join(output_dir, name)
    fig.savefig(f"{base}.svg", bbox_inches="tight", format="svg")
    fig.savefig(f"{base}.pdf", bbox_inches="tight", format="pdf")
    fig.savefig(f"{base}.png", dpi=300, bbox_inches="tight", format="png")
    fig.savefig(f"{base}.tiff", dpi=600, bbox_inches="tight", format="tiff")
    print(f"  Saved {name}.{{svg,pdf,png,tiff}}")


def grouped_bar_with_error(
    ax,
    df: pd.DataFrame,
    x_col: str,
    y_col: str,
    group_col: str,
    groups: list,
    categories: list,
    width: float = 0.18,
    ylabel: str = "",
    title: str = "",
    yscale: str = None,
    ylim=None,
):
    """Draw grouped bars with optional error bars from std."""
    x = np.arange(len(categories))
    n = len(groups)
    for i, grp in enumerate(groups):
        grp_df = df[df[group_col] == grp]
        means = []
        stds = []
        for cat in categories:
            sub = grp_df[grp_df[x_col] == cat]
            if len(sub):
                means.append(sub[y_col].mean())
                stds.append(sub[y_col].std(ddof=0) if len(sub) > 1 else 0)
            else:
                means.append(0)
                stds.append(0)
        offset = (i - (n - 1) / 2) * width
        ax.bar(
            x + offset,
            means,
            width,
            yerr=stds,
            label=tool_label(grp),
            color=tool_color(grp),
            edgecolor="white",
            linewidth=0.5,
            capsize=2,
            error_kw={"linewidth": 0.8},
        )
    ax.set_xticks(x)
    ax.set_xticklabels(categories, rotation=45, ha="right", fontsize=6)
    ax.set_xlabel("Dataset", fontweight="bold")
    if ylabel:
        ax.set_ylabel(ylabel, fontweight="bold")
    if title:
        ax.set_title(title, fontweight="bold", fontsize=10, loc="left")
    if yscale:
        ax.set_yscale(yscale)
    if ylim is not None:
        ax.set_ylim(ylim)
    ax.legend(loc="best", title="Tool")


# -----------------------------------------------------------------------------
# Figure 1: Human 4-dataset multi-tool runtime / memory / speedup
# -----------------------------------------------------------------------------
def plot_figure_1_human_comparison(output_dir: str):
    """Figure 1: runtime, memory, and speedup for the human 4-dataset panel."""
    print("\n[Figure 1] Human 4-dataset comparison")
    perf_path = os.path.join(BASE_DIR, "results_hostile_centrifuge", "metrics", "performance.csv")
    df = read_csv(perf_path)
    if df is None or df.empty:
        print("  Warning: performance data not found; skipping Figure 1.")
        return

    df = prepare_performance(df)
    df = df[df["dataset"].isin(HUMAN_DATASETS) & df["tool"].isin(HUMAN_TOOLS)]
    if df.empty:
        print("  Warning: no matching human performance data; skipping Figure 1.")
        return

    fig = plt.figure(figsize=(8.5, 3.0))
    gs = fig.add_gridspec(1, 3, width_ratios=[1.2, 1.2, 1.0], wspace=0.35)

    # Panel A: runtime
    ax1 = fig.add_subplot(gs[0])
    grouped_bar_with_error(
        ax1,
        df,
        x_col="dataset",
        y_col="runtime_seconds",
        group_col="tool",
        groups=[t for t in HUMAN_TOOLS if t in df["tool"].unique()],
        categories=HUMAN_DATASETS,
        width=0.18,
        ylabel="Runtime (s)",
        title="A",
        yscale="log",
    )

    # Panel B: memory
    ax2 = fig.add_subplot(gs[1])
    grouped_bar_with_error(
        ax2,
        df,
        x_col="dataset",
        y_col="memory_gb",
        group_col="tool",
        groups=[t for t in HUMAN_TOOLS if t in df["tool"].unique()],
        categories=HUMAN_DATASETS,
        width=0.18,
        ylabel="Peak memory (GB)",
        title="B",
    )

    # Panel C: speedup relative to KneadData
    ax3 = fig.add_subplot(gs[2])
    summary = (
        df.groupby(["dataset", "tool"])["runtime_seconds"]
        .agg(["mean", "std"])
        .reset_index()
    )
    base = (
        summary[summary["tool"] == "kneaddata"][["dataset", "mean"]]
        .rename(columns={"mean": "kneaddata_mean"})
    )
    speedup = summary[summary["tool"] != "kneaddata"].merge(base, on="dataset", how="inner")
    speedup["speedup"] = speedup["kneaddata_mean"] / speedup["mean"]

    tools = [t for t in HUMAN_TOOLS if t != "kneaddata" and t in speedup["tool"].unique()]
    x = np.arange(len(HUMAN_DATASETS))
    width = 0.22
    for i, tool in enumerate(tools):
        tool_df = speedup[speedup["tool"] == tool]
        vals = [
            tool_df[tool_df["dataset"] == d]["speedup"].values[0]
            if len(tool_df[tool_df["dataset"] == d])
            else np.nan
            for d in HUMAN_DATASETS
        ]
        offset = (i - (len(tools) - 1) / 2) * width
        ax3.bar(
            x + offset,
            vals,
            width,
            label=tool_label(tool),
            color=tool_color(tool),
            edgecolor="white",
            linewidth=0.5,
        )
        for xi, v in zip(x + offset, vals):
            if not np.isnan(v):
                ax3.text(xi, v * 1.08, f"{v:.1f}×", ha="center", va="bottom", fontsize=5)

    ax3.axhline(1.0, color="black", linestyle="--", linewidth=0.8, alpha=0.5)
    ax3.set_xticks(x)
    ax3.set_xticklabels(HUMAN_DATASETS, rotation=45, ha="right", fontsize=6)
    ax3.set_xlabel("Dataset", fontweight="bold")
    ax3.set_ylabel("Speedup vs. KneadData", fontweight="bold")
    ax3.set_title("C", fontweight="bold", fontsize=10, loc="left")
    ax3.set_yscale("log")
    ax3.legend(loc="best", title="Tool")

    plt.tight_layout()
    save_figure(fig, "figure_1_human_comparison", output_dir)
    plt.close(fig)


# -----------------------------------------------------------------------------
# Figure 2: Human 4-dataset accuracy (Precision / Recall / F1)
# -----------------------------------------------------------------------------
def plot_figure_2_human_accuracy(output_dir: str):
    """Figure 2: Precision, Recall, and F1 for the human 4-dataset panel."""
    print("\n[Figure 2] Human 4-dataset accuracy")
    acc_path = os.path.join(BASE_DIR, "analysis_final_v3", "accuracy_hostile", "accuracy.csv")
    df = read_csv(acc_path)
    if df is None or df.empty:
        print("  Warning: accuracy data not found; skipping Figure 2.")
        return

    df.columns = [c.lower() for c in df.columns]
    if "dataset" not in df.columns or "tool" not in df.columns:
        print("  Warning: accuracy CSV missing required columns; skipping Figure 2.")
        return

    df = df[df["dataset"].isin(HUMAN_DATASETS) & df["tool"].isin(HUMAN_TOOLS)]
    if df.empty:
        print("  Warning: no matching human accuracy data; skipping Figure 2.")
        return

    fig = plt.figure(figsize=(8.5, 2.8))
    gs = fig.add_gridspec(1, 3, wspace=0.4)
    metrics = [("precision", "Precision"), ("recall", "Recall"), ("f1", "F1-score")]
    tools = [t for t in HUMAN_TOOLS if t in df["tool"].unique()]

    for idx, (metric, title) in enumerate(metrics):
        ax = fig.add_subplot(gs[idx])
        grouped_bar_with_error(
            ax,
            df,
            x_col="dataset",
            y_col=metric,
            group_col="tool",
            groups=tools,
            categories=HUMAN_DATASETS,
            width=0.18,
            ylabel=title,
            title=chr(65 + idx),
            ylim=(0.8, 1.01),
        )

    plt.tight_layout()
    save_figure(fig, "figure_2_human_accuracy", output_dir)
    plt.close(fig)


# -----------------------------------------------------------------------------
# Figure 3: RustyClean mode decision boundary
# -----------------------------------------------------------------------------
def load_mode_summary():
    """Load the RustyClean AUTO mode summary written by analyze_decision_boundary.py."""
    candidates = [
        os.path.join(BASE_DIR, "analysis_final_v3", "decision_boundary", "mode_summary.csv"),
        os.path.join(BASE_DIR, "results_analysis", "mode_summary.csv"),
        os.path.join(BASE_DIR, "results_rc_modes", "metrics", "mode_summary.csv"),
    ]
    for path in candidates:
        df = read_csv(path)
        if df is not None and not df.empty:
            return df
    return None


def prepare_mode_summary(df: pd.DataFrame) -> pd.DataFrame:
    """Normalise mode-summary column names and derive host_pct if absent."""
    df = df.copy()
    df.columns = [c.lower() for c in df.columns]
    # Normalise string columns.
    for col in ("mode", "chosen_mode", "expected_mode"):
        if col in df.columns:
            df[col] = df[col].astype(str).str.lower().str.strip()
    if "dataset" in df.columns:
        df["dataset"] = df["dataset"].str.strip()
    if "host_pct" not in df.columns and "dataset" in df.columns:
        df["host_pct"] = df["dataset"].apply(extract_host_pct)
    # Provide a unified 'mode' column for panels A/B while keeping chosen_mode
    # intact for the decision-region panel.
    if "mode" not in df.columns and "chosen_mode" in df.columns:
        df["mode"] = df["chosen_mode"]
    if "chosen_mode" not in df.columns and "mode" in df.columns:
        df["chosen_mode"] = df["mode"]
    return df


def load_rc_mode_accuracy():
    """Fallback accuracy for RustyClean modes (if mode_summary lacks F1)."""
    path = os.path.join(BASE_DIR, "results_rc_modes", "metrics", "accuracy.csv")
    df = read_csv(path)
    if df is None or df.empty:
        return None
    df.columns = [c.lower() for c in df.columns]
    return df


def plot_figure_3_rc_mode_decision(output_dir: str):
    """Figure 3: runtime vs host%, F1 vs host%, and AUTO chosen-mode region."""
    print("\n[Figure 3] RustyClean mode decision boundary")
    perf_path = os.path.join(BASE_DIR, "results_rc_modes", "metrics", "performance.csv")
    perf = read_csv(perf_path)
    mode_summary = load_mode_summary()

    if perf is None or perf.empty:
        print("  Warning: RC-mode performance data not found; skipping Figure 3.")
        return

    perf = prepare_performance(perf)
    perf["host_pct"] = perf["dataset"].apply(extract_host_pct)
    perf = perf[perf["tool"].isin(RC_MODES)]

    fig = plt.figure(figsize=(8.5, 2.8))
    gs = fig.add_gridspec(1, 3, wspace=0.4)

    # Panel A: runtime vs host%
    ax1 = fig.add_subplot(gs[0])
    for tool in RC_MODES:
        sub = perf[perf["tool"] == tool]
        if sub.empty:
            continue
        summ = sub.groupby("host_pct")["runtime_seconds"].agg(["mean", "std"]).reset_index()
        ax1.plot(
            summ["host_pct"],
            summ["mean"],
            marker="o",
            markersize=4,
            label=tool_label(tool),
            color=tool_color(tool),
            linewidth=1.2,
        )
        ax1.fill_between(
            summ["host_pct"],
            summ["mean"] - summ["std"],
            summ["mean"] + summ["std"],
            color=tool_color(tool),
            alpha=0.15,
        )
    ax1.set_xlabel("Host contamination proportion", fontweight="bold")
    ax1.set_ylabel("Runtime (s)", fontweight="bold")
    ax1.set_title("A", fontweight="bold", fontsize=10, loc="left")
    ax1.set_yscale("log")
    ax1.legend(loc="best", title="Mode")

    # Panel B: F1 vs host%
    ax2 = fig.add_subplot(gs[1])
    f1_available = False
    if mode_summary is not None and not mode_summary.empty:
        ms = prepare_mode_summary(mode_summary)
        if "f1" in ms.columns:
            f1_available = True
            for tool in RC_MODES:
                sub = ms[ms["mode"] == tool]
                if sub.empty:
                    continue
                summ = sub.groupby("host_pct")["f1"].agg(["mean", "std"]).reset_index()
                ax2.plot(
                    summ["host_pct"],
                    summ["mean"],
                    marker="o",
                    markersize=4,
                    label=tool_label(tool),
                    color=tool_color(tool),
                    linewidth=1.2,
                )
                ax2.fill_between(
                    summ["host_pct"],
                    np.clip(summ["mean"] - summ["std"], 0, 1),
                    np.clip(summ["mean"] + summ["std"], 0, 1),
                    color=tool_color(tool),
                    alpha=0.15,
                )

    if not f1_available:
        # Fallback: try standalone accuracy CSV and merge host_pct from dataset names.
        acc = load_rc_mode_accuracy()
        if acc is not None and not acc.empty and "dataset" in acc.columns:
            acc["host_pct"] = acc["dataset"].apply(extract_host_pct)
            for tool in RC_MODES:
                sub = acc[acc["tool"] == tool]
                if sub.empty:
                    continue
                summ = sub.groupby("host_pct")["f1"].agg(["mean", "std"]).reset_index()
                ax2.plot(
                    summ["host_pct"],
                    summ["mean"],
                    marker="o",
                    markersize=4,
                    label=tool_label(tool),
                    color=tool_color(tool),
                    linewidth=1.2,
                )
            f1_available = True

    if not f1_available:
        print("  Warning: no F1 data available for RC-mode panel B.")

    ax2.set_xlabel("Host contamination proportion", fontweight="bold")
    ax2.set_ylabel("F1-score", fontweight="bold")
    ax2.set_title("B", fontweight="bold", fontsize=10, loc="left")
    ax2.set_ylim(0.8, 1.01)
    ax2.legend(loc="best", title="Mode")

    # Panel C: chosen-mode region
    ax3 = fig.add_subplot(gs[2])
    region_plotted = False
    if mode_summary is not None and not mode_summary.empty:
        ms = prepare_mode_summary(mode_summary)
        if "chosen_mode" in ms.columns or "mode" in ms.columns:
            region_df = ms.copy()
            if "chosen_mode" in region_df.columns:
                region_df["chosen"] = region_df["chosen_mode"].str.lower().str.strip()
            else:
                # If no explicit chosen_mode column, use the AUTO rows.
                region_df = region_df[region_df["mode"] == "auto"]
                region_df["chosen"] = region_df["expected_mode"] if "expected_mode" in region_df.columns else None

            if region_df["chosen"].notna().any():
                region_plotted = True
                mode_order = ["bowtie2", "kraken2"]
                mode_num = {m: i for i, m in enumerate(mode_order)}
                region_df["chosen_num"] = region_df["chosen"].map(mode_num)
                region_df = region_df.sort_values("host_pct")

                for mode, num in mode_num.items():
                    sub = region_df[region_df["chosen"] == mode]
                    if sub.empty:
                        continue
                    ax3.scatter(
                        sub["host_pct"],
                        sub["chosen_num"],
                        label=tool_label(mode),
                        color=tool_color(mode),
                        s=40,
                        marker="s",
                        edgecolors="white",
                        linewidth=0.5,
                        zorder=3,
                    )

                # Overlay expected boundary if available.
                if "expected_mode" in region_df.columns:
                    region_df["expected_num"] = region_df["expected_mode"].str.lower().str.strip().map(mode_num)
                    region_df_sorted = region_df.sort_values("host_pct")
                    ax3.plot(
                        region_df_sorted["host_pct"],
                        region_df_sorted["expected_num"],
                        color="black",
                        linewidth=1.0,
                        linestyle="--",
                        label="Expected boundary",
                        zorder=2,
                    )

                ax3.set_yticks(list(mode_num.values()))
                ax3.set_yticklabels([tool_label(m) for m in mode_order])
                ax3.set_ylim(-0.5, len(mode_order) - 0.5)
                ax3.set_xlabel("Host contamination proportion", fontweight="bold")
                ax3.set_ylabel("AUTO chosen mode", fontweight="bold")
                ax3.set_title("C", fontweight="bold", fontsize=10, loc="left")
                ax3.legend(loc="best", title="Mode")

    if not region_plotted:
        ax3.text(0.5, 0.5, "No chosen-mode data", ha="center", va="center", transform=ax3.transAxes)
        ax3.set_title("C", fontweight="bold", fontsize=10, loc="left")

    plt.tight_layout()
    save_figure(fig, "figure_3_rc_mode_decision", output_dir)
    plt.close(fig)


# -----------------------------------------------------------------------------
# Figure 4: AUTO scalability
# -----------------------------------------------------------------------------
def plot_figure_4_auto_scalability(output_dir: str):
    """Figure 4: AUTO runtime, throughput, and branch correctness."""
    print("\n[Figure 4] AUTO scalability")
    path = os.path.join(BASE_DIR, "analysis_final_v3", "auto_scale", "scaling_summary.json")
    data = read_json(path)
    if not data:
        print("  Warning: auto_scale data not found; skipping Figure 4.")
        return

    df = pd.DataFrame([row for row in data if row is not None])
    if df.empty or "wall_seconds" not in df.columns:
        print("  Warning: auto_scale JSON lacks timing data; skipping Figure 4.")
        return

    df = df.copy()
    df["runtime_seconds"] = pd.to_numeric(df["wall_seconds"], errors="coerce")
    df["n_samples"] = pd.to_numeric(df["samples"], errors="coerce")
    df["throughput_sph"] = df["n_samples"] / (df["runtime_seconds"] / 3600.0)
    df["branch_accuracy"] = pd.to_numeric(df.get("branch_accuracy"), errors="coerce")
    df = df.dropna(subset=["n_samples", "runtime_seconds"])

    fig = plt.figure(figsize=(8.5, 2.8))
    gs = fig.add_gridspec(1, 3, wspace=0.4)

    # Panel A: runtime vs n_samples
    ax1 = fig.add_subplot(gs[0])
    ax1.plot(
        df["n_samples"],
        df["runtime_seconds"],
        marker="o",
        markersize=5,
        color=COLORS["auto"],
        linewidth=1.5,
    )
    ax1.set_xlabel("Number of samples", fontweight="bold")
    ax1.set_ylabel("Runtime (s)", fontweight="bold")
    ax1.set_title("A", fontweight="bold", fontsize=10, loc="left")
    ax1.set_xscale("log")
    ax1.set_yscale("log")

    # Panel B: throughput
    ax2 = fig.add_subplot(gs[1])
    ax2.plot(
        df["n_samples"],
        df["throughput_sph"],
        marker="o",
        markersize=5,
        color=COLORS["auto"],
        linewidth=1.5,
    )
    ax2.set_xlabel("Number of samples", fontweight="bold")
    ax2.set_ylabel("Throughput (samples / hour)", fontweight="bold")
    ax2.set_title("B", fontweight="bold", fontsize=10, loc="left")
    ax2.set_xscale("log")

    # Panel C: branch correctness
    ax3 = fig.add_subplot(gs[2])
    if df["branch_accuracy"].notna().any():
        ax3.plot(
            df["n_samples"],
            df["branch_accuracy"],
            marker="s",
            markersize=5,
            color=COLORS["auto"],
            linewidth=1.5,
        )
        ax3.axhline(1.0, color="black", linestyle="--", linewidth=0.8, alpha=0.5)
        ax3.set_xlabel("Number of samples", fontweight="bold")
        ax3.set_ylabel("Branch accuracy", fontweight="bold")
        ax3.set_title("C", fontweight="bold", fontsize=10, loc="left")
        ax3.set_ylim(0.8, 1.02)
        ax3.set_xscale("log")
    else:
        ax3.text(0.5, 0.5, "No branch accuracy data", ha="center", va="center", transform=ax3.transAxes)
        ax3.set_title("C", fontweight="bold", fontsize=10, loc="left")

    plt.tight_layout()
    save_figure(fig, "figure_4_auto_scalability", output_dir)
    plt.close(fig)


# -----------------------------------------------------------------------------
# Figure 5: Cross-species accuracy
# -----------------------------------------------------------------------------
def plot_figure_5_cross_species(output_dir: str):
    """Figure 5: grouped bar of F1 across host species."""
    print("\n[Figure 5] Cross-species accuracy")
    path = os.path.join(BASE_DIR, "analysis_final_v3", "accuracy_cross_species", "accuracy.csv")
    df = read_csv(path)
    if df is None or df.empty:
        print("  Warning: cross-species accuracy data not found; skipping Figure 5.")
        return

    df.columns = [c.lower() for c in df.columns]
    if "dataset" not in df.columns or "tool" not in df.columns or "f1" not in df.columns:
        print("  Warning: cross-species accuracy CSV missing required columns; skipping Figure 5.")
        return

    df["species"] = df["dataset"].apply(extract_species)
    species_present = [s for s in CROSS_SPECIES_ORDER if s in df["species"].unique()]
    if not species_present:
        print("  Warning: no recognised species in cross-species data; skipping Figure 5.")
        return

    tools = sorted(df["tool"].unique())
    fig, ax = plt.subplots(figsize=(6.0, 3.0))

    x = np.arange(len(species_present))
    width = 0.7 / max(len(tools), 1)
    for i, tool in enumerate(tools):
        means = []
        stds = []
        for sp in species_present:
            sub = df[(df["species"] == sp) & (df["tool"] == tool)]["f1"]
            means.append(sub.mean() if len(sub) else np.nan)
            stds.append(sub.std(ddof=0) if len(sub) > 1 else 0)
        offset = (i - (len(tools) - 1) / 2) * width
        ax.bar(
            x + offset,
            means,
            width,
            yerr=stds,
            label=tool_label(tool),
            color=tool_color(tool),
            edgecolor="white",
            linewidth=0.5,
            capsize=2,
            error_kw={"linewidth": 0.8},
        )

    ax.set_xticks(x)
    ax.set_xticklabels([s.capitalize() for s in species_present], rotation=45, ha="right", fontsize=7)
    ax.set_xlabel("Host species", fontweight="bold")
    ax.set_ylabel("F1-score", fontweight="bold")
    ax.set_ylim(0.8, 1.01)
    ax.legend(loc="best", title="Tool")

    plt.tight_layout()
    save_figure(fig, "figure_5_cross_species_accuracy", output_dir)
    plt.close(fig)


# -----------------------------------------------------------------------------
# Figure 6: Real-data summary
# -----------------------------------------------------------------------------
def plot_figure_6_real_data(output_dir: str):
    """Figure 6: runtime and memory for real metagenomic samples."""
    print("\n[Figure 6] Real-data summary")
    path = os.path.join(BASE_DIR, "results_real_data", "metrics", "performance.csv")
    df = read_csv(path)
    if df is None or df.empty:
        print("  Warning: real-data performance data not found; skipping Figure 6.")
        return

    df = prepare_performance(df)
    df = df[df["dataset"].isin(REAL_SAMPLES) & df["tool"].isin(REAL_TOOLS)]
    if df.empty:
        print("  Warning: no matching real-data performance records; skipping Figure 6.")
        return

    fig = plt.figure(figsize=(7.2, 3.0))
    gs = fig.add_gridspec(1, 2, wspace=0.35)

    tools = [t for t in REAL_TOOLS if t in df["tool"].unique()]

    ax1 = fig.add_subplot(gs[0])
    grouped_bar_with_error(
        ax1,
        df,
        x_col="dataset",
        y_col="runtime_seconds",
        group_col="tool",
        groups=tools,
        categories=REAL_SAMPLES,
        width=0.13,
        ylabel="Runtime (s)",
        title="A",
        yscale="log",
    )

    ax2 = fig.add_subplot(gs[1])
    grouped_bar_with_error(
        ax2,
        df,
        x_col="dataset",
        y_col="memory_gb",
        group_col="tool",
        groups=tools,
        categories=REAL_SAMPLES,
        width=0.13,
        ylabel="Peak memory (GB)",
        title="B",
    )

    plt.tight_layout()
    save_figure(fig, "figure_6_real_data_summary", output_dir)
    plt.close(fig)


# -----------------------------------------------------------------------------
# Main entry point
# -----------------------------------------------------------------------------
def main():
    output_dir = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_OUTPUT_DIR
    os.makedirs(output_dir, exist_ok=True)

    print("=" * 70)
    print("RustyClean Benchmark - Publication Figures v2")
    print("=" * 70)
    print(f"Project base directory: {BASE_DIR}")
    print(f"Output directory:       {output_dir}")
    print()

    plot_figure_1_human_comparison(output_dir)
    plot_figure_2_human_accuracy(output_dir)
    plot_figure_3_rc_mode_decision(output_dir)
    plot_figure_4_auto_scalability(output_dir)
    plot_figure_5_cross_species(output_dir)
    plot_figure_6_real_data(output_dir)

    print()
    print("=" * 70)
    print("Figure generation complete.")
    print(f"Figures written to: {output_dir}")
    print("=" * 70)


if __name__ == "__main__":
    main()
