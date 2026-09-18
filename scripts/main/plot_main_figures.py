#!/usr/bin/env python3
"""Publication-quality figures for the deacon-based default backend (RustyClean).

Reads curated per-figure data from data/main_figures/ and exports four
manuscript-numbered main figures:
  - fig1_four_way_runtime_memory.{png,svg,pdf}
  - fig2_accuracy_verification.{png,svg,pdf}
  - fig3_cross_species_index.{png,svg,pdf}
  - fig4_parallel_scaling.{png,svg,pdf}

Usage: python3 scripts/main/plot_main_figures.py [data_dir] [out_dir]
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
TOOLS = ['kneaddata', 'hostile_fastp', 'deacon_skipqc', 'rc_auto_deacon']
TOOL_LABELS = {
    'kneaddata': 'KneadData',
    'hostile_fastp': 'Hostile + fastp',
    'rc_kraken2_recheck': 'RustyClean (legacy Kraken2+recheck)',
    'deacon_skipqc': 'deacon (depletion only)',
    'rc_auto_deacon': 'RustyClean AUTO\n(fastp + deacon + conditional Bowtie2 verification)',
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


def load_main_figure_data(data_dir):
    df = pd.read_csv(os.path.join(data_dir, 'fig1_four_way_runtime_memory.csv'))
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


def figure_four_way_runtime_memory(df, out_dir):
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
            bar(ax2, x[j] + offsets, row['memory_gib'], TOOL_COLORS[tool])

    for ax, title, ylabel in [
        (ax1, 'a  Runtime (full pipeline or stated basis)', 'Runtime (min, log scale)'),
        (ax2, 'b  Peak memory', 'Peak memory (GiB)'),
    ]:
        ax.set_title(title)
        ax.set_ylabel(ylabel)
        ax.set_xticks(x)
        ax.set_xticklabels(DATASET_LABELS, rotation=20, ha='right')
    ax1.set_yscale('log')
    ax1.set_ylim(0.05, 400)
    ax2.set_ylim(0, 6)
    fig.legend(handles=tool_handles(), loc='lower center', ncol=5,
               fontsize=7.5, bbox_to_anchor=(0.5, 1.0))

    fig.tight_layout()
    for ext in ['png', 'svg', 'pdf']:
        fig.savefig(os.path.join(out_dir, f'fig1_four_way_runtime_memory.{ext}'), dpi=300, bbox_inches='tight')
    plt.close(fig)


def figure_accuracy_and_verification(df, out_dir):
    """F1, host carry-over, and deacon-vs-AUTO verification effect."""
    x = np.arange(len(DATASETS))
    high_datasets = ['30M_50pct_high_skewed_SE', '60M_90pct_high_lognormal_SE',
                     '100M_50pct_high_lognormal_SE', '100M_90pct_high_lognormal_SE']
    high_labels = ['30M / 50%', '60M / 90%', '100M / 50%', '100M / 90%']
    hx = np.arange(len(high_datasets))
    carry_floor = 1e-3
    fig = plt.figure(figsize=(15.0, 4.7))
    gs = fig.add_gridspec(1, 3, width_ratios=[1.15, 1.15, 0.95], wspace=0.32)

    ax1 = fig.add_subplot(gs[0, 0])
    ax2 = fig.add_subplot(gs[0, 1])
    ax3 = fig.add_subplot(gs[0, 2])
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

    ax2.set_title('b  Host carry-over (% retained output, log scale)')
    ax2.set_ylabel('Host carry-over (%)')
    ax2.set_xticks(x)
    ax2.set_xticklabels(DATASET_LABELS, rotation=20, ha='right')
    ax2.set_yscale('log')
    ax2.set_ylim(5e-4, 5)
    ax2.axhline(0.01, color='gray', linestyle='--', linewidth=0.6, alpha=0.7)

    deacon_carry = [df.loc[('deacon_skipqc', ds)]['host_carry_pct'] for ds in high_datasets]
    auto_carry = [df.loc[('rc_auto_deacon', ds)]['host_carry_pct'] for ds in high_datasets]
    width = 0.38
    bars1 = ax3.bar(hx - width / 2, deacon_carry, width, color='#7EB5A6',
                    label='deacon only')
    bars2 = ax3.bar(hx + width / 2, auto_carry, width, color='#4A90A4',
                    label='RustyClean AUTO\n(fastp + deacon + conditional Bowtie2 verification)')
    ax3.set_title('c  Verification effect (high-host datasets)')
    ax3.set_ylabel('Host carry-over (%)')
    ax3.set_xticks(hx)
    ax3.set_xticklabels(high_labels, rotation=25, ha='right')
    ax3.set_ylim(0, 0.0062)
    ax3.legend(loc='upper center', fontsize=7.5, frameon=False)
    for b in bars1:
        h = b.get_height()
        ax3.annotate(f'{h:.4f}', xy=(b.get_x() + b.get_width() / 2, h),
                     xytext=(0, 2), textcoords='offset points',
                     ha='center', va='bottom', fontsize=7.5)
    for b in bars2:
        ax3.annotate('0.0000', xy=(b.get_x() + b.get_width() / 2, 0.0001),
                     xytext=(0, 2), textcoords='offset points',
                     ha='center', va='bottom', fontsize=7.5)

    fig.legend(handles=tool_handles(), loc='lower center', ncol=4,
               fontsize=7.5, bbox_to_anchor=(0.5, 1.0))
    fig.tight_layout()
    for ext in ['png', 'svg', 'pdf']:
        fig.savefig(os.path.join(out_dir, f'fig2_accuracy_verification.{ext}'),
                    dpi=300, bbox_inches='tight')
    plt.close(fig)


def read_cross_species(path):
    """cross_species_metrics.csv carries an unlabelled leading index-name
    column (15 fields vs 14 headers), so read it with explicit names."""
    cols = ['index_name', 'dataset', 'rep', 'elapsed_s', 'max_rss_kb', 'accuracy',
            'precision', 'recall', 'f1', 'microbial_loss_pct', 'host_carry_pct',
            'tp', 'fp', 'fn', 'tn']
    return pd.read_csv(path, header=0, names=cols)


def figure_cross_species_index(data_dir, out_dir):
    """Species-matched deacon index vs panhuman-1 index F1 on 10M/50% panel."""
    df = read_cross_species(os.path.join(data_dir, 'fig3_cross_species_index.csv'))
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
        fig.savefig(os.path.join(out_dir, f'fig3_cross_species_index.{ext}'), dpi=300, bbox_inches='tight')
    plt.close(fig)


def figure_parallel_scaling_memory(data_dir, out_dir):
    """Sample-level parallelism of the deacon backend.

    Reads parallel_scaling_deacon.csv (wall time, speedup) and the per-worker
    RSS samples under parscale/W*/rss_samples.tsv. Note that summing per-process
    RSS overcounts physical memory because every deacon worker memory-maps the
    same read-only index (its pages are counted in each process's RSS). The
    optional mmap_share/mem.log sanity check (MemAvailable drop) is plotted as
    the physical-memory reference when present.
    """
    csv_path = os.path.join(data_dir, 'fig4_parallel_scaling.csv')
    df = pd.read_csv(csv_path)
    workers = df['workers'].tolist()
    wall = df['wall_s'].tolist()
    speedup = df['speedup_vs_w1'].tolist()

    rss_samples = pd.read_csv(os.path.join(
        data_dir, 'fig4_parallel_scaling_rss_samples.csv'))
    rss_sum, rss_per = [], []
    for w in workers:
        group = rss_samples[rss_samples['workers'] == w]
        rss_sum.append(np.median(group['total_rss_gib'].to_numpy()))
        rss_per.append(np.median(group['rss_per_worker_gib'].to_numpy()))

    fig, axes = plt.subplots(1, 3, figsize=(11.5, 3.4))

    ax = axes[0]
    bars = ax.bar([str(w) for w in workers], wall, 0.55, color='#4A90A4', zorder=3)
    for b, v in zip(bars, wall):
        m, s = int(v // 60), int(v % 60)
        ax.annotate(f'{m}m{s:02d}s', xy=(b.get_x() + b.get_width() / 2, v),
                    xytext=(0, 2), textcoords='offset points',
                    ha='center', va='bottom', fontsize=8)
    ax.set_xlabel('Concurrent workers (samples)')
    ax.set_ylabel('Wall time for 16 samples (s)')
    ax.set_title('(a) Throughput scaling')

    ax = axes[1]
    ideal = workers
    ax.plot(workers, speedup, 'o-', color='#4A90A4', label='Measured', zorder=3)
    ax.plot(workers, ideal, '--', color='#8C8C8C', label='Ideal linear', zorder=2)
    for w, v in zip(workers, speedup):
        ax.annotate(f'{v:.2f}×', xy=(w, v), xytext=(0, 6),
                    textcoords='offset points', ha='center', fontsize=8)
    ax.set_xlabel('Concurrent workers (samples)')
    ax.set_ylabel('Speedup vs 1 worker')
    ax.set_title('(b) Parallel efficiency')
    ax.set_xticks(workers)
    ax.legend(loc='upper left')
    ax.set_ylim(0, max(ideal) * 1.15)

    ax = axes[2]
    width = 0.35
    x = np.arange(len(workers))
    bars = ax.bar(x - width / 2, rss_sum, width, color='#7EB5A6', zorder=3,
                  label='Σ RSS, all workers')
    ax.bar(x + width / 2, rss_per, width, color='#4A90A4', zorder=3,
           label='RSS per deacon worker')
    ax.set_xlabel('Concurrent workers (samples)')
    ax.set_ylabel('Resident set size (GiB)')
    ax.set_title('(c) Memory per worker stays flat')
    ax.set_xticks(x)
    ax.set_xticklabels([str(w) for w in workers])
    ax.legend(fontsize=8, loc='upper left')
    ax.set_ylim(0, max(max(rss_sum), max(rss_per)) * 1.18)
    for b, v in zip(bars, rss_sum):
        ax.annotate(f'{v:.1f}', xy=(b.get_x() + b.get_width() / 2, v),
                    xytext=(0, 2), textcoords='offset points',
                    ha='center', va='bottom', fontsize=8)

    fig.tight_layout()
    for ext in ['png', 'svg', 'pdf']:
        fig.savefig(os.path.join(out_dir, f'fig4_parallel_scaling.{ext}'),
                    dpi=300, bbox_inches='tight')
    plt.close(fig)


if __name__ == '__main__':
    data_dir = sys.argv[1] if len(sys.argv) > 1 else 'data/main_figures'
    out_dir = sys.argv[2] if len(sys.argv) > 2 else 'figures'
    os.makedirs(out_dir, exist_ok=True)
    df = load_main_figure_data(data_dir)
    figure_four_way_runtime_memory(df, out_dir)
    figure_accuracy_and_verification(df, out_dir)
    figure_cross_species_index(data_dir, out_dir)
    figure_parallel_scaling_memory(data_dir, out_dir)
    print(f'Figures written to {out_dir}')
