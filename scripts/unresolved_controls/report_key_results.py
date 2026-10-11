#!/usr/bin/env python3
"""Create concise reviewer-facing tables from unresolved-control summaries."""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

import numpy as np
import pandas as pd


def sample_sd(x):
    return float(np.std(x, ddof=1)) if len(x) > 1 else float("nan")


def tool_accuracy_table(acc: pd.DataFrame, source: str, tools=None):
    rows = []
    q = acc[acc["source"] == source]
    for tool, g in q.groupby("tool"):
        if tools and tool not in tools:
            continue
        rows.append({
            "tool": tool,
            "runs": len(g),
            "f1_mean": float(g["f1"].mean()),
            "f1_sd": sample_sd(g["f1"]),
            "host_retention_pct_mean": float(g["host_input_retention_pct"].mean()),
            "host_retention_pct_sd": sample_sd(g["host_input_retention_pct"]),
            "microbial_loss_pct_mean": float(g["microbial_loss_pct"].mean()),
            "microbial_loss_pct_sd": sample_sd(g["microbial_loss_pct"]),
        })
    return rows


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--controls-root", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    summary = args.controls_root / "summary"
    acc = pd.read_csv(summary / "combined_accuracy.csv")
    perf = pd.read_csv(summary / "combined_performance.csv")

    # Recheck controls: legacy no-recheck; fresh always; threshold default.
    controls = []
    conditions = [
        ("norecheck", "no_recheck", "legacy_norecheck"),
        ("threshold", "conditional_default_0.30", "threshold_0.30"),
        ("always", "always_recheck_0.00", "threshold_0.00"),
    ]
    for source, label, condition in conditions:
        g = acc[(acc.source == source) & (acc.condition == condition)]
        p = perf[(perf.source == source) & (perf.condition == condition)]
        controls.append({
            "condition": label,
            "datasets": int(g.dataset.nunique()),
            "runs": len(g),
            "f1_mean": float(g.f1.mean()),
            "host_input_retention_pct_mean": float(g.host_input_retention_pct.mean()),
            "microbial_loss_pct_mean": float(g.microbial_loss_pct.mean()),
            "runtime_s_mean": float(p.runtime_s.mean()),
            "runtime_s_median": float(p.runtime_s.median()),
        })

    # Threshold sweep: one deterministic scoring replicate per dataset/threshold.
    t = acc[(acc.source == "threshold") & (acc.tool == "rustyclean_auto")].copy()
    t["threshold"] = t["condition"].str.extract(r"threshold_([0-9.]+)")[0].astype(float)
    p = perf[(perf.source == "threshold") & (perf.tool == "rustyclean_auto")].copy()
    p["threshold"] = p["condition"].str.extract(r"threshold_([0-9.]+)")[0].astype(float)
    def recheck_flag(raw):
        match = re.search(r'bowtie2_recheck_ms\\*"\s*:\s*([0-9.eE+-]+)', raw)
        return bool(match and float(match.group(1)) > 0)
    p["recheck_fired"] = p["extra"].map(recheck_flag)
    sweep = []
    for threshold in sorted(t.threshold.unique()):
        ga = t[t.threshold == threshold]
        gp = p[p.threshold == threshold]
        sweep.append({
            "threshold": float(threshold),
            "datasets": int(ga.dataset.nunique()),
            "f1_mean": float(ga.f1.mean()),
            "host_input_retention_pct_mean": float(ga.host_input_retention_pct.mean()),
            "microbial_loss_pct_mean": float(ga.microbial_loss_pct.mean()),
            "runtime_s_median": float(gp.runtime_s.median()) if len(gp) else np.nan,
            "recheck_rate": float(gp.recheck_fired.mean()) if gp.recheck_fired.notna().any() else np.nan,
        })

    cleanifier = tool_accuracy_table(acc, "cleanifier")
    mock = tool_accuracy_table(acc, "mock")

    # Equal-thread accuracy is valid independent of timing; timing is emitted separately.
    equal_accuracy = tool_accuracy_table(acc, "equal_thread")

    # Runtime summaries for completed panels other than the rerunning equal panel.
    runtime_panels = {}
    for source in ["threshold", "always", "cleanifier", "mock", "norecheck"]:
        q = perf[perf.source == source]
        runtime_panels[source] = [
            {
                "tool": tool, "condition": condition, "runs": len(g),
                "runtime_s_mean": float(g.runtime_s.mean()),
                "runtime_s_sd": sample_sd(g.runtime_s),
                "max_memory_kb_mean": float(g.max_memory_kb.mean()),
            }
            for (tool, condition), g in q.groupby(["tool", "condition"])
        ]

    result = {
        "recheck_controls": controls,
        "threshold_sweep": sweep,
        "cleanifier_accuracy": cleanifier,
        "mock_ground_truth_accuracy": mock,
        "equal_thread_accuracy": equal_accuracy,
        "runtime_panels": runtime_panels,
    }
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "key_results.json").write_text(json.dumps(result, indent=2) + "\n")
    with (args.output_dir / "threshold_sweep_compact.csv").open("w") as handle:
        handle.write("threshold,f1_mean,host_retention_pct,microbial_loss_pct,runtime_s_median,recheck_rate\n")
        for r in sweep:
            handle.write(",".join(str(r[k]) for k in ["threshold","f1_mean","host_input_retention_pct_mean","microbial_loss_pct_mean","runtime_s_median","recheck_rate"]) + "\n")
    # Per-dataset source tables used by the revised manuscript.
    per_dir = args.output_dir / "per_dataset"
    per_dir.mkdir(parents=True, exist_ok=True)
    comparator = acc[
        ((acc.source == "threshold") & (acc.condition == "threshold_0.30") & (acc.tool == "rustyclean_auto")) |
        ((acc.source == "cleanifier") & (acc.condition == "threshold_0.5") & (acc.tool == "cleanifier")) |
        ((acc.source == "equal_thread") & (acc.condition == "fastp_plus_hostile") & (acc.tool == "fastp_hostile"))
    ].copy()
    comparator.to_csv(per_dir / "accuracy_comparators.csv", index=False)
    runtime_rows = [
        ((perf.source == "threshold") & (perf.condition == "threshold_0.30") & (perf.tool == "rustyclean_auto")),
        ((perf.source == "cleanifier") & (perf.condition == "threshold_0.5") & (perf.tool == "cleanifier")),
    ]
    perf[runtime_rows[0] | runtime_rows[1]].to_csv(per_dir / "runtime_rustyclean_default_cleanifier.csv", index=False)
    acc[(acc.source == "mock")].to_csv(per_dir / "mock_accuracy.csv", index=False)
    acc[
        ((acc.source == "norecheck") & (acc.condition == "legacy_norecheck")) |
        ((acc.source == "always") & (acc.condition == "threshold_0.00")) |
        ((acc.source == "threshold") & (acc.condition == "threshold_0.30"))
    ].to_csv(per_dir / "recheck_controls_accuracy.csv", index=False)

    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
