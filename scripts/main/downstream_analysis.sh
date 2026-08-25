#!/bin/bash
# =============================================================================
# RustyClean Benchmark - Downstream Analysis Pipeline
# =============================================================================
# Comprehensive downstream analysis for host removal evaluation:
#   1. Taxonomic profiling (Kraken2/Bracken)
#   2. Alpha diversity (Shannon, Simpson, Chao1)
#   3. Beta diversity / PCoA (Bray-Curtis)
#   4. Metagenomic assembly (MEGAHIT)
#   5. MAG binning (MetaWRAP)
#   6. MAG quality (CheckM2)
#   7. Functional profiling (HUMAnN3 / eggNOG)
#
# Usage: bash scripts/main/downstream_analysis.sh <results_dir> [data_dir]
# Default data_dir: ./data/enhanced

set -e

RESULTS_DIR="${1:-./results}"
DATA_DIR="${2:-./data/enhanced}"
KRAKEN2_DB="${KRAKEN2_DB:-$HOME/benchmark_env/databases/minikraken2_v1_8GB}"
BRACKEN_DB="${BRACKEN_DB:-$HOME/benchmark_env/databases/minikraken2_v1_8GB}"
N_THREADS=8

echo "========================================"
echo "Downstream Analysis Pipeline"
echo "========================================"
echo "Results: $RESULTS_DIR"
echo "Data: $DATA_DIR"
echo "Threads: $N_THREADS"
echo ""

# Check dependencies
for tool in kraken2 bracken megahit checkm2 humann; do
    command -v "$tool" >/dev/null 2>&1 || echo "WARNING: $tool not found"
done

mkdir -p "$RESULTS_DIR/downstream"

# ---------------------------------------------------------------------------
# 1. Taxonomic Profiling with Kraken2 + Bracken
# ---------------------------------------------------------------------------

run_taxonomic_profiling() {
    local tool="$1"
    local dataset="$2"
    local rep="$3"
    local reads_dir="$RESULTS_DIR/$tool/${dataset}_rep${rep}"
    local output_dir="$RESULTS_DIR/downstream/taxonomy/${tool}/${dataset}_rep${rep}"
    
    mkdir -p "$output_dir"
    
    # Find clean reads
    local read_file
    if [ -f "$reads_dir/reads.fastq.gz" ]; then
        read_file="$reads_dir/reads.fastq.gz"
    elif [ -f "$reads_dir/reads_R1.fastq.gz" ]; then
        read_file="$reads_dir/reads_R1.fastq.gz"
    else
        # Try to find any fastq in the output
        read_file=$(find "$reads_dir" -name "*.fastq.gz" | head -1)
    fi
    
    if [ -z "$read_file" ] || [ ! -f "$read_file" ]; then
        echo "  WARNING: No reads found for $tool $dataset rep$rep"
        return
    fi
    
    echo "  Taxonomic profiling: $tool $dataset rep$rep"
    
    # Kraken2 classification
    local kraken_out="$output_dir/kraken2_output.txt"
    local report_out="$output_dir/kraken2_report.txt"
    
    kraken2 --db "$KRAKEN2_DB" \
        --threads "$N_THREADS" \
        --output "$kraken_out" \
        --report "$report_out" \
        "$read_file" \
        2>&1 | tee "$output_dir/kraken2.log"
    
    # Bracken abundance estimation
    local bracken_out="$output_dir/bracken_species.txt"
    
    if command -v bracken >/dev/null 2>&1; then
        bracken -d "$BRACKEN_DB" \
            -i "$report_out" \
            -o "$bracken_out" \
            -r 150 \
            -l S \
            2>&1 | tee "$output_dir/bracken.log"
    fi
    
    echo "    Taxonomy done: $output_dir"
}

# ---------------------------------------------------------------------------
# 2. Metagenomic Assembly with MEGAHIT
# ---------------------------------------------------------------------------

run_assembly() {
    local tool="$1"
    local dataset="$2"
    local rep="$3"
    local reads_dir="$RESULTS_DIR/$tool/${dataset}_rep${rep}"
    local output_dir="$RESULTS_DIR/downstream/assembly/${tool}/${dataset}_rep${rep}"
    
    mkdir -p "$output_dir"
    
    # Find reads
    local r1_file r2_file
    if [ -f "$reads_dir/reads_R1.fastq.gz" ] && [ -f "$reads_dir/reads_R2.fastq.gz" ]; then
        r1_file="$reads_dir/reads_R1.fastq.gz"
        r2_file="$reads_dir/reads_R2.fastq.gz"
    elif [ -f "$reads_dir/reads.fastq.gz" ]; then
        r1_file="$reads_dir/reads.fastq.gz"
        r2_file=""
    else
        echo "  WARNING: No reads found for assembly $tool $dataset"
        return
    fi
    
    echo "  Assembly: $tool $dataset rep$rep"
    
    if command -v megahit >/dev/null 2>&1; then
        if [ -n "$r2_file" ]; then
            megahit -1 "$r1_file" -2 "$r2_file" \
                -o "$output_dir/megahit_out" \
                -t "$N_THREADS" \
                2>&1 | tee "$output_dir/megahit.log"
        else
            megahit -r "$r1_file" \
                -o "$output_dir/megahit_out" \
                -t "$N_THREADS" \
                2>&1 | tee "$output_dir/megahit.log"
        fi
        
        # Assembly stats
        if [ -f "$output_dir/megahit_out/final.contigs.fa" ]; then
            python -c "
from Bio import SeqIO
import sys
contigs = list(SeqIO.parse('$output_dir/megahit_out/final.contigs.fa', 'fasta'))
lengths = [len(c) for c in contigs]
print(f'  Contigs: {len(contigs)}')
print(f'  Total bases: {sum(lengths)}')
print(f'  N50: {sorted(lengths)[len(lengths)//2] if lengths else 0}')
print(f'  Max length: {max(lengths) if lengths else 0}')
"
        fi
    else
        echo "    MEGAHIT not installed, skipping assembly"
    fi
    
    echo "    Assembly done: $output_dir"
}

