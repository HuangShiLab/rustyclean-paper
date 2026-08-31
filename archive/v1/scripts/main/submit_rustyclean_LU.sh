#!/bin/bash

# Split sample_list.txt into chunks of 15 samples and submit one RustyClean SLURM job per chunk.

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR" || exit 1

# Remove old RustyClean split lists to avoid duplicates
rm -f rustyclean_sample_list_part*.txt

# Split into files with 15 lines each, numeric suffix (part00.txt, part01.txt, ...)
echo "Splitting sample_list.txt into chunks of 15 samples ..."
split -l 15 -d sample_list.txt rustyclean_sample_list_part --additional-suffix=.txt

# Submit one SLURM job per chunk
for list in rustyclean_sample_list_part*.txt; do
    echo "Submitting RustyClean pipeline for ${list}"
    sbatch rustyclean_LU.sh "$list"
done

echo "All RustyClean jobs submitted."
