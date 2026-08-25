#!/usr/bin/env python3
# =============================================================================
# RustyClean Benchmark - Final Comprehensive Report Generator
# =============================================================================
# Generates a comprehensive Markdown report and a JSON key-numbers file for the
# HPC benchmark paper, combining results from the human multi-tool comparison,
# RustyClean mode decision-boundary analysis, AUTO scalability, cross-species
# validation, and real-data validation.
#
# Usage:
#     python scripts/main/generate_final_report.py [output_dir]
#
# The optional output_dir defaults to:
#     /lustre1/g/aos_shihuang/rustyclean-paper/results_analysis
# =============================================================================

import json
import os
import sys
from datetime import datetime

import numpy as np
import pandas as pd

# -----------------------------------------------------------------------------
# Base directory on the HPC filesystem.  Can be overridden via environment
# variable so the same script can be tested outside the production path.
# -----------------------------------------------------------------------------
BASE_DIR = os.environ.get(
    "RUSTYCLEAN_PAPER_DIR", "/lustre1/g/aos_shihuang/rustyclean-paper"
)
DEFAULT_OUTPUT_DIR = os.path.join(BASE_DIR, "results_analysis")

# -----------------------------------------------------------------------------
# Input data sources
# -----------------------------------------------------------------------------
INPUT_FILES = {
    "human_performance": os.path.join(
        BASE_DIR, "results_hostile_centrifuge", "metrics", "performance.csv"
    ),
    "human_accuracy": os.path.join(
        BASE_DIR, "results_hostile_centrifuge", "metrics", "accuracy.csv"
    ),
    "mode_summary": os.path.join(BASE_DIR, "results_analysis", "mode_summary.csv"),
    "auto_scale": os.path.join(
        BASE_DIR, "results_auto_scale", "metrics", "auto_scale.csv"
    ),
    "cross_species_accuracy": os.path.join(
        BASE_DIR, "results_cross_species", "metrics", "accuracy.csv"
    ),
    "real_data_performance": os.path.join(
        BASE_DIR, "results_real_data", "metrics", "performance.csv"
    ),
}

# Expected experimental layout (mirrors generate_publication_figures_v2.py)
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
RC_MODES = ["kraken2", "bowtie2", "auto"]
CROSS_SPECIES_ORDER = ["human", "mouse", "rat", "pig", "rice", "monkey"]


# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
def parse_time_to_seconds(value):
    """Parse GNU time elapsed strings (m:ss, h:mm:ss) or numeric values to seconds."""
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


