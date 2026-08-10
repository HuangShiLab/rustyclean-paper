#!/usr/bin/env python3
# =============================================================================
# RustyClean Benchmark - Performance Analysis & Visualization
# =============================================================================
# Analyzes and visualizes benchmark performance results.
#
# Usage: python scripts/analyze_performance.py <results_dir> [output_dir]
# Example: python scripts/analyze_performance.py ./results ./analysis

import os
import sys
import re
import pandas as pd
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import seaborn as sns
from scipy import stats

# Set style
sns.set_style("whitegrid")
sns.set_context("paper", font_scale=1.3)

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

def parse_time_to_seconds(time_str):
    """Parse GNU time elapsed string to seconds."""
    if not time_str or time_str == 'unknown':
        return np.nan
    
    time_str = str(time_str).strip()
    
    # Format: H:MM:SS or M:SS or SS.SS
    parts = time_str.split(':')
    if len(parts) == 3:
        return int(parts[0]) * 3600 + int(parts[1]) * 60 + float(parts[2])
    elif len(parts) == 2:
        return int(parts[0]) * 60 + float(parts[1])
    else:
        try:
            return float(parts[0])
        except:
            return np.nan

def load_performance_data(results_dir):
    """Load performance metrics from CSV."""
    perf_file = os.path.join(results_dir, 'metrics', 'performance.csv')
    
    if not os.path.exists(perf_file):
        print(f"ERROR: Performance file not found: {perf_file}")
        return None
    
    df = pd.read_csv(perf_file)
    
    # Parse runtime
    df['runtime_seconds'] = df['runtime_seconds'].apply(parse_time_to_seconds)
    
    # Convert memory to MB (coerce non-numeric values such as 'unknown')
    df['max_memory_kb'] = pd.to_numeric(df['max_memory_kb'], errors='coerce')
    df['max_memory_mb'] = df['max_memory_kb'] / 1024
    
    return df

def load_file_sizes(results_dir):
    """Load output file sizes."""
    size_file = os.path.join(results_dir, 'metrics', 'file_sizes.csv')
    
    if not os.path.exists(size_file):
        return None
    
    df = pd.read_csv(size_file, names=['tool', 'dataset', 'rep', 'metric', 'value'])
    df['output_size_mb'] = df['value'] / (1024 * 1024)
    
    return df

def create_comparison_figure(df, metric, ylabel, title, output_path, log_scale=False):
    """Create comparison bar plot."""
    fig, ax = plt.subplots(figsize=(10, 6))
    
    # Summary statistics
    summary = df.groupby(['dataset', 'tool'])[metric].agg(['mean', 'std']).reset_index()
    
    # Create grouped bar plot
    datasets = sorted(df['dataset'].unique())
    tools = sorted(df['tool'].unique())
    
    x = np.arange(len(datasets))
    width = 0.35
    
    for i, tool in enumerate(tools):
        tool_data = summary[summary['tool'] == tool]
        means = tool_data['mean'].values
        stds = tool_data['std'].values
        
        offset = (i - 0.5) * width
        ax.bar(x + offset, means, width, yerr=stds, label=tool, capsize=5)
    
    ax.set_xlabel('Dataset')
    ax.set_ylabel(ylabel)
    ax.set_title(title)
    ax.set_xticks(x)
    ax.set_xticklabels(datasets, rotation=45, ha='right')
    ax.legend()
    
    if log_scale:
        ax.set_yscale('log')
    
    plt.tight_layout()
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    plt.close()
    
    print(f"  Saved: {output_path}")

