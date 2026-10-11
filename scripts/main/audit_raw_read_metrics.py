#!/usr/bin/env python3
"""Audit archived read-level confusion matrices against biological metrics.

The audit deliberately starts from TP/FP/FN/TN rather than summary rates.
Two archived schemas are recognized:

RETAINED_MICROBE
    TP = retained microbe, FP = retained host,
    FN = lost microbe,  TN = removed host.

REMOVED_HOST
    TP = removed host,  FP = lost microbe,
    FN = retained host, TN = retained microbe.

Usage: python3 scripts/main/audit_raw_read_metrics.py [output_dir]
"""
from __future__ import annotations

import csv
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXPECTED = {
    "5M_1pct_low_even_SE": (5_000_000, 0.009),
    "10M_10pct_med_even_SE": (9_500_000, 0.10),
    "30M_50pct_high_skewed_SE": (23_900_000, 0.597),
    "60M_90pct_high_lognormal_SE": (56_200_000, 0.914),
    "100M_50pct_high_lognormal_SE": (87_800_000, 0.541),
    "100M_90pct_high_lognormal_SE": (93_600_000, 0.914),
}
TOL = 5e-7
LABEL_TOL = 0.0001


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def metrics_from_counts(tp: int, fp: int, fn: int, tn: int, schema: str) -> dict[str, float]:
    total = tp + fp + fn + tn
    precision = tp / (tp + fp) if tp + fp else 0.0
    recall = tp / (tp + fn) if tp + fn else 0.0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    accuracy = (tp + tn) / total if total else 0.0
    if schema == "RETAINED_MICROBE":
        microbe_in = tp + fn
        host_in = fp + tn
        microbe_loss = fn / microbe_in if microbe_in else 0.0
        host_retention = fp / host_in if host_in else 0.0
        host_output_fraction = fp / (tp + fp) if tp + fp else 0.0
    elif schema == "REMOVED_HOST":
        host_in = tp + fn
        microbe_in = fp + tn
        host_retention = fn / host_in if host_in else 0.0
        microbe_loss = fp / microbe_in if microbe_in else 0.0
        host_output_fraction = fn / (fn + tn) if fn + tn else 0.0
    else:
        raise ValueError(schema)
    return {
        "accuracy_recomputed": accuracy,
        "precision_recomputed": precision,
        "recall_recomputed": recall,
        "f1_recomputed": f1,
        "microbial_loss_pct_recomputed": 100 * microbe_loss,
        "host_input_retention_pct_recomputed": 100 * host_retention,
        "host_output_fraction_pct_recomputed": 100 * host_output_fraction,
        "input_microbe_reads": microbe_in,
        "input_host_reads": host_in,
        "input_total_reads": total,
        "host_input_fraction": host_in / total if total else 0.0,
    }


def close(a: float, b: float, tol: float = TOL) -> bool:
    return abs(a - b) <= tol


def rows_from_file(path: Path, schema: str, mapping: dict[str, str]) -> list[dict[str, object]]:
    out = []
    for source_row in read_csv(path):
        get = lambda key: source_row.get(mapping[key], "")
        tp, fp = int(float(get("tp"))), int(float(get("fp")))
        fn, tn = int(float(get("fn"))), int(float(get("tn")))
        row: dict[str, object] = {
            "source_file": str(path),
            "schema": schema,
            "tool_or_index": get("tool_or_index"),
            "dataset": get("dataset"),
            "rep": get("rep"),
            "tp": tp,
            "fp": fp,
            "fn": fn,
            "tn": tn,
            "reported_microbial_loss_pct": "",
            "reported_host_retention_pct": "",
            "microbial_loss_label_match": "",
            "host_retention_label_match": "",
        }
        if not row["tool_or_index"]:
            row["tool_or_index"] = "rustyclean_auto" if "auto_metrics" in path.name else "unknown"
        row.update(metrics_from_counts(tp, fp, fn, tn, schema))
        checks = []
        reported = {
            "accuracy": float(get("accuracy")),
            "precision": float(get("precision")),
            "recall": float(get("recall")),
            "f1": float(get("f1")),
        }
        for key, value in reported.items():
            ok = close(value, float(row[f"{key}_recomputed"]))
            row[f"{key}_reported"] = value
            row[f"{key}_formula_match"] = ok
            if not ok:
                checks.append(key)
        if mapping.get("microbial_loss") and get("microbial_loss") and get("host_retention"):
            label_scale = 100 if schema == "REMOVED_HOST" else 1
            row["reported_microbial_loss_pct"] = float(get("microbial_loss")) * label_scale
            row["reported_host_retention_pct"] = float(get("host_retention")) * label_scale
            row["microbial_loss_label_match"] = close(
                row["reported_microbial_loss_pct"],
                row["microbial_loss_pct_recomputed"],
                LABEL_TOL,
                )
            row["host_retention_label_match"] = close(
                row["reported_host_retention_pct"],
                row["host_input_retention_pct_recomputed"],
                LABEL_TOL,
            )
            if not row["microbial_loss_label_match"]:
                checks.append("microbial_loss_label")
            if not row["host_retention_label_match"]:
                checks.append("host_retention_label")
        dataset = str(row["dataset"])
        if dataset in EXPECTED:
            expected_total, expected_host_fraction = EXPECTED[dataset]
            row["expected_nominal_reads"] = expected_total
            row["expected_host_fraction"] = expected_host_fraction
            row["total_vs_nominal_ratio"] = float(row["input_total_reads"]) / expected_total
            row["host_fraction_close_to_nominal"] = abs(float(row["host_input_fraction"]) - expected_host_fraction) <= 0.015
            if not row["host_fraction_close_to_nominal"]:
                checks.append("host_fraction_schema_or_labels")
        else:
            row["host_fraction_close_to_nominal"] = ""
            row["total_vs_nominal_ratio"] = ""
        row["audit_flags"] = ";".join(checks) if checks else "PASS"
        out.append(row)
    return out