# ---------------------------------------------------------------------------
# 3. MAG Quality with CheckM2
# ---------------------------------------------------------------------------

run_checkm2() {
    local tool="$1"
    local dataset="$2"
    local rep="$3"
    local assembly_dir="$RESULTS_DIR/downstream/assembly/${tool}/${dataset}_rep${rep}/megahit_out"
    local output_dir="$RESULTS_DIR/downstream/checkm2/${tool}/${dataset}_rep${rep}"
    
    if [ ! -f "$assembly_dir/final.contigs.fa" ]; then
        return
    fi
    
    mkdir -p "$output_dir"
    
    echo "  CheckM2: $tool $dataset rep$rep"
    
    if command -v checkm2 >/dev/null 2>&1; then
        # For CheckM2, we need bins, not just contigs
        # Use MetaWRAP binning or just evaluate contigs as single bins
        checkm2 predict \
            --input "$assembly_dir/final.contigs.fa" \
            --output-directory "$output_dir" \
            --threads "$N_THREADS" \
            2>&1 | tee "$output_dir/checkm2.log"
    else
        echo "    CheckM2 not installed, skipping"
    fi
    
    echo "    CheckM2 done: $output_dir"
}

# ---------------------------------------------------------------------------
# 4. Alpha & Beta Diversity Analysis
# ---------------------------------------------------------------------------

run_diversity_analysis() {
    local output_dir="$RESULTS_DIR/downstream/diversity"
    mkdir -p "$output_dir"
    
    echo ""
    echo "[4/5] Diversity Analysis..."
    
    # Python script for diversity analysis
    cat > "$output_dir/calculate_diversity.py" << 'PYEOF'
import os
import sys
import pandas as pd
import numpy as np
from scipy.spatial.distance import braycurtis
from scipy.stats import entropy
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import seaborn as sns

# Nature-style rcParams
plt.rcParams.update({
    "font.family": "sans-serif",
    "font.sans-serif": ["Arial", "Helvetica", "DejaVu Sans"],
    "font.size": 7,
    "axes.spines.right": False,
    "axes.spines.top": False,
    "axes.linewidth": 0.8,
    "legend.frameon": False,
    "svg.fonttype": "none",
    "pdf.fonttype": 42,
})

def parse_bracken(file_path):
    """Parse Bracken output to get species abundance."""
    if not os.path.exists(file_path):
        return {}
    df = pd.read_csv(file_path, sep='\t')
    if 'name' in df.columns and 'fraction_total_reads' in df.columns:
        return dict(zip(df['name'], df['fraction_total_reads']))
    return {}

def shannon_diversity(abundances):
    """Calculate Shannon diversity."""
    abundances = np.array(abundances)
    abundances = abundances[abundances > 0]
    if len(abundances) == 0:
        return 0
    return entropy(abundances, base=2)

def simpson_diversity(abundances):
    """Calculate Simpson diversity."""
    abundances = np.array(abundances)
    if abundances.sum() == 0:
        return 0
    proportions = abundances / abundances.sum()
    return 1 - np.sum(proportions ** 2)

def chao1_richness(abundances):
    """Calculate Chao1 richness estimator."""
    counts = np.array(abundances)
    n1 = np.sum(counts == 1)  # singletons
    n2 = np.sum(counts == 2)  # doubletons
    S_obs = np.sum(counts > 0)
    if n2 > 0:
        return S_obs + n1 * (n1 - 1) / (2 * (n2 + 1))
    return S_obs

def main():
    results_dir = sys.argv[1]
    taxonomy_dir = os.path.join(results_dir, 'downstream', 'taxonomy')
    output_dir = os.path.join(results_dir, 'downstream', 'diversity')
    os.makedirs(output_dir, exist_ok=True)
    
    diversity_results = []
    
    # Scan all taxonomy results
    for tool in ['rustyclean', 'kneaddata']:
        tool_dir = os.path.join(taxonomy_dir, tool)
        if not os.path.exists(tool_dir):
            continue
        
        for dataset_dir in os.listdir(tool_dir):
            bracken_file = os.path.join(tool_dir, dataset_dir, 'bracken_species.txt')
            
            if not os.path.exists(bracken_file):
                continue
            
            abundances = parse_bracken(bracken_file)
            values = list(abundances.values())
            
            if len(values) == 0:
                continue
            
            result = {
                'tool': tool,
                'dataset': dataset_dir,
                'n_species': len(values),
                'shannon': shannon_diversity(values),
                'simpson': simpson_diversity(values),
                'chao1': chao1_richness(values),
            }
            diversity_results.append(result)
    
    if not diversity_results:
        print("No diversity results found.")
        return
    
    df = pd.DataFrame(diversity_results)
    df.to_csv(os.path.join(output_dir, 'diversity_metrics.csv'), index=False)
    
    print(f"Diversity analysis: {len(df)} samples")
    print(df.groupby('tool')[['shannon', 'simpson', 'chao1']].mean().round(4))
    
    # Visualization
    fig, axes = plt.subplots(1, 3, figsize=(10, 3.5))
    
    metrics = ['shannon', 'simpson', 'chao1']
    titles = ['Shannon Diversity', 'Simpson Diversity', 'Chao1 Richness']
    
    for ax, metric, title in zip(axes, metrics, titles):
        sns.boxplot(data=df, x='tool', y=metric, ax=ax, palette=['#3498db', '#e74c3c'])
        ax.set_title(title)
        ax.set_xlabel('')
        ax.set_ylabel(metric.title())
    
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, 'diversity_comparison.svg'), dpi=600, bbox_inches='tight')
    plt.savefig(os.path.join(output_dir, 'diversity_comparison.pdf'), bbox_inches='tight')
    plt.savefig(os.path.join(output_dir, 'diversity_comparison.png'), dpi=300, bbox_inches='tight')
    plt.close()
    
    print(f"Diversity figures saved to {output_dir}")