def create_speedup_figure(df, output_path):
    """Create speedup comparison figure."""
    summary = df.groupby(['dataset', 'tool'])['runtime_seconds'].mean().reset_index()
    
    # Pivot to get rustyclean and kneaddata side by side
    pivot = summary.pivot(index='dataset', columns='tool', values='runtime_seconds')
    
    if 'rustyclean' not in pivot.columns or 'kneaddata' not in pivot.columns:
        print("WARNING: Missing tool data for speedup calculation")
        return
    
    pivot['speedup'] = pivot['kneaddata'] / pivot['rustyclean']
    
    fig, ax = plt.subplots(figsize=(8, 6))
    
    colors = ['#2ecc71' if x >= 10 else '#f39c12' if x >= 5 else '#e74c3c' for x in pivot['speedup']]
    
    ax.barh(pivot.index, pivot['speedup'], color=colors)
    ax.axvline(x=1, color='red', linestyle='--', alpha=0.7, label='No speedup')
    ax.axvline(x=10, color='green', linestyle='--', alpha=0.7, label='10x speedup')
    ax.set_xlabel('Speedup (KneadData time / RustyClean time)')
    ax.set_title('RustyClean Speedup vs KneadData')
    ax.legend()
    
    # Add value labels
    for i, (idx, row) in enumerate(pivot.iterrows()):
        ax.text(row['speedup'] + 0.5, i, f"{row['speedup']:.1f}x", va='center')
    
    plt.tight_layout()
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    plt.close()
    
    print(f"  Saved: {output_path}")

def create_memory_comparison(df, output_path):
    """Create memory usage comparison."""
    summary = df.groupby(['dataset', 'tool'])['max_memory_mb'].mean().reset_index()
    pivot = summary.pivot(index='dataset', columns='tool', values='max_memory_mb')
    
    if 'rustyclean' not in pivot.columns or 'kneaddata' not in pivot.columns:
        return
    
    pivot['memory_ratio'] = pivot['kneaddata'] / pivot['rustyclean']
    
    fig, ax = plt.subplots(figsize=(8, 6))
    
    x = np.arange(len(pivot.index))
    width = 0.35
    
    ax.bar(x - width/2, pivot['rustyclean'], width, label='RustyClean', color='#3498db')
    ax.bar(x + width/2, pivot['kneaddata'], width, label='KneadData', color='#e74c3c')
    
    ax.set_xlabel('Dataset')
    ax.set_ylabel('Peak Memory (MB)')
    ax.set_title('Peak Memory Usage Comparison')
    ax.set_xticks(x)
    ax.set_xticklabels(pivot.index, rotation=45, ha='right')
    ax.legend()
    
    plt.tight_layout()
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    plt.close()
    
    print(f"  Saved: {output_path}")

def create_throughput_figure(df, output_path):
    """Create throughput comparison (reads/second)."""
    # Load metadata to get total reads
    # For now, estimate from dataset name
    
    def extract_reads(dataset_name):
        """Extract number of reads from dataset name."""
        match = re.match(r'(\d+)[M]', dataset_name)
        if match:
            return int(match.group(1)) * 1000000
        return 0
    
    df['total_reads'] = df['dataset'].apply(extract_reads)
    df['throughput'] = df['total_reads'] / df['runtime_seconds']
    
    summary = df.groupby(['dataset', 'tool'])['throughput'].mean().reset_index()
    
    fig, ax = plt.subplots(figsize=(10, 6))
    
    sns.barplot(data=summary, x='dataset', y='throughput', hue='tool', ax=ax)
    ax.set_xlabel('Dataset')
    ax.set_ylabel('Throughput (reads/second)')
    ax.set_title('Processing Throughput Comparison')
    ax.set_yscale('log')
    plt.xticks(rotation=45, ha='right')
    plt.legend(title='Tool')
    
    plt.tight_layout()
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    plt.close()
    
    print(f"  Saved: {output_path}")

