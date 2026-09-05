#!/usr/bin/env python3
"""Turn the parallel-scaling measurements into a verdict.

Reads the per-task CSVs written by benchmark_parallel_scaling.sh and answers the
question the experiment exists for: does RustyClean turn extra cores into extra
throughput better than KneadData and Hostile do?

Three comparisons come out of the same table, and they are not the same claim:

  rustyclean_batch        vs kneaddata   both trim reads first
  rustyclean_batch_skipqc vs hostile     neither trims
  rustyclean_batch        vs rustyclean_xargs

The third is the one that isolates scheduling. The first two mix the scheduler
with how fast each tool's alignment step is, so a win there does not by itself
show that the worker pool is doing anything a shell loop could not.

Speed-up is always computed against the SAME arm at W=1, never against another
tool, so a slow arm cannot look like a well-scaling one.

Usage:
    analyze_parallel_scaling.py [--runs DIR] [--out DIR]
"""

import argparse
import csv
import glob
import os
import sys
from collections import defaultdict

# Pairs whose comparison is meaningful, and what each one is actually testing.
COMPARISONS = [
    ("rustyclean_batch", "kneaddata",
     "with read trimming — RustyClean's pool vs one KneadData process per sample"),
    ("rustyclean_batch_skipqc", "hostile",
     "without read trimming — RustyClean's pool vs one Hostile process per sample"),
    ("rustyclean_batch", "rustyclean_xargs",
     "same tool, same work: RustyClean's pool vs the same binary under xargs"),
]

NUMERIC = ("wall_seconds", "user_seconds", "sys_seconds", "cpu_efficiency",
           "samples_per_hour", "peak_rss_kb", "peak_anon_kb", "peak_cgroup_kb",
           "baseline_anon_kb")


def load(runs_dir):
    """Every measured row, keyed by (arm, workers). Later files win."""
    rows = {}
    paths = sorted(glob.glob(os.path.join(runs_dir, "metrics", "parallel_scaling*.csv")))
    if not paths:
        sys.exit(f"no metrics under {runs_dir}/metrics — has the benchmark run?")
    for path in paths:
        with open(path, newline="") as fh:
            for row in csv.DictReader(fh):
                if not row.get("arm"):
                    continue
                # A skipped or failed arm carries no timing; keep it so the
                # summary can say the arm is absent rather than omit it.
                try:
                    w = int(row["workers"])
                except (TypeError, ValueError):
                    continue
                for k in NUMERIC:
                    try:
                        row[k] = float(row[k])
                    except (TypeError, ValueError, KeyError):
                        row[k] = None
                row["n_failed"] = int(row["n_failed"]) if str(row.get("n_failed", "")).isdigit() else 0
                rows[(row["arm"], w)] = row
    return rows


def summarise(rows, out_dir):
    arms = sorted({a for a, _ in rows})
    widths = sorted({w for _, w in rows})

    out = []
    for arm in arms:
        base = rows.get((arm, 1), {}).get("wall_seconds")
        for w in widths:
            r = rows.get((arm, w))
            if not r:
                continue
            wall = r["wall_seconds"]
            speedup = (base / wall) if (base and wall) else None
            out.append({
                "arm": arm,
                "workers": w,
                "threads": r.get("threads", ""),
                "cpus": r.get("cpus", ""),
                "n_samples": r.get("n_samples", ""),
                "n_failed": r["n_failed"],
                "wall_seconds": f"{wall:.1f}" if wall else "",
                "samples_per_hour": f"{r['samples_per_hour']:.1f}" if r["samples_per_hour"] else "",
                "speedup_vs_w1": f"{speedup:.3f}" if speedup else "",
                "parallel_efficiency": f"{speedup / w:.3f}" if speedup else "",
                "cpu_efficiency": f"{r['cpu_efficiency']:.3f}" if r["cpu_efficiency"] else "",
                "peak_anon_gb": f"{r['peak_anon_kb'] / 1048576:.2f}" if r["peak_anon_kb"] else "",
                "peak_anon_gb_per_worker": (f"{r['peak_anon_kb'] / 1048576 / w:.2f}"
                                            if r["peak_anon_kb"] else ""),
                "peak_cgroup_gb": f"{r['peak_cgroup_kb'] / 1048576:.2f}" if r["peak_cgroup_kb"] else "",
                "node": r.get("node", ""),
            })

    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "parallel_scaling_summary.csv")
    with open(path, "w", newline="") as fh:
        wtr = csv.DictWriter(fh, fieldnames=list(out[0].keys()))
        wtr.writeheader()
        wtr.writerows(out)
    return out, arms, widths, path


