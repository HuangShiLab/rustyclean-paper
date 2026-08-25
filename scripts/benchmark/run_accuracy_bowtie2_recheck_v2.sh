#!/bin/bash
#SBATCH --job-name=rc_bt2recheck_acc
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=04:00:00
#SBATCH --output=/home/shihuang/rc_bt2recheck_acc_%j.out
#SBATCH --error=/home/shihuang/rc_bt2recheck_acc_%j.err

set -e
source /group/aos_shihuang/conda/etc/profile.d/conda.sh
conda activate /lustre1/g/aos_shihuang/rustyclean-paper/.conda_envs/rustyclean-benchmark

python /lustre1/g/aos_shihuang/rustyclean/compute_accuracy_bowtie2_recheck_v2.py \
    /lustre1/g/aos_shihuang/rustyclean-paper/bowtie2_recheck_v2 \
    /lustre1/g/aos_shihuang/rustyclean-paper/bowtie2_recheck_v2/metrics/accuracy_bowtie2_recheck.csv
