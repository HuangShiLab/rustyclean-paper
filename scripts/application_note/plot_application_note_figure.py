#!/usr/bin/env python3
"""Create the combined Application Note performance figure.

The figure places the four-tool runtime/memory panels above the sample-level
parallel-scaling panels.  It reads the curated source tables in
data/main_figures and writes fig1_runtime_memory_scaling.{png,svg,pdf}.

Usage:
  python3 scripts/application_note/plot_application_note_figure.py \
      [data_dir] [out_dir]
"""
from pathlib import Path
import sys

import matplotlib as mpl
mpl.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.patches import Patch

mpl.rcParams.update({
    'font.family': 'sans-serif',
    'font.sans-serif': ['Arial', 'Helvetica', 'DejaVu Sans', 'sans-serif'],
    'font.size': 9,
    'axes.labelsize': 9.5,
    'axes.titlesize': 10.5,
    'xtick.labelsize': 8.5,
    'ytick.labelsize': 8.5,
    'legend.fontsize': 8,
    'axes.spines.right': False,
    'axes.spines.top': False,
    'axes.linewidth': 0.75,
    'xtick.major.width': 0.75,
    'ytick.major.width': 0.75,
    'legend.frameon': False,
    'figure.dpi': 300,
    'svg.fonttype': 'none',
    'pdf.fonttype': 42,
})

TOOLS = ['kneaddata', 'hostile_fastp', 'deacon_skipqc', 'rc_auto_deacon', 'rc_auto_deacon_norecheck']
LABELS = {
    'kneaddata': 'KneadData',
    'hostile_fastp': 'Hostile + fastp',
    'deacon_skipqc': 'Deacon (depletion only)',
    'rc_auto_deacon': 'RustyClean AUTO\n(fastp + deacon + conditional Bowtie2 verification)',
    'rc_auto_deacon_norecheck': 'RustyClean AUTO without recheck\n(fastp + deacon)',
}
COLORS = {
    'kneaddata': '#D4A373',
    'hostile_fastp': '#C75B5B',
    'deacon_skipqc': '#7EB5A6',
    'rc_auto_deacon': '#4A90A4',
    'rc_auto_deacon_norecheck': '#E17054',
}
DATASETS = [
    '5M_1pct_low_even_SE', '10M_10pct_med_even_SE',
    '30M_50pct_high_skewed_SE', '60M_90pct_high_lognormal_SE',
    '100M_50pct_high_lognormal_SE', '100M_90pct_high_lognormal_SE'
]
DATASET_LABELS = ['5M / 1%', '10M / 10%', '30M / 50%', '60M / 90%',
                  '100M / 50%', '100M / 90%']


def plot_four_way(ax_runtime, ax_memory, perf):
    x = np.arange(len(DATASETS))
    width = 0.15
    for i, tool in enumerate(TOOLS):
        offset = (i - (len(TOOLS) - 1) / 2) * width
        for j, dataset in enumerate(DATASETS):
            row = perf.loc[(tool, dataset)]
            ax_runtime.bar(x[j] + offset, row['runtime_s'] / 60, width,
                           color=COLORS[tool], zorder=3)
            ax_memory.bar(x[j] + offset, row['memory_gib'], width,
                          color=COLORS[tool], zorder=3)

    ax_runtime.set_title('a  Runtime (full pipeline or stated basis)')
    ax_runtime.set_ylabel('Runtime (min, log scale)')
    ax_runtime.set_yscale('log')
    ax_runtime.set_ylim(0.05, 400)
    ax_runtime.set_xticks(x)
    ax_runtime.set_xticklabels(DATASET_LABELS, rotation=20, ha='right')

    ax_memory.set_title('b  Peak memory')
    ax_memory.set_ylabel('Peak memory (GiB)')
    ax_memory.set_ylim(0, 6)
    ax_memory.set_xticks(x)
    ax_memory.set_xticklabels(DATASET_LABELS, rotation=20, ha='right')


