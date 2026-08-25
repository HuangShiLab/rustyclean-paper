#!/bin/bash
#SBATCH --job-name=rc_acc_kneaddata_100M
#SBATCH --partition=amd
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=128G
#SBATCH --time=02:00:00
#SBATCH --output=/home/shihuang/rc_acc_kneaddata_100M_%j.out
#SBATCH --error=/home/shihuang/rc_acc_kneaddata_100M_%j.err

set -e
source /group/aos_shihuang/conda/etc/profile.d/conda.sh
export PATH="/group/aos_shihuang/conda/envs/rustyclean-benchmark/bin:${PATH}"

cd /lustre1/g/aos_shihuang/rustyclean-paper
python3 scripts/main/analyze_accuracy_v2.py \
    /scr/u/shihuang/rustyclean-paper/data/enhanced \
    /lustre1/g/aos_shihuang/rustyclean-paper/kneaddata_100M_matched \
    /lustre1/g/aos_shihuang/rustyclean-paper/analysis_kneaddata_100M_accuracy \
    --tools kneaddata
