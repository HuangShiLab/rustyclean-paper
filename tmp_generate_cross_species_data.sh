#!/bin/bash
#SBATCH --job-name=gen_cross_species
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=2-00:00:00
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err

set -e

source /group/aos_shihuang/conda/etc/profile.d/conda.sh
conda activate rustyclean-benchmark

# =============================================================================
# Cross-species host-contamination simulated data generation
# =============================================================================
# Uses scratch for fast I/O; outputs are in OUTPUT_DIR.

OUTPUT_DIR="${1:-/scr/u/shihuang/rustyclean-paper/data/cross_species}"
MICROBE_DIR="${2:-/lustre1/g/aos_shihuang/rustyclean-paper/genomes/genomes_fasta}"
HOST_BASE="/lustre1/g/aos_shihuang/databases/host_genomes_cross"

mkdir -p "$OUTPUT_DIR"

command -v iss >/dev/null 2>&1 || {
    echo "ERROR: insilicoseq (iss) not found."
    exit 1
}

HOSTS=(
    "human:human.fa:9606"
    "mouse:mouse.fa:10090"
    "rat:rat.fa:10116"
    "pig:pig.fa:9823"
    "rice:rice.fa:4530"
    "monkey:monkey.fa:9544"
)

DATASETS=(
    "10M_10pct_med_even_SE:10000000:0.10:med:even:SE"
    "30M_50pct_med_lognormal_SE:30000000:0.50:med:lognormal:SE"
    "60M_90pct_high_lognormal_SE:60000000:0.90:high:lognormal:SE"
)

log() { echo "[$(date +%H:%M:%S)] $*"; }