def rows_from_deacon_file(path: Path) -> list[dict[str, object]]:
    """Read deacon_metrics.csv, whose data rows have an extra tool field."""
    out: list[dict[str, object]] = []
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.reader(handle)
        next(reader)
        for fields in reader:
            if len(fields) != 15:
                raise ValueError(f"expected 15 fields in {path}, got {len(fields)}")
            (_tool, dataset, rep, _elapsed, _rss, accuracy, precision, recall, f1,
             reported_micro_loss, reported_host_carry, tp, fp, fn, tn) = fields
            tp, fp, fn, tn = map(int, map(float, (tp, fp, fn, tn)))
            row: dict[str, object] = {
                "source_file": str(path), "schema": "RETAINED_MICROBE",
                "tool_or_index": "deacon", "dataset": dataset, "rep": rep,
                "tp": tp, "fp": fp, "fn": fn, "tn": tn,
            }
            row.update(metrics_from_counts(tp, fp, fn, tn, "RETAINED_MICROBE"))
            checks = []
            reported = {
                "accuracy": float(accuracy), "precision": float(precision),
                "recall": float(recall), "f1": float(f1),
            }
            for key, value in reported.items():
                ok = close(value, float(row[f"{key}_recomputed"]))
                row[f"{key}_reported"] = value
                row[f"{key}_formula_match"] = ok
                if not ok:
                    checks.append(key)
            row["reported_microbial_loss_pct"] = float(reported_micro_loss)
            row["reported_host_retention_pct"] = float(reported_host_carry)
            row["microbial_loss_label_match"] = close(
                row["reported_microbial_loss_pct"], row["microbial_loss_pct_recomputed"], LABEL_TOL)
            row["host_retention_label_match"] = close(
                row["reported_host_retention_pct"], row["host_input_retention_pct_recomputed"], LABEL_TOL)
            if not row["microbial_loss_label_match"]:
                checks.append("microbial_loss_label")
            if not row["host_retention_label_match"]:
                checks.append("host_retention_label")
            if dataset in EXPECTED:
                expected_total, expected_host_fraction = EXPECTED[dataset]
                row["expected_nominal_reads"] = expected_total
                row["expected_host_fraction"] = expected_host_fraction
                row["total_vs_nominal_ratio"] = float(row["input_total_reads"]) / expected_total
                row["host_fraction_close_to_nominal"] = abs(
                    float(row["host_input_fraction"]) - expected_host_fraction) <= 0.015
                if not row["host_fraction_close_to_nominal"]:
                    checks.append("host_fraction_schema_or_labels")
            else:
                row["host_fraction_close_to_nominal"] = ""
                row["total_vs_nominal_ratio"] = ""
            row["audit_flags"] = ";".join(checks) if checks else "PASS"
            out.append(row)
    return out


