#!/usr/bin/env python3
import argparse
import csv
import gzip
import json
from pathlib import Path


def open_report(path):
    return gzip.open(path, "rt", newline="") if str(path).endswith(".gz") else open(path, "rt", newline="")


def metrics(rows, rescue):
    host_total = microbe_total = host_removed = microbe_removed = 0
    retained_microbe = 0
    for row in rows:
        deacon_remove = row["deacon_remove"] == "1"
        cleanifier_remove = row["cleanifier_remove"] == "1"
        if deacon_remove and cleanifier_remove:
            removed = True
        elif not deacon_remove and not cleanifier_remove:
            removed = False
        else:
            removed = float(row["microbe_score"]) < rescue
        retained = not removed
        is_host = row["truth"].lower() in {"host", "human"}
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
    args = parser.parse_args()
    root = Path(args.run_root)
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    train_rows = []
    sampled_path = outdir / "training_sample.tsv"
    with sampled_path.open("w", newline="") as out:
        fields = ["read_id", "truth", "deacon_remove", "cleanifier_remove", "microbe_score"]
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
    for rescue_i in range(0, 105, 5):
        rescue = rescue_i / 100.0
        sweep.append({"microbe_score_rescue": rescue,
                      **metrics(train_rows, rescue)})
    feasible = [row for row in sweep if row["host_retention_pct"] <= args.host_target_pct]
    selected = max(feasible or sweep, key=lambda row: (row["f1"], -row["microbial_loss_pct"]))
    with (outdir / "threshold_sweep_train.tsv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(sweep[0]), delimiter="\t")
        writer.writeheader()
        writer.writerows(sweep)

    validation = []
    for dataset in args.validation_datasets:
        def rows():
            with open_report(root / dataset / "per_read_report.tsv.gz") as handle:
                yield from csv.DictReader(handle, delimiter="\t")
        validation.append({"dataset": dataset, "thresholds": "default_0.30", **metrics(rows(), 0.30)})
        validation.append({"dataset": dataset, "thresholds": json.dumps(selected),
                           **metrics(rows(), selected["microbe_score_rescue"])})
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
        "selected_microbe_score_rescue": selected["microbe_score_rescue"],
        "selected_training_metrics": selected,
    }
    (outdir / "calibration_manifest.json").write_text(json.dumps(manifest, indent=2))
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
