#!/usr/bin/env python3
"""Compare the two arms of the Kraken2 index ablation.

    arm A  kraken16  -- mixed database (bacteria/archaea/viral/human)
    arm B  t2t_only  -- human-only database, T2T-CHM13v2.0

Everything else is held identical, so any difference is attributable to the
index. Reports host carry-over, microbial loss, F1, runtime and peak memory.

Usage:
    python compare_k2_index_ablation.py [arm_b_dir]

`arm_b_dir` defaults to the ablation project directory on the cluster; pass a
local path to run against downloaded metrics.
"""
import csv
import statistics as st
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def arm_a(name):
    """Arm A from the current run if it exists, otherwise from the v1 archive."""
    fresh = REPO / "data/benchmark_results" / name
    if fresh.exists():
        return fresh
    archived = REPO / "archive/v1/data/benchmark_results" / name
    if archived.exists():
        print(f"note: arm A taken from the v1 archive ({archived.relative_to(REPO)}); "
              f"rerun stage 4 to compare against fresh results", file=sys.stderr)
        return archived
    return fresh


ARM_A_ACC = arm_a("accuracy_bowtie2_recheck.csv")
ARM_A_PERF = arm_a("performance_bowtie2_recheck.csv")
ARM_B_DIR = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
    "/lustre1/g/aos_shihuang/rustyclean-paper/k2_index_ablation/metrics")

DATASETS = [
    "30M_50pct_high_skewed_SE",
    "60M_90pct_high_lognormal_SE",
    "100M_50pct_high_lognormal_SE",
    "100M_90pct_high_lognormal_SE",
]
SHORT = {d: d.split("_")[0] + " / " + d.split("_")[1] for d in DATASETS}


def rd(path):
    if not Path(path).exists():
        print(f"MISSING: {path}", file=sys.stderr)
        return []
    with open(path) as fh:
        return list(csv.DictReader(fh))


def rates(row):
    """Positive class is a retained microbial read."""
    tp, fp, tn, fn = (int(float(row[k])) for k in ("tp", "fp", "tn", "fn"))
    host_carry = fp / (fp + tn) * 100 if fp + tn else 0.0
    micro_loss = fn / (tp + fn) * 100 if tp + fn else 0.0
    return float(row["f1"]), micro_loss, host_carry


def first(rows, dataset):
    for r in rows:
        if r["dataset"] == dataset:
            return r
    return None


def mean_perf(rows, dataset, col):
    v = [float(r[col]) for r in rows if r["dataset"] == dataset and r.get(col)]
    return st.mean(v) if v else 0.0


def main():
    a_acc, b_acc = rd(ARM_A_ACC), rd(ARM_B_DIR / "accuracy_k2_t2t_only.csv")
    a_perf, b_perf = rd(ARM_A_PERF), rd(ARM_B_DIR / "performance_k2_t2t_only.csv")
    if not b_acc:
        print("\nArm B not found. Run benchmark_k2_index_ablation.sh and "
              "run_accuracy_k2_index_ablation.sh first.", file=sys.stderr)
        sys.exit(1)

    hdr = (f"{'dataset':<14}{'host carry-over %':>26}{'microbial loss %':>24}"
           f"{'F1':>20}{'runtime min':>18}{'peak GB':>16}")
    print("\nKraken2 index ablation — mixed (kraken16) vs human-only (t2t_only)")
    print("=" * len(hdr))
    print(hdr)
    print(f"{'':<14}{'mixed':>12}{'human':>7}{'Δ':>7}"
          f"{'mixed':>12}{'human':>6}{'Δ':>6}"
          f"{'mixed':>10}{'human':>10}{'mixed':>9}{'human':>9}{'mixed':>8}{'human':>8}")
    print("-" * len(hdr))

    deltas = []
    for d in DATASETS:
        ra, rb = first(a_acc, d), first(b_acc, d)
        if not ra or not rb:
            print(f"{SHORT[d]:<14}  (missing)")
            continue
        f1a, mla, hca = rates(ra)
        f1b, mlb, hcb = rates(rb)
        deltas.append((hca, hcb, mla, mlb))
        ta = mean_perf(a_perf, d, "runtime_seconds") / 60
        tb = mean_perf(b_perf, d, "runtime_seconds") / 60
        ma = mean_perf(a_perf, d, "max_memory_kb") / 1048576
        mb = mean_perf(b_perf, d, "max_memory_kb") / 1048576
        print(f"{SHORT[d]:<14}{hca:>12.3f}{hcb:>7.3f}{hcb-hca:>+7.3f}"
              f"{mla:>12.3f}{mlb:>6.3f}{mlb-mla:>+6.3f}"
              f"{f1a:>10.4f}{f1b:>10.4f}{ta:>9.1f}{tb:>9.1f}{ma:>8.1f}{mb:>8.1f}")

    if deltas:
        hca = st.mean(x[0] for x in deltas); hcb = st.mean(x[1] for x in deltas)
        mla = st.mean(x[2] for x in deltas); mlb = st.mean(x[3] for x in deltas)
        print("-" * len(hdr))
        print(f"{'MEAN':<14}{hca:>12.3f}{hcb:>7.3f}{hcb-hca:>+7.3f}"
              f"{mla:>12.3f}{mlb:>6.3f}{mlb-mla:>+6.3f}")
        print(f"\nHost carry-over {hca:.3f}% -> {hcb:.3f}% "
              f"({hca/hcb:.1f}x lower)" if hcb else "")
        print("\nInterpretation:")
        print("  A large drop means the 1.41% carry-over measured with kraken16 was")
        print("  largely an index artefact: Kraken2 assigned host reads to ancestors")
        print("  of Homo sapiens that an exact taxid match did not remove.")
        print("  A small drop means it is a genuine property of k-mer classification,")
        print("  which supports the false-negative argument in the manuscript.")


if __name__ == "__main__":
    main()