def render(out, arms, widths, rows):
    lines = []
    add = lines.append

    add("=" * 96)
    add("PARALLEL SCALING — batch wall time for the whole panel at each worker count")
    add("=" * 96)
    add("")
    add(f"{'arm':<26}{'W':>3} {'T':>3} {'wall':>9} {'samp/h':>9} "
        f"{'speedup':>8} {'par.eff':>8} {'cpu.eff':>8} {'anon GB':>9} {'fail':>5}")
    add("-" * 96)
    for arm in arms:
        for r in [x for x in out if x["arm"] == arm]:
            add(f"{arm:<26}{r['workers']:>3} {str(r['threads']):>3} "
                f"{r['wall_seconds']:>9} {r['samples_per_hour']:>9} "
                f"{r['speedup_vs_w1']:>8} {r['parallel_efficiency']:>8} "
                f"{r['cpu_efficiency']:>8} {r['peak_anon_gb']:>9} {r['n_failed']:>5}")
        add("")

    add("Parallel efficiency is speed-up divided by the worker count: 1.00 means the")
    add("Nth worker was worth as much as the first, and 0.50 means half of it was lost")
    add("to contention. CPU efficiency is (user+sys)/(wall x cores) measured over the")
    add("whole process tree -- it says whether the cores were busy at all, and separates")
    add("'the tool cannot fill them' from 'the tool filled them with wasted work'.")
    add("")

    add("=" * 96)
    add("HEAD TO HEAD — ratio of batch wall time, >1 means the first arm finished sooner")
    add("=" * 96)
    for a, b, why in COMPARISONS:
        add("")
        add(f"{a}  vs  {b}")
        add(f"    {why}")
        any_row = False
        for w in widths:
            ra, rb = rows.get((a, w)), rows.get((b, w))
            if not ra or not rb or not ra["wall_seconds"] or not rb["wall_seconds"]:
                continue
            any_row = True
            ratio = rb["wall_seconds"] / ra["wall_seconds"]
            ma = ra["peak_anon_kb"] / 1048576 if ra["peak_anon_kb"] else 0
            mb = rb["peak_anon_kb"] / 1048576 if rb["peak_anon_kb"] else 0
            verdict = "faster" if ratio > 1.02 else ("slower" if ratio < 0.98 else "tied")
            add(f"      W={w:<3} {ratio:5.2f}x  ({verdict:>6})   "
                f"{ra['wall_seconds']:8.0f}s vs {rb['wall_seconds']:8.0f}s   "
                f"peak anon {ma:5.1f} vs {mb:5.1f} GB")
        if not any_row:
            add("      no worker count has both arms measured")
    add("")
    return "\n".join(lines)


