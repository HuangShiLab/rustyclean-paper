#!/usr/bin/env python3
"""Generate updated publication figures for RustyClean manuscript."""
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
    'rustyclean': '#4A90A4',
    'hostile': '#C75B5B',
    'kneaddata': '#D4A373',
}


def plot_matched_panel_runtime(out_dir):
    """Figure: runtime comparison on matched panel."""
    data = {
        'dataset': ['30M / 50%', '60M / 90%', '100M / 50%', '100M / 90%'],
        'rustyclean': [4.5, 8.2, 14.9, 13.4],
        'hostile': [5.8, 11.9, 27.8, 22.5],
        'kneaddata': [38.0, 104.3, 224.9, 241.6],
    }
    df = pd.DataFrame(data)

    fig, ax = plt.subplots(figsize=(8.5, 6.0))
    x = np.arange(len(df))
    width = 0.25

    ax.bar(x - width, df['rustyclean'], width, label='RustyClean', color=COLORS['rustyclean'])
    ax.bar(x, df['hostile'], width, label='Hostile', color=COLORS['hostile'])
    ax.bar(x + width, df['kneaddata'], width, label='KneadData', color=COLORS['kneaddata'])

    ax.set_ylabel('Runtime (minutes)')
    ax.set_title('Host-depletion runtime on matched simulated panel')
    ax.set_xticks(x)
    ax.set_xticklabels(df['dataset'])
    ax.legend()
    ax.set_yscale('log')
    ax.set_ylim(1, 400)

    plt.tight_layout()
    for ext in ['png', 'svg', 'pdf']:
        plt.savefig(os.path.join(out_dir, f'fig_matched_panel_runtime.{ext}'), dpi=300)
    plt.close()


def plot_matched_panel_memory(out_dir):
    """Figure: memory comparison on matched panel."""
    data = {
        'dataset': ['30M / 50%', '60M / 90%', '100M / 50%', '100M / 90%'],
        'rustyclean': [15.5, 15.5, 15.6, 15.5],
        'hostile': [3.6, 3.6, 3.6, 3.6],
        'kneaddata': [1.1, 1.1, 1.1, 1.1],
    }
    df = pd.DataFrame(data)

    fig, ax = plt.subplots(figsize=(8.5, 6.0))
    x = np.arange(len(df))
    width = 0.25

    ax.bar(x - width, df['rustyclean'], width, label='RustyClean', color=COLORS['rustyclean'])
    ax.bar(x, df['hostile'], width, label='Hostile', color=COLORS['hostile'])
    ax.bar(x + width, df['kneaddata'], width, label='KneadData', color=COLORS['kneaddata'])

    ax.set_ylabel('Peak memory (GB)')
    ax.set_title('Peak memory on matched simulated panel')
    ax.set_xticks(x)
    ax.set_xticklabels(df['dataset'])
    ax.legend()
    ax.set_ylim(0, 20)

    plt.tight_layout()
    for ext in ['png', 'svg', 'pdf']:
        plt.savefig(os.path.join(out_dir, f'fig_matched_panel_memory.{ext}'), dpi=300)
    plt.close()


def plot_f1_by_host(out_dir):
    """Figure: F1 by host fraction for RustyClean default backend."""
    host_pct = [0, 1, 5, 10, 30, 50, 70, 90, 99]
    f1 = [0.9995, 0.9998, 0.9998, 0.9974, 0.9994, 0.9975, 0.9987, 0.9963, 0.9796]

    fig, ax = plt.subplots(figsize=(8.5, 6.0))
    ax.plot(host_pct, f1, marker='o', color=COLORS['rustyclean'], linewidth=1.5, markersize=5)
    ax.axhline(0.99, color='gray', linestyle='--', linewidth=0.8, alpha=0.7)
    ax.set_xlabel('Host fraction (%)')
    ax.set_ylabel('F1 score')
    ax.set_title('RustyClean accuracy across host fractions')
    ax.set_ylim(0.97, 1.0005)
    ax.set_xscale('log')
    ax.set_xticks(host_pct)
    ax.set_xticklabels([str(p) for p in host_pct])

    plt.tight_layout()
    for ext in ['png', 'svg', 'pdf']:
        plt.savefig(os.path.join(out_dir, f'fig_f1_by_host_fraction.{ext}'), dpi=300)
    plt.close()


def plot_cross_species(out_dir):
    """Figure: cross-species F1 comparison."""
    hosts = ['human', 'monkey', 'mouse', 'rat', 'pig', 'rice']
    rc_f1 = [0.9999, 0.9999, 0.9998, 0.9999, 0.9999, 0.9997]
    kd_f1 = [0.9959, 0.9960, 0.9960, 0.9960, 0.9960, 0.9960]

    fig, ax = plt.subplots(figsize=(8.5, 6.0))
    x = np.arange(len(hosts))
    width = 0.35

    ax.bar(x - width/2, rc_f1, width, label='RustyClean', color=COLORS['rustyclean'])
    ax.bar(x + width/2, kd_f1, width, label='KneadData', color=COLORS['kneaddata'])

    ax.set_ylabel('F1 score')
    ax.set_title('Cross-species host depletion accuracy')
    ax.set_xticks(x)
    ax.set_xticklabels(hosts)
    ax.legend()
    ax.set_ylim(0.994, 1.0002)

    plt.tight_layout()
    for ext in ['png', 'svg', 'pdf']:
        plt.savefig(os.path.join(out_dir, f'fig_cross_species.{ext}'), dpi=300)
    plt.close()


if __name__ == '__main__':
    out_dir = sys.argv[1] if len(sys.argv) > 1 else 'figures_updated'
    os.makedirs(out_dir, exist_ok=True)
    plot_matched_panel_runtime(out_dir)
    plot_matched_panel_memory(out_dir)
    plot_f1_by_host(out_dir)
    plot_cross_species(out_dir)
    print(f'Figures written to {out_dir}')
