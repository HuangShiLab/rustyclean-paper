#!/usr/bin/env python3
"""Summarize unresolved-control runs without altering raw count-level data."""
from __future__ import annotations

import argparse
import csv
import json
import math
from collections import defaultdict
from pathlib import Path

DATASETS = [
    "5M_1pct_low_even_SE", "10M_10pct_med_even_SE", "30M_50pct_high_skewed_SE",
    "60M_90pct_high_lognormal_SE", "100M_50pct_high_lognormal_SE",
    "100M_90pct_high_lognormal_SE",
]
EXPECTED_THRESHOLDS = [0.0, 0.05, 0.10, 0.15, 0.20, 0.25, 0.30,
                       0.35, 0.40, 0.50, 0.60, 0.80, 1.01]


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        return []
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, rows: list[dict], fields: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def as_float(row: dict, key: str, default: float = math.nan) -> float:
    try:
        return float(row[key])
    except (KeyError, TypeError, ValueError):
        return default


def recompute(row: dict) -> dict:
    tp, fp, fn, tn = (int(row.get(k, 0) or 0) for k in ("tp", "fp", "fn", "tn"))
    total = tp + fp + fn + tn
    precision = tp / (tp + fp) if tp + fp else 1.0
    recall = tp / (tp + fn) if tp + fn else 1.0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    out = dict(row)
    out.update({
        "accuracy": (tp + tn) / total if total else 0.0,
        "precision": precision, "recall": recall, "f1": f1,
        "host_input_retention_pct": 100 * fp / (fp + tn) if fp + tn else 0.0,
        "microbial_loss_pct": 100 * fn / (tp + fn) if tp + fn else 0.0,
        "host_output_fraction_pct": 100 * fp / (tp + fp) if tp + fp else 0.0,
    })
    return out


def mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else math.nan


def sd(values: list[float]) -> float:
    if len(values) < 2:
        return math.nan
    mu = mean(values)
    return math.sqrt(sum((x - mu) ** 2 for x in values) / (len(values) - 1))


def paired_tests(deltas: list[float]) -> tuple[float, float]:
    try:
        from scipy import stats
    except ImportError:
        return math.nan, math.nan
    if len(deltas) < 2:
        return math.nan, math.nan
    tresult = stats.ttest_1samp(deltas, 0.0)
    try:
        wresult = stats.wilcoxon(deltas, zero_method="wilcox", alternative="two-sided")
        wp = float(wresult.pvalue)
    except (ValueError, TypeError):
        wp = math.nan
    return float(tresult.pvalue), wp


def collect_accuracy(roots: list[Path], labels: list[str]) -> list[dict]:
    combined = []
    for root, label in zip(roots, labels):
        rows = read_csv(root / "metrics" / "accuracy.csv")
        for row in rows:
            fixed = recompute(row)
            fixed["source"] = label
            if "condition" not in fixed or not fixed["condition"]:
                fixed["condition"] = "legacy_norecheck" if label == "norecheck" else "unspecified"
            combined.append(fixed)
    return combined


def collect_performance(roots: list[Path], labels: list[str]) -> list[dict]:
    combined = []
    for root, label in zip(roots, labels):
        for row in read_csv(root / "metrics" / "performance.csv"):
            row["source"] = label
            if not row.get("condition"):
                row["condition"] = "legacy_norecheck" if label == "norecheck" else "unspecified"
            row["runtime_s"] = as_float(row, "runtime_s", as_float(row, "runtime_seconds"))
            row["max_memory_kb"] = as_float(row, "max_memory_kb")
            combined.append(row)
    return combined


def group_means(rows: list[dict], keys: list[str], value_keys: list[str]) -> list[dict]:
    groups: dict[tuple, list[dict]] = defaultdict(list)
    for row in rows:
        groups[tuple(row.get(key, "") for key in keys)].append(row)
    output = []
    for key, group in sorted(groups.items()):
        item = dict(zip(keys, key))
        item["replicates"] = len(group)
        for value_key in value_keys:
            values = [as_float(row, value_key) for row in group]
            item[f"{value_key}_mean"] = mean(values)
            item[f"{value_key}_sd"] = sd(values)
        output.append(item)
    return output