def create_summary_table(df, output_path):
    """Create summary comparison table."""
    summary = df.groupby('tool').agg({
        'runtime_seconds': ['mean', 'std', 'min', 'max'],
        'max_memory_mb': ['mean', 'std', 'min', 'max']
    }).round(2)
    
    # Flatten column names
    summary.columns = ['_'.join(col).strip() for col in summary.columns.values]
    summary = summary.reset_index()
    
    # Calculate speedup and memory ratio
    if 'rustyclean' in summary['tool'].values and 'kneaddata' in summary['tool'].values:
        rc_time = summary[summary['tool'] == 'rustyclean']['runtime_seconds_mean'].values[0]
        kd_time = summary[summary['tool'] == 'kneaddata']['runtime_seconds_mean'].values[0]
        
        rc_mem = summary[summary['tool'] == 'rustyclean']['max_memory_mb_mean'].values[0]
        kd_mem = summary[summary['tool'] == 'kneaddata']['max_memory_mb_mean'].values[0]
        
        print(f"\nOverall Comparison:")
        print(f"  Average Runtime:")
        print(f"    RustyClean: {rc_time:.1f} seconds")
        print(f"    KneadData: {kd_time:.1f} seconds")
        print(f"    Speedup: {kd_time/rc_time:.1f}x")
        print(f"")
        print(f"  Average Peak Memory:")
        print(f"    RustyClean: {rc_mem:.1f} MB")
        print(f"    KneadData: {kd_mem:.1f} MB")
        print(f"    Memory Ratio: {kd_mem/rc_mem:.1f}x")
    
    # Save to CSV
    summary.to_csv(output_path, index=False)
    print(f"  Summary table saved: {output_path}")
    
    return summary

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    if len(sys.argv) < 2:
        print("Usage: python analyze_performance.py <results_dir> [output_dir]")
        sys.exit(1)
    
    results_dir = sys.argv[1]
    output_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(results_dir, 'analysis')
    
    os.makedirs(output_dir, exist_ok=True)
    figures_dir = os.path.join(output_dir, 'figures')
    os.makedirs(figures_dir, exist_ok=True)
    
    print("=" * 60)
    print("RustyClean Benchmark - Performance Analysis")
    print("=" * 60)
    print(f"Results: {results_dir}")
    print(f"Output: {output_dir}")
    print()
    
    # Load data
    df = load_performance_data(results_dir)
    if df is None or df.empty:
        print("No performance data found.")
        return
    
    print(f"Loaded {len(df)} performance records")
    print(f"Tools: {', '.join(df['tool'].unique())}")
    print(f"Datasets: {', '.join(df['dataset'].unique())}")
    print()
    
    # Generate figures
    print("Generating figures...")
    
    # Runtime comparison
    create_comparison_figure(
        df, 'runtime_seconds', 'Runtime (seconds)',
        'Runtime Comparison', os.path.join(figures_dir, '01_runtime_comparison.png'),
        log_scale=True
    )
    
    # Speedup
    create_speedup_figure(df, os.path.join(figures_dir, '02_speedup.png'))
    
    # Memory comparison
    create_memory_comparison(df, os.path.join(figures_dir, '03_memory_comparison.png'))
    
    # Throughput
    create_throughput_figure(df, os.path.join(figures_dir, '04_throughput.png'))
    
    # Summary table
    print("\nGenerating summary...")
    create_summary_table(df, os.path.join(output_dir, 'performance_summary.csv'))
    
    # Statistical tests
    print("\nStatistical Tests:")
    for dataset in df['dataset'].unique():
        rc_data = df[(df['dataset'] == dataset) & (df['tool'] == 'rustyclean')]['runtime_seconds']
        kd_data = df[(df['dataset'] == dataset) & (df['tool'] == 'kneaddata')]['runtime_seconds']
        
        if len(rc_data) >= 2 and len(kd_data) >= 2:
            # Wilcoxon rank-sum test (Mann-Whitney U)
            statistic, p_value = stats.ranksums(kd_data, rc_data)
            significance = "***" if p_value < 0.001 else "**" if p_value < 0.01 else "*" if p_value < 0.05 else "ns"
            
            print(f"  {dataset}: p={p_value:.4f} ({significance})")
    
    print()
    print(f"All figures saved to: {figures_dir}")
    print(f"Analysis complete!")

if __name__ == '__main__':
    main()
