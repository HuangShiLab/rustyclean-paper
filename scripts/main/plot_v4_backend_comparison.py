#!/usr/bin/env python3
# =============================================================================
# RustyClean v4 backend comparison figures
# =============================================================================
# Generates publication-style runtime and accuracy comparison plots for the
# minimap2 / bowtie2 / centrifuge backend benchmark (results_rc_mm_bt_cf_v4).
#
# Usage: python scripts/plot_v4_backend_comparison.py <results_dir> <out_dir>
# Example: python scripts/plot_v4_backend_comparison.py \
#              $SCRATCH_DIR/results_rc_mm_bt_cf_v4 \
#              /lustre1/g/aos_shihuang/rustyclean-paper/analysis_final_v3/figures

import os
import sys
import pandas as pd
import numpy as np
import matplotlib as mpl
mpl.use('Agg')
import matplotlib.pyplot as plt

mpl.rcParams.update({
    "font.family": "sans-serif",
    "font.sans-serif": ["Arial", "Helvetica", "DejaVu Sans", "sans-serif"],
    "font.size": 7,
    "axes.labelsize": 8,
    "axes.titlesize": 9,
    "xtick.labelsize": 7,
    "ytick.labelsize": 7,
    "legend.fontsize": 7,
    "axes.spines.right": False,
    "axes.spines.top": False,
    "axes.linewidth": 0.8,
    "xtick.major.width": 0.8,
    "ytick.major.width": 0.8,
    "xtick.major.size": 3,
    "ytick.major.size": 3,
    "legend.frameon": False,
    "figure.dpi": 300,
    "svg.fonttype": "none",
    "pdf.fonttype": 42,
})

COLORS = {
    'rc_minimap2': '#7EB5A6',   # teal
    'rc_bowtie2': '#4A90A4',    # steel blue
    'rc_centrifuge': '#C75B5B', # muted red
}

LABELS = {
    'rc_minimap2': 'RustyClean-minimap2',
    'rc_bowtie2': 'RustyClean-bowtie2',
    'rc_centrifuge': 'RustyClean-centrifuge',
}


def parse_hms(s):
    """Convert GNU time 'H:MM:SS' or 'M:SS' string to seconds."""
    if pd.isna(s) or s in ('', 'unknown'):
        return np.nan
    parts = str(s).strip().split(':')
    if len(parts) == 3:
        return int(parts[0]) * 3600 + int(parts[1]) * 60 + float(parts[2])
    elif len(parts) == 2:
        return int(parts[0]) * 60 + float(parts[1])
    else:
        try:
            return float(parts[0])
        except ValueError:
            return np.nan


def load_performance(results_dir):
    csv = os.path.join(results_dir, 'performance_rc_mm_bt_cf_v4_corrected.csv')
    if not os.path.exists(csv):
        csv = os.path.join(results_dir, 'performance_rc_mm_bt_cf_v4.csv')
    df = pd.read_csv(csv)
    if 'runtime_seconds' in df.columns:
        df['runtime_s'] = df['runtime_seconds'].apply(
            lambda x: parse_hms(x) if isinstance(x, str) and ':' in x else float(x)
        )
    else:
        df['runtime_s'] = np.nan
    df['runtime_min'] = df['runtime_s'] / 60.0
    df['memory_gb'] = df['max_memory_kb'] / 1024.0 / 1024.0
    return df


def load_accuracy(results_dir):
    csv = os.path.join(results_dir, 'accuracy_rc_mm_bt_cf_v4.csv')
    if not os.path.exists(csv):
        return None
    return pd.read_csv(csv)


def order_datasets(df):
    order = ['5M_1pct_low_even_SE', '10M_10pct_med_even_SE',
             '30M_50pct_high_skewed_SE', '60M_90pct_high_lognormal_SE']
    df = df.copy()
    df['dataset'] = pd.Categorical(df['dataset'], categories=order, ordered=True)
    return df.sort_values('dataset')


