#!/usr/bin/env python3
"""
RustyClean 极简验证 — 结果分析脚本
用法: python analyze_minimal.py <data_dir> <results_dir>
"""

import sys
import os
import pandas as pd
import numpy as np

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

# Nature-style minimal rcParams
plt.rcParams.update({
    "font.family": "sans-serif",
    "font.sans-serif": ["Arial", "Helvetica", "DejaVu Sans"],
    "font.size": 7,
    "axes.labelsize": 8,
    "axes.titlesize": 9,
    "axes.spines.right": False,
    "axes.spines.top": False,
    "axes.linewidth": 0.8,
    "legend.frameon": False,
})

def parse_time(t):
    if pd.isna(t) or t == 'unknown':
        return np.nan
    parts = str(t).split(':')
    if len(parts) == 3:
        return int(parts[0])*3600 + int(parts[1])*60 + float(parts[2])
    elif len(parts) == 2:
        return int(parts[0])*60 + float(parts[1])
    try:
        return float(parts[0])
    except:
        return np.nan

def load_ground_truth(data_dir, dataset):
    gt_file = os.path.join(data_dir, dataset, 'ground_truth_labels.txt')
    if not os.path.exists(gt_file):
        return None
    labels = {}
    with open(gt_file) as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) == 2:
                labels[parts[0]] = parts[1]
    return labels

def read_fastq_ids(filepath):
    ids = set()
    import gzip
    opener = gzip.open if filepath.endswith('.gz') else open
    with opener(filepath, 'rt') as f:
        for i, line in enumerate(f):
            if i % 4 == 0:
                read_id = line.strip().split()[0][1:]
                ids.add(read_id)
    return ids

def find_outputs(results_dir, tool, dataset, rep):
    """Find all output FASTQ files. For PE data both R1 and R2 are returned."""
    tool_dir = os.path.join(results_dir, tool, f"{dataset}_rep{rep}")
    outputs = []
    if not os.path.exists(tool_dir):
        return outputs
    for root, dirs, files in os.walk(tool_dir):
        for f in files:
            if f.endswith('.fastq.gz') or f.endswith('.fastq'):
                outputs.append(os.path.join(root, f))
    return outputs

def compute_metrics(output_ids, ground_truth):
    TP, TN, FP, FN = 0, 0, 0, 0
    for read_id, true_label in ground_truth.items():
        in_output = read_id in output_ids
        if true_label == 'host':
            if in_output:
                TP += 1
            else:
                FN += 1
        else:
            if in_output:
                FP += 1
            else:
                TN += 1
    
    total = TP + TN + FP + FN
    accuracy = (TP + TN) / total if total > 0 else 0
    precision = TP / (TP + FP) if (TP + FP) > 0 else 0
    recall = TP / (TP + FN) if (TP + FN) > 0 else 0
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0
    
    return {'Accuracy': accuracy, 'Precision': precision, 'Recall': recall, 'F1': f1,
            'FP_rate': FP/total if total > 0 else 0, 'FN_rate': FN/total if total > 0 else 0}