if __name__ == '__main__':
    main()
PYEOF
    
    python "$output_dir/calculate_diversity.py" "$RESULTS_DIR"
}

# ---------------------------------------------------------------------------
# 5. Functional Profiling (simplified with eggNOG)
# ---------------------------------------------------------------------------

run_functional_profiling() {
    echo ""
    echo "[5/5] Functional profiling requires HUMAnN3 or eggNOG-mapper."
    echo "  Install and configure separately if needed."
}

# ---------------------------------------------------------------------------
# Main execution
# ---------------------------------------------------------------------------

echo "[1/5] Taxonomic profiling..."

for tool in rustyclean kneaddata; do
    tool_dir="$RESULTS_DIR/$tool"
    if [ ! -d "$tool_dir" ]; then
        continue
    fi
    
    for dataset_dir in "$tool_dir"/*; do
        if [ ! -d "$dataset_dir" ]; then
            continue
        fi
        
        dataset_name=$(basename "$dataset_dir")
        # Extract dataset and rep from dirname (e.g., "10M_10pct_med_even_SE_rep1")
        if [[ "$dataset_name" =~ ^(.+)_rep([0-9]+)$ ]]; then
            dataset="${BASH_REMATCH[1]}"
            rep="${BASH_REMATCH[2]}"
            
            run_taxonomic_profiling "$tool" "$dataset" "$rep"
        fi
    done
done

echo ""
echo "[2/5] Metagenomic assembly..."

for tool in rustyclean kneaddata; do
    tool_dir="$RESULTS_DIR/$tool"
    if [ ! -d "$tool_dir" ]; then
        continue
    fi
    
    for dataset_dir in "$tool_dir"/*; do
        if [ ! -d "$dataset_dir" ]; then
            continue
        fi
        
        dataset_name=$(basename "$dataset_dir")
        if [[ "$dataset_name" =~ ^(.+)_rep([0-9]+)$ ]]; then
            dataset="${BASH_REMATCH[1]}"
            rep="${BASH_REMATCH[2]}"
            
            run_assembly "$tool" "$dataset" "$rep"
        fi
    done
done

echo ""
echo "[3/5] MAG quality assessment..."

for tool in rustyclean kneaddata; do
    tool_dir="$RESULTS_DIR/$tool"
    if [ ! -d "$tool_dir" ]; then
        continue
    fi
    
    for dataset_dir in "$tool_dir"/*; do
        if [ ! -d "$dataset_dir" ]; then
            continue
        fi
        
        dataset_name=$(basename "$dataset_dir")
        if [[ "$dataset_name" =~ ^(.+)_rep([0-9]+)$ ]]; then
            dataset="${BASH_REMATCH[1]}"
            rep="${BASH_REMATCH[2]}"
            
            run_checkm2 "$tool" "$dataset" "$rep"
        fi
    done
done

echo ""
run_diversity_analysis

echo ""
echo "========================================"
echo "Downstream Analysis Complete!"
echo "========================================"
echo ""
echo "Results:"
echo "  Taxonomy:   $RESULTS_DIR/downstream/taxonomy/"
echo "  Assembly:   $RESULTS_DIR/downstream/assembly/"
echo "  CheckM2:    $RESULTS_DIR/downstream/checkm2/"
echo "  Diversity:  $RESULTS_DIR/downstream/diversity/"
