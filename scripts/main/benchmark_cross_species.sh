#!/bin/bash
#SBATCH --job-name=cross_species
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=128G
#SBATCH --time=12:00:00
#SBATCH --output=/home/%u/cross_species_%j.out
#SBATCH --error=/home/%u/cross_species_%j.err

set -e

source /group/aos_shihuang/conda/etc/profile.d/conda.sh
export PATH="/group/aos_shihuang/conda/envs/fastp/bin:/group/aos_shihuang/conda/envs/kraken2/bin:/group/aos_shihuang/conda/envs/bowtie2/bin:/group/aos_shihuang/conda/envs/kneaddata/bin:$HOME/.local/bin:${PATH}"

DATA_DIR="${SCRATCH_DIR:-/scr/u/$USER/rustyclean-paper}/data/cross_species_v2"
RESULTS_DIR="${RUNS_DIR:-/lustre1/g/aos_shihuang/rustyclean-paper/runs}/cross_species_results"
METRICS_DIR="${RESULTS_DIR}/metrics"
LOGS_DIR="${RESULTS_DIR}/logs"
INDEX_DIR="/lustre1/g/aos_shihuang/rustyclean-paper/cross_species_indices"

THREADS=8
RUSTYCLEAN="/lustre1/g/aos_shihuang/rustyclean/target/release/rustyclean"

SPECIES=("human" "mouse" "rat" "pig" "rice" "monkey")

mkdir -p "${METRICS_DIR}" "${LOGS_DIR}" "${INDEX_DIR}"

echo "Job started at: $(date)"
echo "Host: $(hostname)"
echo "Threads: ${THREADS}"

if [ ! -f "${METRICS_DIR}/performance.csv" ]; then
    echo "tool,species,dataset,rep,runtime_seconds,max_memory_kb,timestamp" > "${METRICS_DIR}/performance.csv"
fi

parse_time() {
    local timefile="$1"
    local runtime="unknown"
    local max_mem="unknown"
    if [ -f "${timefile}" ]; then
        runtime=$(grep "Elapsed (wall clock) time" "${timefile}" | awk -F': ' '{print $NF}')
        [ -z "${runtime}" ] && runtime="unknown"
        max_mem=$(grep "Maximum resident set size (kbytes):" "${timefile}" | awk '{print $NF}' || echo "unknown")
    fi

    local runtime_sec="unknown"
    if [ "${runtime}" != "unknown" ] && [ -n "${runtime}" ]; then
        runtime_sec=$(echo "${runtime}" | awk -F: '{
            if (NF == 3) { printf "%d", $1*3600 + $2*60 + $3 }
            else if (NF == 2) { printf "%d", $1*60 + $2 }
            else { printf "%d", $1 }
        }')
    fi
    echo "${runtime_sec} ${max_mem}"
}

build_index() {
    local species="$1"
    local fasta="/lustre1/g/aos_shihuang/databases/host_genomes_cross/${species}.fa"
    local idx="${INDEX_DIR}/${species}_bt2"

    if [ -f "${idx}.1.bt2" ] || [ -f "${idx}.1.bt2l" ]; then
        echo "  [${species}] Index exists: ${idx}"
    else
        echo "  [${species}] Building Bowtie2 index from ${fasta}..."
        bowtie2-build --threads "${THREADS}" "${fasta}" "${idx}" > "${LOGS_DIR}/build_${species}.log" 2>&1
    fi
}

for SPECIES in "${SPECIES[@]}"; do
    DATASET="${SPECIES}_10M_50pct_med_even_SE"
    R1="${DATA_DIR}/${DATASET}/reads.fastq.gz"
    if [ ! -f "${R1}" ]; then
        echo "WARNING: Input not found: ${R1}" >&2
        continue
    fi

    echo "=== Species: ${SPECIES} | Dataset: ${DATASET} ==="

    build_index "${SPECIES}"
    IDX="${INDEX_DIR}/${SPECIES}_bt2"

    # RustyClean bowtie2, 3 replicates
    for REP in 1 2 3; do
        OUT="${RESULTS_DIR}/rustyclean/${DATASET}/rep_${REP}"
        rm -rf "${OUT}"
        mkdir -p "${OUT}"
        logfile="${LOGS_DIR}/rustyclean_${DATASET}_rep${REP}.log"
        timefile="${LOGS_DIR}/rustyclean_${DATASET}_rep${REP}.time"

        echo "  [RC rep ${REP}] Running RustyClean bowtie2..."
        /usr/bin/time -v -o "${timefile}" \
            "${RUSTYCLEAN}" \
                --mode bowtie2 \
                --skip-qc \
                --r1 "${R1}" \
                --host-index "${IDX}" \
                --max-contamination 100.0 \
                -o "${OUT}" \
                -t "${THREADS}" \
                --checkpoint-dir "${OUT}/.checkpoints" \
                --clean \
                > "${logfile}" 2>&1 || {
            echo "  [RC rep ${REP}] FAILED on ${DATASET}" >&2
            echo "rustyclean,${SPECIES},${DATASET},${REP},FAILED,,$(date -Iseconds)" >> "${METRICS_DIR}/performance.csv"
            continue
        }

        read runtime_sec max_mem < <(parse_time "${timefile}")
        echo "rustyclean,${SPECIES},${DATASET},${REP},${runtime_sec},${max_mem},$(date -Iseconds)" >> "${METRICS_DIR}/performance.csv"
        echo "  [RC rep ${REP}] Done: runtime=${runtime_sec}s, max_mem=${max_mem}kB"
    done

    # KneadData, single run
    KD_OUT="${RESULTS_DIR}/kneaddata/${DATASET}"
    rm -rf "${KD_OUT}"
    mkdir -p "${KD_OUT}"
    kd_log="${LOGS_DIR}/kneaddata_${DATASET}.log"
    kd_time="${LOGS_DIR}/kneaddata_${DATASET}.time"

    echo "  [KneadData] Running KneadData..."
    /usr/bin/time -v -o "${kd_time}" \
        kneaddata -un "${R1}" --output-prefix clean \
            -db "${IDX}" --threads "${THREADS}" \
            --output "${KD_OUT}" --remove-intermediate-output \
            > "${kd_log}" 2>&1 || {
        echo "  [KneadData] FAILED on ${DATASET}" >&2
        echo "kneaddata,${SPECIES},${DATASET},1,FAILED,,$(date -Iseconds)" >> "${METRICS_DIR}/performance.csv"
    }
    read kd_runtime kd_mem < <(parse_time "${kd_time}")
    echo "kneaddata,${SPECIES},${DATASET},1,${kd_runtime},${kd_mem},$(date -Iseconds)" >> "${METRICS_DIR}/performance.csv"
    echo "  [KneadData] Done: runtime=${kd_runtime}s, max_mem=${kd_mem}kB"
done

echo "Job finished at: $(date)"
