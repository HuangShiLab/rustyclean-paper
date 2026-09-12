#!/usr/bin/env python3
"""Publication-quality figures for the deacon-based default backend (RustyClean).

Reads the authoritative summary tables under data/deacon_panel/ and exports:
  - fig2_deacon_panel.{png,svg,pdf}    five-way runtime + memory per dataset
  - fig3_deacon_accuracy.{png,svg,pdf} F1 and host carry-over per dataset/tool
  - fig5_cross_species.{png,svg,pdf}   species-matched vs panhuman-1 index F1
  - fig6_verification.{png,svg,pdf}    verification tier: deacon vs AUTO carry

Usage: python3 scripts/main/plot_deacon_figures.py [data_dir] [out_dir]
"""
import os
import sys

import numpy as np
import pandas as pd
import matplotlib as mpl

mpl.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Patch

mpl.rcParams.update({
    "font.family": "sans-serif",
    "font.sans-serif": ["Arial", "Helvetica", "DejaVu Sans", "sans-serif"],
    "font.size": 10,
    "axes.labelsize": 11,
    "axes.titlesize": 12,
    "xtick.labelsize": 10,
    "ytick.labelsize": 10,
    "legend.fontsize": 9,
    "axes.spines.right": False,
    "axes.spines.top": False,
    "axes.linewidth": 0.8,
    "xtick.major.width": 0.8,
    "ytick.major.width": 0.8,
    "xtick.major.size": 4,
    "ytick.major.size": 4,
    "legend.frameon": False,
    "figure.dpi": 300,
    "svg.fonttype": "none",
    "pdf.fonttype": 42,
})

# Tool display order, colours and legend labels (consistent with the legacy
# figure script: RustyClean steel blue, Hostile muted red, KneadData tan).
TOOLS = ['kneaddata', 'hostile_fastp', 'rc_kraken2_recheck', 'deacon_skipqc', 'rc_auto_deacon']
TOOL_LABELS = {
    'kneaddata': 'KneadData',
    'hostile_fastp': 'Hostile + fastp',
    'rc_kraken2_recheck': 'RustyClean (legacy Kraken2+recheck)',
    'deacon_skipqc': 'deacon (depletion only)',
    'rc_auto_deacon': 'RustyClean AUTO (deacon)',
}
TOOL_COLORS = {
    'kneaddata': '#D4A373',
    'hostile_fastp': '#C75B5B',
    'rc_kraken2_recheck': '#8C8C8C',
    'deacon_skipqc': '#7EB5A6',
    'rc_auto_deacon': '#4A90A4',
}

DATASETS = ['5M_1pct_low_even_SE', '10M_10pct_med_even_SE', '30M_50pct_high_skewed_SE',
            '60M_90pct_high_lognormal_SE', '100M_50pct_high_lognormal_SE', '100M_90pct_high_lognormal_SE']
DATASET_LABELS = ['5M / 1%', '10M / 10%', '30M / 50%', '60M / 90%', '100M / 50%', '100M / 90%']

WIDTH = 0.16


def load_five_way(data_dir):
    df = pd.read_csv(os.path.join(data_dir, 'five_way_summary.csv'))
    return df.set_index(['tool', 'dataset'])


def bar(ax, x, height, color, label=None):
    """Bar that skips NaN heights (conditions that were not run)."""
    if not np.isnan(height):
        ax.bar(x, height, WIDTH, color=color, label=label, zorder=3)


def annotate_zero(ax, x, y, text='0'):
    """Mark a true-zero value on a log-scale axis without drawing a fake bar."""
    ax.annotate(text, xy=(x, y), xytext=(0, 3), textcoords='offset points',
                ha='center', va='bottom', fontsize=8, fontweight='bold')


def tool_handles():
    """Legend handles in tool order (works even when a tool has no row for
    the first dataset, e.g. the legacy backend on the small datasets)."""
    return [Patch(color=TOOL_COLORS[t], label=TOOL_LABELS[t]) for t in TOOLS]


