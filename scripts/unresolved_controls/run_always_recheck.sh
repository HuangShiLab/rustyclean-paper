#!/bin/bash
# Always-recheck control: threshold 0.00 in a separate standardized result set.
#SBATCH --job-name=rc_always_recheck
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --time=24:00:00
#SBATCH --array=0-5
#SBATCH --output=logs/%x-%A_%a.out
#SBATCH --error=logs/%x-%A_%a.err

export RESULTS_SUBDIR="${RESULTS_SUBDIR:-always_recheck}"
export THRESHOLDS="${THRESHOLDS:-0.00}"
if [[ -n "${SLURM_SUBMIT_DIR:-}" && -f "${SLURM_SUBMIT_DIR}/scripts/unresolved_controls/run_recheck_threshold_sweep.sh" ]]; then
    CONTROL_SCRIPT_DIR="${SLURM_SUBMIT_DIR}/scripts/unresolved_controls"
else
    CONTROL_SCRIPT_DIR="/lustre1/g/aos_shihuang/rustyclean-paper/scripts/unresolved_controls"
fi
export CONTROL_SCRIPT_DIR
exec bash "${CONTROL_SCRIPT_DIR}/run_recheck_threshold_sweep.sh"
