#!/bin/bash
# =============================================================================
# RustyClean Benchmark - Enhanced Simulated Data Generation
# =============================================================================
# Generates diverse simulated metagenomic datasets with varying:
#   - host contamination ratios (1% to 99%)
#   - dataset sizes (5M to 100M reads)
#   - microbial complexity (low: 5 sp, medium: 30 sp, high: 100 sp)
#   - community types (even vs. lognormal abundance)
#   - read modes (single-end vs. paired-end)
#   - host types (human vs. mouse)
#
# Usage: bash scripts/main/generate_enhanced_data.sh [output_dir] [genome_dir]
# Default output_dir: ./data/enhanced
# Default genome_dir: ~/benchmark_env/genomes

set -e

OUTPUT_DIR="${1:-./data/enhanced}"
GENOME_DIR="${2:-$HOME/benchmark_env/genomes}"
HUMAN_GENOME="${3:-$HOME/benchmark_env/databases/GRCh38.fa.gz}"

echo "========================================"
echo "Enhanced Simulated Data Generation"
echo "========================================"

command -v iss >/dev/null 2>&1 || {
    echo "ERROR: InsilicoSeq (iss) not found. Install: conda install -c bioconda insilicoseq"
    exit 1
}

mkdir -p "$OUTPUT_DIR"

# ---------------------------------------------------------------------------
# Enhanced Dataset Configuration
# ---------------------------------------------------------------------------
# Format: "name:total_reads:host_pct:complexity:abundance_dist:read_mode"
#   complexity: low=5, med=30, high=100 species
#   abundance_dist: even, lognormal, skewed
#   read_mode: SE, PE

DATASETS=(
    # --- Low contamination series (to test false positives) ---
    "5M_1pct_low_even_SE:5000000:0.01:low:even:SE"
    "5M_5pct_low_even_SE:5000000:0.05:low:even:SE"
    "10M_1pct_med_lognormal_SE:10000000:0.01:med:lognormal:SE"
    "10M_5pct_med_lognormal_SE:10000000:0.05:med:lognormal:SE"
    
    # --- Medium contamination series (balanced) ---
    "10M_10pct_med_even_SE:10000000:0.10:med:even:SE"
    "10M_30pct_med_lognormal_SE:10000000:0.30:med:lognormal:SE"
    "20M_50pct_med_lognormal_PE:20000000:0.50:med:lognormal:PE"
    "30M_50pct_high_skewed_SE:30000000:0.50:high:skewed:SE"
    
    # --- High contamination series (to test false negatives) ---
    "30M_70pct_med_lognormal_SE:30000000:0.70:med:lognormal:SE"
    "30M_90pct_med_lognormal_SE:30000000:0.90:med:lognormal:SE"
    "60M_90pct_high_lognormal_SE:60000000:0.90:high:lognormal:SE"
    "60M_99pct_med_lognormal_SE:60000000:0.99:med:lognormal:SE"
    
    # --- Large dataset series (scalability test) ---
    "100M_50pct_high_lognormal_SE:100000000:0.50:high:lognormal:SE"
    "100M_90pct_high_lognormal_SE:100000000:0.90:high:lognormal:SE"
    
    # --- Paired-end series ---
    "20M_10pct_med_even_PE:20000000:0.10:med:even:PE"
    "20M_50pct_med_lognormal_PE:20000000:0.50:med:lognormal:PE"
    "20M_90pct_med_lognormal_PE:20000000:0.90:med:lognormal:PE"
    
    # --- Extreme scenarios ---
    "10M_0pct_med_lognormal_SE:10000000:0.00:med:lognormal:SE"
    "10M_100pct_med_lognormal_SE:10000000:1.00:med:lognormal:SE"
)

# ---------------------------------------------------------------------------
# Enhanced Genome Preparation
# ---------------------------------------------------------------------------

echo "[1/5] Preparing input genomes..."

MICROBIAL_FASTA="$OUTPUT_DIR/microbial_genomes.fasta"
HUMAN_FASTA="$OUTPUT_DIR/human_genome.fasta"

