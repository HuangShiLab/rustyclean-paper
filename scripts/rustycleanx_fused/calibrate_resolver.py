#!/usr/bin/env python3
"""Calibrate the production-query conflict resolver without re-running tools.

Inputs are compact, sampled evidence files produced by
``rustyclean-x --bin calibration_evidence``.  Training thresholds are selected
only on --train-datasets.  Validation files are scored once with the frozen
rule.
"""
from __future__ import annotations

import argparse
import gzip
import itertools
import json
from pathlib import Path

import numpy as np
import pandas as pd


def load_evidence(paths: list[Path]) -> pd.DataFrame:
    frames = []
    for path in paths:
        frame = pd.read_csv(path, sep="\t", compression="gzip")
        frames.append(frame)
    return pd.concat(frames, ignore_index=True, copy=False)


def prepare(data: pd.DataFrame) -> tuple[pd.DataFrame, np.ndarray, np.ndarray, np.ndarray]:
    data = data.copy()
    data["is_host"] = data["truth"].str.lower().isin({"host", "human"})
    # This is the existing safe union-depletion rule: either production query
    # removes, otherwise keep.  The resolver can only rescue removals.
    data["union_remove"] = ~((data["deacon_keep"] == 1) & (data["cleanifier_keep"] == 1))
    data["both_remove"] = (data["deacon_keep"] == 0) & (data["cleanifier_keep"] == 0)
    return (
        data,
        data["is_host"].to_numpy(dtype=bool),
        data["union_remove"].to_numpy(dtype=bool),
        data["both_remove"].to_numpy(dtype=bool),
    )


def metrics(data: pd.DataFrame, microbe_threshold: float, host_threshold: float) -> dict[str, float | int]:
    is_host = data["is_host"].to_numpy(dtype=bool)
    remove = data["union_remove"].to_numpy(dtype=bool)
    rescue = remove & (data["microbe_score"].to_numpy() >= microbe_threshold) & (
        data["host_score"].to_numpy() <= host_threshold
    )
    removed = remove & ~rescue
    host_total = int(is_host.sum())
    microbe_total = int(len(data) - host_total)
    host_removed = int((is_host & removed).sum())
    microbe_removed = int((~is_host & removed).sum())
    host_retained = host_total - host_removed
    microbe_retained = microbe_total - microbe_removed
    retained_total = host_retained + microbe_retained
    precision = microbe_retained / retained_total if retained_total else 1.0
    recall = microbe_retained / microbe_total if microbe_total else 1.0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    return {
        "host_retention_pct": 100.0 * host_retained / host_total if host_total else 0.0,
        "microbial_loss_pct": 100.0 * microbe_removed / microbe_total if microbe_total else 0.0,
        "host_rescued": int((is_host & rescue).sum()),
        "microbe_rescued": int((~is_host & rescue).sum()),
        "host_removed": host_removed,
        "microbe_removed": microbe_removed,
        "retained_total": retained_total,
        "precision": precision,
        "recall": recall,
        "f1": f1,
    }


