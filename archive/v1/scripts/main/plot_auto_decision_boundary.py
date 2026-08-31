#!/usr/bin/env python3
"""
Plot AUTO decision boundary: forced bowtie2 vs forced kraken2 runtime
as a function of host fraction, with the AUTO selection regions shaded.
"""

import sys
import re
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from pathlib import Path


def extract_host_pct(dataset_name):
    m = re.search(r'(\d+)pct', dataset_name)
    if m:
        return int(m.group(1))
    if '0pct' in dataset_name:
        return 0
    if '100pct' in dataset_name:
        return 100
    return None


def parse_runtime_seconds(val):
    if isinstance(val, (int, float)):
        return float(val)
    if isinstance(val, str):
        if val == 'unknown' or val == 'FAILED' or val == '':
            return None
        # m:ss or h:mm:ss
        parts = val.split(':')
        if len(parts) == 3:
            return float(parts[0]) * 3600 + float(parts[1]) * 60 + float(parts[2])
        elif len(parts) == 2:
            return float(parts[0]) * 60 + float(parts[1])
        else:
            return float(parts[0])
    return None


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <metrics_csv> <output_dir>", file=sys.stderr)
        sys.exit(1)

    csv_path = Path(sys.argv[1])
    out_dir = Path(sys.argv[2])
    out_dir.mkdir(parents=True, exist_ok=True)

    df = pd.read_csv(csv_path)
    df['runtime_seconds'] = df['runtime_seconds'].apply(parse_runtime_seconds)
    df['host_pct'] = df['dataset'].apply(extract_host_pct)
    df = df.dropna(subset=['runtime_seconds', 'host_pct'])

    # Summarize by mode and host_pct (mean over replicates if any)
    summary = df.groupby(['mode', 'host_pct'])['runtime_seconds'].mean().reset_index()

    bt = summary[summary['mode'] == 'bowtie2'].sort_values('host_pct')
    k2 = summary[summary['mode'] == 'kraken2'].sort_values('host_pct')

    fig, ax = plt.subplots(figsize=(6, 4))
    ax.plot(bt['host_pct'], bt['runtime_seconds'] / 60, marker='o', label='Bowtie2', color='#C75B5B')
    ax.plot(k2['host_pct'], k2['runtime_seconds'] / 60, marker='s', label='Kraken2', color='#4A90A4')

    # AUTO thresholds
    low_thr = 10.0
    high_thr = 30.0
    ax.axvline(low_thr, color='gray', linestyle='--', linewidth=0.8)
    ax.axvline(high_thr, color='gray', linestyle='--', linewidth=0.8)
    ax.text(low_thr + 0.5, ax.get_ylim()[1] * 0.95, 'low', fontsize=7, color='gray')
    ax.text(high_thr + 0.5, ax.get_ylim()[1] * 0.95, 'high', fontsize=7, color='gray')

    ax.set_xlabel('Host fraction (%)')
    ax.set_ylabel('Runtime (min)')
    ax.set_title('AUTO mode backend crossover (10 M reads)')
    ax.legend(frameon=False)
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)

    plt.tight_layout()
    out_png = out_dir / 'auto_decision_boundary.png'
    out_svg = out_dir / 'auto_decision_boundary.svg'
    plt.savefig(out_png, dpi=300)
    plt.savefig(out_svg)
    plt.close()

    print(f"Wrote {out_png} and {out_svg}")


if __name__ == '__main__':
    main()