def equal_thread_summary(performance: list[dict]) -> list[dict]:
    by_key: dict[tuple, dict] = {}
    for row in performance:
        tool_map = {"rustyclean": "rustyclean_auto", "rustyclean_auto": "rustyclean_auto",
                    "hostile_fastp": "fastp_hostile", "fastp_hostile": "fastp_hostile"}
        if row.get("source") not in {"equal_thread", "legacy_equal_thread_100m90"}:
            continue
        tool = tool_map.get(row.get("tool"))
        if not tool:
            continue
        by_key[(row["dataset"], int(row["rep"]), tool)] = row
    datasets = sorted({key[0] for key in by_key})
    output = []
    all_deltas: list[float] = []
    all_speedups: list[float] = []
    for dataset in datasets:
        deltas = []
        for rep in sorted({key[1] for key in by_key if key[0] == dataset}):
            rc = by_key.get((dataset, rep, "rustyclean_auto"))
            hostile = by_key.get((dataset, rep, "fastp_hostile"))
            if not rc or not hostile:
                continue
            delta = hostile["runtime_s"] - rc["runtime_s"]
            deltas.append(delta)
            speedup = hostile["runtime_s"] / rc["runtime_s"] if rc["runtime_s"] else math.nan
            all_speedups.append(speedup)
            output.append({
                "dataset": dataset, "rep": rep,
                "rustyclean_runtime_s": rc["runtime_s"], "hostile_runtime_s": hostile["runtime_s"],
                "hostile_minus_rustyclean_s": delta,
                "speedup_hostile_over_rustyclean": speedup,
            })
        if deltas:
            all_deltas.extend(deltas)
    if output:
        tp, wp = paired_tests(all_deltas)
        output.append({
            "dataset": "ALL_PAIRED", "rep": "", "rustyclean_runtime_s": "",
            "hostile_runtime_s": "", "hostile_minus_rustyclean_s": mean(all_deltas),
            "speedup_hostile_over_rustyclean": mean(all_speedups),
            "paired_delta_mean_s": mean(all_deltas), "paired_delta_sd_s": sd(all_deltas),
            "paired_t_p": tp, "paired_wilcoxon_p": wp, "paired_n": len(all_deltas),
        })
    return output