combine_microbes() {
    local complexity="$1"
    local output="$2"
    local n_species

    case "$complexity" in
        low) n_species=5 ;;
        med) n_species=30 ;;
        high) n_species=100 ;;
        *) n_species=30 ;;
    esac

    > "$output"
    if [ -d "$MICROBE_DIR" ]; then
        local all_genomes=("$MICROBE_DIR"/*.fasta "$MICROBE_DIR"/*.fa)
        all_genomes=($(for g in "${all_genomes[@]}"; do [ -f "$g" ] && echo "$g"; done))
        local count=${#all_genomes[@]}

        if [ "$count" -eq 0 ]; then
            echo "  WARNING: no microbial genomes in $MICROBE_DIR"
            exit 1
        else
            for i in $(seq 0 $((n_species - 1))); do
                local idx=$((i % count))
                cat "${all_genomes[$idx]}" >> "$output"
            done
            log "  Combined $n_species microbial genomes (from $count available)"
        fi
    else
        echo "ERROR: microbial genome dir not found: $MICROBE_DIR"
        exit 1
    fi
}

python_generate_abundance() {
    python3 - "$1" "$2" "$3" << 'PYEOF'
import sys
import numpy as np

distribution = sys.argv[2]
n = int(sys.argv[1])

if distribution == 'lognormal':
    abundances = np.random.lognormal(0, 2, n)
elif distribution == 'even':
    abundances = np.ones(n)
elif distribution == 'skewed':
    abundances = np.array([0.5] + [0.5/(n-1)] * (n-1))
else:
    abundances = np.random.lognormal(0, 2, n)

abundances = abundances / abundances.sum()
with open(sys.argv[3], 'w') as f:
    for i, ab in enumerate(abundances):
        f.write(f"species_{i+1}\t{ab:.8f}\n")
PYEOF
}

estimate_complexity() {
    case "$1" in
        low) echo 5 ;;
        med) echo 30 ;;
        high) echo 100 ;;
        *) echo 30 ;;
    esac
}

log "========================================"
log "Cross-species simulated data generation"
log "Output: $OUTPUT_DIR"
log "Microbial genomes: $MICROBE_DIR"
log "Host genomes: $HOST_BASE"
log "========================================"

for host_def in "${HOSTS[@]}"; do
    IFS=':' read -r HOST_NAME HOST_FA HOST_TAXID <<< "$host_def"
    HOST_FASTA="$HOST_BASE/$HOST_FA"

    if [ ! -f "$HOST_FASTA" ]; then
        log "WARNING: host FASTA not found: $HOST_FASTA; skipping $HOST_NAME"
        continue
    fi

    log "=== Host: $HOST_NAME (taxid $HOST_TAXID) ==="

    for dataset_config in "${DATASETS[@]}"; do
        IFS=':' read -r DS_NAME TOTAL_READS HOST_PCT COMPLEXITY ABUNDANCE_DIST READ_MODE <<< "$dataset_config"
        DATASET_NAME="${HOST_NAME}_${DS_NAME}"
        DATASET_DIR="$OUTPUT_DIR/$DATASET_NAME"

        log "--- Dataset: $DATASET_NAME ---"

        if [ -f "$DATASET_DIR/completed.flag" ]; then
            log "  Already generated. Skipping."
            continue
        fi

        mkdir -p "$DATASET_DIR"

        MICROBE_FA="$DATASET_DIR/microbial_input.fasta"
        combine_microbes "$COMPLEXITY" "$MICROBE_FA"

        N_SPECIES=$(estimate_complexity "$COMPLEXITY")
        ABUNDANCE_FILE="$DATASET_DIR/abundance.txt"
        python_generate_abundance "$N_SPECIES" "$ABUNDANCE_DIST" "$ABUNDANCE_FILE"

        HOST_READS=$(python3 -c "print(int($TOTAL_READS * $HOST_PCT))")
        MICROBE_READS=$(python3 -c "print(int($TOTAL_READS * (1 - $HOST_PCT)))")

        log "  Host reads: $HOST_READS, Microbial reads: $MICROBE_READS"

        if [ "$MICROBE_READS" -gt 0 ]; then
            log "  Generating microbial reads..."
            iss generate \
                --genomes "$MICROBE_FA" \
                --abundance_file "$ABUNDANCE_FILE" \
                --model miseq \
                --n_reads "$MICROBE_READS" \
                --output "$DATASET_DIR/microbe" \
                --cpus 8 \
                > "$DATASET_DIR/microbe.log" 2>&1
        fi

        if [ "$HOST_READS" -gt 0 ]; then
            log "  Generating host reads..."
            iss generate \
                --genomes "$HOST_FASTA" \
                --model miseq \
                --n_reads "$HOST_READS" \
                --output "$DATASET_DIR/host" \
                --cpus 8 \
                > "$DATASET_DIR/host.log" 2>&1
        fi

        log "  Merging and labeling..."
        if [ "$MICROBE_READS" -gt 0 ] && [ "$HOST_READS" -gt 0 ]; then
            cat "$DATASET_DIR/microbe_reads.fastq" "$DATASET_DIR/host_reads.fastq" > "$DATASET_DIR/reads.fastq"
            awk -v n="$MICROBE_READS" '
                NR%4==1 {
                    if ((NR+3)/4 <= n) {
                        print substr($0, 2) "\tmicrobe"
                    } else {
                        print substr($0, 2) "\thost"
                    }
                }
            ' "$DATASET_DIR/reads.fastq" > "$DATASET_DIR/ground_truth_labels.txt"
        elif [ "$MICROBE_READS" -gt 0 ]; then
            cp "$DATASET_DIR/microbe_reads.fastq" "$DATASET_DIR/reads.fastq"
            awk 'NR%4==1 {print substr($0, 2) "\tmicrobe"}' "$DATASET_DIR/reads.fastq" > "$DATASET_DIR/ground_truth_labels.txt"
        else
            cp "$DATASET_DIR/host_reads.fastq" "$DATASET_DIR/reads.fastq"
            awk 'NR%4==1 {print substr($0, 2) "\thost"}' "$DATASET_DIR/reads.fastq" > "$DATASET_DIR/ground_truth_labels.txt"
        fi

        pigz -p 8 "$DATASET_DIR/reads.fastq"

        cat > "$DATASET_DIR/metadata.json" << EOF
{
    "dataset_name": "$DATASET_NAME",
    "host_species": "$HOST_NAME",
    "host_taxid": $HOST_TAXID,
    "total_reads": $TOTAL_READS,
    "host_percentage": $HOST_PCT,
    "host_reads": $HOST_READS,
    "microbial_reads": $MICROBE_READS,
    "complexity": "$COMPLEXITY",
    "abundance_distribution": "$ABUNDANCE_DIST",
    "read_mode": "$READ_MODE",
    "read_length": 150,
    "simulator": "InsilicoSeq",
    "model": "miseq"
}
EOF

        touch "$DATASET_DIR/completed.flag"
        log "  Completed: $DATASET_NAME"
    done
done

log "========================================"
log "Cross-species data generation complete!"
log "========================================"
