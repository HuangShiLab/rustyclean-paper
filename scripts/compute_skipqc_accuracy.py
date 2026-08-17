#!/usr/bin/env python3
import csv, gzip, sys
from pathlib import Path

def read_fastq_ids(path):
    ids = set()
    opener = gzip.open if str(path).endswith('.gz') else open
    with opener(path, 'rt', encoding='utf-8', errors='ignore') as fh:
        for i, line in enumerate(fh):
            if i % 4 == 0:
                rid = line.split()[0][1:]
                rid = rid.split('/')[0].split('#')[0]
                ids.add(rid)
    return ids

def read_ground_truth(gt_path):
    host, microbe = set(), set()
    with open(gt_path, 'r', encoding='utf-8') as fh:
        for line in fh:
            line = line.strip()
            if not line or '\t' not in line:
                continue
            rid, label = line.split('\t', 1)
            rid = rid.split('/')[0].split('#')[0]
            (host if label.lower() == 'host' else microbe).add(rid)
    return host, microbe

def compute_metrics(host, microbe, kept):
    tp = len(kept & microbe)
    fp = len(kept & host)
    fn = len(microbe - kept)
    tn = len(host - kept)
    tot = tp + fp + tn + fn
    acc = (tp + tn) / tot
    prec = tp / (tp + fp) if (tp + fp) else 0
    rec = tp / (tp + fn) if (tp + fn) else 0
    f1 = 2 * prec * rec / (prec + rec) if (prec + rec) else 0
    return acc, prec, rec, f1, tp, fp, tn, fn

base = Path('/lustre1/g/aos_shihuang/rustyclean-paper')
data = Path('/scr/u/shihuang/rustyclean-paper/data/enhanced')
out_csv = base / 'results_100M_skipqc_matched' / 'accuracy.csv'
out_csv.parent.mkdir(parents=True, exist_ok=True)

with open(out_csv, 'w', newline='') as fh:
    w = csv.writer(fh)
    w.writerow(['dataset','rep','tool','accuracy','precision','recall','f1','tp','fp','tn','fn'])
    for ds in ['100M_50pct_high_lognormal_SE', '100M_90pct_high_lognormal_SE']:
        host, microbe = read_ground_truth(data / ds / 'ground_truth_labels.txt')
        clean_dir = base / 'rustyclean_auto_sylph_skipqc_100M_matched' / 'rustyclean_auto_sylph_skipqc' / ds / 'rep_1'
        clean = list(clean_dir.rglob('*_clean*.fastq.gz'))[0]
        kept = read_fastq_ids(clean)
        acc, prec, rec, f1, tp, fp, tn, fn = compute_metrics(host, microbe, kept)
        print(f'{ds} skipqc: f1={f1:.4f} precision={prec:.4f} recall={rec:.4f}')
        w.writerow([ds, 1, 'rustyclean_auto_sylph_skipqc', f'{acc:.6f}', f'{prec:.6f}', f'{rec:.6f}', f'{f1:.6f}', tp, fp, tn, fn])
