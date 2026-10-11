#!/usr/bin/env python3
"""Paired statistical comparison of RustyClean and Hostile+fastp runtimes."""

import argparse
import csv
from collections import defaultdict
from pathlib import Path

from scipy import stats


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("metrics_csv")
    parser.add_argument("--alpha", type=float, default=0.05)
    args = parser.parse_args()

    paired: dict[str, dict[tuple[int, str], float]] = defaultdict(dict)
    with open(args.metrics_csv, newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            paired[row["dataset"]][(int(row["rep"]), row["tool"])] = float(row["runtime_s"])

    print(
        "dataset,n,rc_mean_s,hostile_mean_s,mean_delta_s,rc_faster_wins,"
        "paired_t,p_t,wilcoxon_p"
    )
    for dataset in sorted(paired):
        pairs = paired[dataset]
        reps = sorted({rep for rep, _ in pairs})
        complete = []
        for rep in reps:
            if (rep, "rustyclean") in pairs and (rep, "hostile_fastp") in pairs:
                complete.append(
                    (pairs[(rep, "rustyclean")], pairs[(rep, "hostile_fastp")])
                )
        rc = [x for x, _ in complete]
        hostile = [y for _, y in complete]
        deltas = [y - x for x, y in complete]
        t_result = stats.ttest_rel(rc, hostile)
        try:
            w_result = stats.wilcoxon(rc, hostile, alternative="two-sided")
        except ValueError:
            w_result = type("Result", (), {"pvalue": 1.0})()
        print(
            f"{dataset},{len(complete)},{sum(rc) / len(rc):.3f},"
            f"{sum(hostile) / len(hostile):.3f},{sum(deltas) / len(deltas):.3f},"
            f"{sum(x < y for x, y in complete)},{t_result.pvalue:.3g},"
            f"{w_result.pvalue:.3g}"
        )


if __name__ == "__main__":
    main()
