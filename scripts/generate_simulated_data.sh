#!/bin/bash
# =============================================================================
# RustyClean Benchmark - Simulated Data Generation
# =============================================================================
# Uses InsilicoSeq to generate simulated metagenomic reads with known
# host contamination levels.
#
# Usage: bash scripts/generate_simulated_data.sh [output_dir] [genome_dir]
# Default output_dir: ./data/simulated
# Default genome_dir: ~/benchmark_env/genomes

set -e

OUTPUT_DIR="${1:-./data/simulated}"
GENOME_DIR="${2:-$HOME/benchmark_env/genomes}"
HUMAN_GENOME="${3:-$HOME/benchmark_env/databases/GRCh38.fa.gz}"

echo "========================================"
echo "Generating Simulated Metagenome Data"
echo "========================================"

# Check dependencies
command -v iss >/dev/null 2>&1 || {
    echo "ERROR: InsilicoSeq (iss) not found. Install: conda install -c bioconda insilicoseq"
    exit 1
}

mkdir -p "$OUTPUT_DIR"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
READ_LENGTH=150
PAIRED_END=true

# Datasets: "name:total_reads:host_percent"
DATASETS=(
    "10M_10pct:10000000:0.10"
    "30M_50pct:30000000:0.50"
    "60M_90pct:60000000:0.90"
    "20M_PE_50pct:20000000:0.50"
)

N_SPECIES=30

# ---------------------------------------------------------------------------
# Prepare input files
# ---------------------------------------------------------------------------

echo "[1/4] Preparing input genomes..."

MICROBIAL_FASTA="$OUTPUT_DIR/microbial_genomes.fasta"
HUMAN_FASTA="$OUTPUT_DIR/human_genome.fasta"

