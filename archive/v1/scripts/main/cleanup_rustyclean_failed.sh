#!/bin/bash
# Run this as yfz96 before resubmitting RustyClean jobs.
# It removes failed checkpoints and failed-sample logs so the corrected script can start fresh.

set -euo pipefail

OUTDIR="/lustre1/g/aos_shihuang/data/LU/results/rustyclean_out"

cd "${OUTDIR}" || exit 1

# Remove failed-sample logs
rm -f rustyclean_sample_list_part*_failed_samples.txt

# Remove checkpoints only for samples that do NOT have clean output
python3 - <<'PY'
from pathlib import Path
out = Path('.')
removed = 0
kept = 0
for d in out.iterdir():
    if d.is_dir() and d.name.startswith('U'):
        has_clean = any(d.rglob('*_clean_R1.fastq.gz'))
        chk = d / '.rustyclean_checkpoints'
        if not has_clean and chk.exists():
            import shutil
            shutil.rmtree(chk)
            removed += 1
        elif chk.exists():
            kept += 1
print(f'Removed checkpoints for {removed} failed/incomplete samples')
print(f'Kept checkpoints for {kept} samples with clean output')
PY

echo "Cleanup done. You can now resubmit with: cd /lustre1/g/aos_shihuang/data/LU/Scripts && bash submit_rustyclean_LU.sh"