def figure_deacon_panel(df, out_dir):
    """Five-way comparison: runtime (log) and peak memory per dataset."""
    x = np.arange(len(DATASETS))
    fig = plt.figure(figsize=(7.5, 3.8))
    gs = fig.add_gridspec(1, 2, wspace=0.35)

    ax1 = fig.add_subplot(gs[0, 0])
    ax2 = fig.add_subplot(gs[0, 1])
    for i, tool in enumerate(TOOLS):
        offsets = (i - (len(TOOLS) - 1) / 2) * WIDTH
        for j, ds in enumerate(DATASETS):
            try:
                row = df.loc[(tool, ds)]
            except KeyError:
                continue
            bar(ax1, x[j] + offsets, row['runtime_s'] / 60.0, TOOL_COLORS[tool])
            bar(ax2, x[j] + offsets, row['memory_gb'], TOOL_COLORS[tool])

    for ax, title, ylabel in [
        (ax1, 'a  Runtime (full pipeline or stated basis)', 'Runtime (min, log scale)'),
        (ax2, 'b  Peak memory', 'Peak memory (GB)'),
    ]:
        ax.set_title(title)
        ax.set_ylabel(ylabel)
        ax.set_xticks(x)
        ax.set_xticklabels(DATASET_LABELS, rotation=20, ha='right')
    ax1.set_yscale('log')
    ax1.set_ylim(0.05, 400)
    ax2.set_ylim(0, 18)
    fig.legend(handles=tool_handles(), loc='lower center', ncol=5,
               fontsize=7.5, bbox_to_anchor=(0.5, 1.0))

    fig.tight_layout()
    for ext in ['png', 'svg', 'pdf']:
        fig.savefig(os.path.join(out_dir, f'fig2_deacon_panel.{ext}'), dpi=300, bbox_inches='tight')
    plt.close(fig)


def figure_deacon_accuracy(df, out_dir):
    """F1 and host carry-over per dataset and tool (five-way panel)."""
    x = np.arange(len(DATASETS))
    fig = plt.figure(figsize=(7.5, 3.8))
    gs = fig.add_gridspec(1, 2, wspace=0.35)

    ax1 = fig.add_subplot(gs[0, 0])
    ax2 = fig.add_subplot(gs[0, 1])
    carry_floor = 1e-3  # annotation height for true-zero carry values
    for i, tool in enumerate(TOOLS):
        offsets = (i - (len(TOOLS) - 1) / 2) * WIDTH
        for j, ds in enumerate(DATASETS):
            try:
                row = df.loc[(tool, ds)]
            except KeyError:
                continue
            f1, carry = row['f1'], row['host_carry_pct']
            bar(ax1, x[j] + offsets, f1, TOOL_COLORS[tool])
            if carry <= 0:
                annotate_zero(ax2, x[j] + offsets, carry_floor * 1.2)
            else:
                bar(ax2, x[j] + offsets, carry, TOOL_COLORS[tool])

    ax1.set_title('a  F1 score')
    ax1.set_ylabel('F1 score')
    ax1.set_xticks(x)
    ax1.set_xticklabels(DATASET_LABELS, rotation=20, ha='right')
    ax1.set_ylim(0.95, 1.001)

    ax2.set_title('b  Host carry-over (% of retained output, log scale)')
    ax2.set_ylabel('Host carry-over (%)')
    ax2.set_xticks(x)
    ax2.set_xticklabels(DATASET_LABELS, rotation=20, ha='right')
    ax2.set_yscale('log')
    ax2.set_ylim(5e-4, 5)
    ax2.axhline(0.01, color='gray', linestyle='--', linewidth=0.6, alpha=0.7)
    fig.legend(handles=tool_handles(), loc='lower center', ncol=5,
               fontsize=7.5, bbox_to_anchor=(0.5, 1.0))

    fig.tight_layout()
    for ext in ['png', 'svg', 'pdf']:
        fig.savefig(os.path.join(out_dir, f'fig3_deacon_accuracy.{ext}'), dpi=300, bbox_inches='tight')
    plt.close(fig)


def read_cross_species(path):
    """cross_species_metrics.csv carries an unlabelled leading index-name
    column (15 fields vs 14 headers), so read it with explicit names."""
    cols = ['index_name', 'dataset', 'rep', 'elapsed_s', 'max_rss_kb', 'accuracy',
            'precision', 'recall', 'f1', 'microbial_loss_pct', 'host_carry_pct',
            'tp', 'fp', 'fn', 'tn']
    return pd.read_csv(path, header=0, names=cols)


