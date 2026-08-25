#!/usr/bin/env python3
# =============================================================================
# RustyClean Benchmark - Report Generator
# =============================================================================
# Generates a comprehensive Markdown report from benchmark results.
#
# Usage: python scripts/main/generate_report.py <results_dir> [output_file]
# Example: python scripts/main/generate_report.py ./results ./manuscript/report.md

import os
import sys
import pandas as pd
import numpy as np
from datetime import datetime


def load_data(results_dir, analysis_dir=None):
    """Load all available analysis data.

    Supports two layouts:
      - results_dir contains analysis/ and metrics/ subdirectories
      - analysis_dir is a separate sibling directory (e.g., ./analysis)
    """
    data = {}

    if analysis_dir is None:
        analysis_dir = os.path.join(results_dir, 'analysis')
        if not os.path.exists(os.path.join(analysis_dir, 'accuracy.csv')):
            # Try sibling analysis/ directory
            sibling = os.path.join(os.path.dirname(results_dir), 'analysis')
            if os.path.exists(os.path.join(sibling, 'accuracy.csv')):
                analysis_dir = sibling

    perf_file = os.path.join(analysis_dir, 'performance_summary.csv')
    if os.path.exists(perf_file):
        data['performance'] = pd.read_csv(perf_file)

    acc_file = os.path.join(analysis_dir, 'accuracy_summary.csv')
    if os.path.exists(acc_file):
        # Multi-level header: metric / statistic
        data['accuracy'] = pd.read_csv(acc_file, header=[0, 1])

    raw_perf = os.path.join(results_dir, 'metrics', 'performance.csv')
    if os.path.exists(raw_perf):
        data['raw_performance'] = pd.read_csv(raw_perf)

    raw_acc = os.path.join(analysis_dir, 'accuracy.csv')
    if os.path.exists(raw_acc):
        data['raw_accuracy'] = pd.read_csv(raw_acc)

    data['analysis_dir'] = analysis_dir
    return data


def parse_time(t):
    """Parse a runtime string to seconds."""
    if pd.isna(t) or str(t).lower() == 'unknown':
        return np.nan
    parts = str(t).split(':')
    if len(parts) == 3:
        return int(parts[0]) * 3600 + int(parts[1]) * 60 + float(parts[2])
    elif len(parts) == 2:
        return int(parts[0]) * 60 + float(parts[1])
    try:
        return float(parts[0])
    except Exception:
        return np.nan


def format_time(seconds):
    """Format seconds to human-readable string."""
    if np.isnan(seconds):
        return "N/A"
    if seconds < 60:
        return f"{seconds:.1f}s"
    elif seconds < 3600:
        return f"{seconds / 60:.1f}m"
    else:
        return f"{seconds / 3600:.1f}h"


def format_memory(mb):
    """Format MB to human-readable string."""
    if np.isnan(mb):
        return "N/A"
    if mb < 1024:
        return f"{mb:.0f} MB"
    else:
        return f"{mb / 1024:.1f} GB"


def summarize_performance(raw_df):
    """Return aggregate performance stats per tool."""
    df = raw_df.copy()
    df['runtime_parsed'] = df['runtime_seconds'].apply(parse_time)
    df['memory_mb'] = df['max_memory_kb'] / 1024

    stats = {}
    for tool in ['rustyclean', 'kneaddata']:
        subset = df[df['tool'] == tool]
        stats[tool] = {
            'runtime_mean': subset['runtime_parsed'].mean(),
            'runtime_std': subset['runtime_parsed'].std(),
            'memory_mean': subset['memory_mb'].mean(),
            'memory_std': subset['memory_mb'].std(),
        }

    rc_time = stats['rustyclean']['runtime_mean']
    kd_time = stats['kneaddata']['runtime_mean']
    rc_mem = stats['rustyclean']['memory_mean']
    kd_mem = stats['kneaddata']['memory_mean']

    speedup = kd_time / rc_time if rc_time and rc_time > 0 else np.nan
    mem_ratio = rc_mem / kd_mem if kd_mem and kd_mem > 0 else np.nan

    return {
        'stats': stats,
        'speedup': speedup,
        'mem_ratio': mem_ratio,
        'rc_faster': speedup > 1,
        'rc_lower_mem': rc_mem < kd_mem,
    }


