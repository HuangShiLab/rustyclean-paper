#!/usr/bin/env python3
import csv, glob, re
from pathlib import Path

def elapsed_seconds(path):
    text=Path(path).read_text(errors='ignore')
    for line in text.splitlines():
        if 'Elapsed (wall clock) time' in line:
            value=line.split()[-1].strip()
            parts=[float(x) for x in value.split(':')]
            return sum(x*(60**i) for i,x in enumerate(reversed(parts)))
    raise FileNotFoundError(path)

root=Path('/lustre1/g/aos_shihuang/rustyclean-paper/runs/unresolved_controls/production_index_comparison')
for metric_path in glob.glob(str(root/'metrics'/'*.tsv')):
    rows=[]; fields=None
    with open(metric_path,newline='') as f:
        reader=csv.DictReader(f); fields=reader.fieldnames; rows=list(reader)
    for row in rows:
        tool=row['tool']; dataset=row['dataset']; rep=row['replicate']
        timefile=root/'logs'/f'{dataset}.{tool}.rep{rep}.time'
        row['runtime_s']=f'{elapsed_seconds(timefile):.6f}'
    with open(metric_path,'w',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=fields,lineterminator='\n'); writer.writeheader(); writer.writerows(rows)
    print(metric_path)