def all_rows() -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    retained_mapping = {
        "tool_or_index": "tool", "dataset": "dataset", "rep": "rep",
        "tp": "tp", "fp": "fp", "fn": "fn", "tn": "tn",
        "accuracy": "accuracy", "precision": "precision", "recall": "recall", "f1": "f1",
        "microbial_loss": "microbial_loss_pct", "host_retention": "host_carry_pct",
    }
    p = ROOT / "archive/v1/data/benchmark_results/accuracy_comparison.csv"
    rows += rows_from_file(p, "RETAINED_MICROBE", retained_mapping)

    p = ROOT / "runs/deacon_panel/metrics/auto_metrics.csv"
    rows += rows_from_file(p, "RETAINED_MICROBE", retained_mapping)

    p = ROOT / "runs/deacon_panel/metrics/deacon_metrics.csv"
    rows += rows_from_deacon_file(p)

    p = ROOT / "data/deacon_panel/fill_100m_raw/fill_100m_metrics.csv"
    rows += rows_from_file(p, "RETAINED_MICROBE", retained_mapping)

    p = ROOT / "data/paired_triplicate/100M_90pct_high_lognormal_SE/paired_accuracy.csv"
    rows += rows_from_file(p, "RETAINED_MICROBE", retained_mapping)

    p = ROOT / "runs/deacon_panel/metrics/cross_species_metrics.csv"
    mapping = dict(retained_mapping)
    mapping["tool_or_index"] = "index"
    rows += rows_from_file(p, "RETAINED_MICROBE", mapping)

    p = ROOT / "archive/v1/data/accuracy_rc_mm_bt_cf_v4.csv"
    mapping = {
        "tool_or_index": "tool", "dataset": "dataset", "rep": "rep",
        "tp": "TP", "fp": "FP", "fn": "FN", "tn": "TN",
        "accuracy": "Accuracy", "precision": "Precision", "recall": "Recall", "f1": "F1",
        "microbial_loss": "Microbe_Loss_Rate", "host_retention": "Host_Remaining_Rate",
    }
    rows += rows_from_file(p, "REMOVED_HOST", mapping)
    return rows


