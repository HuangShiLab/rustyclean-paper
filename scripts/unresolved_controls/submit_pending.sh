#!/bin/bash
# Submit the standardized pending panel. Mock truth is intentionally excluded
# because it requires a user-supplied manifest of real/reference inputs.
set -euo pipefail
command -v sbatch >/dev/null 2>&1 || { echo "sbatch not found" >&2; exit 2; }
mkdir -p logs
for runner in \
    run_equal_thread_panel.sh \
    run_always_recheck.sh \
    run_threshold_sweep_batch.sh \
    run_cleanifier_benchmark.sh; do
    echo "[submit] ${runner}"
    sbatch "scripts/unresolved_controls/${runner}"
done