# Combine microbial genomes
if [ ! -f "$MICROBIAL_FASTA" ]; then
    echo "Combining microbial genomes..."
    if [ -d "$GENOME_DIR/genomes_fasta" ]; then
        cat "$GENOME_DIR"/genomes_fasta/*.fasta > "$MICROBIAL_FASTA"
    else
        echo "WARNING: Microbial genome directory not found. Creating minimal test with E. coli..."
        if [ ! -f "$OUTPUT_DIR/ecoli_test.fasta" ]; then
            curl -s "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nuccore&id=U00096.3&rettype=fasta&retmode=text" > "$OUTPUT_DIR/ecoli_test.fasta"
        fi
        cp "$OUTPUT_DIR/ecoli_test.fasta" "$MICROBIAL_FASTA"
    fi
else
    echo "Microbial genomes already combined."
fi

# Prepare human genome
if [ ! -f "$HUMAN_FASTA" ]; then
    if [ -f "$HUMAN_GENOME" ]; then
        echo "Extracting human genome..."
        if [[ "$HUMAN_GENOME" == *.gz ]]; then
            gunzip -c "$HUMAN_GENOME" > "$HUMAN_FASTA"
        else
            cp "$HUMAN_GENOME" "$HUMAN_FASTA"
        fi
    else
        echo "WARNING: Human genome not found. Downloading chromosome 1..."
        curl -s "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nuccore&id=NC_000001.11&rettype=fasta&retmode=text" > "$HUMAN_FASTA"
    fi
else
    echo "Human genome already prepared."
fi

# ---------------------------------------------------------------------------
# Generate abundance profiles
# ---------------------------------------------------------------------------

echo ""
echo "[2/4] Generating abundance profiles..."

cat > "$OUTPUT_DIR/generate_abundance.py" << 'PYEOF'
import sys
import numpy as np

def generate_abundance(n_species, output_file):
    mu, sigma = 0, 2
    abundances = np.random.lognormal(mu, sigma, n_species)
    abundances = abundances / abundances.sum()
    with open(output_file, 'w') as f:
        for i, ab in enumerate(abundances):
            f.write(f"species_{i+1}\t{ab:.6f}\n")
    return abundances

if __name__ == '__main__':
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 30
    out = sys.argv[2] if len(sys.argv) > 2 else 'abundance.txt'
    generate_abundance(n, out)
    print(f"Generated abundance for {n} species: {out}")
PYEOF

python "$OUTPUT_DIR/generate_abundance.py" "$N_SPECIES" "$OUTPUT_DIR/microbial_abundance.txt"

# ---------------------------------------------------------------------------
# Generate simulated reads
# ---------------------------------------------------------------------------

echo ""
echo "[3/4] Generating simulated reads with InsilicoSeq..."

for dataset_config in "${DATASETS[@]}"; do
    IFS=':' read -r DATASET_NAME TOTAL_READS HOST_PCT <<< "$dataset_config"
    
    echo ""
    echo "--- Dataset: $DATASET_NAME ---"
    
    DATASET_DIR="$OUTPUT_DIR/$DATASET_NAME"
    mkdir -p "$DATASET_DIR"
    
    if [ -f "$DATASET_DIR/completed.flag" ]; then
        echo "  Already generated. Skipping."
        continue
    fi
    
    HOST_READS=$(python -c "print(int($TOTAL_READS * $HOST_PCT))")
    MICROBE_READS=$(python -c "print(int($TOTAL_READS * (1 - $HOST_PCT)))")
    
    echo "  Host reads: $HOST_READS, Microbial reads: $MICROBE_READS"
    
    # Generate host reads
    echo "  Generating host reads..."
    iss generate \
        --genomes "$HUMAN_FASTA" \
        --model miseq \
        --n_reads "$HOST_READS" \
        --output "$DATASET_DIR/host" \
        --cpus 4 \
        2>&1 | tee "$DATASET_DIR/host.log"
    
    # Generate microbial reads
    echo "  Generating microbial reads..."
    iss generate \
        --genomes "$MICROBIAL_FASTA" \
        --abundance_file "$OUTPUT_DIR/microbial_abundance.txt" \
        --model miseq \
        --n_reads "$MICROBE_READS" \
        --output "$DATASET_DIR/microbe" \
        --cpus 4 \
        2>&1 | tee "$DATASET_DIR/microbe.log"
    
    # Merge and label
    echo "  Merging and labeling reads..."
    
    if [ "$PAIRED_END" = true ] && [[ "$DATASET_NAME" == *"PE"* ]]; then
        cat "$DATASET_DIR/host_R1.fastq" "$DATASET_DIR/microbe_R1.fastq" > "$DATASET_DIR/reads_R1.fastq"
        cat "$DATASET_DIR/host_R2.fastq" "$DATASET_DIR/microbe_R2.fastq" > "$DATASET_DIR/reads_R2.fastq"
        
        pigz -p 4 "$DATASET_DIR/reads_R1.fastq"
        pigz -p 4 "$DATASET_DIR/reads_R2.fastq"
        
        echo "  Output: reads_R1.fastq.gz, reads_R2.fastq.gz"
    else
        cat "$DATASET_DIR/host_reads.fastq" "$DATASET_DIR/microbe_reads.fastq" > "$DATASET_DIR/reads.fastq"
        
        # Create ground truth labels
        awk -v n="$HOST_READS" '
            NR%4==1 {
                if ((NR+3)/4 <= n) {
                    print substr($0, 2) "\thost"
                } else {
                    print substr($0, 2) "\tmicrobe"
                }
            }
        ' "$DATASET_DIR/reads.fastq" > "$DATASET_DIR/ground_truth_labels.txt"
        
        pigz -p 4 "$DATASET_DIR/reads.fastq"
        echo "  Output: reads.fastq.gz"
    fi
    
    # Metadata
    cat > "$DATASET_DIR/metadata.json" << EOF
{
    "dataset_name": "$DATASET_NAME",
    "total_reads": $TOTAL_READS,
    "host_percentage": $HOST_PCT,
    "host_reads": $HOST_READS,
    "microbial_reads": $MICROBE_READS,
    "read_length": $READ_LENGTH,
    "paired_end": $([[ "$DATASET_NAME" == *"PE"* ]] && echo "true" || echo "false"),
    "simulator": "InsilicoSeq"
}
EOF
    
    touch "$DATASET_DIR/completed.flag"
    echo "  Dataset completed."
    
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "========================================"
echo "Simulated Data Generation Complete!"
echo "========================================"
for dataset_config in "${DATASETS[@]}"; do
    IFS=':' read -r DATASET_NAME _ _ <<< "$dataset_config"
    echo "  - $OUTPUT_DIR/$DATASET_NAME"
done
echo ""
echo "Next: bash scripts/run_benchmark.sh"