def plot_runtime_memory(perf, out_dir):
    perf = order_datasets(perf)
    fig, axes = plt.subplots(1, 2, figsize=(6.5, 2.4))

    ax1 = axes[0]
    x = np.arange(4)
    width = 0.25
    for i, tool in enumerate(['rc_minimap2', 'rc_bowtie2', 'rc_centrifuge']):
        sub = perf[perf['tool'] == tool]
        ax1.bar(x + (i - 1) * width, sub['runtime_min'], width,
                label=LABELS[tool], color=COLORS[tool])
    ax1.set_ylabel('Runtime (min)')
    ax1.set_title('(a) Runtime')
    ax1.set_xticks(x)
    ax1.set_xticklabels([d.replace('_', '\n') for d in perf['dataset'].cat.categories])
    ax1.legend(frameon=False)

    ax2 = axes[1]
    for i, tool in enumerate(['rc_minimap2', 'rc_bowtie2', 'rc_centrifuge']):
        sub = perf[perf['tool'] == tool]
        ax2.bar(x + (i - 1) * width, sub['memory_gb'], width,
                label=LABELS[tool], color=COLORS[tool])
    ax2.set_ylabel('Peak memory (GB)')
    ax2.set_title('(b) Peak memory')
    ax2.set_xticks(x)
    ax2.set_xticklabels([d.replace('_', '\n') for d in perf['dataset'].cat.categories])

    plt.tight_layout()
    for ext in ['png', 'svg', 'pdf']:
        out = os.path.join(out_dir, f'figure_v4_runtime_memory.{ext}')
        fig.savefig(out, dpi=300, bbox_inches='tight')
        print(f'Saved {out}')
    plt.close(fig)


def plot_accuracy(acc, out_dir):
    acc = order_datasets(acc)
    fig, axes = plt.subplots(1, 2, figsize=(6.5, 2.4))

    ax1 = axes[0]
    x = np.arange(4)
    width = 0.25
    for i, tool in enumerate(['rc_minimap2', 'rc_bowtie2', 'rc_centrifuge']):
        sub = acc[acc['tool'] == tool]
        ax1.bar(x + (i - 1) * width, sub['F1'], width,
                label=LABELS[tool], color=COLORS[tool])
    ax1.set_ylabel('F1 score')
    ax1.set_ylim([0.94, 1.001])
    ax1.set_title('(a) Host-removal F1')
    ax1.set_xticks(x)
    ax1.set_xticklabels([d.replace('_', '\n') for d in acc['dataset'].cat.categories])
    ax1.legend(frameon=False)

    ax2 = axes[1]
    for i, tool in enumerate(['rc_minimap2', 'rc_bowtie2', 'rc_centrifuge']):
        sub = acc[acc['tool'] == tool]
        ax2.bar(x + (i - 1) * width, sub['Microbe_Loss_Rate'] * 100, width,
                label=LABELS[tool], color=COLORS[tool])
    ax2.set_ylabel('Microbe loss (%)')
    ax2.set_title('(b) Microbial read loss')
    ax2.set_xticks(x)
    ax2.set_xticklabels([d.replace('_', '\n') for d in acc['dataset'].cat.categories])

    plt.tight_layout()
    for ext in ['png', 'svg', 'pdf']:
        out = os.path.join(out_dir, f'figure_v4_accuracy.{ext}')
        fig.savefig(out, dpi=300, bbox_inches='tight')
        print(f'Saved {out}')
    plt.close(fig)


def main():
    if len(sys.argv) < 3:
        print('Usage: python plot_v4_backend_comparison.py <results_dir> <out_dir>')
        sys.exit(1)
    results_dir = sys.argv[1]
    out_dir = sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)

    perf = load_performance(results_dir)
    plot_runtime_memory(perf, out_dir)

    acc = load_accuracy(results_dir)
    if acc is not None:
        plot_accuracy(acc, out_dir)
    else:
        print('Accuracy CSV not found; skipping accuracy figure.')


if __name__ == '__main__':
    main()
