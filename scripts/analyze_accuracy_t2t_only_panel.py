#!/usr/bin/env python3
"""
Accuracy analysis for T2T-only matched panel.
Handles RustyClean (rep_N), Hostile and KneadData output structures.
"""

import os
import sys
import subprocess
import tempfile
from pathlib import Path
import pandas as pd


def normalize_id(rid):
    rid = rid.split()[0]
    for suffix in ['#0/1', '#0/2', '/1', '/2']:
        if rid.endswith(suffix):
            rid = rid[:-len(suffix)]
    return rid


def extract_fastq_ids(fq_path, out_ids_path):
    fq_path = str(fq_path)
    if fq_path.endswith('.gz'):
        cmd = f"zcat '{fq_path}' | awk 'NR%4==1{{sub(/^[@>]/, \"\"); print $1}}'"
    else:
        cmd = f"awk 'NR%4==1{{sub(/^[@>]/, \"\"); print $1}}' '{fq_path}'"
    with open(out_ids_path, 'w') as fh:
        subprocess.run(cmd, shell=True, stdout=fh, check=True)


def load_ground_truth(data_dir, dataset_name):
    gt_file = Path(data_dir) / dataset_name / 'ground_truth_labels.txt'
    if not gt_file.exists():
        return None
    labels = {}
    with open(gt_file) as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) == 2:
                labels[parts[0]] = parts[1]
    return labels


def compute_metrics(output_ids, ground_truth):
    TP = TN = FP = FN = 0
    for rid, true_label in ground_truth.items():
        in_output = rid in output_ids
        is_host = true_label.lower().startswith('host')
        if is_host:
            FN += in_output
            TP += not in_output
        else:
            TN += in_output
            FP += not in_output
    total = TP + TN + FP + FN
    return {
        'tp': TP, 'tn': TN, 'fp': FP, 'fn': FN,
        'accuracy': (TP + TN) / total if total else 0,
        'precision': TP / (TP + FP) if (TP + FP) else 0,
        'recall': TP / (TP + FN) if (TP + FN) else 0,
        'f1': 2 * TP / (2 * TP + FP + FN) if (2 * TP + FP + FN) else 0,
    }


def find_clean_fastq_rc(rep_dir):
    """RustyClean output: look for final clean FASTQ under rep_N."""
    candidates = []
    for p in rep_dir.rglob('*.fastq.gz'):
        rel = str(p.relative_to(rep_dir))
        skip_parts = ['.checkpoints', '.work', 'work/', 'trimmed_', 'auto_survey_', 'recheck_',
                      'bowtie2.', 'kraken2.', 'minimap2.', 'classified.', 'unclassified.', 'contam']
        if any(part in rel.lower() for part in skip_parts):
            continue
        fname = p.name.lower()
        if 'clean' in fname or 'rmhost' in fname or 'rm_host' in fname:
            candidates.append(p)
    if not candidates:
        return None
    candidates.sort(key=lambda p: (not 'clean' in p.name.lower(), len(str(p.relative_to(rep_dir)))))
    return candidates[0]


def find_clean_fastq_simple(tool_dir):
    """Hostile/KneadData output: look for clean FASTQ directly under dataset dir."""
    candidates = []
    for p in tool_dir.rglob('*.fastq.gz'):
        fname = p.name.lower()
        if 'clean' in fname or 'rmhost' in fname or 'rm_host' in fname:
            candidates.append(p)
    if not candidates:
        return None
    # Prefer files with 'clean' in name, then shortest path
    candidates.sort(key=lambda p: (not 'clean' in p.name.lower(), len(str(p.relative_to(tool_dir)))))
    return candidates[0]


def process_tool(data_dir, results_dir, tool_name, rows):
    tool_dir = results_dir / tool_name
    if not tool_dir.exists():
        print(f"Tool dir not found: {tool_dir}", file=sys.stderr)
        return

    datasets = [d.name for d in sorted(tool_dir.iterdir()) if d.is_dir()]
    print(f"Tool: {tool_name} | Datasets: {datasets}", flush=True)

    with tempfile.TemporaryDirectory() as tmpdir:
        for dataset in datasets:
            gt = load_ground_truth(data_dir, dataset)
            if not gt:
                print(f"  {dataset}: no ground truth, skipping", flush=True)
                continue
            gt_norm = {normalize_id(k): v for k, v in gt.items()}
            dataset_dir = tool_dir / dataset

            if tool_name == 'rustyclean_t2t_only':
                rep_dirs = sorted([d for d in dataset_dir.iterdir() if d.is_dir() and d.name.startswith('rep_')])
                if not rep_dirs:
                    print(f"  {dataset}: no rep dirs, skipping", flush=True)
                    continue
                for rep_dir in rep_dirs:
                    rep = rep_dir.name.replace('rep_', '')
                    fq = find_clean_fastq_rc(rep_dir)
                    if not fq:
                        print(f"  {dataset} {rep_dir.name}: no clean FASTQ found", flush=True)
                        continue
                    _process_fq(fq, tmpdir, dataset, rep, tool_name, gt_norm, rows)
            else:
                fq = find_clean_fastq_simple(dataset_dir)
                if not fq:
                    print(f"  {dataset}: no clean FASTQ found", flush=True)
                    continue
                _process_fq(fq, tmpdir, dataset, '1', tool_name, gt_norm, rows)


def _process_fq(fq, tmpdir, dataset, rep, tool_name, gt_norm, rows):
    ids_file = Path(tmpdir) / f"{tool_name}_{dataset}_{rep}.ids"
    extract_fastq_ids(fq, ids_file)
    output_ids = set()
    with open(ids_file) as fh:
        for line in fh:
            output_ids.add(normalize_id(line.strip()))

    metrics = compute_metrics(output_ids, gt_norm)
    rows.append({
        'dataset': dataset,
        'rep': rep,
        'tool': tool_name,
        **metrics,
    })
    print(f"  {dataset} rep{rep}: f1={metrics['f1']:.4f} precision={metrics['precision']:.4f} recall={metrics['recall']:.4f}", flush=True)


def main():
    if len(sys.argv) < 4:
        print(f"Usage: {sys.argv[0]} <data_dir> <results_dir> <output_dir>", file=sys.stderr)
        sys.exit(1)

    data_dir = Path(sys.argv[1])
    results_dir = Path(sys.argv[2])
    output_dir = Path(sys.argv[3])
    output_dir.mkdir(parents=True, exist_ok=True)

    rows = []
    for tool in ['rustyclean_t2t_only', 'hostile', 'kneaddata']:
        process_tool(data_dir, results_dir, tool, rows)

    df = pd.DataFrame(rows)
    if df.empty:
        print("No results found.")
        sys.exit(1)

    out_csv = output_dir / 'accuracy_t2t_only_panel.csv'
    df.to_csv(out_csv, index=False)
    print(f"Wrote {out_csv}", flush=True)


if __name__ == '__main__':
    main()