def make_status(accuracy: list[dict], performance: list[dict], output_dir: Path) -> dict:
    def coverage(tool: str, source: str, condition: str | None = None) -> list[dict]:
        present: set[tuple[str, int]] = set()
        for row in performance:
            if row.get("tool") == tool and row.get("source") == source:
                if condition is None or row.get("condition") == condition:
                    try:
                        present.add((row["dataset"], int(row["rep"])))
                    except (KeyError, ValueError):
                        pass
        return [
            {"dataset": dataset, "complete_reps": sum((dataset, rep) in present for rep in (1, 2, 3))}
            for dataset in DATASETS
        ]

    threshold_rows = [row for row in performance if row.get("source") in {"threshold", "always"}]
    threshold_conditions = {row.get("condition") for row in threshold_rows}
    expected_conditions = {f"threshold_{value:.2f}" for value in EXPECTED_THRESHOLDS}
    threshold_presence: dict[str, set[int]] = defaultdict(set)
    for row in threshold_rows:
        try:
            threshold_presence[row["dataset"]].add(int(row["rep"]))
        except (KeyError, ValueError):
            pass
    threshold_complete = all(bool(threshold_presence.get(dataset)) for dataset in DATASETS)
    mock_datasets = sorted({row["dataset"] for row in accuracy if row.get("source") == "mock"})
    status = {
        "status": "compute_pending",
        "datasets_expected": DATASETS,
        "equal_thread": {
            "ready": all(x["complete_reps"] == 3 for x in coverage("rustyclean_auto", "equal_thread"))
            and all(x["complete_reps"] == 3 for x in coverage("fastp_hostile", "equal_thread")),
            "coverage": {"rustyclean": coverage("rustyclean_auto", "equal_thread"),
                         "fastp_hostile": coverage("fastp_hostile", "equal_thread")},
        },
        "cleanifier": {
            "ready": all(x["complete_reps"] == 3 for x in coverage("cleanifier", "cleanifier", "threshold_0.5")),
            "coverage": coverage("cleanifier", "cleanifier", "threshold_0.5"),
        },
        "threshold_sweep": {
            "ready": expected_conditions.issubset(threshold_conditions) and threshold_complete,
            "replicates": "one deterministic scoring replicate per threshold",
            "conditions_observed": sorted(x for x in threshold_conditions if x),
        },
        "always_recheck": {
            "ready": all(x["complete_reps"] == 3 for x in coverage(
                "rustyclean_auto", "always", "threshold_0.00")),
            "coverage": coverage("rustyclean_auto", "always", "threshold_0.00"),
        },
        "no_recheck": {
            "ready": bool([row for row in accuracy if row.get("source") == "norecheck"]),
            "note": "Existing runs/deacon_auto_norecheck accepted after count-level audit.",
        },
        "mock_ground_truth": {
            "ready": bool(mock_datasets),
            "datasets_with_accuracy": mock_datasets,
            "note": "Requires exact ground truth and all three tool arms per replicate.",
        },
    }
    blockers = []
    for key, value in status.items():
        if isinstance(value, dict) and "ready" in value and not value["ready"]:
            blockers.append(key)
    status["blocking_work"] = blockers
    status["status"] = "analysis_ready" if not blockers else "compute_pending"
    return status