def check_fingerprints(runs_dir):
    """Did running more workers change the output?

    The retained-read count per sample is recorded after every arm at every
    worker count. For a deterministic tool it must not move when the worker
    count does. This is the only place a concurrency bug would show: batch wall
    time would look perfectly healthy while the reads coming out differed.
    """
    per_arm = defaultdict(dict)   # arm -> W -> {sample: (count, digest)}
    for path in sorted(glob.glob(os.path.join(runs_dir, "metrics", "fingerprint_W*_*.tsv"))):
        base = os.path.basename(path)[len("fingerprint_W"):-len(".tsv")]
        w_str, _, arm = base.partition("_")
        try:
            w = int(w_str)
        except ValueError:
            continue
        with open(path, newline="") as fh:
            rd = csv.DictReader(fh, delimiter="\t")
            per_arm[arm][w] = {r["sample_id"]: (r["retained_reads"], r.get("id_digest", ""))
                               for r in rd}

    lines = ["=" * 96,
             "OUTPUT INVARIANCE — does the answer change when the worker count does?",
             "=" * 96, ""]
    if not per_arm:
        lines.append("no fingerprint files found; nothing to check")
        return "\n".join(lines), True

    ok = True
    for arm in sorted(per_arm):
        widths = sorted(per_arm[arm])
        ref_w = widths[0]
        ref = per_arm[arm][ref_w]
        missing = sum(1 for v in ref.values() if v[0] == "MISSING")
        notes = []
        for w in widths[1:]:
            cur = per_arm[arm][w]
            diff = [s for s in ref if s in cur and cur[s][0] != ref[s][0]]
            only = set(ref) ^ set(cur)
            if diff:
                notes.append(f"W={w}: {len(diff)} sample(s) retained a different number "
                             f"of reads than at W={ref_w} (e.g. {diff[0]})")
            if only:
                notes.append(f"W={w}: {len(only)} sample(s) present at one W and not the other")
        status = "OK" if not notes else "MISMATCH"
        if notes:
            ok = False
        lines.append(f"  {arm:<26} W={','.join(map(str, widths)):<14} {status}"
                     + (f"   ({missing} sample(s) produced no output)" if missing else ""))
        for n in notes:
            lines.append(f"      {n}")

    # The two RustyClean arms run the same binary over the same reads; only who
    # schedules them differs. Their output must be identical read for read.
    for w in sorted(set(per_arm.get("rustyclean_batch", {})) & set(per_arm.get("rustyclean_xargs", {}))):
        a, b = per_arm["rustyclean_batch"][w], per_arm["rustyclean_xargs"][w]
        diff = [s for s in a if s in b and a[s][0] != b[s][0]]
        if diff:
            ok = False
            lines.append(f"  W={w}: rustyclean_batch and rustyclean_xargs disagree on "
                         f"{len(diff)} sample(s) — the worker pool is not producing the "
                         f"same output as one process per sample (e.g. {diff[0]})")

    lines.append("")
    lines.append("A MISMATCH here outranks every timing number in this report: it would mean"
                 "\nthe faster configuration is not doing the same job.")
    if not ok:
        lines.append("")
        lines.append("Set PARALLEL_DIGEST=1 and rerun to compare the read-id sets themselves,"
                     "\nwhich localises whether reads were lost or merely counted differently.")
    return "\n".join(lines), ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", default=os.environ.get("PARALLEL_RUNS_DIR"),
                    help="the benchmark's run directory (default: $PARALLEL_RUNS_DIR)")
    ap.add_argument("--out", default=None, help="where to write the summary")
    args = ap.parse_args()

    runs = args.runs
    if not runs:
        runs_root = os.environ.get("RUNS_DIR")
        runs = os.path.join(runs_root, "parallel_scaling") if runs_root else None
    if not runs or not os.path.isdir(runs):
        sys.exit("set PARALLEL_RUNS_DIR (source scripts/hpc/config.sh) or pass --runs")
    out_dir = args.out or os.path.join(runs, "summary")

    rows = load(runs)
    out, arms, widths, csv_path = summarise(rows, out_dir)
    text = render(out, arms, widths, rows)
    fp_text, fp_ok = check_fingerprints(runs)

    report = text + "\n" + fp_text + "\n"
    print(report)
    txt_path = os.path.join(out_dir, "parallel_scaling_summary.txt")
    with open(txt_path, "w") as fh:
        fh.write(report)
    print(f"\n  table  -> {csv_path}")
    print(f"  report -> {txt_path}")
    return 0 if fp_ok else 2


if __name__ == "__main__":
    sys.exit(main())
