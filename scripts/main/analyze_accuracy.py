#!/usr/bin/env python3
# =============================================================================
# RustyClean Benchmark - Accuracy Analysis
# =============================================================================
# Computes accuracy metrics (Precision, Recall, F1) for simulated data
# by comparing tool outputs against ground truth labels.
#
# Usage: python scripts/main/analyze_accuracy.py <data_dir> <results_dir> [output_dir]
# Example: python scripts/main/analyze_accuracy.py ./data/simulated ./results ./data/analysis

import os
import sys
import json
import gzip
from collections import defaultdict
import pandas as pd
import numpy as np

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

def parse_time_string(time_str):
    """Parse GNU time elapsed string (e.g., '1:23:45' or '0:12.34') to seconds."""
    if time_str == "unknown" or not time_str:
        return np.nan
    
    parts = time_str.split(':')
    if len(parts) == 3:  # H:MM:SS
        return int(parts[0]) * 3600 + int(parts[1]) * 60 + float(parts[2])
    elif len(parts) == 2:  # M:SS
        return int(parts[0]) * 60 + float(parts[1])
    else:
        try:
            return float(parts[0])
        except:
            return np.nan

def read_fastq_ids(filepath):
    """Read read IDs from FASTQ file (gzipped or plain)."""
    ids = set()

    def _read(handle):
        line_count = 0
        for line in handle:
            if line_count % 4 == 0:
                # Remove @ and trailing info, then strip /1, /2, #0/1, etc.
                read_id = line.strip().split()[0][1:]
                read_id = read_id.split('#')[0]
                read_id = read_id.rsplit('/', 1)[0]
                ids.add(read_id)
            line_count += 1

    if filepath.endswith('.gz'):
        try:
            with gzip.open(filepath, 'rt') as f:
                _read(f)
        except (gzip.BadGzipFile, OSError):
            # Some tools write plain FASTQ with a .gz extension
            with open(filepath, 'r') as f:
                _read(f)
    else:
        with open(filepath, 'r') as f:
            _read(f)

    return ids

def load_ground_truth(data_dir, dataset_name):
    """Load ground truth labels from simulated data."""
    gt_file = os.path.join(data_dir, dataset_name, 'ground_truth_labels.txt')
    
    if not os.path.exists(gt_file):
        print(f"WARNING: Ground truth file not found: {gt_file}")
        return None
    
    labels = {}
    with open(gt_file, 'r') as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) == 2:
                read_id, label = parts
                # Normalize ID to match FASTQ ID normalization in read_fastq_ids:
                # strip /1, /2, #0/1, etc.
                read_id = read_id.split('#')[0]
                read_id = read_id.rsplit('/', 1)[0]
                labels[read_id] = label

    return labels

def compute_accuracy_metrics(output_ids, ground_truth, removed_by_tool=True):
    """
    Compute accuracy metrics.
    
    Args:
        output_ids: Set of read IDs in tool output (clean reads)
        ground_truth: Dict of {read_id: label} where label is 'host' or 'microbe'
        removed_by_tool: True if output_ids are the removed reads, False if kept reads
    
    Returns:
        dict with TP, TN, FP, FN, Accuracy, Precision, Recall, F1
    """
    TP, TN, FP, FN = 0, 0, 0, 0
    
    for read_id, true_label in ground_truth.items():
        in_output = read_id in output_ids
        
        if removed_by_tool:
            # Tool output is removed reads
            if true_label == 'host':
                if in_output:
                    TP += 1  # Correctly removed host
                else:
                    FN += 1  # Missed host
            else:  # microbe
                if in_output:
                    FP += 1  # Incorrectly removed microbe
                else:
                    TN += 1  # Correctly kept microbe
        else:
            # Tool output is kept reads
            if true_label == 'host':
                if in_output:
                    FN += 1  # Incorrectly kept host
                else:
                    TP += 1  # Correctly removed host
            else:  # microbe
                if in_output:
                    TN += 1  # Correctly kept microbe
                else:
                    FP += 1  # Incorrectly removed microbe
    
    total = TP + TN + FP + FN
    accuracy = (TP + TN) / total if total > 0 else 0
    precision = TP / (TP + FP) if (TP + FP) > 0 else 0
    recall = TP / (TP + FN) if (TP + FN) > 0 else 0
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0
    
    host_remaining = FN / (TP + FN) if (TP + FN) > 0 else 0
    microbe_loss = FP / (TN + FP) if (TN + FP) > 0 else 0
    
    return {
        'TP': TP, 'TN': TN, 'FP': FP, 'FN': FN,
        'Accuracy': accuracy,
        'Precision': precision,
        'Recall': recall,
        'F1': f1,
        'Host_Remaining_Rate': host_remaining,
        'Microbe_Loss_Rate': microbe_loss,
        'Total_Reads': total
    }

