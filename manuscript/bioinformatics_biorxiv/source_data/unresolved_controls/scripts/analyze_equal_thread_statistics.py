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
