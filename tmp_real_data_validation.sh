#!/bin/bash
#SBATCH --job-name=real_data_val
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=128G
#SBATCH --time=2-00:00:00
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err

set -e

source /group/aos_shihuang/conda/etc/profile.d/conda.sh

# Combine required tool binaries
export PATH="/group/aos_shihuang/conda/envs/fastp/bin:/group/aos_shihuang/conda/envs/kraken2/bin:/group/aos_shihuang/conda/envs/kneaddata/bin:/group/aos_shihuang/conda/envs/seqtk/bin:/home/shihuang/.conda/envs/hostile-centrifuge/bin:${PATH}"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
WORK_DIR="/scr/u/shihuang/rustyclean-paper/real_data"
RESULTS_DIR="/lustre1/g/aos_shihuang/rustyclean-paper/results_real_data"
METRICS_DIR="${RESULTS_DIR}/metrics"
LOGS_DIR="${RESULTS_DIR}/logs"

RUSTYCLEAN="/lustre1/g/aos_shihuang/rustyclean/target/release/rustyclean"
KRAKEN2_DB="/lustre1/g/aos_shihuang/databases/kraken2/kraken16"
CF_INDEX="/lustre1/g/aos_shihuang/databases/centrifuge/host_indexes/human_t2t_hla_cf"
KNEADDATA_DB="/lustre1/g/aos_shihuang/databases/kneaddata/hg_39"
BT2_INDEX="/lustre1/g/aos_shihuang/databases/kneaddata/hg_39"

THREADS=16

mkdir -p "$WORK_DIR" "$RESULTS_DIR" "$METRICS_DIR" "$LOGS_DIR"

# ---------------------------------------------------------------------------
# Sample definitions
# Format: sample_name:accession:sample_type
# ---------------------------------------------------------------------------
SAMPLES=(
    "HMP_oral:SRS011086:oral"
    "HMP_vaginal:SRS011157:vaginal"
)

# Optional cancer sample (WGS, large); add if time/disk permit
# "CRC_wgs:SRR1781841:cancer"

log() { echo "[$(date +%H:%M:%S)] $*"; }

run_timed() {
    local tool_name="$1"
    local sample="$2"
    shift 2
    local cmd="$*"

    local timefile="${LOGS_DIR}/${tool_name}_${sample}.time"
    local logfile="${LOGS_DIR}/${tool_name}_${sample}.log"

    log "  [${tool_name}] Running on ${sample}..."
    /usr/bin/time -v -o "$timefile" bash -c "$cmd" > "$logfile" 2>&1 || {
        log "  [${tool_name}] FAILED on ${sample}"
        echo "${tool_name},${sample},FAILED,,$(date -Iseconds)" >> "${METRICS_DIR}/performance.csv"
        return 1
    }

    local runtime="unknown"
    local max_mem="unknown"
    if [ -f "$timefile" ]; then
        runtime=$(grep "Elapsed (wall clock) time" "$timefile" | sed -n 's/.*Elapsed (wall clock) time: //p' || echo "unknown")
        max_mem=$(grep "Maximum resident set size" "$timefile" | sed -n 's/.*Maximum resident set size (kbytes): //p' || echo "unknown")
    fi

    local runtime_sec="unknown"
    if [ "$runtime" != "unknown" ]; then
        runtime_sec=$(echo "$runtime" | awk -F: '{
            if (NF == 3) { printf "%d", $1*3600 + $2*60 + $3 }
            else if (NF == 2) { printf "%d", $1*60 + $2 }
            else { printf "%d", $1 }
        }')
    fi

    echo "${tool_name},${sample},${runtime_sec},${max_mem},$(date -Iseconds)" >> "${METRICS_DIR}/performance.csv"
    log "  [${tool_name}] Done: runtime=${runtime_sec}s, max_mem=${max_mem}kB"
}

# ---------------------------------------------------------------------------
# Initialize metrics file
# ---------------------------------------------------------------------------
echo "tool,sample,runtime_seconds,max_memory_kb,timestamp" > "${METRICS_DIR}/performance.csv"

