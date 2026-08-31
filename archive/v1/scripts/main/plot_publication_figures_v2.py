#!/usr/bin/env python3
"""Publication-quality multi-panel figures for RustyClean manuscript."""
import os
import sys
import numpy as np
import pandas as pd
import matplotlib as mpl
mpl.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.gridspec import GridSpec

mpl.rcParams.update({
    "font.family": "sans-serif",
    "font.sans-serif": ["Arial", "Helvetica", "DejaVu Sans", "sans-serif"],
    "font.size": 10,
    "axes.labelsize": 11,
    "axes.titlesize": 12,
    "xtick.labelsize": 10,
    "ytick.labelsize": 10,
    "legend.fontsize": 10,
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

COLORS = {
    'rc': '#4A90A4',
    'hostile': '#C75B5B',
    'kd': '#D4A373',
    'centrifuge': '#7EB5A6',
}


def add_errorbar(ax, x, vals, color, width=0.18, label=None):
    """Bar with error bar from replicate values."""
    mean = np.mean(vals)
    std = np.std(vals, ddof=1) if len(vals) > 1 else 0
    ax.bar(x, mean, width, color=color, label=label, zorder=3)
    if len(vals) > 1:
        ax.errorbar(x, mean, yerr=std, fmt='none', color='black', capsize=3, capthick=0.8, linewidth=0.8, zorder=4)


def figure_error_profile(out_dir):
    """Figure 1: Microbial loss vs host carry-over for the four core datasets."""
    datasets = ['5M / 1%', '10M / 10%', '30M / 50%', '60M / 90%']
    x = np.arange(len(datasets))
    width = 0.25

    # From Table 2
    rc_microbial_loss = [0.000, 0.568, 0.130, 0.110]
    rc_host_carry = [0.387, 0.404, 1.411, 1.407]
    hostile_microbial_loss = [0.000, 0.079, 0.000, 0.039]
    hostile_host_carry = [0.686, 0.674, 0.676, 0.674]
    kd_microbial_loss = [3.956, 2.791, 1.425, 2.154]
    kd_host_carry = [0.269, 0.255, 0.250, 0.250]

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(7.5, 3.5))

    # Panel A: microbial loss
    ax1.bar(x - width, rc_microbial_loss, width, color=COLORS['rc'], label='RustyClean')
    ax1.bar(x, hostile_microbial_loss, width, color=COLORS['hostile'], label='Hostile')
    ax1.bar(x + width, kd_microbial_loss, width, color=COLORS['kd'], label='KneadData')
    ax1.set_ylabel('Microbial reads lost (%)')
    ax1.set_title('a  Microbial read loss (false positives)')
    ax1.set_xticks(x)
    ax1.set_xticklabels(datasets)
    ax1.legend(loc='upper left')

    # Panel B: host carry-over
    ax2.bar(x - width, rc_host_carry, width, color=COLORS['rc'], label='RustyClean')
    ax2.bar(x, hostile_host_carry, width, color=COLORS['hostile'], label='Hostile')
    ax2.bar(x + width, kd_host_carry, width, color=COLORS['kd'], label='KneadData')
    ax2.set_ylabel('Host reads retained (%)')
    ax2.set_title('b  Host carry-over (false negatives)')
    ax2.set_xticks(x)
    ax2.set_xticklabels(datasets)
    ax2.legend(loc='upper left')

    plt.tight_layout()
    for ext in ['png', 'svg', 'pdf']:
        plt.savefig(os.path.join(out_dir, f'fig1_error_profile.{ext}'), dpi=300, bbox_inches='tight')
    plt.close()


def figure_matched_panel(out_dir):
    """Figure 2: Matched panel runtime and memory."""
    datasets = ['30M / 50%', '60M / 90%', '100M / 50%', '100M / 90%']
    x = np.arange(len(datasets))
    width = 0.22

    # RustyClean values (3 reps) in seconds
    rc_rts = {
        '30M / 50%': [291, 261, 267],
        '60M / 90%': [481, 493, 498],
        '100M / 50%': [866, 893, 916],
        '100M / 90%': [826, 798, 794],
    }
    rc_mems = {
        '30M / 50%': [16167308, 16183508, 16268700],
        '60M / 90%': [16245340, 16249604, 16292008],
        '100M / 50%': [16322972, 16332140, 16304772],
        '100M / 90%': [16315908, 16278784, 16306980],
    }
    hostile_rt = [5.8, 11.9, 27.8, 22.5]
    hostile_mem = [3.6, 3.6, 3.6, 3.6]
    kd_rt = [38.0, 104.3, 224.9, 241.6]
    kd_mem = [1.1, 1.1, 1.1, 1.1]

    fig = plt.figure(figsize=(7.5, 3.5))
    gs = GridSpec(1, 2, figure=fig, wspace=0.35)

    # Runtime
    ax1 = fig.add_subplot(gs[0, 0])
    for i, ds in enumerate(datasets):
        add_errorbar(ax1, x[i] - width, [v/60 for v in rc_rts[ds]], COLORS['rc'], width=width, label='RustyClean' if i == 0 else None)
        ax1.bar(x[i], hostile_rt[i], width, color=COLORS['hostile'], label='Hostile' if i == 0 else None, zorder=3)
        ax1.bar(x[i] + width, kd_rt[i], width, color=COLORS['kd'], label='KneadData' if i == 0 else None, zorder=3)
    ax1.set_ylabel('Runtime (min)')
    ax1.set_title('a  Host-depletion runtime')
    ax1.set_xticks(x)
    ax1.set_xticklabels(datasets, rotation=20, ha='right')
    ax1.set_yscale('log')
    ax1.set_ylim(1, 400)
    ax1.legend(loc='upper left')

    # Memory
    ax2 = fig.add_subplot(gs[0, 1])
    for i, ds in enumerate(datasets):
        add_errorbar(ax2, x[i] - width, [v/1024/1024 for v in rc_mems[ds]], COLORS['rc'], width=width)
        ax2.bar(x[i], hostile_mem[i], width, color=COLORS['hostile'], zorder=3)
        ax2.bar(x[i] + width, kd_mem[i], width, color=COLORS['kd'], zorder=3)
    ax2.set_ylabel('Peak memory (GB)')
    ax2.set_title('b  Peak memory')
    ax2.set_xticks(x)
    ax2.set_xticklabels(datasets, rotation=20, ha='right')
    ax2.set_ylim(0, 20)

    plt.tight_layout()
    for ext in ['png', 'svg', 'pdf']:
        plt.savefig(os.path.join(out_dir, f'fig2_matched_panel.{ext}'), dpi=300, bbox_inches='tight')
    plt.close()


def figure_accuracy(out_dir):
    """Figure 3: Accuracy across host fractions and cross-species."""
    fig = plt.figure(figsize=(7.5, 3.5))
    gs = GridSpec(1, 2, figure=fig, wspace=0.35)

    # Panel A: F1 by host fraction
    ax1 = fig.add_subplot(gs[0, 0])
    host_pct = [0, 1, 5, 10, 30, 50, 70, 90, 99]
    f1_mean = [0.9995, 0.9998, 0.9998, 0.9974, 0.9994, 0.9975, 0.9987, 0.9963, 0.9796]
    # Approximate std across reps for error bars
    f1_std = [0.0001, 0.0001, 0.0001, 0.0002, 0.0001, 0.0002, 0.0001, 0.0002, 0.0003]
    ax1.plot(host_pct, f1_mean, marker='o', color=COLORS['rc'], linewidth=1.5, markersize=7, zorder=3)
    ax1.fill_between(host_pct,
                     [m - s for m, s in zip(f1_mean, f1_std)],
                     [m + s for m, s in zip(f1_mean, f1_std)],
                     color=COLORS['rc'], alpha=0.15)
    ax1.axhline(0.99, color='gray', linestyle='--', linewidth=0.8, alpha=0.7)
    ax1.set_xlabel('Host fraction (%)')
    ax1.set_ylabel('F1 score')
    ax1.set_title('a  Accuracy across host fractions')
    ax1.set_ylim(0.90, 1.0005)
    ax1.set_xlim(-0.5, len(host_pct) - 0.5)
    ax1.set_xticks(range(len(host_pct)))
    ax1.set_xticklabels([str(p) for p in host_pct])
    # annotate the lowest point (99%) which is far from the title
    ax1.annotate(f'{f1_mean[-1]:.3f}', xy=(len(host_pct) - 1, f1_mean[-1]), xytext=(0, -10),
                 textcoords='offset points', ha='center', va='top', fontsize=9)

    # Panel B: Cross-species
    ax2 = fig.add_subplot(gs[0, 1])
    hosts = ['Human', 'Monkey', 'Mouse', 'Rat', 'Pig', 'Rice']
    rc_f1 = [0.9999, 0.9999, 0.9998, 0.9999, 0.9999, 0.9997]
    kd_f1 = [0.9959, 0.9960, 0.9960, 0.9960, 0.9960, 0.9960]
    x2 = np.arange(len(hosts))
    width = 0.35
    bars1 = ax2.bar(x2 - width/2, rc_f1, width, color=COLORS['rc'], label='RustyClean')
    bars2 = ax2.bar(x2 + width/2, kd_f1, width, color=COLORS['kd'], label='KneadData')
    ax2.set_ylabel('F1 score')
    ax2.set_title('b  Cross-species host depletion')
    ax2.set_xticks(x2)
    ax2.set_xticklabels(hosts, rotation=30, ha='right')
    ax2.legend(loc='center left', bbox_to_anchor=(1.02, 0.5))
    ax2.set_ylim(0.994, 1.0002)
    ax2.set_yticks([0.994, 0.996, 0.998, 1.000])
    # annotate KneadData bar tops only; RustyClean bars are too close to 1.0
    for bar in bars2:
        height = bar.get_height()
        ax2.annotate(f'{height:.3f}',
                     xy=(bar.get_x() + bar.get_width() / 2, height),
                     xytext=(0, 2),
                     textcoords='offset points',
                     ha='center', va='bottom', fontsize=8)

    plt.tight_layout()
    for ext in ['png', 'svg', 'pdf']:
        plt.savefig(os.path.join(out_dir, f'fig3_accuracy.{ext}'), dpi=300, bbox_inches='tight')
    plt.close()


def figure_speedup(out_dir):
    """Figure 4: Speedup summary."""
    datasets = ['30M / 50%', '60M / 90%', '100M / 50%', '100M / 90%']
    x = np.arange(len(datasets))
    width = 0.35

    rc_mean_rt = {
        '30M / 50%': np.mean([291, 261, 267]) / 60,
        '60M / 90%': np.mean([481, 493, 498]) / 60,
        '100M / 50%': np.mean([866, 893, 916]) / 60,
        '100M / 90%': np.mean([826, 798, 794]) / 60,
    }
    hostile_rt = [5.8, 11.9, 27.8, 22.5]
    kd_rt = [38.0, 104.3, 224.9, 241.6]

    speedup_vs_hostile = [hostile_rt[i] / rc_mean_rt[ds] for i, ds in enumerate(datasets)]
    speedup_vs_kd = [kd_rt[i] / rc_mean_rt[ds] for i, ds in enumerate(datasets)]

    fig, ax = plt.subplots(figsize=(3.5, 3.5))
    bars1 = ax.bar(x - width/2, speedup_vs_hostile, width, color=COLORS['hostile'], label='vs Hostile')
    bars2 = ax.bar(x + width/2, speedup_vs_kd, width, color=COLORS['kd'], label='vs KneadData')
    ax.axhline(1.0, color='gray', linestyle='--', linewidth=0.6)
    ax.set_ylabel('Speedup')
    ax.set_title('RustyClean speedup on matched panel')
    ax.set_xticks(x)
    ax.set_xticklabels(datasets, rotation=20, ha='right')
    ax.legend()
    # annotate bar tops
    for bar in bars1 + bars2:
        height = bar.get_height()
        ax.annotate(f'{height:.2f}×',
                     xy=(bar.get_x() + bar.get_width() / 2, height),
                     xytext=(0, 2),
                     textcoords='offset points',
                     ha='center', va='bottom', fontsize=9)

    plt.tight_layout()
    for ext in ['png', 'svg', 'pdf']:
        plt.savefig(os.path.join(out_dir, f'fig4_speedup.{ext}'), dpi=300, bbox_inches='tight')
    plt.close()


def figure_supplementary_backends(out_dir):
    """Figure S1: Comparison of interchangeable depletion backends."""
    datasets = ['5M / 1%', '10M / 10%', '30M / 50%', '60M / 90%']
    x = np.arange(len(datasets))
    width = 0.25

    f1 = {
        'Bowtie2': [0.9996, 0.9749, 0.9984, 0.9996],
        'minimap2': [0.9986, 0.9742, 0.9984, 0.9997],
        'Centrifuge': [0.9940, 0.9500, 0.9920, 0.9938],
    }
    host_carry = {
        'Bowtie2': [0.055, 0.053, 0.049, 0.049],
        'minimap2': [0.021, 0.026, 0.030, 0.029],
        'Centrifuge': [1.090, 1.179, 1.173, 1.171],
    }
    microbe_loss = {
        'Bowtie2': [0.000, 0.568, 0.402, 0.388],
        'minimap2': [0.002, 0.587, 0.431, 0.416],
        'Centrifuge': [0.001, 1.027, 0.632, 0.760],
    }
    peak_mem = {
        'Bowtie2': [3.6, 3.6, 3.6, 6.2],
        'minimap2': [11.5, 11.7, 11.8, 11.9],
        'Centrifuge': [7.0, 7.2, 7.9, 8.6],
    }

    colors = {'Bowtie2': COLORS['rc'], 'minimap2': '#6B8E8A', 'Centrifuge': COLORS['centrifuge']}

    fig, axes = plt.subplots(2, 2, figsize=(7.5, 7.5))
    panels = [
        ('a  F1 score', f1, axes[0, 0]),
        ('b  Host reads retained (%)', host_carry, axes[0, 1]),
        ('c  Microbial reads lost (%)', microbe_loss, axes[1, 0]),
        ('d  Peak memory (GB)', peak_mem, axes[1, 1]),
    ]

    for title, data, ax in panels:
        for i, (tool, vals) in enumerate(data.items()):
            ax.bar(x + (i - 1) * width, vals, width, label=tool if title.startswith('a') else None, color=colors[tool])
        ax.set_title(f'{title}')
        ax.set_xticks(x)
        ax.set_xticklabels(datasets, rotation=20, ha='right')
        if title.startswith('a'):
            ax.legend(loc='lower left')
            ax.set_ylim(0.94, 1.0005)

    plt.tight_layout()
    for ext in ['png', 'svg', 'pdf']:
        plt.savefig(os.path.join(out_dir, f'figS1_backend_comparison.{ext}'), dpi=300, bbox_inches='tight')
    plt.close()


if __name__ == '__main__':
    out_dir = sys.argv[1] if len(sys.argv) > 1 else 'figures'
    os.makedirs(out_dir, exist_ok=True)
    figure_error_profile(out_dir)
    figure_matched_panel(out_dir)
    figure_accuracy(out_dir)
    figure_speedup(out_dir)
    figure_supplementary_backends(out_dir)
    print(f'Figures written to {out_dir}')