def figure_cross_species(data_dir, out_dir):
    """Species-matched deacon index vs panhuman-1 index F1 on 10M/50% panel."""
    df = read_cross_species(os.path.join(data_dir, 'cross_species_metrics.csv'))
    hosts = ['human', 'monkey', 'mouse', 'pig', 'rat', 'rice']
    host_labels = [h.capitalize() for h in hosts]

    matched, panhuman = [], []
    for h in hosts:
        rows = df[df['dataset'] == h]
        panhuman.append(float(rows[rows['index_name'] == 'panhuman']['f1'].iloc[0]))
        if h == 'human':
            matched.append(float(rows[rows['index_name'] == 'panhuman']['f1'].iloc[0]))
        else:
            matched.append(float(rows[rows['index_name'] == h]['f1'].iloc[0]))

    x = np.arange(len(hosts))
    width = 0.35
    fig, ax = plt.subplots(figsize=(4.6, 3.2))
    bars1 = ax.bar(x - width / 2, matched, width, color='#4A90A4',
                   label='Species-matched index')
    bars2 = ax.bar(x + width / 2, panhuman, width, color='#C75B5B',
                   label='panhuman-1 index')
    ax.set_ylabel('F1 score')
    ax.set_title('Cross-species depletion accuracy', pad=26)
    ax.set_xticks(x)
    ax.set_xticklabels(host_labels, rotation=30, ha='right')
    ax.set_ylim(0, 1.05)
    ax.legend(loc='center left', bbox_to_anchor=(1.02, 0.5), fontsize=8)
    for i in range(len(hosts)):
        if abs(matched[i] - panhuman[i]) < 1e-9:
            # twin bars (human): single centred label above both
            ax.annotate(f'{matched[i]:.3f}', xy=(x[i], matched[i]),
                        xytext=(0, 2), textcoords='offset points',
                        ha='center', va='bottom', fontsize=7)
        else:
            ax.annotate(f'{matched[i]:.3f}', xy=(x[i] - width / 2, matched[i]),
                        xytext=(0, 2), textcoords='offset points',
                        ha='center', va='bottom', fontsize=7)
            ax.annotate(f'{panhuman[i]:.3f}', xy=(x[i] + width / 2, panhuman[i]),
                        xytext=(0, 2), textcoords='offset points',
                        ha='center', va='bottom', fontsize=7)
    fig.tight_layout()
    for ext in ['png', 'svg', 'pdf']:
        fig.savefig(os.path.join(out_dir, f'fig5_cross_species.{ext}'), dpi=300, bbox_inches='tight')
    plt.close(fig)


def figure_verification(df, out_dir):
    """Verification tier: deacon-only vs full AUTO host carry-over."""
    datasets = ['30M_50pct_high_skewed_SE', '60M_90pct_high_lognormal_SE', '100M_50pct_high_lognormal_SE']
    labels = ['30M / 50%', '60M / 90%', '100M / 50%']
    deacon_carry = [df.loc[('deacon_skipqc', ds)]['host_carry_pct'] for ds in datasets]
    auto_carry = [df.loc[('rc_auto_deacon', ds)]['host_carry_pct'] for ds in datasets]

    x = np.arange(len(datasets))
    width = 0.35
    fig, ax = plt.subplots(figsize=(4.6, 3.2))
    bars1 = ax.bar(x - width / 2, deacon_carry, width, color='#7EB5A6',
                   label='deacon only')
    bars2 = ax.bar(x + width / 2, auto_carry, width, color='#4A90A4',
                   label='RustyClean AUTO\n(deacon + Bowtie2 verification)')
    ax.set_ylabel('Host carry-over (% of retained output)')
    ax.set_title('Verification tier eliminates residual host reads')
    ax.set_xticks(x)
    ax.set_xticklabels(labels, rotation=20, ha='right')
    ax.set_ylim(0, 0.0045)
    ax.legend(loc='center left', bbox_to_anchor=(1.02, 0.5), fontsize=8)
    for b in bars1:
        h = b.get_height()
        ax.annotate(f'{h:.4f}', xy=(b.get_x() + b.get_width() / 2, h),
                    xytext=(0, 2), textcoords='offset points',
                    ha='center', va='bottom', fontsize=8)
    for b in bars2:
        ax.annotate('0.0000', xy=(b.get_x() + b.get_width() / 2, 0.0001),
                    xytext=(0, 2), textcoords='offset points',
                    ha='center', va='bottom', fontsize=8)
    fig.tight_layout()
    for ext in ['png', 'svg', 'pdf']:
        fig.savefig(os.path.join(out_dir, f'fig6_verification.{ext}'), dpi=300, bbox_inches='tight')
    plt.close(fig)


if __name__ == '__main__':
    data_dir = sys.argv[1] if len(sys.argv) > 1 else 'data/deacon_panel'
    out_dir = sys.argv[2] if len(sys.argv) > 2 else 'figures'
    os.makedirs(out_dir, exist_ok=True)
    df = load_five_way(data_dir)
    figure_deacon_panel(df, out_dir)
    figure_deacon_accuracy(df, out_dir)
    figure_cross_species(data_dir, out_dir)
    figure_verification(df, out_dir)
    print(f'Figures written to {out_dir}')