def find_tool_outputs(results_dir, tool, dataset, rep):
    """Find all output FASTQ files from a tool.
    
    Returns a list of paths. For paired-end data, both R1 and R2 are returned.
    """
    tool_dir = os.path.join(results_dir, tool, f"{dataset}_rep{rep}")
    outputs = []
    
    if tool == 'rustyclean':
        for root, dirs, files in os.walk(tool_dir):
            for f in files:
                if f.endswith('.fastq.gz') or f.endswith('.fastq'):
                    outputs.append(os.path.join(root, f))
    elif tool == 'kneaddata':
        for root, dirs, files in os.walk(tool_dir):
            for f in files:
                # KneadData final clean outputs contain 'clean' but not 'contam'/'trim'.
                if ('clean' in f and
                    not 'contam' in f and
                    not 'trim' in f and
                    (f.endswith('.fastq.gz') or f.endswith('.fastq'))):
                    outputs.append(os.path.join(root, f))
    
    return outputs

# ---------------------------------------------------------------------------
# Main analysis
# ---------------------------------------------------------------------------

def main():
    if len(sys.argv) < 3:
        print("Usage: python analyze_accuracy.py <data_dir> <results_dir> [output_dir]")
        sys.exit(1)
    
    data_dir = sys.argv[1]
    results_dir = sys.argv[2]
    output_dir = sys.argv[3] if len(sys.argv) > 3 else os.path.join(results_dir, 'analysis')
    
    os.makedirs(output_dir, exist_ok=True)
    
    print("=" * 60)
    print("RustyClean Benchmark - Accuracy Analysis")
    print("=" * 60)
    print(f"Data directory: {data_dir}")
    print(f"Results directory: {results_dir}")
    print(f"Output directory: {output_dir}")
    print()
    
    # Find all datasets
    datasets = []
    for item in os.listdir(data_dir):
        if os.path.isdir(os.path.join(data_dir, item)) and os.path.exists(
            os.path.join(data_dir, item, 'completed.flag')):
            datasets.append(item)
    
    print(f"Found {len(datasets)} datasets: {', '.join(datasets)}")
    print()
    
    # Analyze each dataset
    all_results = []
    
    for dataset in datasets:
        print(f"--- Dataset: {dataset} ---")
        
        # Load ground truth
        ground_truth = load_ground_truth(data_dir, dataset)
        if not ground_truth:
            print(f"  Skipping (no ground truth)")
            continue
        
        print(f"  Ground truth: {len(ground_truth)} reads")
        
        for tool in ['rustyclean', 'kneaddata']:
            for rep in [1, 2, 3]:
                output_files = find_tool_outputs(results_dir, tool, dataset, rep)
                
                if not output_files:
                    print(f"  {tool} rep{rep}: Output not found")
                    continue
                
                print(f"  Analyzing {tool} rep{rep}...")
                
                # Collect read IDs from all output FASTQ files (PE: union of R1/R2)
                output_ids = set()
                for output_file in output_files:
                    output_ids.update(read_fastq_ids(output_file))
                
                # Determine if output is removed or kept reads
                # For rustyclean: output is clean (kept) reads
                # For kneaddata: output is clean (kept) reads
                removed_by_tool = False
                
                metrics = compute_accuracy_metrics(output_ids, ground_truth, removed_by_tool)
                
                result = {
                    'Dataset': dataset,
                    'Tool': tool,
                    'Replicate': rep,
                    **metrics
                }
                all_results.append(result)
                
                print(f"    Accuracy: {metrics['Accuracy']:.4f}, Precision: {metrics['Precision']:.4f}, "
                      f"Recall: {metrics['Recall']:.4f}, F1: {metrics['F1']:.4f}")
    
    # Create results dataframe
    df = pd.DataFrame(all_results)
    
    if df.empty:
        print("\nNo results to analyze. Please run the benchmark first.")
        return
    
    # Save raw results
    output_csv = os.path.join(output_dir, 'accuracy.csv')
    df.to_csv(output_csv, index=False)
    print(f"\nAccuracy results saved: {output_csv}")
    
    # Compute summary statistics
    print("\n" + "=" * 60)
    print("Summary Statistics (mean ± std)")
    print("=" * 60)
    
    summary = df.groupby(['Dataset', 'Tool']).agg({
        'Accuracy': ['mean', 'std'],
        'Precision': ['mean', 'std'],
        'Recall': ['mean', 'std'],
        'F1': ['mean', 'std'],
        'Host_Remaining_Rate': ['mean', 'std'],
        'Microbe_Loss_Rate': ['mean', 'std']
    }).round(4)
    
    print(summary.to_string())
    
    # Save summary
    summary_csv = os.path.join(output_dir, 'accuracy_summary.csv')
    summary.to_csv(summary_csv)
    print(f"\nSummary saved: {summary_csv}")
    
    # Overall comparison
    print("\n" + "=" * 60)
    print("Overall Tool Comparison")
    print("=" * 60)
    
    overall = df.groupby('Tool').agg({
        'Accuracy': 'mean',
        'Precision': 'mean',
        'Recall': 'mean',
        'F1': 'mean',
        'Host_Remaining_Rate': 'mean',
        'Microbe_Loss_Rate': 'mean'
    }).round(4)
    
    print(overall.to_string())
    print()
    
    # Print key findings
    rc_f1 = overall.loc['rustyclean', 'F1'] if 'rustyclean' in overall.index else 0
    kd_f1 = overall.loc['kneaddata', 'F1'] if 'kneaddata' in overall.index else 0
    
    rc_precision = overall.loc['rustyclean', 'Precision'] if 'rustyclean' in overall.index else 0
    kd_precision = overall.loc['kneaddata', 'Precision'] if 'kneaddata' in overall.index else 0
    
    rc_recall = overall.loc['rustyclean', 'Recall'] if 'rustyclean' in overall.index else 0
    kd_recall = overall.loc['kneaddata', 'Recall'] if 'kneaddata' in overall.index else 0
    
    print(f"Key Findings:")
    print(f"  F1-Score: RustyClean={rc_f1:.4f}, KneadData={kd_f1:.4f}")
    print(f"  Precision: RustyClean={rc_precision:.4f}, KneadData={kd_precision:.4f}")
    print(f"  Recall: RustyClean={rc_recall:.4f}, KneadData={kd_recall:.4f}")
    
    if rc_f1 > 0 and kd_f1 > 0:
        f1_diff = abs(rc_f1 - kd_f1)
        if f1_diff < 0.01:
            print(f"  -> Comparable accuracy (F1 difference: {f1_diff:.4f})")
        elif rc_f1 > kd_f1:
            print(f"  -> RustyClean higher F1 by {f1_diff:.4f}")
        else:
            print(f"  -> KneadData higher F1 by {f1_diff:.4f}")
    
    print()

if __name__ == '__main__':
    main()