def sweep(train: pd.DataFrame, microbe_values: np.ndarray, host_values: np.ndarray,
          host_limit_pct: float, max_dataset_host_pct: float) -> tuple[list[dict], dict]:
    rows = []
    step = float(microbe_values[1] - microbe_values[0]) if len(microbe_values) > 1 else 1.0
    n_bins = len(microbe_values)
    candidates = train[train["union_remove"]].copy()
    candidates["microbe_bin"] = np.clip(
        np.floor(candidates["microbe_score"].to_numpy() / step + 1e-12), 0, n_bins - 1
    ).astype(np.int16)
    candidates["host_bin"] = np.clip(
        np.floor(candidates["host_score"].to_numpy() / step + 1e-12), 0, n_bins - 1
    ).astype(np.int16)

    host_total = int(train["is_host"].sum())
    microbe_total = int(len(train) - host_total)
    candidate_host_total = int(candidates["is_host"].sum())
    candidate_microbe_total = int(len(candidates) - candidate_host_total)

    def rescue_matrix(frame: pd.DataFrame, host_only: bool) -> np.ndarray:
        selected = frame[frame["is_host"]] if host_only else frame[~frame["is_host"]]
        host_hist, _, _ = np.histogram2d(
            selected["microbe_bin"],
            selected["host_bin"],
            bins=(n_bins, n_bins),
            range=((0, n_bins), (0, n_bins)),
        )
        rescue = np.zeros((n_bins, n_bins), dtype=np.int64)
        for i in reversed(range(n_bins)):
            prefix = np.cumsum(host_hist[i])
            rescue[i] = prefix
            if i + 1 < n_bins:
                rescue[i] += rescue[i + 1]
        return rescue

    overall_host_rescue = rescue_matrix(candidates, True)
    microbe_rescue = np.zeros_like(overall_host_rescue)
    microbe_rescue = rescue_matrix(candidates, False)
    per_dataset_host_rescue = {}
    per_dataset_host_total = {}
    per_dataset_candidate_host_total = {}
    for name, frame in candidates.groupby("dataset", sort=False):
        dataset_host_total = int(train.loc[train["dataset"] == name, "is_host"].sum())
        per_dataset_host_total[name] = dataset_host_total
        per_dataset_candidate_host_total[name] = int(frame["is_host"].sum())
        per_dataset_host_rescue[name] = rescue_matrix(frame, True)

    for i, microbe_threshold in enumerate(microbe_values):
        for j, host_threshold in enumerate(host_values):
            host_rescued = int(overall_host_rescue[i, j])
            microbe_rescued = int(microbe_rescue[i, j])
            host_removed = candidate_host_total - host_rescued
            microbe_removed = candidate_microbe_total - microbe_rescued
            host_retained = host_total - host_removed
            host_retention = 100.0 * host_retained / host_total if host_total else 0.0
            microbial_loss = 100.0 * microbe_removed / microbe_total if microbe_total else 0.0
            dataset_host_pct = []
            for name in sorted(per_dataset_host_total):
                total_host = per_dataset_host_total[name]
                rescued = int(per_dataset_host_rescue[name][i, j])
                candidate_host = per_dataset_candidate_host_total[name]
                dataset_host_pct.append(
                    100.0 * (total_host - candidate_host + rescued) / total_host
                    if total_host else 0.0
                )
            rows.append({
                "microbe_score_rescue": float(microbe_threshold),
                "host_score_max": float(host_threshold),
                "host_retention_pct": host_retention,
                "max_dataset_host_retention_pct": max(dataset_host_pct),
                "microbial_loss_pct": microbial_loss,
                "host_rescued": host_rescued,
                "microbe_rescued": microbe_rescued,
                "host_removed": host_removed,
                "microbe_removed": microbe_removed,
                "feasible": bool(host_retention <= host_limit_pct and max(dataset_host_pct) <= max_dataset_host_pct),
            })
    feasible = [row for row in rows if row["feasible"]]
    pool = feasible if feasible else rows
    selected = min(pool, key=lambda row: (row["microbial_loss_pct"], -row["host_retention_pct"], row["microbe_score_rescue"]))
    return rows, selected


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence-root", required=True)
    parser.add_argument("--train-datasets", nargs="+", required=True)
    parser.add_argument("--validation-datasets", nargs="+", required=True)
    parser.add_argument("--outdir", required=True)
    parser.add_argument("--host-limit-pct", type=float, default=0.0030,
                        help="Overall training host-retention limit, stricter than Deacon")
    parser.add_argument("--max-dataset-host-pct", type=float, default=0.0060)
    parser.add_argument("--suffix", default=".sample5.tsv.gz")
    parser.add_argument("--step", type=float, default=0.02)
    args = parser.parse_args()

    root = Path(args.evidence_root)
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    train = load_evidence([root / f"{name}{args.suffix}" for name in args.train_datasets])
    train, _, _, _ = prepare(train)

    microbe_values = np.round(np.arange(0.0, 1.0001 + 1e-12, args.step), 6)
    host_values = np.round(np.arange(0.0, 1.0001 + 1e-12, args.step), 6)
    sweep_rows, selected = sweep(
        train,
        microbe_values,
        host_values,
        args.host_limit_pct,
        args.max_dataset_host_pct,
    )
    sweep_columns = list(sweep_rows[0])
    with (outdir / "resolver_sweep_train.tsv").open("w") as handle:
        handle.write("\t".join(sweep_columns) + "\n")
        for row in sweep_rows:
            handle.write("\t".join(str(row[key]) for key in sweep_columns) + "\n")

    validation = []
    for dataset in args.validation_datasets:
        frame = load_evidence([root / f"{dataset}{args.suffix}"])
        frame, _, _, _ = prepare(frame)
        row = {
            "dataset": dataset,
            "rule": "union+calibrated_witness_host_gate",
            "microbe_score_rescue": selected["microbe_score_rescue"],
            "host_score_max": selected["host_score_max"],
            **metrics(frame, selected["microbe_score_rescue"], selected["host_score_max"]),
        }
        validation.append(row)
        validation.append({
            "dataset": dataset,
            "rule": "union_depletion_ablation",
            "microbe_score_rescue": 0.0,
            "host_score_max": 1.0,
            **metrics(frame, 0.0, 1.0),
        })
    validation_columns = list(validation[0])
    with (outdir / "resolver_validation_sampled.tsv").open("w") as handle:
        handle.write("\t".join(validation_columns) + "\n")
        for row in validation:
            handle.write("\t".join(str(row[key]) for key in validation_columns) + "\n")

    manifest = {
        "training_datasets": args.train_datasets,
        "validation_datasets": args.validation_datasets,
        "sampling_suffix": args.suffix,
        "threshold_grid_step": args.step,
        "host_limit_pct": args.host_limit_pct,
        "max_dataset_host_pct": args.max_dataset_host_pct,
        "training_rows": len(train),
        "candidate_rows": int(train["union_remove"].sum()),
        "selected_rule": selected,
    }
    (outdir / "resolver_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