# ---------------------------------------------------------------------------
# Download real data via fasterq-dump
# ---------------------------------------------------------------------------
for sample_def in "${SAMPLES[@]}"; do
    IFS=':' read -r SAMPLE_NAME ACCESSION SAMPLE_TYPE <<< "$sample_def"
    SAMPLE_DIR="$WORK_DIR/$SAMPLE_NAME"
    mkdir -p "$SAMPLE_DIR"

    log "=== Sample: $SAMPLE_NAME ($ACCESSION, $SAMPLE_TYPE) ==="

    if [ ! -f "$SAMPLE_DIR/reads.fastq.gz" ]; then
        log "  Downloading $ACCESSION via fasterq-dump..."
        cd "$SAMPLE_DIR"
        fasterq-dump "$ACCESSION" --split-files --threads "$THREADS" --progress > "$SAMPLE_DIR/fasterq_dump.log" 2>&1 || {
            log "  fasterq-dump failed; trying fastq-dump..."
            fastq-dump "$ACCESSION" --split-files > "$SAMPLE_DIR/fastq_dump.log" 2>&1
        }

        # Single-end or paired-end handling
        if [ -f "$SAMPLE_DIR/${ACCESSION}_2.fastq" ]; then
            log "  Paired-end detected."
            mv "$SAMPLE_DIR/${ACCESSION}_1.fastq" "$SAMPLE_DIR/reads_R1.fastq"
            mv "$SAMPLE_DIR/${ACCESSION}_2.fastq" "$SAMPLE_DIR/reads_R2.fastq"
            pigz -p "$THREADS" "$SAMPLE_DIR/reads_R1.fastq" "$SAMPLE_DIR/reads_R2.fastq"
        else
            log "  Single-end detected."
            mv "$SAMPLE_DIR/${ACCESSION}.fastq" "$SAMPLE_DIR/reads.fastq" || \
            mv "$SAMPLE_DIR/${ACCESSION}_1.fastq" "$SAMPLE_DIR/reads.fastq"
            pigz -p "$THREADS" "$SAMPLE_DIR/reads.fastq"
        fi
        cd -
    else
        log "  Reads already present."
    fi

    # Determine read mode
    if [ -f "$SAMPLE_DIR/reads_R1.fastq.gz" ]; then
        MODE="PE"
        R1="$SAMPLE_DIR/reads_R1.fastq.gz"
        R2="$SAMPLE_DIR/reads_R2.fastq.gz"
    else
        MODE="SE"
        R1="$SAMPLE_DIR/reads.fastq.gz"
        R2=""
    fi

    OUT_RC_K2="${RESULTS_DIR}/rustyclean_k2/${SAMPLE_NAME}"
    OUT_RC_BT2="${RESULTS_DIR}/rustyclean_bt2/${SAMPLE_NAME}"
    OUT_RC_AUTO="${RESULTS_DIR}/rustyclean_auto/${SAMPLE_NAME}"
    OUT_KD="${RESULTS_DIR}/kneaddata/${SAMPLE_NAME}"
    OUT_HOSTILE="${RESULTS_DIR}/hostile/${SAMPLE_NAME}"
    OUT_CF="${RESULTS_DIR}/centrifuge/${SAMPLE_NAME}"

    mkdir -p "$OUT_RC_K2" "$OUT_RC_BT2" "$OUT_RC_AUTO" "$OUT_KD" "$OUT_HOSTILE" "$OUT_CF"

    # RustyClean Kraken2
    if [ "$MODE" = "PE" ]; then
        run_timed "rustyclean_k2" "$SAMPLE_NAME" "$RUSTYCLEAN --r1 $R1 --r2 $R2 --kraken2-db $KRAKEN2_DB -o $OUT_RC_K2 -t $THREADS --memory-mapping"
    else
        run_timed "rustyclean_k2" "$SAMPLE_NAME" "$RUSTYCLEAN --r1 $R1 --kraken2-db $KRAKEN2_DB -o $OUT_RC_K2 -t $THREADS --memory-mapping"
    fi

    # RustyClean Bowtie2
    if [ "$MODE" = "PE" ]; then
        run_timed "rustyclean_bt2" "$SAMPLE_NAME" "$RUSTYCLEAN --r1 $R1 --r2 $R2 --mode bowtie2 --host-index $BT2_INDEX -o $OUT_RC_BT2 -t $THREADS"
    else
        run_timed "rustyclean_bt2" "$SAMPLE_NAME" "$RUSTYCLEAN --r1 $R1 --mode bowtie2 --host-index $BT2_INDEX -o $OUT_RC_BT2 -t $THREADS"
    fi

    # RustyClean AUTO
    if [ "$MODE" = "PE" ]; then
        run_timed "rustyclean_auto" "$SAMPLE_NAME" "$RUSTYCLEAN --r1 $R1 --r2 $R2 --mode auto --host-index $BT2_INDEX --kraken2-db $KRAKEN2_DB -o $OUT_RC_AUTO -t $THREADS --memory-mapping"
    else
        run_timed "rustyclean_auto" "$SAMPLE_NAME" "$RUSTYCLEAN --r1 $R1 --mode auto --host-index $BT2_INDEX --kraken2-db $KRAKEN2_DB -o $OUT_RC_AUTO -t $THREADS --memory-mapping"
    fi

    # KneadData
    if [ "$MODE" = "PE" ]; then
        run_timed "kneaddata" "$SAMPLE_NAME" "kneaddata -i1 $R1 -i2 $R2 -db $KNEADDATA_DB -o $OUT_KD -t $THREADS --remove-intermediate-output"
    else
        run_timed "kneaddata" "$SAMPLE_NAME" "kneaddata -i1 $R1 -db $KNEADDATA_DB -o $OUT_KD -t $THREADS --remove-intermediate-output"
    fi

    # Hostile
    if [ "$MODE" = "PE" ]; then
        run_timed "hostile" "$SAMPLE_NAME" "hostile clean --fastq1 $R1 --fastq2 $R2 --out-dir $OUT_HOSTILE --threads $THREADS"
    else
        run_timed "hostile" "$SAMPLE_NAME" "hostile clean --fastq $R1 --out-dir $OUT_HOSTILE --threads $THREADS"
    fi

    # Centrifuge
    if [ "$MODE" = "PE" ]; then
        run_timed "centrifuge" "$SAMPLE_NAME" "centrifuge -x $CF_INDEX -1 $R1 -2 $R2 -S $OUT_CF/classification.tsv --report-file $OUT_CF/report.tsv -p $THREADS --mm; centrifuge-kreport -x $CF_INDEX $OUT_CF/classification.tsv > $OUT_CF/kreport.txt"
    else
        run_timed "centrifuge" "$SAMPLE_NAME" "centrifuge -x $CF_INDEX -U $R1 -S $OUT_CF/classification.tsv --report-file $OUT_CF/report.tsv -p $THREADS --mm; centrifuge-kreport -x $CF_INDEX $OUT_CF/classification.tsv > $OUT_CF/kreport.txt"
    fi

done

log "Real-data benchmark complete. Metrics: ${METRICS_DIR}/performance.csv"
