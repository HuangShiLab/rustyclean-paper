#!/bin/bash
#SBATCH --job-name=gen_cross_species_v2
#SBATCH --partition=amd
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=12:00:00
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err

set -e

# Use the project conda env directly (name-based activation fails on HPC)
export PATH="/lustre1/g/aos_shihuang/rustyclean-paper/.conda_envs/rustyclean-benchmark/bin:${PATH}"

# =============================================================================
# Cross-species host-contamination simulated data generation (v2)
# One 10M-read SE dataset per host species with ~50% host contamination.
# Uses ART_Illumina HS25 (the same simulator used for the enhanced datasets).
# =============================================================================

OUTPUT_DIR="${1:-${SCRATCH_DIR:-/scr/u/$USER/rustyclean-paper}/data/cross_species_v2}"
MICROBE_DIR="${2:-/lustre1/g/aos_shihuang/rustyclean-paper/genomes/genomes_fasta}"
HOST_BASE="/lustre1/g/aos_shihuang/databases/host_genomes_cross"

mkdir -p "$OUTPUT_DIR"

command -v art_illumina >/dev/null 2>&1 || {
    echo "ERROR: art_illumina not found in PATH."
    exit 1
}
command -v pigz >/dev/null 2>&1 || {
    echo "ERROR: pigz not found in PATH."
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

DS_NAME="10M_50pct_med_even_SE"
TOTAL_READS=10000000
HOST_PCT=0.50
READ_LENGTH=150
N_MICROBE_SPECIES=30

log() { echo "[$(date +%H:%M:%S)] $*"; }

combine_microbes() {
    local output="$1"
    local n_species=$N_MICROBE_SPECIES

    > "$output"
    if [ -d "$MICROBE_DIR" ]; then
        local all_genomes=("$MICROBE_DIR"/*.fasta "$MICROBE_DIR"/*.fa)
        all_genomes=($(for g in "${all_genomes[@]}"; do if [ -f "$g" ]; then echo "$g"; fi; done))
        local count=${#all_genomes[@]}

        if [ "$count" -eq 0 ]; then
            echo "ERROR: no microbial genomes in $MICROBE_DIR"
            exit 1
        fi

        for i in $(seq 0 $((n_species - 1))); do
            local idx=$((i % count))
            cat "${all_genomes[$idx]}" >> "$output"
        done
        log "  Combined $n_species microbial genomes (from $count available)"
    else
        echo "ERROR: microbial genome dir not found: $MICROBE_DIR"
        exit 1
    fi
}

log "========================================"
log "Cross-species simulated data generation (v2)"
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

    DATASET_NAME="${HOST_NAME}_${DS_NAME}"
    DATASET_DIR="$OUTPUT_DIR/$DATASET_NAME"

    log "=== Dataset: $DATASET_NAME ==="

    if [ -f "$DATASET_DIR/completed.flag" ]; then
        log "  Already generated. Skipping."
        continue
    fi

    mkdir -p "$DATASET_DIR"

    MICROBE_FA="$DATASET_DIR/microbial_input.fasta"
    combine_microbes "$MICROBE_FA"

    HOST_READS=$(python3 -c "print(int($TOTAL_READS * $HOST_PCT))")
    MICROBE_READS=$(python3 -c "print($TOTAL_READS - $HOST_READS)")
    # reads per microbial species so total microbial reads ~= MICROBE_READS
    READS_PER_MICROBE=$(python3 -c "print(int($MICROBE_READS / $N_MICROBE_SPECIES))")

    log "  Host reads: $HOST_READS, Microbial reads: $MICROBE_READS ($READS_PER_MICROBE per species)"

    if [ "$MICROBE_READS" -gt 0 ]; then
        log "  Generating microbial reads with ART..."
        art_illumina \
            -ss HS25 \
            -i "$MICROBE_FA" \
            -l "$READ_LENGTH" \
            -c "$READS_PER_MICROBE" \
            -o "$DATASET_DIR/microbe" \
            > "$DATASET_DIR/microbe.log" 2>&1
    fi

    if [ "$HOST_READS" -gt 0 ]; then
        log "  Generating host reads with ART..."
        art_illumina \
            -ss HS25 \
            -i "$HOST_FASTA" \
            -l "$READ_LENGTH" \
            -c "$HOST_READS" \
            -o "$DATASET_DIR/host" \
            > "$DATASET_DIR/host.log" 2>&1
    fi

    log "  Merging and labeling..."
    if [ "$MICROBE_READS" -gt 0 ] && [ "$HOST_READS" -gt 0 ]; then
        cat "$DATASET_DIR/microbe.fq" "$DATASET_DIR/host.fq" > "$DATASET_DIR/reads.fastq"
        awk '"'"'NR%4==1 {print substr($0, 2) "\tmicrobe"}'"'"' "$DATASET_DIR/microbe.fq" > "$DATASET_DIR/ground_truth_labels.txt"
        awk '"'"'NR%4==1 {print substr($0, 2) "\thost"}'"'"' "$DATASET_DIR/host.fq" >> "$DATASET_DIR/ground_truth_labels.txt"
    elif [ "$MICROBE_READS" -gt 0 ]; then
        cp "$DATASET_DIR/microbe.fq" "$DATASET_DIR/reads.fastq"
        awk '"'"'NR%4==1 {print substr($0, 2) "\tmicrobe"}'"'"' "$DATASET_DIR/microbe.fq" > "$DATASET_DIR/ground_truth_labels.txt"
    else
        cp "$DATASET_DIR/host.fq" "$DATASET_DIR/reads.fastq"
        awk '"'"'NR%4==1 {print substr($0, 2) "\thost"}'"'"' "$DATASET_DIR/host.fq" > "$DATASET_DIR/ground_truth_labels.txt"
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
    "complexity": "med",
    "abundance_distribution": "even",
    "read_mode": "SE",
    "read_length": $READ_LENGTH,
    "simulator": "ART_illumina_HS25",
    "model": "hiseq2500"
}
EOF

    touch "$DATASET_DIR/completed.flag"
    log "  Completed: $DATASET_NAME"
done

log "========================================"
log "Cross-species data generation complete!"
log "========================================"
