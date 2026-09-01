#!/bin/bash
#SBATCH --job-name=real_downstream
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=128G
#SBATCH --time=24:00:00
#SBATCH --output=/home/%u/real_downstream_%j.out
#SBATCH --error=/home/%u/real_downstream_%j.err

set -e

source /group/aos_shihuang/conda/etc/profile.d/conda.sh
export PATH="/group/aos_shihuang/conda/envs/megahit/bin:/group/aos_shihuang/conda/envs/bracken/bin:/group/aos_shihuang/conda/envs/kraken2/bin:${PATH}"

RESULTS_DIR="/lustre1/g/aos_shihuang/rustyclean-paper/real_data_results"
DOWNSTREAM_DIR="${RESULTS_DIR}/downstream"
KRAKEN2_DB="/lustre1/g/aos_shihuang/databases/kraken2/kraken16"
BRACKEN_DB="/lustre1/g/aos_shihuang/databases/kraken2/kraken16"

THREADS=8

mkdir -p "${DOWNSTREAM_DIR}"

echo "Job started at: $(date)"

find_clean_fastq() {
    local sample_dir="$1"
    # Look for clean FASTQ; prefer R1 for PE
    find "${sample_dir}" -name "*.fastq.gz" | grep -i clean | sort | awk '
        { 
            key = $0; 
            gsub(/_R1/, "", key); 
            if (tolower($0) ~ /_r1/ || tolower($0) ~ /_1\.fastq/ || tolower($0) ~ /paired_1/) score = 0;
            else if (tolower($0) ~ /_r2/ || tolower($0) ~ /_2\.fastq/) score = 2;
            else score = 1;
            print score "\t" $0;
        }
    ' | sort -k1,1n -k2,2 | head -1 | cut -f2
}

for TOOL in rustyclean kneaddata; do
    echo "=== Tool: ${TOOL} ==="
    for SAMPLE_DIR in "${RESULTS_DIR}/${TOOL}"/*; do
        [ -d "${SAMPLE_DIR}" ] || continue
        SAMPLE=$(basename "${SAMPLE_DIR}")
        echo "  Sample: ${SAMPLE}"

        OUT="${DOWNSTREAM_DIR}/${TOOL}/${SAMPLE}"
        mkdir -p "${OUT}"

        # Find clean FASTQ(s)
        CLEAN_R1=$(find_clean_fastq "${SAMPLE_DIR}")
        if [ -z "${CLEAN_R1}" ]; then
            echo "    WARNING: no clean FASTQ found, skipping"
            continue
        fi
        echo "    Clean R1: ${CLEAN_R1}"

        # MEGAHIT assembly
        ASM_OUT="${OUT}/megahit"
        if [ ! -d "${ASM_OUT}/final.contigs.fa" ]; then
            echo "    Running MEGAHIT..."
            megahit -1 "${CLEAN_R1}" -o "${ASM_OUT}" -t "${THREADS}" -m 0.9 --min-contig-len 500 > "${OUT}/megahit.log" 2>&1 || {
                echo "    MEGAHIT failed for ${TOOL}/${SAMPLE}"
            }
        fi

        # Kraken2 / Bracken profiling
        K2_OUT="${OUT}/kraken2"
        mkdir -p "${K2_OUT}"
        echo "    Running Kraken2..."
        kraken2 --db "${KRAKEN2_DB}" --threads "${THREADS}" --report "${K2_OUT}/report.k2" \
            --output "${K2_OUT}/output.k2" "${CLEAN_R1}" > "${K2_OUT}/kraken2.log" 2>&1 || true

        echo "    Running Bracken..."
        bracken -d "${BRACKEN_DB}" -i "${K2_OUT}/report.k2" -o "${K2_OUT}/bracken_S.txt" \
            -l S -t "${THREADS}" > "${K2_OUT}/bracken.log" 2>&1 || true
    done
done

echo "Job finished at: $(date)"