def write_csv(rows: list[dict[str, object]], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = list(rows[0].keys())
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def write_report(rows: list[dict[str, object]], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    groups: dict[tuple[str, str], list[dict[str, object]]] = {}
    for row in rows:
        groups.setdefault((row["schema"], Path(str(row["source_file"])).name), []).append(row)

    lines = [
        "# Raw-read metric audit",
        "",
        "## Scope and method",
        "",
        "This audit starts from archived TP/FP/FN/TN counts, not from summary",
        "percentages. It recognizes two schemas. In the main panel and cross-species",
        "tables, TP is a retained microbe, FP a retained host, FN a lost microbe and",
        "TN a removed host. In the archived backend comparison, TP is a removed host,",
        "FP a lost microbe, FN a retained host and TN a retained microbe. The schema",
        "choice is checked against nominal host fractions. Standardized biological",
        "metrics are microbial loss divided by microbial input, host retention divided",
        "by host input, and host output fraction divided by retained reads.",
        "",
        "Raw FASTQ and ground-truth files are not present in this repository snapshot,",
        "so this is a count-level audit of archived outputs plus generator/formula",
        "inspection, not a fresh FASTQ-to-FASTQ replay.",
        "",
        "## Verdict by source",
        "",
        "Source | Schema | Rows | Formula/label verdict",
        "---|---|---:|---",
    ]
    for (schema, filename), group in sorted(groups.items()):
        failed = [r for r in group if r["audit_flags"] != "PASS"]
        if not failed:
            verdict = "counts and reported summaries agree under this schema"
        else:
            flags = sorted({str(flag) for r in failed for flag in str(r["audit_flags"]).split(";") if flag})
            verdict = "issues: " + ", ".join(flags)
        lines.append(f"`{filename}` | {schema} | {len(group)} | {verdict}")

    lines += [
        "",
        "## Principal findings",
        "",
        "1. The main Table 2 sources use the retained-microbe schema. Their F1 values",
        "   are retained-microbe F1. `host_carry_pct` is host reads divided by true",
        "   host input, not by retained output. Thus the apparent near-constant",
        "   Hostile/KneadData rates are input-relative rates and are not, by themselves,",
        "   evidence of a count bug.",
        "2. The RustyClean verification trade-off is real in the archived counts:",
        "   verification removes almost all residual host reads but increases microbial",
        "   FN counts on 60M/90%, 100M/50% and 100M/90%. It should be described as a",
        "   host-removal versus microbial-preservation trade-off, not as an accuracy",
        "   gain.",
        "3. Cross-species counts use the retained-microbe schema. The large panhuman-1",
        "   values are failed host removal (retained monkey/mouse/pig/rat/rice host",
        "   reads), not microbial loss. The archived `microbial_loss_pct` and",
        "   `host_carry_pct` columns are biologically correct, but the manuscript had",
        "   interpreted `host_carry_pct` as microbial loss.",
        "4. The 5--60M Hostile accuracy source is labelled `hostile_raw`, whereas the",
        "   manuscript arm is fastp + Hostile. Thus accuracy and runtime for those",
        "   cells come from different runs. The two 100M Hostile cells come from the",
        "   later fastp + Hostile fill run. The apparent drop in Hostile host",
        "   retention at 100M is therefore a provenance discontinuity, not evidence",
        "   that the count formulas are wrong.",
        "5. The archived backend S1 uses the removed-host schema. Its own",
        "   `Host_Remaining_Rate` and `Microbe_Loss_Rate` formulas are correct, but the",
        "   hardcoded manuscript table/figure mixed formulas and must be regenerated",
        "   from this source.",
        "6. `deacon_metrics.csv` has a malformed header: data rows begin with a tool",
        "   field that is absent from the header. Counts are auditable after adding the",
        "   missing header field, but the file must be fixed for machine readability.",
        "7. The prior revision incorrectly swapped comparator error columns in the",
        "   main summary CSV. That transformation must be reverted; the original",
        "   comparator labels and `fmh_accuracy.py` agree with their raw counts.",
        "",
        "## Counts that answer reviewer questions",
        "",
        "Dataset | Tool/schema | Input microbes | Input hosts | Microbial loss (%) | Host input retention (%) | Host output fraction (%)",
        "---|---|---:|---:|---:|---:|---:",
    ]
    wanted = [
        ("5M_1pct_low_even_SE", "hostile_raw"), ("5M_1pct_low_even_SE", "kneaddata"),
        ("10M_10pct_med_even_SE", "hostile_raw"), ("10M_10pct_med_even_SE", "kneaddata"),
        ("60M_90pct_high_lognormal_SE", "hostile_raw"), ("60M_90pct_high_lognormal_SE", "kneaddata"),
        ("60M_90pct_high_lognormal_SE", "deacon"), ("60M_90pct_high_lognormal_SE", "rustyclean"),
        ("100M_50pct_high_lognormal_SE", "hostile_fastp"), ("100M_50pct_high_lognormal_SE", "kneaddata"),
        ("100M_50pct_high_lognormal_SE", "rc_auto"), ("100M_90pct_high_lognormal_SE", "rustyclean"),
    ]
    seen = set()
    for row in rows:
        tool = str(row["tool_or_index"])
        dataset = str(row["dataset"])
        key = (dataset, tool)
        if key in seen or key not in wanted:
            continue
        seen.add(key)
        lines.append(
            f"{dataset} | {tool} | {row['input_microbe_reads']} | {row['input_host_reads']} | "
            f"{float(row['microbial_loss_pct_recomputed']):.6g} | "
            f"{float(row['host_input_retention_pct_recomputed']):.6g} | "
            f"{float(row['host_output_fraction_pct_recomputed']):.6g}"
        )

    lines += [
        "",
        "## Cross-species interpretation",
        "",
        "Index | Dataset | Input microbes | Input hosts | Microbial loss (%) | Host input retention (%)",
        "---|---|---:|---:|---:|---:",
    ]
    for row in rows:
        if "cross_species_metrics" not in str(row["source_file"]):
            continue
        lines.append(
            f"{row['tool_or_index']} | {row['dataset']} | {row['input_microbe_reads']} | "
            f"{row['input_host_reads']} | {float(row['microbial_loss_pct_recomputed']):.6g} | "
            f"{float(row['host_input_retention_pct_recomputed']):.6g}"
        )

    lines += [
        "",
        "## Remaining limits",
        "",
        "- The audit cannot detect read-ID collisions or duplicated ground-truth",
        "  labels without the original FASTQ/label files.",
        "- It cannot verify that the correct cleaned FASTQ was selected in historical",
        "  runs, although the archived generators show the intended selection rule.",
        "- The 100M KneadData and Hostile comparator file contains summary rates but",
        "  no TP/FP/FN/TN counts, so those two rows cannot be audited count-by-count.",
        "  They require regeneration from archived outputs or a rerun.",
        "- GNU-time max RSS does not establish aggregate process-tree memory. The",
        "  1.1 GiB KneadData value is therefore not sufficient evidence that its full",
        "  Bowtie2 workflow can run within 1.1 GiB.",
        "- Comparator timing and memory remain unaudited here because raw GNU-time",
        "  logs are not in the repository snapshot.",
        "",
    ]
    path.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    out = Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / "data/metric_audit")
    rows = all_rows()
    write_csv(rows, out / "raw_read_metric_audit.csv")
    write_report(rows, out / "RAW_READ_METRIC_AUDIT.md")
    failed = [row for row in rows if row["audit_flags"] != "PASS"]
    print(f"Audited {len(rows)} count rows; {len(failed)} flagged")
    for row in failed:
        print(f"{row['source_file']} | {row['tool_or_index']} | {row['dataset']} | {row['audit_flags']}")
    print(f"Wrote {out/'raw_read_metric_audit.csv'}")
    print(f"Wrote {out/'RAW_READ_METRIC_AUDIT.md'}")


if __name__ == "__main__":
    main()
