#!/usr/bin/env python3
"""
Integrate all T2T-only benchmark results into summary tables and figures.
Run after all HPC jobs have completed.
"""

import sys
import re
import pandas as pd
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt


def parse_runtime_seconds(val):
    if isinstance(val, (int, float)):
        return float(val)
    if isinstance(val, str):
        if val.lower() in ('unknown', 'failed', ''):
            return None
        parts = val.split(':')
        if len(parts) == 3:
            return float(parts[0]) * 3600 + float(parts[1]) * 60 + float(parts[2])
        elif len(parts) == 2:
            return float(parts[0]) * 60 + float(parts[1])
        else:
            try:
                return float(parts[0])
            except ValueError:
                return None
    return None


def extract_host_pct(name):
    m = re.search(r'(\d+)pct', name)
    return int(m.group(1)) if m else None


def read_performance_csv(path):
    if not path.exists():
        return pd.DataFrame()
    df = pd.read_csv(path)
    if 'runtime_seconds' in df.columns:
        df['runtime_seconds'] = df['runtime_seconds'].apply(parse_runtime_seconds)
    if 'max_memory_kb' in df.columns:
        df['max_memory_gb'] = pd.to_numeric(df['max_memory_kb'], errors='coerce') / 1024 / 1024
    return df


def integrate_performance(base_dir):
    sources = [
        ('t2t_only_matched_panel', 'T2T matched panel'),
        ('t2t_only_extended_panel', 'T2T extended panel'),
        ('t2t_only_pe_panel', 'T2T PE panel'),
        ('backend_runtime_v2', 'Backend runtime'),
        ('cross_species_results', 'Cross-species'),
        ('real_data_results', 'Real data'),
    ]
    frames = []
    for subdir, label in sources:
        p = base_dir / subdir / 'metrics' / 'performance.csv'
        df = read_performance_csv(p)
        if not df.empty:
            df['source'] = label
            frames.append(df)

    # Add legacy mixed-host results for reference
    legacy = base_dir / 'results_v2' / 'metrics' / 'performance.csv'
    df = read_performance_csv(legacy)
    if not df.empty:
        df['source'] = 'Legacy mixed-host'
        df['tool'] = df['tool'].replace({'rustyclean': 'rustyclean_mixed_host'})
        frames.append(df)

    for tool in ['hostile', 'centrifuge', 'fast2brad']:
        p = base_dir / 'results_v2' / 'metrics' / f'performance_{tool}.csv'
        df = read_performance_csv(p)
        if not df.empty:
            df['source'] = 'Legacy mixed-host'
            frames.append(df)

    if not frames:
        return pd.DataFrame()
    return pd.concat(frames, ignore_index=True)


def integrate_accuracy(base_dir):
    sources = [
        ('t2t_only_matched_panel', 'T2T matched panel'),
        ('t2t_only_extended_panel', 'T2T extended panel'),
        ('t2t_only_pe_panel', 'T2T PE panel'),
    ]
    frames = []
    for subdir, label in sources:
        p = base_dir / subdir / 'analysis' / 'accuracy_t2t_only_panel.csv'
        if p.exists():
            df = pd.read_csv(p)
            df['source'] = label
            frames.append(df)

    # Cross-species accuracy (once computed)
    p = base_dir / 'cross_species_results' / 'analysis' / 'accuracy_cross_species.csv'
    if p.exists():
        df = pd.read_csv(p)
        df['source'] = 'Cross-species'
        frames.append(df)

    # Backend comparison accuracy
    p = base_dir / 'results_rc_mm_bt_cf_v4' / 'accuracy_rc_mm_bt_cf_v4.csv'
    if p.exists():
        df = pd.read_csv(p)
        df['source'] = 'Backend comparison'
        frames.append(df)

    if not frames:
        return pd.DataFrame()
    return pd.concat(frames, ignore_index=True)


def summarise_accuracy(acc_df):
    if acc_df.empty:
        return acc_df
    summary = acc_df.groupby(['dataset', 'tool']).agg({
        'f1': ['mean', 'std'],
        'precision': ['mean', 'std'],
        'recall': ['mean', 'std'],
    }).reset_index()
    summary.columns = ['dataset', 'tool', 'f1_mean', 'f1_std', 'precision_mean', 'precision_std', 'recall_mean', 'recall_std']
    return summary


def summarise_performance(perf_df):
    if perf_df.empty:
        return perf_df
    summary = perf_df.groupby(['dataset', 'tool']).agg({
        'runtime_seconds': ['mean', 'std'],
        'max_memory_gb': ['mean', 'std'],
    }).reset_index()
    summary.columns = ['dataset', 'tool', 'runtime_mean', 'runtime_std', 'memory_mean', 'memory_std']
    return summary


def plot_runtime_memory(perf_df, out_dir):
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    # Filter T2T matched panel SE data for the main comparison
    df = perf_df[perf_df['source'] == 'T2T matched panel'].copy()
    if df.empty:
        print("No T2T matched panel performance data yet.")
        return

    df['host_pct'] = df['dataset'].apply(extract_host_pct)
    df = df.dropna(subset=['host_pct', 'runtime_seconds'])

    fig, axes = plt.subplots(1, 2, figsize=(10, 4))
    colors = {'rustyclean_t2t_only': '#4A90A4', 'hostile': '#C75B5B', 'kneaddata': '#5B5BC7'}

    for tool, group in df.groupby('tool'):
        group = group.sort_values('host_pct')
        color = colors.get(tool, '#333333')
        axes[0].plot(group['host_pct'], group['runtime_seconds'] / 60, marker='o', label=tool, color=color)
        axes[1].plot(group['host_pct'], group['max_memory_gb'], marker='s', label=tool, color=color)

    axes[0].set_xlabel('Host fraction (%)')
    axes[0].set_ylabel('Runtime (min)')
    axes[0].set_title('T2T-only matched panel: runtime')
    axes[0].legend(frameon=False)
    axes[0].spines['top'].set_visible(False)
    axes[0].spines['right'].set_visible(False)

    axes[1].set_xlabel('Host fraction (%)')
    axes[1].set_ylabel('Peak memory (GB)')
    axes[1].set_title('T2T-only matched panel: memory')
    axes[1].legend(frameon=False)
    axes[1].spines['top'].set_visible(False)
    axes[1].spines['right'].set_visible(False)

    plt.tight_layout()
    plt.savefig(out_dir / 't2t_matched_runtime_memory.png', dpi=300)
    plt.savefig(out_dir / 't2t_matched_runtime_memory.svg')
    plt.close()
    print(f"Wrote {out_dir / 't2t_matched_runtime_memory.*'}")


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <base_dir> <output_dir>", file=sys.stderr)
        sys.exit(1)

    base_dir = Path(sys.argv[1])
    out_dir = Path(sys.argv[2])
    out_dir.mkdir(parents=True, exist_ok=True)

    perf = integrate_performance(base_dir)
    acc = integrate_accuracy(base_dir)

    if not perf.empty:
        perf.to_csv(out_dir / 'integrated_performance.csv', index=False)
        perf_summary = summarise_performance(perf)
        perf_summary.to_csv(out_dir / 'performance_summary.csv', index=False)
        plot_runtime_memory(perf, out_dir)

    if not acc.empty:
        acc.to_csv(out_dir / 'integrated_accuracy.csv', index=False)
        acc_summary = summarise_accuracy(acc)
        acc_summary.to_csv(out_dir / 'accuracy_summary.csv', index=False)

    print(f"Integration complete. Outputs in {out_dir}")


if __name__ == '__main__':
    main()