def plot_threshold(tradeoff: list[dict], output: Path) -> None:
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        return
    by_dataset: dict[str, list[dict]] = defaultdict(list)
    for row in tradeoff:
        if isinstance(row.get("threshold_mean"), float):
            by_dataset[row["dataset"]].append(row)
    if not by_dataset:
        return
    fig, axes = plt.subplots(1, 3, figsize=(9, 3), constrained_layout=True)
    metrics = [("f1_mean", "Retained-microbe F1"), ("host_input_retention_pct_mean", "Host retention (%)"),
               ("runtime_s_mean", "Runtime (s)")]
    for dataset, rows in sorted(by_dataset.items()):
        ordered = sorted(rows, key=lambda x: x["threshold_mean"])
        x = [row["threshold_mean"] for row in ordered]
        for ax, metric, label in zip(axes, metrics, [m[1] for m in metrics]):
            values = [row.get(metric) for row in ordered]
            if any(value is None or (isinstance(value, float) and math.isnan(value)) for value in values):
                continue
            ax.plot(x, values, marker="o", label=dataset)
            ax.set_xlabel("Recheck threshold")
            ax.set_title(label)
    for ax in axes:
        ax.spines[["top", "right"]].set_visible(False)
        ax.tick_params(labelsize=7)
    axes[0].legend(fontsize=5, frameon=False)
    fig.savefig(output.with_suffix(".png"), dpi=300)
    fig.savefig(output.with_suffix(".svg"))
    plt.close(fig)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--controls-root", type=Path, default=Path("runs/unresolved_controls"))
    parser.add_argument("--legacy-paired", type=Path, default=Path("data/paired_triplicate/100M_90pct_high_lognormal_SE/paired_runtime_corrected.csv"))
    parser.add_argument("--norecheck", type=Path, default=Path("runs/deacon_auto_norecheck"))
    parser.add_argument("--output-dir", type=Path, default=Path("data/unresolved_controls"))
    args = parser.parse_args()

    roots = [args.controls_root / "equal_thread_panel", args.controls_root / "threshold_sweep",
             args.controls_root / "always_recheck", args.controls_root / "cleanifier_benchmark",
             args.controls_root / "mock_truth_validation", args.norecheck]
    labels = ["equal_thread", "threshold", "always", "cleanifier", "mock", "norecheck"]
    accuracy = collect_accuracy(roots, labels)
    performance = collect_performance(roots, labels)
    if args.legacy_paired.is_file():
        for row in read_csv(args.legacy_paired):
            row["source"] = "legacy_equal_thread_100m90"
            row["dataset"] = row.get("dataset", "100M_90pct_high_lognormal_SE")
            row["runtime_s"] = as_float(row, "runtime_s", as_float(row, "runtime_seconds"))
            performance.append(row)
            args.controls_root.mkdir(parents=True, exist_ok=True)
            # Keep legacy paired rows in inventory but exclude from standardized accuracy.
    fields = ["source", "tool", "condition", "dataset", "rep", "tp", "fp", "fn", "tn",
              "unmapped_kept", "host_total", "microbe_total", "retained_total",
              "accuracy", "precision", "recall", "f1", "host_input_retention_pct",
              "microbial_loss_pct", "host_output_fraction_pct"]
    write_csv(args.output_dir / "combined_accuracy.csv", accuracy, fields)
    perf_fields = ["source", "tool", "condition", "dataset", "rep", "runtime_s",
                   "max_memory_kb", "threads", "node", "timestamp", "extra"]
    write_csv(args.output_dir / "combined_performance.csv", performance, perf_fields)

    summary = group_means(accuracy, ["source", "tool", "condition", "dataset"],
                          ["f1", "host_input_retention_pct", "microbial_loss_pct",
                           "host_output_fraction_pct", "retained_total"])
    write_csv(args.output_dir / "accuracy_summary.csv", summary,
              ["source", "tool", "condition", "dataset", "replicates", "f1_mean", "f1_sd",
               "host_input_retention_pct_mean", "host_input_retention_pct_sd",
               "microbial_loss_pct_mean", "microbial_loss_pct_sd",
               "host_output_fraction_pct_mean", "host_output_fraction_pct_sd",
               "retained_total_mean"])
    perf_summary = group_means(performance, ["source", "tool", "condition", "dataset"],
                               ["runtime_s", "max_memory_kb"])
    write_csv(args.output_dir / "runtime_summary.csv", perf_summary,
              ["source", "tool", "condition", "dataset", "replicates", "runtime_s_mean",
               "runtime_s_sd", "max_memory_kb_mean", "max_memory_kb_sd"])
    equal = equal_thread_summary(performance)
    if equal:
        write_csv(args.output_dir / "equal_thread_paired_summary.csv", equal,
                  ["dataset", "rep", "rustyclean_runtime_s", "hostile_runtime_s",
                   "hostile_minus_rustyclean_s", "speedup_hostile_over_rustyclean",
                   "paired_delta_mean_s", "paired_delta_sd_s", "paired_t_p",
                   "paired_wilcoxon_p", "paired_n"])
    tradeoff = group_means(accuracy + performance, ["dataset", "tool", "condition"],
                           ["f1", "host_input_retention_pct", "microbial_loss_pct",
                            "runtime_s"])
    for row in tradeoff:
        condition = str(row.get("condition", ""))
        try:
            row["threshold_mean"] = float(condition.split("threshold_")[1].split(":")[0])
        except (IndexError, ValueError):
            row["threshold_mean"] = math.nan
    write_csv(args.output_dir / "threshold_tradeoff.csv", tradeoff,
              ["dataset", "tool", "condition", "replicates", "threshold_mean", "f1_mean", "f1_sd",
               "host_input_retention_pct_mean", "host_input_retention_pct_sd",
               "microbial_loss_pct_mean", "microbial_loss_pct_sd", "runtime_s_mean", "runtime_s_sd"])
    plot_threshold(tradeoff, args.output_dir / "threshold_sweep.png")
    status = make_status(accuracy, performance, args.output_dir)
    (args.output_dir / "status.json").write_text(json.dumps(status, indent=2) + "\n")
    print(json.dumps(status, indent=2))


if __name__ == "__main__":
    main()
