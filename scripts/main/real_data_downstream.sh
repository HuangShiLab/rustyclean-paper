#!/bin/bash
#SBATCH --job-name=rc_real_downstream
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --array=0-8
#SBATCH --output=logs/%x-%A_%a.out
#SBATCH --error=logs/%x-%A_%a.err

set -e

source /group/aos_shihuang/conda/etc/profile.d/conda.sh
export PATH="/group/aos_shihuang/conda/envs/fastp/bin:/group/aos_shihuang/conda/envs/kraken2/bin:/group/aos_shihuang/conda/envs/bracken/bin:/group/aos_shihuang/conda/envs/megahit/bin:/group/aos_shihuang/conda/envs/kneaddata/bin:${PATH}"

PROJECT_DIR="/lustre1/g/aos_shihuang/rustyclean-paper"
RESULTS_DIR="${PROJECT_DIR}/results_real_data"
KRAKEN2_DB="/lustre1/g/aos_shihuang/databases/kraken2/kraken16"
THREADS=8

TOOLS=(rustyclean_k2 rustyclean_auto kneaddata)
SAMPLES=(vaginal_swab oral_saliva breast_cancer_stool)

N_TOOLS=${#TOOLS[@]}
TOOL_IDX=$((SLURM_ARRAY_TASK_ID / ${#SAMPLES[@]}))
SAMPLE_IDX=$((SLURM_ARRAY_TASK_ID % ${#SAMPLES[@]}))
TOOL="${TOOLS[$TOOL_IDX]}"
SAMPLE="${SAMPLES[$SAMPLE_IDX]}"

OUT_DIR="${RESULTS_DIR}/downstream/${TOOL}/${SAMPLE}"
mkdir -p "$OUT_DIR"

echo "Job started at: $(date)"
echo "Tool: $TOOL, Sample: $SAMPLE"

# Find clean reads
READS_DIR="${RESULTS_DIR}/${TOOL}/${SAMPLE}"
R1=""
R2=""

if [ "$TOOL" = "kneaddata" ]; then
    if [ -f "${READS_DIR}/clean_paired_1.fastq" ] && [ -f "${READS_DIR}/clean_paired_2.fastq" ]; then
        R1="${READS_DIR}/clean_paired_1.fastq"
        R2="${READS_DIR}/clean_paired_2.fastq"
    elif [ -f "${READS_DIR}/clean.fastq" ]; then
        R1="${READS_DIR}/clean.fastq"
    fi
else
    # RustyClean output: find clean_R1 file directly
    R1=$(find "$READS_DIR" -maxdepth 3 \( -name "${SAMPLE}_clean_R1.fastq.gz" -o -name "${SAMPLE}_clean_R1.fastq" \) | head -1)
    if [ -n "$R1" ]; then
        R2="${R1/_R1/_R2}"
        [ -f "$R2" ] || R2=""
    fi
fi

if [ -z "$R1" ] || [ ! -f "$R1" ]; then
    echo "ERROR: No clean reads found for $TOOL/$SAMPLE"
    exit 1
fi

echo "R1: $R1"
echo "R2: ${R2:-none}"

# 1. Taxonomic profiling with Kraken2 + Bracken
echo "[1/2] Taxonomic profiling..."
kraken2 --db "$KRAKEN2_DB" --threads "$THREADS" \
    --output "${OUT_DIR}/kraken2_output.txt" \
    --report "${OUT_DIR}/kraken2_report.txt" \
    --gzip-compressed \
    ${R2:+--paired} "$R1" ${R2:+"$R2"} > "${OUT_DIR}/kraken2.log" 2>&1

bracken -d "$KRAKEN2_DB" -i "${OUT_DIR}/kraken2_report.txt" \
    -o "${OUT_DIR}/bracken_species.txt" -r 150 -l S > "${OUT_DIR}/bracken.log" 2>&1 || true

# 2. Metagenomic assembly with MEGAHIT (skip if too large)
echo "[2/2] Assembly..."
MEGAHIT_OUT="${OUT_DIR}/megahit"
rm -rf "$MEGAHIT_OUT"
if [ -n "$R2" ]; then
    megahit -1 "$R1" -2 "$R2" -o "$MEGAHIT_OUT" -t "$THREADS" --out-prefix "$SAMPLE" > "${OUT_DIR}/megahit.log" 2>&1 || true
else
    megahit -r "$R1" -o "$MEGAHIT_OUT" -t "$THREADS" --out-prefix "$SAMPLE" > "${OUT_DIR}/megahit.log" 2>&1 || true
fi

echo "Job finished at: $(date)"