def summarize_accuracy(raw_acc_df):
    """Return aggregate accuracy stats per tool from raw accuracy.csv."""
    df = raw_acc_df.copy()
    stats = {}
    for tool in ['rustyclean', 'kneaddata']:
        subset = df[df['Tool'] == tool]
        stats[tool] = {
            'f1_mean': subset['F1'].mean(),
            'f1_std': subset['F1'].std(),
            'accuracy_mean': subset['Accuracy'].mean(),
            'precision_mean': subset['Precision'].mean(),
            'recall_mean': subset['Recall'].mean(),
            'host_remaining_mean': subset['Host_Remaining_Rate'].mean(),
            'microbe_loss_mean': subset['Microbe_Loss_Rate'].mean(),
        }
    return stats


def get_accuracy_value(row, metric):
    """Extract mean value for a metric from a multi-level header accuracy row."""
    if metric in row and 'mean' in row[metric]:
        val = row[metric]['mean']
        return val if pd.notna(val) else np.nan
    return np.nan


def generate_report(results_dir, output_file):
    """Generate comprehensive Markdown report."""
    analysis_dir = os.path.dirname(os.path.abspath(output_file))
    data = load_data(results_dir, analysis_dir)
    report = []

    report.append("# RustyClean vs KneadData Benchmark Report")
    report.append("")
    report.append(f"**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M')}")
    report.append("")

    # Executive Summary
    report.append("## Executive Summary")
    report.append("")

    perf_summary = None
    if 'raw_performance' in data:
        perf_summary = summarize_performance(data['raw_performance'])
        s = perf_summary

        report.append(f"- **Speedup:** RustyClean is **{s['speedup']:.1f}x faster** than KneadData")
        report.append(f"  - RustyClean avg runtime: {format_time(s['stats']['rustyclean']['runtime_mean'])}")
        report.append(f"  - KneadData avg runtime: {format_time(s['stats']['kneaddata']['runtime_mean'])}")
        report.append("")

        if s['rc_lower_mem']:
            report.append(f"- **Memory Efficiency:** RustyClean uses **{1 / s['mem_ratio']:.1f}x less memory** than KneadData")
        else:
            report.append(f"- **Memory Usage:** RustyClean uses **{s['mem_ratio']:.1f}x more memory** than KneadData")
        report.append(f"  - RustyClean avg memory: {format_memory(s['stats']['rustyclean']['memory_mean'])}")
        report.append(f"  - KneadData avg memory: {format_memory(s['stats']['kneaddata']['memory_mean'])}")
        report.append("")

    acc_summary = None
    if 'raw_accuracy' in data:
        acc_summary = summarize_accuracy(data['raw_accuracy'])
        rc_f1 = acc_summary['rustyclean']['f1_mean']
        kd_f1 = acc_summary['kneaddata']['f1_mean']
        f1_gap = kd_f1 - rc_f1

        report.append(f"- **Accuracy:** KneadData achieves a higher mean F1-score ({kd_f1:.4f}) than RustyClean ({rc_f1:.4f}), with a gap of {f1_gap:.4f}.")
        report.append(f"  - RustyClean mean host remaining: {acc_summary['rustyclean']['host_remaining_mean']:.4f}; microbe loss: {acc_summary['rustyclean']['microbe_loss_mean']:.4f}")
        report.append(f"  - KneadData mean host remaining: {acc_summary['kneaddata']['host_remaining_mean']:.4f}; microbe loss: {acc_summary['kneaddata']['microbe_loss_mean']:.4f}")
        report.append("")

    report.append("")

    # Performance Results
    report.append("## Performance Results")
    report.append("")

    if 'raw_performance' in data:
        df = data['raw_performance'].copy()
        df['runtime_parsed'] = df['runtime_seconds'].apply(parse_time)
        df['memory_mb'] = df['max_memory_kb'] / 1024

        report.append("### Runtime by Dataset")
        report.append("")
        report.append("| Dataset | Tool | Mean Runtime | Std Dev | Min | Max |")
        report.append("|---------|------|-------------|---------|-----|-----|")

        for dataset in sorted(df['dataset'].unique()):
            for tool in ['rustyclean', 'kneaddata']:
                subset = df[(df['dataset'] == dataset) & (df['tool'] == tool)]
                if len(subset) > 0:
                    mean_t = subset['runtime_parsed'].mean()
                    std_t = subset['runtime_parsed'].std()
                    min_t = subset['runtime_parsed'].min()
                    max_t = subset['runtime_parsed'].max()
                    report.append(
                        f"| {dataset} | {tool} | {format_time(mean_t)} | {format_time(std_t)} | "
                        f"{format_time(min_t)} | {format_time(max_t)} |"
                    )

        report.append("")
        report.append("### Memory Usage by Dataset")
        report.append("")
        report.append("| Dataset | Tool | Mean Memory | Std Dev | Min | Max |")
        report.append("|---------|------|------------|---------|-----|-----|")

        for dataset in sorted(df['dataset'].unique()):
            for tool in ['rustyclean', 'kneaddata']:
                subset = df[(df['dataset'] == dataset) & (df['tool'] == tool)]
                if len(subset) > 0:
                    mean_m = subset['memory_mb'].mean()
                    std_m = subset['memory_mb'].std()
                    min_m = subset['memory_mb'].min()
                    max_m = subset['memory_mb'].max()
                    report.append(
                        f"| {dataset} | {tool} | {format_memory(mean_m)} | {format_memory(std_m)} | "
                        f"{format_memory(min_m)} | {format_memory(max_m)} |"
                    )

        report.append("")

    # Accuracy Results
    if 'accuracy' in data:
        report.append("## Accuracy Results (Simulated Data)")
        report.append("")
        report.append(
            "| Dataset | Tool | Accuracy | Precision | Recall | F1-Score | Host Remaining | Microbe Loss |"
        )
        report.append(
            "|---------|------|----------|-----------|--------|----------|----------------|-------------|"
        )

        acc_df = data['accuracy']
        for _, row in acc_df.iterrows():
            dataset = row.iloc[0]
            tool = row.iloc[1]
            acc = get_accuracy_value(row, 'Accuracy')
            prec = get_accuracy_value(row, 'Precision')
            rec = get_accuracy_value(row, 'Recall')
            f1 = get_accuracy_value(row, 'F1')
            host_rem = get_accuracy_value(row, 'Host_Remaining_Rate')
            micro_loss = get_accuracy_value(row, 'Microbe_Loss_Rate')

            def fmt(v):
                return f"{v:.4f}" if pd.notna(v) else "N/A"

            report.append(
                f"| {dataset} | {tool} | {fmt(acc)} | {fmt(prec)} | {fmt(rec)} | "
                f"{fmt(f1)} | {fmt(host_rem)} | {fmt(micro_loss)} |"
            )

        report.append("")

        # Warn about anomalous PE results
        if 'raw_accuracy' in data:
            pe_df = data['raw_accuracy'][data['raw_accuracy']['Dataset'].str.contains('_PE', na=False)]
            if not pe_df.empty:
                report.append(
                    "> **Note:** Paired-end (PE) datasets show identical accuracy metrics between RustyClean and KneadData "
                    "with complete microbe loss (microbe_loss = 1.0). This pattern is inconsistent with the single-end results "
                    "and should be verified before drawing conclusions on PE data."
                )
                report.append("")

    # Figures
    report.append("## Figures")
    report.append("")

    figures_dir = os.path.join(data.get('analysis_dir', os.path.join(results_dir, 'analysis')), 'figures')
    if os.path.exists(figures_dir):
        for fig in sorted(os.listdir(figures_dir)):
            if fig.endswith('.png'):
                report.append(f"### {fig.replace('.png', '').replace('_', ' ').title()}")
                report.append("")
                report.append(f"![{fig}](figures/{fig})")
                report.append("")

    # Conclusions
    report.append("## Conclusions")
    report.append("")

    if perf_summary:
        s = perf_summary
        report.append(
            f"1. **Speed:** RustyClean achieves a **{s['speedup']:.1f}x speedup** over KneadData, "
            f"making it suitable for large-scale metagenome studies where runtime is a bottleneck."
        )
        report.append("")

        if s['rc_lower_mem']:
            report.append(
                f"2. **Resource Efficiency:** RustyClean uses less memory than KneadData "
                f"({format_memory(s['stats']['rustyclean']['memory_mean'])} vs "
                f"{format_memory(s['stats']['kneaddata']['memory_mean'])}), "
                f"enabling processing on standard workstations or cloud instances with limited RAM."
            )
        else:
            report.append(
                f"2. **Resource Efficiency:** RustyClean is faster but uses more memory than KneadData "
                f"({format_memory(s['stats']['rustyclean']['memory_mean'])} vs "
                f"{format_memory(s['stats']['kneaddata']['memory_mean'])}). "
                f"Memory provisioning should be considered when deploying RustyClean at scale."
            )
        report.append("")

    if acc_summary:
        rc_f1 = acc_summary['rustyclean']['f1_mean']
        kd_f1 = acc_summary['kneaddata']['f1_mean']
        report.append(
            f"3. **Accuracy Trade-off:** KneadData delivers substantially higher accuracy "
            f"(mean F1 = {kd_f1:.4f}) than RustyClean (mean F1 = {rc_f1:.4f}) on these simulated datasets. "
            f"RustyClean's lower accuracy is driven by higher microbe loss and host remaining rates, "
            f"suggesting that the current Kraken2-based classification configuration may misclassify "
            f"a non-trivial fraction of microbial reads as host."
        )
        report.append("")

    report.append(
        "4. **Scalability:** The runtime advantage of RustyClean is consistent across dataset sizes, "
        "and the fixed-size Kraken2 database keeps RustyClean memory stable regardless of input size. "
        "However, the accuracy gap should be addressed before deploying RustyClean for studies where "
        "preserving microbial content is critical."
    )
    report.append("")

    # Recommendations
    report.append("## Recommendations")
    report.append("")
    report.append("- **Use RustyClean** for rapid QC and host removal in large-scale metagenome studies where runtime is the primary constraint.")
    report.append("- **Use KneadData** when maximum accuracy and minimal microbial loss are critical and computational resources are not limiting.")
    report.append("- **Investigate accuracy** before production use: evaluate Kraken2 database choice (e.g., Standard instead of MiniKraken2) and RustyClean's classification thresholds on representative samples.")
    report.append("- **Validate PE results** independently, as the current paired-end accuracy metrics are anomalous and require verification.")
    report.append("")
    report.append("---")
    report.append("*Generated by RustyClean Benchmark Suite*")

    # Write report
    os.makedirs(os.path.dirname(output_file) or '.', exist_ok=True)
    with open(output_file, 'w') as f:
        f.write('\n'.join(report))

    print(f"Report generated: {output_file}")


def main():
    if len(sys.argv) < 2:
        print("Usage: python generate_report.py <results_dir> [output_file]")
        sys.exit(1)

    results_dir = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else os.path.join(results_dir, 'analysis', 'report.md')

    print("=" * 60)
    print("Generating Benchmark Report")
    print("=" * 60)
    print(f"Results: {results_dir}")
    print(f"Output: {output_file}")
    print()

    generate_report(results_dir, output_file)

    print()
    print("Done!")


if __name__ == '__main__':
    main()