def format_seconds(seconds):
    """Format seconds as h:mm:ss (or m:ss / s for small values)."""
    if seconds is None or pd.isna(seconds):
        return "N/A"
    seconds = float(seconds)
    if seconds < 60:
        return f"{seconds:.1f}s"
    if seconds < 3600:
        m = int(seconds // 60)
        s = seconds % 60
        return f"{m}:{s:05.2f}"
    h = int(seconds // 3600)
    remainder = seconds % 3600
    m = int(remainder // 60)
    s = remainder % 60
    return f"{h}:{m:02d}:{s:05.2f}"


def format_memory(mb):
    """Format MB to human-readable string."""
    if mb is None or pd.isna(mb):
        return "N/A"
    mb = float(mb)
    if mb < 1024:
        return f"{mb:.0f} MB"
    return f"{mb / 1024:.1f} GB"


def read_csv(path):
    """Read a CSV if it exists, otherwise return None."""
    if not path or not os.path.exists(path):
        return None
    try:
        return pd.read_csv(path)
    except Exception as exc:
        print(f"Warning: could not read {path}: {exc}")
        return None


def normalize_columns(df):
    """Lower-case and strip column names for robust matching."""
    if df is None:
        return None
    df = df.copy()
    df.columns = [c.strip().lower() for c in df.columns]
    return df


def prepare_performance(df):
    """Normalize a performance DataFrame: parse runtime and add memory units."""
    df = normalize_columns(df)
    if "runtime_seconds" in df.columns:
        df["runtime_seconds"] = df["runtime_seconds"].apply(parse_time_to_seconds)
    for col in ("max_memory_kb", "memory_kb", "peak_memory_kb"):
        if col in df.columns:
            df["memory_mb"] = pd.to_numeric(df[col], errors="coerce") / 1024
            df["memory_gb"] = df["memory_mb"] / 1024
            break
    df = df.rename(columns={"sample": "dataset"})
    if "tool" in df.columns:
        df["tool"] = df["tool"].astype(str).str.lower().str.strip()
    if "dataset" in df.columns:
        df["dataset"] = df["dataset"].astype(str).str.strip()
    return df


def prepare_accuracy(df):
    """Normalize an accuracy DataFrame: lower-case tool/dataset columns."""
    df = normalize_columns(df)
    if "tool" in df.columns:
        df["tool"] = df["tool"].astype(str).str.lower().str.strip()
    if "dataset" in df.columns:
        df["dataset"] = df["dataset"].astype(str).str.strip()
    # Ensure canonical metric columns exist.
    metric_aliases = {
        "f1_score": "f1",
        "f1-score": "f1",
        "f1score": "f1",
        "host_remaining_rate": "host_remaining",
        "host_remaining_pct": "host_remaining",
        "host_rate": "host_remaining",
        "microbe_loss_rate": "microbe_loss",
        "microbe_loss_pct": "microbe_loss",
        "microbe_rate": "microbe_loss",
    }
    df = df.rename(columns=metric_aliases)
    return df


def extract_host_pct(name):
    """Extract host percentage from a dataset name such as '10M_10pct_*'."""
    import re

    m = re.search(r"_(\d+)pct_", str(name))
    if m:
        return float(m.group(1)) / 100.0
    return np.nan


def extract_species(name):
    """Extract species token from dataset names such as 'human_5M_1pct'."""
    return str(name).split("_")[0].lower()


# -----------------------------------------------------------------------------
# Summary statistics
# -----------------------------------------------------------------------------
def summarize_human_performance(df):
    """Return aggregate performance stats per tool and overall speedup."""
    df = prepare_performance(df)
    df = df[df["dataset"].isin(HUMAN_DATASETS)]
    if df.empty:
        return None

    stats = {}
    for tool in sorted(df["tool"].unique()):
        subset = df[df["tool"] == tool]
        stats[tool] = {
            "runtime_mean_s": subset["runtime_seconds"].mean(),
            "runtime_std_s": subset["runtime_seconds"].std(),
            "memory_mean_mb": subset["memory_mb"].mean(),
            "memory_std_mb": subset["memory_mb"].std(),
            "n": len(subset),
        }

    # Speedup relative to KneadData when RustyClean Kraken2 is present.
    speedups = {}
    if "kneaddata" in stats:
        base = stats["kneaddata"]["runtime_mean_s"]
        for tool, s in stats.items():
            if tool != "kneaddata" and base and base > 0:
                speedups[tool] = base / s["runtime_mean_s"]

    return {"stats": stats, "speedups": speedups}


def summarize_human_accuracy(df):
    """Return aggregate accuracy stats per tool for the human 4 datasets."""
    df = prepare_accuracy(df)
    df = df[df["dataset"].isin(HUMAN_DATASETS)]
    if df.empty:
        return None

    stats = {}
    for tool in sorted(df["tool"].unique()):
        subset = df[df["tool"] == tool]
        stats[tool] = {
            "accuracy_mean": subset.get("accuracy", pd.Series(np.nan)).mean(),
            "precision_mean": subset.get("precision", pd.Series(np.nan)).mean(),
            "recall_mean": subset.get("recall", pd.Series(np.nan)).mean(),
            "f1_mean": subset.get("f1", pd.Series(np.nan)).mean(),
            "host_remaining_mean": subset.get("host_remaining", pd.Series(np.nan)).mean(),
            "microbe_loss_mean": subset.get("microbe_loss", pd.Series(np.nan)).mean(),
            "n": len(subset),
        }
    return stats


def summarize_mode_summary(df):
    """Return summary of RustyClean mode comparison / AUTO decision boundary."""
    df = normalize_columns(df)
    if df is None or df.empty:
        return None

    for col in ("mode", "chosen_mode", "expected_mode"):
        if col in df.columns:
            df[col] = df[col].astype(str).str.lower().str.strip()
    if "dataset" in df.columns:
        df["dataset"] = df["dataset"].astype(str).str.strip()
        df["host_pct"] = df["dataset"].apply(extract_host_pct)

    # Unify mode / chosen_mode.
    if "mode" not in df.columns and "chosen_mode" in df.columns:
        df["mode"] = df["chosen_mode"]

    stats = {}
    if "mode" in df.columns:
        for mode in sorted(df["mode"].unique()):
            subset = df[df["mode"] == mode]
            stats[mode] = {
                "count": len(subset),
                "f1_mean": subset.get("f1", pd.Series(np.nan)).mean(),
                "runtime_mean_s": subset.get(
                    "runtime_seconds", pd.Series(np.nan)
                ).apply(parse_time_to_seconds).mean(),
                "memory_mean_mb": subset.get("memory_mb", pd.Series(np.nan)).mean(),
            }

    decision = None
    if "chosen_mode" in df.columns and "expected_mode" in df.columns:
        valid = df[["chosen_mode", "expected_mode"]].dropna()
        if not valid.empty:
            correct = (valid["chosen_mode"] == valid["expected_mode"]).sum()
            total = len(valid)
            decision = {
                "correct": int(correct),
                "total": int(total),
                "accuracy": float(correct / total) if total else np.nan,
            }

    return {"stats": stats, "decision": decision}


def summarize_auto_scale(df):
    """Return AUTO scalability summary: runtime, throughput, branch correctness."""
    df = normalize_columns(df)
    if df is None or df.empty:
        return None

    if "runtime_seconds" in df.columns:
        df["runtime_seconds"] = df["runtime_seconds"].apply(parse_time_to_seconds)
    if "n_samples" in df.columns and "runtime_seconds" in df.columns:
        df["throughput_sph"] = df["n_samples"] / (df["runtime_seconds"] / 3600.0)
    if "branch_correct" in df.columns:
        df["branch_correct"] = df["branch_correct"].astype(bool)

    summary = {}
    if "n_samples" in df.columns:
        grouped = (
            df.groupby("n_samples")
            .agg(
                runtime_mean_s=("runtime_seconds", "mean"),
                runtime_std_s=("runtime_seconds", "std"),
                throughput_mean_sph=("throughput_sph", "mean"),
                throughput_std_sph=("throughput_sph", "std"),
            )
            .reset_index()
        )
        summary["by_n_samples"] = grouped.to_dict(orient="records")

    if "branch_correct" in df.columns:
        bc = df["branch_correct"]
        summary["branch_correct"] = {
            "correct": int(bc.sum()),
            "total": int(len(bc)),
            "accuracy": float(bc.mean()),
        }

    return summary


def summarize_cross_species(df):
    """Return cross-species accuracy summary per tool and species."""
    df = prepare_accuracy(df)
    if df is None or df.empty:
        return None

    if "species" not in df.columns and "dataset" in df.columns:
        df["species"] = df["dataset"].apply(extract_species)

    overall = {}
    for tool in sorted(df["tool"].unique()):
        subset = df[df["tool"] == tool]
        overall[tool] = {
            "f1_mean": subset.get("f1", pd.Series(np.nan)).mean(),
            "f1_std": subset.get("f1", pd.Series(np.nan)).std(),
            "n": len(subset),
        }

    by_species = {}
    if "species" in df.columns:
        for sp in sorted(df["species"].unique()):
            by_species[sp] = {}
            sp_df = df[df["species"] == sp]
            for tool in sorted(sp_df["tool"].unique()):
                sub = sp_df[sp_df["tool"] == tool]
                by_species[sp][tool] = {
                    "f1_mean": sub.get("f1", pd.Series(np.nan)).mean(),
                    "n": len(sub),
                }

    return {"overall": overall, "by_species": by_species}


def summarize_real_data(df):
    """Return real-data performance summary per tool and sample."""
    df = prepare_performance(df)
    df = df[df["dataset"].isin(REAL_SAMPLES)]
    if df.empty:
        return None

    overall = {}
    for tool in sorted(df["tool"].unique()):
        subset = df[df["tool"] == tool]
        overall[tool] = {
            "runtime_mean_s": subset["runtime_seconds"].mean(),
            "runtime_std_s": subset["runtime_seconds"].std(),
            "memory_mean_mb": subset["memory_mb"].mean(),
            "memory_std_mb": subset["memory_mb"].std(),
            "n": len(subset),
        }

    by_sample = {}
    for sample in sorted(df["dataset"].unique()):
        by_sample[sample] = {}
        sample_df = df[df["dataset"] == sample]
        for tool in sorted(sample_df["tool"].unique()):
            sub = sample_df[sample_df["tool"] == tool]
            by_sample[sample][tool] = {
                "runtime_mean_s": sub["runtime_seconds"].mean(),
                "memory_mean_mb": sub["memory_mb"].mean(),
                "n": len(sub),
            }

    return {"overall": overall, "by_sample": by_sample}


# -----------------------------------------------------------------------------
# Markdown formatting helpers
# -----------------------------------------------------------------------------
def fmt_num(v, fmt="{:.4f}"):
    """Format a numeric value, returning N/A for missing values."""
    if v is None or pd.isna(v):
        return "N/A"
    return fmt.format(float(v))


def make_table(headers, rows):
    """Build a Markdown table from headers and rows."""
    lines = []
    lines.append("| " + " | ".join(headers) + " |")
    lines.append("| " + " | ".join(["---"] * len(headers)) + " |")
    for row in rows:
        lines.append("| " + " | ".join(str(x) for x in row) + " |")
    return lines


# -----------------------------------------------------------------------------
# Report generation
# -----------------------------------------------------------------------------
def load_all_data():
    """Load all input CSVs with graceful handling of missing files."""
    data = {}
    for key, path in INPUT_FILES.items():
        df = read_csv(path)
        if df is not None:
            print(f"  Loaded {key}: {len(df)} rows from {path}")
        else:
            print(f"  Missing {key}: {path}")
        data[key] = df
    return data


def list_figures(figures_dir):
    """List generated figure files in the figures directory."""
    if not os.path.isdir(figures_dir):
        return []
    extensions = (".png", ".svg", ".pdf", ".tiff")
    return sorted(
        f
        for f in os.listdir(figures_dir)
        if f.lower().endswith(extensions)
    )


def generate_report(output_dir):
    """Generate comprehensive Markdown report and key-numbers JSON."""
    os.makedirs(output_dir, exist_ok=True)
    report_path = os.path.join(output_dir, "final_report.md")
    json_path = os.path.join(output_dir, "key_numbers.json")
    figures_dir = os.path.join(output_dir, "figures")

    print("=" * 70)
    print("RustyClean Benchmark - Final Report Generator")
    print("=" * 70)
    print(f"Project base directory: {BASE_DIR}")
    print(f"Output directory:       {output_dir}")
    print()
    print("Loading input data...")
    data = load_all_data()
    print()

    # Compute summaries
    summaries = {
        "human_performance": summarize_human_performance(data.get("human_performance")),
        "human_accuracy": summarize_human_accuracy(data.get("human_accuracy")),
        "mode_summary": summarize_mode_summary(data.get("mode_summary")),
        "auto_scale": summarize_auto_scale(data.get("auto_scale")),
        "cross_species": summarize_cross_species(data.get("cross_species_accuracy")),
        "real_data": summarize_real_data(data.get("real_data_performance")),
    }

    report = []
    key_numbers = {}

    # -------------------------------------------------------------------------
    # Title and abstract
    # -------------------------------------------------------------------------
    report.append("# RustyClean: A Fast and Accurate Host-Decontamination Pipeline for Metagenomics")
    report.append("")
    report.append(f"**Comprehensive benchmark report**  ")
    report.append(f"**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M')}  ")
    report.append(f"**Project directory:** `{BASE_DIR}`")
    report.append("")

    report.append("## Abstract")
    report.append("")
    abstract_parts = []
    hp = summaries["human_performance"]
    ha = summaries["human_accuracy"]
    if hp and hp["speedups"]:
        speedup_texts = [
            f"{tool}: {fmt_num(v, '{:.1f}')}×"
            for tool, v in sorted(hp["speedups"].items())
        ]
        abstract_parts.append(
            f"on the four human simulated datasets, RustyClean modes achieved speedups of "
            f"{', '.join(speedup_texts)} over KneadData"
        )
    if ha:
        f1_texts = [
            f"{tool} F1 = {fmt_num(s['f1_mean'])}"
            for tool, s in sorted(ha.items())
            if not pd.isna(s["f1_mean"])
        ]
        if f1_texts:
            abstract_parts.append(f"with accuracy metrics of {', '.join(f1_texts)}")

    cs = summaries["cross_species"]
    if cs and cs["overall"]:
        cs_texts = [
            f"{tool} = {fmt_num(v['f1_mean'])}"
            for tool, v in sorted(cs["overall"].items())
            if not pd.isna(v["f1_mean"])
        ]
        if cs_texts:
            abstract_parts.append(
                f"cross-species host removal averaged {', '.join(cs_texts)}"
            )

    if abstract_parts:
        report.append(
            "This report summarizes the HPC benchmark evaluation of RustyClean against "
            "KneadData, Hostile, and Centrifuge across simulated human datasets, "
            "RustyClean mode decision boundaries, AUTO scalability, cross-species "
            "host genomes, and real metagenomic samples. "
            + "; ".join(abstract_parts)
            + "."
        )
    else:
        report.append(
            "This report summarizes the HPC benchmark evaluation of RustyClean. "
            "Input data were not available at the time of generation; please re-run "
            "the script once all benchmark outputs are ready."
        )
    report.append("")

    # -------------------------------------------------------------------------
    # Methods summary
    # -------------------------------------------------------------------------
    report.append("## Methods Summary")
    report.append("")
    report.append("### Datasets")
    report.append("")
    report.append("- **Simulated human datasets:** four Illumina-style short-read datasets "
                  "generated with InsilicoSeq, spanning 5–60 M reads and 1–90% host "
                  "contamination with varying abundance distributions (even / skewed / log-normal).")
    report.append("- **Cross-species datasets:** simulated reads against six host genomes "
                  f"({', '.join(CROSS_SPECIES_ORDER)}).")
    report.append("- **Real data validation:** three publicly available metagenomic samples "
                  f"({', '.join(REAL_SAMPLES)}).")
    report.append("")

    report.append("### Tools and Modes")
    report.append("")
    report.append("- **RustyClean Kraken2 (rustyclean_k2):** Kraken2-based taxonomic classification.")
    report.append("- **RustyClean Centrifuge (rustyclean_cf):** Centrifuge-based classification.")
    report.append("- **RustyClean Bowtie2 (rustyclean_bt2):** Bowtie2 alignment to host genome.")
    report.append("- **RustyClean AUTO (rustyclean_auto):** adaptive mode selection between "
                  "Kraken2 and Bowtie2 based on estimated host contamination.")
    report.append("- **KneadData:** Trimmomatic + Bowtie2 host-removal pipeline.")
    report.append("- **Hostile:** read-level host-removal tool using minimap2.")
    report.append("")

    report.append("### Metrics")
    report.append("")
    report.append("- **Runtime:** elapsed wall-clock time, parsed from `m:ss` or `h:mm:ss` strings.")
    report.append("- **Memory:** peak resident set size, reported in MB or GB.")
    report.append("- **Speedup:** ratio of KneadData mean runtime to target tool mean runtime.")
    report.append("- **Accuracy:** Accuracy, Precision, Recall, F1-score, host-remaining rate, "
                  "and microbe-loss rate against simulated ground-truth labels.")
    report.append("- **AUTO correctness:** fraction of samples for which the AUTO branch chose the "
                  "expected (fastest or best-scoring) mode.")
    report.append("")

    # -------------------------------------------------------------------------
    # Results: Human 4 datasets
    # -------------------------------------------------------------------------
    report.append("## Results")
    report.append("")
    report.append("### 1. Human 4-Dataset Benchmark")
    report.append("")

    if hp:
        report.append("#### Runtime and Memory")
        report.append("")
        headers = ["Tool", "Mean runtime", "Std runtime", "Mean memory", "Std memory", "N"]
        rows = []
        for tool, s in sorted(hp["stats"].items()):
            rows.append([
                tool,
                format_seconds(s["runtime_mean_s"]),
                format_seconds(s["runtime_std_s"]),
                format_memory(s["memory_mean_mb"]),
                format_memory(s["memory_std_mb"]),
                s["n"],
            ])
        report.extend(make_table(headers, rows))
        report.append("")

        report.append("#### Speedup vs. KneadData")
        report.append("")
        if hp["speedups"]:
            headers = ["Tool", "Speedup", "Interpretation"]
            rows = []
            for tool, sp in sorted(hp["speedups"].items()):
                rows.append([
                    tool,
                    fmt_num(sp, "{:.2f}×"),
                    "faster" if sp > 1 else "slower",
                ])
            report.extend(make_table(headers, rows))
            key_numbers["human_speedups"] = {
                k: float(v) for k, v in hp["speedups"].items()
            }
        else:
            report.append("*No KneadData baseline available for speedup calculation.*")
        report.append("")

        key_numbers["human_performance"] = {
            tool: {
                k: (float(v) if not pd.isna(v) else None)
                for k, v in s.items()
            }
            for tool, s in hp["stats"].items()
        }
    else:
        report.append("*Human performance data not available.*")
        report.append("")

    if ha:
        report.append("#### Accuracy")
        report.append("")
        headers = [
            "Tool",
            "Accuracy",
            "Precision",
            "Recall",
            "F1",
            "Host remaining",
            "Microbe loss",
            "N",
        ]
        rows = []
        for tool, s in sorted(ha.items()):
            rows.append([
                tool,
                fmt_num(s["accuracy_mean"]),
                fmt_num(s["precision_mean"]),
                fmt_num(s["recall_mean"]),
                fmt_num(s["f1_mean"]),
                fmt_num(s["host_remaining_mean"]),
                fmt_num(s["microbe_loss_mean"]),
                s["n"],
            ])
        report.extend(make_table(headers, rows))
        report.append("")
        key_numbers["human_accuracy"] = {
            tool: {
                k: (float(v) if not pd.isna(v) else None)
                for k, v in s.items()
            }
            for tool, s in ha.items()
        }
    else:
        report.append("*Human accuracy data not available.*")
        report.append("")

    # -------------------------------------------------------------------------
    # Results: Tool comparison
    # -------------------------------------------------------------------------
    report.append("### 2. Tool Comparison")
    report.append("")
    report.append(
        "The human benchmark compares RustyClean Kraken2, RustyClean Centrifuge, "
        "KneadData, and Hostile. RustyClean modes are evaluated on speed, memory, "
        "and accuracy. KneadData serves as the reference against which speedup is "
        "calculated."
    )
    report.append("")
    if hp and ha:
        best_speedup_tool = max(
            hp["speedups"].items(), key=lambda x: x[1]
        )[0] if hp["speedups"] else None
        best_f1_tool = max(
            ((t, s["f1_mean"]) for t, s in ha.items() if not pd.isna(s["f1_mean"])),
            key=lambda x: x[1],
            default=(None, None),
        )[0]
        if best_speedup_tool:
            report.append(
                f"- **Fastest relative to KneadData:** {best_speedup_tool} "
                f"({fmt_num(hp['speedups'][best_speedup_tool], '{:.2f}×')} speedup)."
            )
        if best_f1_tool:
            report.append(
                f"- **Highest F1:** {best_f1_tool} (F1 = {fmt_num(ha[best_f1_tool]['f1_mean'])})."
            )
        report.append("")
    else:
        report.append("*Insufficient data for tool comparison.*")
        report.append("")

    # -------------------------------------------------------------------------
    # Results: RustyClean mode comparison and decision boundary
    # -------------------------------------------------------------------------
    report.append("### 3. RustyClean Mode Comparison and AUTO Decision Boundary")
    report.append("")
    ms = summaries["mode_summary"]
    if ms:
        report.append("#### Per-mode summary")
        report.append("")
        headers = ["Mode", "Count", "Mean F1", "Mean runtime", "Mean memory"]
        rows = []
        for mode, s in sorted(ms["stats"].items()):
            rows.append([
                mode,
                s["count"],
                fmt_num(s["f1_mean"]),
                format_seconds(s["runtime_mean_s"]),
                format_memory(s["memory_mean_mb"]),
            ])
        report.extend(make_table(headers, rows))
        report.append("")

        report.append("#### AUTO branch correctness")
        report.append("")
        if ms["decision"]:
            d = ms["decision"]
            report.append(
                f"AUTO chose the expected mode in {d['correct']} of {d['total']} "
                f"datasets (accuracy = {fmt_num(d['accuracy'])})."
            )
            key_numbers["auto_decision_accuracy"] = float(d["accuracy"])
        else:
            report.append("*No chosen-mode / expected-mode information available.*")
        report.append("")

        key_numbers["mode_summary"] = {
            "stats": {
                mode: {k: (float(v) if not pd.isna(v) else None) for k, v in s.items()}
                for mode, s in ms["stats"].items()
            },
            "decision": ms["decision"],
        }
    else:
        report.append("*Mode-summary data not available.*")
        report.append("")

    # -------------------------------------------------------------------------
    # Results: AUTO scalability
    # -------------------------------------------------------------------------
    report.append("### 4. AUTO Scalability")
    report.append("")
    au = summaries["auto_scale"]
    if au:
        if "by_n_samples" in au:
            report.append("#### Runtime and throughput by sample count")
            report.append("")
            headers = [
                "N samples",
                "Mean runtime",
                "Std runtime",
                "Mean throughput (samples/h)",
                "Std throughput",
            ]
            rows = []
            for rec in au["by_n_samples"]:
                rows.append([
                    rec["n_samples"],
                    format_seconds(rec["runtime_mean_s"]),
                    format_seconds(rec["runtime_std_s"]),
                    fmt_num(rec["throughput_mean_sph"], "{:.2f}"),
                    fmt_num(rec["throughput_std_sph"], "{:.2f}"),
                ])
            report.extend(make_table(headers, rows))
            report.append("")
            key_numbers["auto_scalability"] = au["by_n_samples"]

        if "branch_correct" in au:
            bc = au["branch_correct"]
            report.append("#### Branch correctness")
            report.append("")
            report.append(
                f"- Correct decisions: {bc['correct']} / {bc['total']} "
                f"({fmt_num(bc['accuracy'])})."
            )
            report.append("")
            key_numbers["auto_branch_correctness"] = bc
    else:
        report.append("*AUTO scalability data not available.*")
        report.append("")

    # -------------------------------------------------------------------------
    # Results: Cross-species accuracy
    # -------------------------------------------------------------------------
    report.append("### 5. Cross-Species Host Removal Accuracy")
    report.append("")
    cs = summaries["cross_species"]
    if cs:
        report.append("#### Overall F1 per tool")
        report.append("")
        headers = ["Tool", "Mean F1", "Std F1", "N"]
        rows = []
        for tool, s in sorted(cs["overall"].items()):
            rows.append([tool, fmt_num(s["f1_mean"]), fmt_num(s["f1_std"]), s["n"]])
        report.extend(make_table(headers, rows))
        report.append("")

        report.append("#### F1 per species and tool")
        report.append("")
        species_present = [s for s in CROSS_SPECIES_ORDER if s in cs["by_species"]]
        if species_present:
            tools = sorted({t for sp in cs["by_species"].values() for t in sp})
            headers = ["Species"] + tools
            rows = []
            for sp in species_present:
                row = [sp]
                for tool in tools:
                    s = cs["by_species"].get(sp, {}).get(tool, {})
                    row.append(fmt_num(s.get("f1_mean")))
                rows.append(row)
            report.extend(make_table(headers, rows))
            report.append("")

        key_numbers["cross_species"] = {
            "overall": {
                tool: {
                    k: (float(v) if not pd.isna(v) else None)
                    for k, v in s.items()
                }
                for tool, s in cs["overall"].items()
            },
            "by_species": {
                sp: {
                    tool: {k: (float(v) if not pd.isna(v) else None) for k, v in s.items()}
                    for tool, s in tools.items()
                }
                for sp, tools in cs["by_species"].items()
            },
        }
    else:
        report.append("*Cross-species accuracy data not available.*")
        report.append("")

    # -------------------------------------------------------------------------
    # Results: Real data validation
    # -------------------------------------------------------------------------
    report.append("### 6. Real-Data Validation")
    report.append("")
    rd = summaries["real_data"]
    if rd:
        report.append("#### Overall performance per tool")
        report.append("")
        headers = ["Tool", "Mean runtime", "Std runtime", "Mean memory", "Std memory", "N"]
        rows = []
        for tool, s in sorted(rd["overall"].items()):
            rows.append([
                tool,
                format_seconds(s["runtime_mean_s"]),
                format_seconds(s["runtime_std_s"]),
                format_memory(s["memory_mean_mb"]),
                format_memory(s["memory_std_mb"]),
                s["n"],
            ])
        report.extend(make_table(headers, rows))
        report.append("")

        report.append("#### Per-sample runtime and memory")
        report.append("")
        samples = sorted(rd["by_sample"])
        if samples:
            tools = sorted({t for s in rd["by_sample"].values() for t in s})
            headers = ["Sample"] + tools
            rows = []
            for sample in samples:
                row = [sample]
                for tool in tools:
                    s = rd["by_sample"][sample].get(tool, {})
                    row.append(
                        f"{format_seconds(s.get('runtime_mean_s'))} / "
                        f"{format_memory(s.get('memory_mean_mb'))}"
                    )
                rows.append(row)
            report.extend(make_table(headers, rows))
            report.append("")

        key_numbers["real_data"] = {
            "overall": {
                tool: {
                    k: (float(v) if not pd.isna(v) else None)
                    for k, v in s.items()
                }
                for tool, s in rd["overall"].items()
            },
            "by_sample": rd["by_sample"],
        }
    else:
        report.append("*Real-data performance data not available.*")
        report.append("")

    # -------------------------------------------------------------------------
    # Discussion
    # -------------------------------------------------------------------------
    report.append("## Discussion")
    report.append("")
    report.append(
        "- **Speed vs. accuracy trade-off.** RustyClean's classification-based approach "
        "delivers large runtime reductions, especially on high-host-contamination samples, "
        "while maintaining competitive F1 scores. The exact gap depends on the database "
        "and thresholds used."
    )
    report.append(
        "- **Mode selection.** RustyClean AUTO adapts the execution path between Kraken2 "
        "and Bowtie2 based on estimated host burden. Correct branch decisions preserve "
        "the fastest runtime without manual parameter tuning."
    )
    report.append(
        "- **Cross-species generalisation.** Performance across host species indicates "
        "how well the approach transfers beyond the human reference; lower F1 for "
        "evolutionarily distant hosts may signal database bias."
    )
    report.append(
        "- **Real-data behaviour.** Real metagenomic samples validate that runtime and "
        "memory trends observed in simulation hold under noisy, heterogeneous conditions."
    )
    report.append("")

    # -------------------------------------------------------------------------
    # Limitations
    # -------------------------------------------------------------------------
    report.append("## Limitations")
    report.append("")
    report.append(
        "- Benchmark results depend on the specific Kraken2 / Centrifuge / Bowtie2 "
        "databases and index versions used; different releases may change accuracy and runtime."
    )
    report.append(
        "- Simulated datasets approximate real metagenomic communities; strain-level "
        "complexity, sequencing errors, and adapter content may differ."
    )
    report.append(
        "- Peak memory is reported by the operating system's time utility and may "
        "include I/O cache effects on shared HPC filesystems."
    )
    report.append(
        "- AUTO decision correctness is measured against an expected-mode heuristic; "
        "the optimal rule may vary with hardware, database size, and sample composition."
    )
    report.append(
        "- Single-end (SE) and paired-end (PE) behaviours may differ; this report "
        "reflects the datasets present in the input CSVs."
    )
    report.append("")

    # -------------------------------------------------------------------------
    # Figures reference
    # -------------------------------------------------------------------------
    report.append("## Figures")
    report.append("")
    figures = list_figures(figures_dir)
    if figures:
        report.append(
            f"Publication-quality figures were generated by "
            f"`scripts/main/generate_publication_figures_v2.py` and saved to "
            f"`{figures_dir}`. The following files are available:"
        )
        report.append("")
        for fig in figures:
            report.append(f"- `{fig}`")
        report.append("")
    else:
        report.append(
            "*No figure files were found in `results_analysis/figures`. "
            "Run `scripts/main/generate_publication_figures_v2.py` first.*"
        )
        report.append("")

    # -------------------------------------------------------------------------
    # Data provenance
    # -------------------------------------------------------------------------
    report.append("## Data Provenance")
    report.append("")
    report.append("| Source | Path | Status |")
    report.append("|--------|------|--------|")
    for key, path in INPUT_FILES.items():
        status = "Present" if os.path.exists(path) else "Missing"
        report.append(f"| {key} | `{path}` | {status} |")
    report.append("")

    report.append("---")
    report.append("*Generated by RustyClean Benchmark Suite - generate_final_report.py*")

    # Write report
    with open(report_path, "w") as f:
        f.write("\n".join(report))

    # Write key numbers JSON
    with open(json_path, "w") as f:
        json.dump(
            {
                "generated": datetime.now().isoformat(),
                "base_dir": BASE_DIR,
                "output_dir": output_dir,
                "input_status": {
                    k: os.path.exists(p) for k, p in INPUT_FILES.items()
                },
                "key_numbers": key_numbers,
            },
            f,
            indent=2,
        )

    print(f"Report written:  {report_path}")
    print(f"Key numbers:     {json_path}")
    print("=" * 70)
    return report_path, json_path


# -----------------------------------------------------------------------------
# Main entry point
# -----------------------------------------------------------------------------
def main():
    output_dir = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_OUTPUT_DIR
    generate_report(output_dir)


if __name__ == "__main__":
    main()
