#!/usr/bin/env python3
"""Calculate paired statistics for the equal-thread runtime panel."""
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

import numpy as np
from scipy import stats


def bootstrap_geomean(values: np.ndarray, replicates: int, seed: int) -> tuple[float, float]:
    rng = np.random.default_rng(seed)
    estimates = np.exp(rng.choice(np.log(values), size=(replicates, len(values)), replace=True).mean(axis=1))
    return tuple(np.percentile(estimates, [2.5, 97.5]))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--performance", type=Path, required=True)
    parser.add_argument("--rustyclean", default="rustyclean_auto")
    parser.add_argument("--hostile", default="fastp_hostile")
    parser.add_argument("--output-json", type=Path, required=True)
    parser.add_argument("--pair-output", type=Path)
    parser.add_argument("--bootstrap-replicates", type=int, default=100000)
    parser.add_argument("--seed", type=int, default=20251002)
    args = parser.parse_args()

    with args.performance.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    selected = [r for r in rows if r.get("tool") in {args.rustyclean, args.hostile}]
    index: dict[tuple[str, str], dict[str, dict[str, str]]] = {}
    for row in selected:
        index.setdefault((row["dataset"], row["rep"]), {}).setdefault(row["tool"], row)
    pairs = []
    for (dataset, rep), tools in sorted(index.items()):
        if args.rustyclean not in tools or args.hostile not in tools:
            continue
        rustyclean = float(tools[args.rustyclean]["runtime_s"])
        hostile = float(tools[args.hostile]["runtime_s"])
        pairs.append({"dataset": dataset, "rep": rep, "rustyclean_runtime_s": rustyclean,
                      "hostile_runtime_s": hostile, "hostile_minus_rustyclean_s": hostile - rustyclean,
                      "speedup": hostile / rustyclean})
    if not pairs:
        raise SystemExit("no complete paired observations")

    speedup = np.array([p["speedup"] for p in pairs], dtype=float)
    delta = np.array([p["hostile_minus_rustyclean_s"] for p in pairs], dtype=float)
    faster = sum(p["hostile_runtime_s"] > p["rustyclean_runtime_s"] for p in pairs)
    sign_test = stats.binomtest(faster, len(pairs), 0.5, alternative="two-sided")
    t_test = stats.ttest_1samp(delta, 0.0, alternative="two-sided")
    wilcoxon = stats.wilcoxon(delta, alternative="two-sided", zero_method="wilcox")
    lo, hi = bootstrap_geomean(speedup, args.bootstrap_replicates, args.seed)
    dataset_order = sorted({p["dataset"] for p in pairs})
    dataset_summaries = []
    for dataset in dataset_order:
        values = np.array([p["speedup"] for p in pairs if p["dataset"] == dataset], dtype=float)
        deltas = np.array([p["hostile_minus_rustyclean_s"] for p in pairs if p["dataset"] == dataset], dtype=float)
        dataset_summaries.append({
            "dataset": dataset,
            "n": len(values),
            "rustyclean_runtime_s_mean": float(np.mean([p["rustyclean_runtime_s"] for p in pairs if p["dataset"] == dataset])),
            "hostile_runtime_s_mean": float(np.mean([p["hostile_runtime_s"] for p in pairs if p["dataset"] == dataset])),
            "speedup_mean": float(np.mean(values)),
            "speedup_median": float(np.median(values)),
            "hostile_minus_rustyclean_s_mean": float(np.mean(deltas)),
        })
    dataset_speedup = np.array([x["speedup_mean"] for x in dataset_summaries], dtype=float)
    dataset_log_speedup = np.log(dataset_speedup)
    dataset_t_test = stats.ttest_1samp(dataset_log_speedup, 0.0, alternative="two-sided")
    dataset_wilcoxon = stats.wilcoxon(dataset_log_speedup, alternative="two-sided", zero_method="wilcox")
    dataset_sign_test = stats.binomtest(int((dataset_speedup > 1).sum()), len(dataset_speedup), 0.5, alternative="two-sided")
    dataset_t_ci = tuple(map(float, np.exp([
        np.mean(dataset_log_speedup) - stats.t.ppf(0.975, len(dataset_log_speedup) - 1) * stats.sem(dataset_log_speedup),
        np.mean(dataset_log_speedup) + stats.t.ppf(0.975, len(dataset_log_speedup) - 1) * stats.sem(dataset_log_speedup),
    ])))
    rng = np.random.default_rng(args.seed)
    cluster_bootstrap = []
    for _ in range(args.bootstrap_replicates):
        selected_datasets = rng.integers(0, len(dataset_speedup), len(dataset_speedup))
        cluster_bootstrap.append(np.exp(np.mean(dataset_log_speedup[selected_datasets])))
    dataset_cluster_ci = tuple(map(float, np.percentile(cluster_bootstrap, [2.5, 97.5])))
    result = {
        "n_pairs": len(pairs),
        "rustyclean_faster_pairs": faster,
        "hostile_faster_pairs": len(pairs) - faster,
        "sign_test_p": float(sign_test.pvalue),
        "paired_t_statistic": float(t_test.statistic),
        "paired_t_p": float(t_test.pvalue),
        "wilcoxon_p": float(wilcoxon.pvalue),
        "median_hostile_minus_rustyclean_s": float(np.median(delta)),
        "mean_hostile_minus_rustyclean_s": float(np.mean(delta)),
        "median_speedup": float(np.median(speedup)),
        "geometric_mean_speedup": float(np.exp(np.mean(np.log(speedup)))),
        "geometric_mean_speedup_95ci": [float(lo), float(hi)],
        "minimum_speedup": float(np.min(speedup)),
        "maximum_speedup": float(np.max(speedup)),
        "bootstrap_replicates": args.bootstrap_replicates,
        "seed": args.seed,
        "n_datasets": len(dataset_summaries),
        "dataset_level_geometric_mean_speedup": float(np.exp(np.mean(dataset_log_speedup))),
        "dataset_level_geometric_mean_speedup_t_ci": list(dataset_t_ci),
        "dataset_level_geometric_mean_speedup_cluster_bootstrap_ci": list(dataset_cluster_ci),
        "dataset_level_paired_t_p": float(dataset_t_test.pvalue),
        "dataset_level_wilcoxon_p": float(dataset_wilcoxon.pvalue),
        "dataset_level_sign_test_p": float(dataset_sign_test.pvalue),
        "dataset_level_rustyclean_faster_datasets": int((dataset_speedup > 1).sum()),
        "dataset_summaries": dataset_summaries,
    }
    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    args.output_json.write_text(json.dumps(result, indent=2) + "\n")
    if args.pair_output:
        args.pair_output.parent.mkdir(parents=True, exist_ok=True)
        with args.pair_output.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(pairs[0]), lineterminator="\n")
            writer.writeheader()
            writer.writerows(pairs)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