def plot_scaling(ax_wall, ax_speedup, ax_memory, scaling, rss):
    workers = scaling['workers'].astype(int).tolist()
    wall = scaling['wall_s'].tolist()
    speedup = scaling['speedup_vs_w1'].tolist()
    per_worker, total = [], []
    for worker in workers:
        group = rss[rss['workers'] == worker]
        per_worker.append(group['rss_per_worker_gib'].median())
        total.append(group['total_rss_gib'].median())

    bars = ax_wall.bar([str(w) for w in workers], wall, 0.55,
                       color='#4A90A4', zorder=3)
    for bar, value in zip(bars, wall):
        minute, second = int(value // 60), int(value % 60)
        ax_wall.annotate(f'{minute}m{second:02d}s',
                         (bar.get_x() + bar.get_width() / 2, value),
                         xytext=(0, 2), textcoords='offset points',
                         ha='center', fontsize=7.5)
    ax_wall.set_title('c  Throughput scaling')
    ax_wall.set_ylabel('Wall time, 16 samples (s)')
    ax_wall.set_xlabel('Concurrent workers (samples)')

    ax_speedup.plot(workers, speedup, 'o-', color='#4A90A4',
                    label='Measured', zorder=3)
    ax_speedup.plot(workers, workers, '--', color='#8C8C8C',
                    label='Ideal linear', zorder=2)
    for worker, value in zip(workers, speedup):
        ax_speedup.annotate(f'{value:.2f}×', (worker, value),
                            xytext=(0, 5), textcoords='offset points',
                            ha='center', fontsize=7.5)
    ax_speedup.set_title('d  Parallel efficiency')
    ax_speedup.set_ylabel('Speedup vs 1 worker')
    ax_speedup.set_xlabel('Concurrent workers (samples)')
    ax_speedup.set_xticks(workers)
    ax_speedup.set_ylim(0, max(workers) * 1.15)
    ax_speedup.legend(loc='upper left')

    x = np.arange(len(workers))
    width = 0.35
    total_bars = ax_memory.bar(x - width / 2, total, width, color='#7EB5A6',
                               label='Σ RSS, all workers', zorder=3)
    ax_memory.bar(x + width / 2, per_worker, width, color='#4A90A4',
                  label='RSS per Deacon worker', zorder=3)
    for bar, value in zip(total_bars, total):
        ax_memory.annotate(f'{value:.1f}', (bar.get_x() + bar.get_width() / 2, value),
                           xytext=(0, 2), textcoords='offset points',
                           ha='center', fontsize=7.5)
    ax_memory.set_title('e  Memory per worker stays flat')
    ax_memory.set_ylabel('Resident set size (GiB)')
    ax_memory.set_xlabel('Concurrent workers (samples)')
    ax_memory.set_xticks(x)
    ax_memory.set_xticklabels([str(w) for w in workers])
    ax_memory.set_ylim(0, max(max(total), max(per_worker)) * 1.18)
    ax_memory.legend(loc='upper left')


def main(data_dir, out_dir):
    data_dir, out_dir = Path(data_dir), Path(out_dir)
    perf = pd.read_csv(data_dir / 'fig1_five_way_runtime_memory.csv')
    perf = perf.set_index(['tool', 'dataset'])
    scaling = pd.read_csv(data_dir / 'fig4_parallel_scaling.csv')
    rss = pd.read_csv(data_dir / 'fig4_parallel_scaling_rss_samples.csv')

    handles = [Patch(color=COLORS[tool], label=LABELS[tool]) for tool in TOOLS]
    fig = plt.figure(figsize=(10.0, 6.7))
    gs = fig.add_gridspec(2, 3, width_ratios=[1.0, 0.95, 1.05],
                          height_ratios=[1.0, 1.0], hspace=0.46,
                          wspace=0.28)
    ax_runtime = fig.add_subplot(gs[0, 0:2])
    ax_memory = fig.add_subplot(gs[0, 2])
    ax_wall = fig.add_subplot(gs[1, 0])
    ax_speedup = fig.add_subplot(gs[1, 1])
    ax_worker_memory = fig.add_subplot(gs[1, 2])

    plot_four_way(ax_runtime, ax_memory, perf)
    plot_scaling(ax_wall, ax_speedup, ax_worker_memory, scaling, rss)
    fig.legend(handles=handles, loc='lower center', ncol=5,
               bbox_to_anchor=(0.5, 0.985), fontsize=7.5)

    out_dir.mkdir(parents=True, exist_ok=True)
    for extension in ('png', 'svg', 'pdf'):
        fig.savefig(out_dir / f'fig1_runtime_memory_scaling.{extension}',
                    dpi=300, bbox_inches='tight')
    plt.close(fig)
    print(f'Application Note Figure 1 written to {out_dir}')


if __name__ == '__main__':
    data_dir = sys.argv[1] if len(sys.argv) > 1 else 'data/main_figures'
    out_dir = sys.argv[2] if len(sys.argv) > 2 else 'figures'
    main(data_dir, out_dir)
