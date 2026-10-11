#!/usr/bin/env python3
"""Memory-bounded threshold calibration for RustyClean-X fused reports."""
import argparse
import csv
import gzip
import json
from pathlib import Path


def open_report(path):
    return gzip.open(path, "rt", newline="") if str(path).endswith(".gz") else open(path, "rt", newline="")


def make_score(row, gapped_weight, minimizer_weight):
    total = gapped_weight + minimizer_weight
    if total <= 0:
        return 0.0
    return (gapped_weight * min(float(row["gapped_component"]), 1.0)
            + minimizer_weight * min(float(row["minimizer_component"]), 1.0)) / total


def metrics_from_rows(rows, remove, confident, rescue, gapped_weight, minimizer_weight):
    host_total = microbe_total = host_removed = microbe_removed = 0
    retained_microbe = 0
    for row in rows:
        host_score = make_score(row, gapped_weight, minimizer_weight)
        microbe = min(float(row["microbe_score"]), 1.0)
        is_host = row["truth"].lower() in {"host", "human"}
        rescue_call = microbe >= rescue and host_score < confident
        removed = host_score >= remove and not rescue_call
        retained = not removed
        if is_host:
            host_total += 1
            host_removed += int(removed)
        else:
            microbe_total += 1
            microbe_removed += int(removed)
            retained_microbe += int(retained)
    retained_total = host_total - host_removed + microbe_total - microbe_removed
    precision = retained_microbe / retained_total if retained_total else 1.0
    recall = retained_microbe / microbe_total if microbe_total else 1.0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    return {
        "host_retention_pct": 100.0 * (host_total - host_removed) / host_total if host_total else 0.0,
        "microbial_loss_pct": 100.0 * microbe_removed / microbe_total if microbe_total else 0.0,
        "host_removed": host_removed,
        "microbe_removed": microbe_removed,
        "retained_total": retained_total,
        "precision": precision,
        "recall": recall,
        "f1": f1,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-root", required=True)
    parser.add_argument("--train-datasets", nargs="+", required=True)
    parser.add_argument("--validation-datasets", nargs="+", required=True)
    parser.add_argument("--outdir", required=True)
    parser.add_argument("--host-target-pct", type=float, default=0.05)
    parser.add_argument("--sample-every", type=int, default=1000)
    parser.add_argument("--gapped-weight", type=float, default=0.5)
    parser.add_argument("--minimizer-weight", type=float, default=0.5)
    args = parser.parse_args()

    root = Path(args.run_root)
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    sampled_path = outdir / "training_sample.tsv"
    train_rows = []
    with sampled_path.open("w", newline="") as out:
        fields = ["read_id", "truth", "gapped_component", "minimizer_component", "microbe_score"]
        writer = csv.DictWriter(out, fieldnames=fields, delimiter="\t")
        writer.writeheader()
        for dataset in args.train_datasets:
            with open_report(root / dataset / "per_read_report.tsv.gz") as handle:
                for index, row in enumerate(csv.DictReader(handle, delimiter="\t")):
                    if index % args.sample_every:
                        continue
                    sampled = {key: row[key] for key in fields}
                    writer.writerow(sampled)
                    train_rows.append(sampled)

    sweep = []
    for remove_i in range(30, 96, 5):
        remove = remove_i / 100.0
        for confident_i in range(int(remove_i) + 5, 96, 5):
            confident = confident_i / 100.0
            for rescue_i in range(40, 105, 5):
                rescue = rescue_i / 100.0
                sweep.append({
                    "host_score_remove": remove,
                    "host_score_confident": confident,
                    "microbe_score_rescue": rescue,
                    **metrics_from_rows(train_rows, remove, confident, rescue,
                                        args.gapped_weight, args.minimizer_weight),
                })

    feasible = [row for row in sweep if row["host_retention_pct"] <= args.host_target_pct]
    selected = min(feasible or sweep,
                   key=lambda row: (row["microbial_loss_pct"], -row["f1"]))
    with (outdir / "threshold_sweep_train.tsv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(sweep[0]), delimiter="\t")
        writer.writeheader()
        writer.writerows(sweep)

    validation = []
    for dataset in args.validation_datasets:
        def validation_rows():
            with open_report(root / dataset / "per_read_report.tsv.gz") as handle:
                yield from csv.DictReader(handle, delimiter="\t")
        validation.append({"dataset": dataset, "thresholds": "default",
                           **metrics_from_rows(validation_rows(), 0.60, 0.80, 1.00,
                                               args.gapped_weight, args.minimizer_weight)})
        validation.append({
            "dataset": dataset,
            "thresholds": json.dumps(selected),
            **metrics_from_rows(validation_rows(), selected["host_score_remove"],
                                selected["host_score_confident"],
                                selected["microbe_score_rescue"],
                                args.gapped_weight, args.minimizer_weight),
        })
    with (outdir / "validation_metrics.tsv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(validation[0]), delimiter="\t")
        writer.writeheader()
        writer.writerows(validation)

    manifest = {
        "sample_every": args.sample_every,
        "training_sample_rows": len(train_rows),
        "train_datasets": args.train_datasets,
        "validation_datasets": args.validation_datasets,
        "host_target_pct": args.host_target_pct,
        "selected_thresholds": selected,
    }
    (outdir / "calibration_manifest.json").write_text(json.dumps(manifest, indent=2))
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