def main():
    if len(sys.argv) < 3:
        print("Usage: python analyze_minimal.py <data_dir> <results_dir>")
        sys.exit(1)
    
    data_dir = sys.argv[1]
    results_dir = sys.argv[2]
    
    os.makedirs(os.path.join(results_dir, 'figures'), exist_ok=True)
    
    print("=" * 60)
    print("RustyClean 极简验证 — 结果分析")
    print("=" * 60)
    print()
    
    # 1. Performance analysis
    perf_file = os.path.join(results_dir, 'metrics', 'performance.csv')
    if os.path.exists(perf_file):
        df = pd.read_csv(perf_file)
        df['runtime_sec'] = df['runtime_seconds'].apply(parse_time)
        df['memory_mb'] = pd.to_numeric(df['max_memory_kb'], errors='coerce') / 1024
        
        print("【速度对比】")
        print(f"{'Dataset':<15} {'RustyClean':<12} {'KneadData':<12} {'Speedup':<8}")
        print("-" * 55)
        
        speedups = []
        for dataset in sorted(df['dataset'].unique()):
            rc = df[(df['dataset']==dataset) & (df['tool']=='rustyclean')]
            kd = df[(df['dataset']==dataset) & (df['tool']=='kneaddata')]
            
            rc_time = rc['runtime_sec'].values[0] if len(rc) > 0 else np.nan
            kd_time = kd['runtime_sec'].values[0] if len(kd) > 0 else np.nan
            
            rc_min = rc_time / 60 if rc_time > 0 else np.nan
            kd_min = kd_time / 60 if kd_time > 0 else np.nan
            speedup = kd_time / rc_time if rc_time > 0 else np.nan
            speedups.append((dataset, rc_min, kd_min, speedup))
            
            print(f"{dataset:<15} {rc_min:5.1f} min    {kd_min:6.1f} min   {speedup:5.1f}x")
        
        print()
        
        # Speedup figure
        fig, ax = plt.subplots(figsize=(6, 3.5))
        datasets = [s[0] for s in speedups]
        values = [s[3] for s in speedups]
        colors = ['#2ecc71' if v >= 20 else '#f39c12' if v >= 10 else '#e74c3c' for v in values]
        
        ax.barh(datasets, values, color=colors, edgecolor='white', linewidth=0.5)
        ax.axvline(x=10, color='#2ecc71', linestyle='--', linewidth=0.8, alpha=0.5)
        ax.axvline(x=17, color='gray', linestyle='--', linewidth=0.8, alpha=0.5)
        ax.set_xlabel('Speedup (×)', fontweight='bold')
        ax.set_title('RustyClean Speedup vs KneadData', fontweight='bold')
        
        for i, v in enumerate(values):
            if not np.isnan(v):
                ax.text(v + 0.5, i, f'{v:.1f}x', va='center', fontsize=7)
        
        plt.tight_layout()
        fig.savefig(os.path.join(results_dir, 'figures', 'figure_speedup.png'), dpi=300, bbox_inches='tight')
        fig.savefig(os.path.join(results_dir, 'figures', 'figure_speedup.svg'), bbox_inches='tight')
        plt.close()
        print("  保存: figure_speedup.png/svg")
        
        # Memory comparison
        print("\n【内存对比】")
        print(f"{'Dataset':<15} {'RustyClean':<12} {'KneadData':<12} {'Ratio':<8}")
        print("-" * 55)
        for dataset in sorted(df['dataset'].unique()):
            rc = df[(df['dataset']==dataset) & (df['tool']=='rustyclean')]
            kd = df[(df['dataset']==dataset) & (df['tool']=='kneaddata')]
            rc_mem = rc['memory_mb'].values[0] if len(rc) > 0 else np.nan
            kd_mem = kd['memory_mb'].values[0] if len(kd) > 0 else np.nan
            ratio = kd_mem / rc_mem if rc_mem > 0 else np.nan
            print(f"{dataset:<15} {rc_mem:6.1f} MB    {kd_mem:6.1f} MB    {ratio:5.1f}x")
    
    # 2. Accuracy analysis
    print("\n【准确性分析】")
    
    all_results = []
    for dataset in os.listdir(data_dir):
        ds_dir = os.path.join(data_dir, dataset)
        if not os.path.isdir(ds_dir) or not os.path.exists(os.path.join(ds_dir, 'completed.flag')):
            continue
        
        gt = load_ground_truth(data_dir, dataset)
        if not gt:
            continue
        
        for tool in ['rustyclean', 'kneaddata']:
            output_files = find_outputs(results_dir, tool, dataset, 1)
            if not output_files:
                continue
            
            # Collect read IDs from all output FASTQ files (PE: union of R1/R2)
            output_ids = set()
            for output_file in output_files:
                output_ids.update(read_fastq_ids(output_file))
            metrics = compute_metrics(output_ids, gt)
            
            result = {'Dataset': dataset, 'Tool': tool, **metrics}
            all_results.append(result)
            
            print(f"  {dataset} / {tool}: F1={metrics['F1']:.4f}, Precision={metrics['Precision']:.4f}, Recall={metrics['Recall']:.4f}")
    
    if all_results:
        acc_df = pd.DataFrame(all_results)
        acc_df.to_csv(os.path.join(results_dir, 'accuracy.csv'), index=False)
        
        # Summary
        summary = acc_df.groupby('Tool')[['Accuracy', 'Precision', 'Recall', 'F1']].mean()
        print("\n【准确性汇总】")
        print(summary.round(4).to_string())
        
        # Accuracy figure
        fig, axes = plt.subplots(1, 3, figsize=(9, 3))
        metrics = ['Precision', 'Recall', 'F1']
        colors = {'rustyclean': '#4A90A4', 'kneaddata': '#C75B5B'}
        
        for ax, metric in zip(axes, metrics):
            pivot = acc_df.pivot(index='Dataset', columns='Tool', values=metric)
            if 'rustyclean' in pivot.columns and 'kneaddata' in pivot.columns:
                x = np.arange(len(pivot))
                width = 0.35
                ax.bar(x - width/2, pivot['rustyclean'], width, label='RustyClean', color=colors['rustyclean'], edgecolor='white')
                ax.bar(x + width/2, pivot['kneaddata'], width, label='KneadData', color=colors['kneaddata'], edgecolor='white')
                ax.set_xticks(x)
                ax.set_xticklabels(pivot.index, rotation=45, ha='right', fontsize=6)
                ax.set_ylabel(metric, fontweight='bold')
                ax.set_ylim(0.8, 1.01)
                if metric == 'Precision':
                    ax.legend(loc='lower left')
        
        plt.tight_layout()
        fig.savefig(os.path.join(results_dir, 'figures', 'figure_accuracy.png'), dpi=300, bbox_inches='tight')
        plt.close()
        print("\n  保存: figure_accuracy.png")
    
    print()
    print("=" * 60)
    print("分析完成！")
    print(f"结果保存到: {results_dir}")
    print("=" * 60)

if __name__ == '__main__':
    main()