combine_genomes_by_complexity() {
    local complexity="$1"
    local output="$2"
    local n_species
    
    case "$complexity" in
        low) n_species=5 ;;
        med) n_species=30 ;;
        high) n_species=100 ;;
        *) n_species=30 ;;
    esac
    
    if [ -d "$GENOME_DIR/genomes_fasta" ]; then
        local all_genomes=("$GENOME_DIR"/genomes_fasta/*.fasta)
        local count=${#all_genomes[@]}
        
        if [ "$count" -eq 0 ]; then
            echo "    WARNING: No genomes found in $GENOME_DIR/genomes_fasta. Using E. coli fallback."
            if [ ! -f "$OUTPUT_DIR/ecoli_test.fasta" ]; then
                curl -s "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nuccore&id=U00096.3&rettype=fasta&retmode=text" > "$OUTPUT_DIR/ecoli_test.fasta"
            fi
            cp "$OUTPUT_DIR/ecoli_test.fasta" "$output"
            return
        fi
        
        # Deterministically sample n_species genomes (with replacement if needed).
        # This avoids concatenating the same genome thousands of times while still
        # providing enough distinct reference sequences for InsilicoSeq.
        > "$output"
        for i in $(seq 0 $((n_species - 1))); do
            local idx=$((i % count))
            cat "${all_genomes[$idx]}" >> "$output"
        done
        echo "    Combined $n_species genomes (sampled from $count available) for $complexity complexity"
    else
        # Fallback: E. coli genome
        echo "    WARNING: Genome directory not found. Using E. coli as fallback."
        if [ ! -f "$OUTPUT_DIR/ecoli_test.fasta" ]; then
            curl -s "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nuccore&id=U00096.3&rettype=fasta&retmode=text" > "$OUTPUT_DIR/ecoli_test.fasta"
        fi
        cp "$OUTPUT_DIR/ecoli_test.fasta" "$output"
    fi
}

# Prepare human genome
if [ ! -f "$HUMAN_FASTA" ]; then
    if [ -f "$HUMAN_GENOME" ]; then
        if [[ "$HUMAN_GENOME" == *.gz ]]; then
            gunzip -c "$HUMAN_GENOME" > "$HUMAN_FASTA"
        else
            cp "$HUMAN_GENOME" "$HUMAN_FASTA"
        fi
    else
        echo "Downloading human genome chr1..."
        curl -s "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nuccore&id=NC_000001.11&rettype=fasta&retmode=text" > "$HUMAN_FASTA"
    fi
fi

# ---------------------------------------------------------------------------
# Generate abundance profiles with different distributions
# ---------------------------------------------------------------------------

echo ""
echo "[2/5] Generating abundance profiles..."

cat > "$OUTPUT_DIR/generate_abundance.py" << 'PYEOF'
import sys
import numpy as np
import json

def generate_abundance(n_species, distribution, output_file):
    """Generate relative abundance profile."""
    
    if distribution == 'lognormal':
        mu, sigma = 0, 2
        abundances = np.random.lognormal(mu, sigma, n_species)
    elif distribution == 'even':
        abundances = np.ones(n_species)
    elif distribution == 'skewed':
        # One dominant species, rest very rare
        abundances = np.array([0.5] + [0.5/(n_species-1)] * (n_species - 1))
    elif distribution == 'powerlaw':
        # Power law distribution
        abundances = np.array([1.0 / (i+1)**1.5 for i in range(n_species)])
    else:
        abundances = np.random.lognormal(0, 2, n_species)
    
    abundances = abundances / abundances.sum()
    
    with open(output_file, 'w') as f:
        for i, ab in enumerate(abundances):
            f.write(f"species_{i+1}\t{ab:.8f}\n")
    
    return abundances

def estimate_complexity(complexity_str):
    if complexity_str == 'low': return 5
    elif complexity_str == 'med': return 30
    elif complexity_str == 'high': return 100
    return 30

if __name__ == '__main__':
    complexity = sys.argv[1]
    distribution = sys.argv[2]
    output = sys.argv[3]
    n = estimate_complexity(complexity)
    generate_abundance(n, distribution, output)
    print(f"Generated {n} species ({distribution} distribution): {output}")
PYEOF

# ---------------------------------------------------------------------------
# Generate datasets
# ---------------------------------------------------------------------------

echo ""
echo "[3/5] Generating simulated reads..."

for dataset_config in "${DATASETS[@]}"; do
    IFS=':' read -r DATASET_NAME TOTAL_READS HOST_PCT COMPLEXITY ABUNDANCE_DIST READ_MODE <<< "$dataset_config"
    
    echo ""
    echo "--- Dataset: $DATASET_NAME ---"
    echo "  Reads: $TOTAL_READS | Host: $HOST_PCT | Complexity: $COMPLEXITY | Dist: $ABUNDANCE_DIST | Mode: $READ_MODE"
    
    DATASET_DIR="$OUTPUT_DIR/$DATASET_NAME"
    mkdir -p "$DATASET_DIR"
    
    if [ -f "$DATASET_DIR/completed.flag" ]; then
        echo "  Already generated. Skipping."
        continue
    fi
    
    # Prepare microbial genome for this complexity level
    MICROBIAL_FA="$DATASET_DIR/microbial_input.fasta"
    combine_genomes_by_complexity "$COMPLEXITY" "$MICROBIAL_FA"
    
    # Generate abundance profile
    ABUNDANCE_FILE="$DATASET_DIR/abundance.txt"
    python "$OUTPUT_DIR/generate_abundance.py" "$COMPLEXITY" "$ABUNDANCE_DIST" "$ABUNDANCE_FILE"
    
    # Calculate reads
    HOST_READS=$(python -c "print(int($TOTAL_READS * $HOST_PCT))")
    MICROBE_READS=$(python -c "print(int($TOTAL_READS * (1 - $HOST_PCT)))")
    
    # Handle edge cases
    if [ "$HOST_PCT" == "0.00" ] || [ "$HOST_READS" -eq 0 ]; then
        HOST_READS=0
    fi
    if [ "$HOST_PCT" == "1.00" ] || [ "$MICROBE_READS" -eq 0 ]; then
        MICROBE_READS=0
    fi
    
    echo "  Host reads: $HOST_READS, Microbial reads: $MICROBE_READS"
    
    # Generate microbial reads (always needed unless 100% host)
    if [ "$MICROBE_READS" -gt 0 ]; then
        echo "  Generating microbial reads..."
        iss generate \
            --genomes "$MICROBIAL_FA" \
            --abundance_file "$ABUNDANCE_FILE" \
            --model miseq \
            --n_reads "$MICROBE_READS" \
            --output "$DATASET_DIR/microbe" \
            --cpus 4 \
            2>&1 | tee "$DATASET_DIR/microbe.log"
    fi
    
    # Generate host reads (always needed unless 0% host)
    if [ "$HOST_READS" -gt 0 ]; then
        echo "  Generating host reads..."
        iss generate \
            --genomes "$HUMAN_FASTA" \
            --model miseq \
            --n_reads "$HOST_READS" \
            --output "$DATASET_DIR/host" \
            --cpus 4 \
            2>&1 | tee "$DATASET_DIR/host.log"
    fi
    
    # Merge and label
    echo "  Merging and labeling..."
    
    if [ "$READ_MODE" == "PE" ]; then
        # Paired-end
        if [ "$MICROBE_READS" -gt 0 ] && [ "$HOST_READS" -gt 0 ]; then
            cat "$DATASET_DIR/microbe_R1.fastq" "$DATASET_DIR/host_R1.fastq" > "$DATASET_DIR/reads_R1.fastq"
            cat "$DATASET_DIR/microbe_R2.fastq" "$DATASET_DIR/host_R2.fastq" > "$DATASET_DIR/reads_R2.fastq"
            
            # Ground truth labels
            awk -v n="$MICROBE_READS" '
                NR%4==1 {
                    if ((NR+3)/4 <= n) {
                        print substr($0, 2) "\tmicrobe"
                    } else {
                        print substr($0, 2) "\thost"
                    }
                }
            ' "$DATASET_DIR/reads_R1.fastq" > "$DATASET_DIR/ground_truth_labels.txt"
            
        elif [ "$MICROBE_READS" -gt 0 ]; then
            cp "$DATASET_DIR/microbe_R1.fastq" "$DATASET_DIR/reads_R1.fastq"
            cp "$DATASET_DIR/microbe_R2.fastq" "$DATASET_DIR/reads_R2.fastq"
            awk 'NR%4==1 {print substr($0, 2) "\tmicrobe"}' "$DATASET_DIR/reads_R1.fastq" > "$DATASET_DIR/ground_truth_labels.txt"
        else
            cp "$DATASET_DIR/host_R1.fastq" "$DATASET_DIR/reads_R1.fastq"
            cp "$DATASET_DIR/host_R2.fastq" "$DATASET_DIR/reads_R2.fastq"
            awk 'NR%4==1 {print substr($0, 2) "\thost"}' "$DATASET_DIR/reads_R1.fastq" > "$DATASET_DIR/ground_truth_labels.txt"
        fi
        
        pigz -p 4 "$DATASET_DIR/reads_R1.fastq"
        pigz -p 4 "$DATASET_DIR/reads_R2.fastq"
        echo "  Output: reads_R1.fastq.gz, reads_R2.fastq.gz"
        
    else
        # Single-end
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
    "complexity": "$COMPLEXITY",
    "abundance_distribution": "$ABUNDANCE_DIST",
    "read_mode": "$READ_MODE",
    "read_length": 150,
    "simulator": "InsilicoSeq",
    "model": "miseq"
}
EOF
    
    touch "$DATASET_DIR/completed.flag"
    echo "  Completed."
    
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "========================================"
echo "Enhanced Data Generation Complete!"
echo "========================================"

total_datasets=0
for dataset_config in "${DATASETS[@]}"; do
    IFS=':' read -r DATASET_NAME _ _ _ _ _ <<< "$dataset_config"
    if [ -f "$OUTPUT_DIR/$DATASET_NAME/completed.flag" ]; then
        total_datasets=$((total_datasets + 1))
    fi
done

echo ""
echo "Successfully generated: $total_datasets / ${#DATASETS[@]} datasets"
echo ""
echo "Dataset breakdown:"

# Count by host contamination
for pct in 0.00 0.01 0.05 0.10 0.30 0.50 0.70 0.90 0.99 1.00; do
    count=$(grep -c ":$pct:" <<< "$(printf '%s\n' "${DATASETS[@]}")" || true)
    if [ "$count" -gt 0 ]; then
        pct_label=$(python -c "print(f'{${pct}*100:.0f}%')" 2>/dev/null || echo "$pct")
        echo "  Host $pct_label: $count datasets"
    fi
done

echo ""
echo "Next: bash scripts/run_enhanced_benchmark.sh"
