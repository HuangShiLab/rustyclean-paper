#!/bin/bash
#SBATCH --job-name=rustyclean_generate_all
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err
#SBATCH --cpus-per-task=32
#SBATCH --mem=128G
#SBATCH --time=168:00:00
#SBATCH --partition=amd

# =============================================================================
# RustyClean Benchmark — Sequential All-Dataset Generation (single SLURM job)
# =============================================================================
# Generates all enhanced datasets sequentially in one job to avoid SLURM
# job-submission limits. Uses ART_illumina (fast) instead of InsilicoSeq,
# which is too slow for hundreds of millions of reads.

set -euo pipefail

PROJECT_DIR="/lustre1/g/aos_shihuang/rustyclean-paper"
SCRATCH_DIR="${SCRATCH_DIR:-/scr/u/$USER/rustyclean-paper}"
cd "$PROJECT_DIR"

# Locate the repository. SLURM copies the batch script to a spool directory, so
# $0 does not point into the repo under sbatch, and config.sh cannot be found via
# a variable that config.sh itself defines.
if [ -z "${REPO_DIR:-}" ]; then
    for _cand in "${SLURM_SUBMIT_DIR:-}" \
                 "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)" \
                 /lustre1/g/aos_shihuang/rustyclean-paper; do
        if [ -n "$_cand" ] && [ -f "$_cand/scripts/hpc/config.sh" ]; then
            REPO_DIR="$_cand"; break
        fi
    done
fi
if [ -z "${REPO_DIR:-}" ]; then
    echo "ERROR: cannot locate the repository. Set REPO_DIR to its path." >&2
    exit 1
fi
source "$REPO_DIR/scripts/hpc/config.sh"

# Use user scratch for intermediate I/O.
export LOCAL_SCRATCH="$SCRATCH_DIR/.scratch_${SLURM_JOB_ID:-$$}"
activate_conda

command -v art_illumina >/dev/null 2>&1 || {
    echo "ERROR: art_illumina not found. Install: mamba install -c bioconda art" >&2
    exit 1
}
command -v seqtk >/dev/null 2>&1 || {
    echo "ERROR: seqtk not found" >&2
    exit 1
}

mkdir -p "$DATA_DIR"
mkdir -p "$LOG_DIR/generate"

# ---------------------------------------------------------------------------
# Dataset definitions (must match generate_enhanced_data.sh)
# ---------------------------------------------------------------------------
DATASETS=(
    "5M_1pct_low_even_SE:5000000:0.01:low:even:SE"
    "5M_5pct_low_even_SE:5000000:0.05:low:even:SE"
    "10M_1pct_med_lognormal_SE:10000000:0.01:med:lognormal:SE"
    "10M_5pct_med_lognormal_SE:10000000:0.05:med:lognormal:SE"
    "10M_10pct_med_even_SE:10000000:0.10:med:even:SE"
    "10M_30pct_med_lognormal_SE:10000000:0.30:med:lognormal:SE"
    "20M_50pct_med_lognormal_PE:20000000:0.50:med:lognormal:PE"
    "30M_50pct_high_skewed_SE:30000000:0.50:high:skewed:SE"
    "30M_70pct_med_lognormal_SE:30000000:0.70:med:lognormal:SE"
    "30M_90pct_med_lognormal_SE:30000000:0.90:med:lognormal:SE"
    "60M_90pct_high_lognormal_SE:60000000:0.90:high:lognormal:SE"
    "60M_99pct_med_lognormal_SE:60000000:0.99:med:lognormal:SE"
    "100M_50pct_high_lognormal_SE:100000000:0.50:high:lognormal:SE"
    "100M_90pct_high_lognormal_SE:100000000:0.90:high:lognormal:SE"
    "20M_10pct_med_even_PE:20000000:0.10:med:even:PE"
    "20M_90pct_med_lognormal_PE:20000000:0.90:med:lognormal:PE"
    "10M_0pct_med_lognormal_SE:10000000:0.00:med:lognormal:SE"
    "10M_100pct_med_lognormal_SE:10000000:1.00:med:lognormal:SE"
)

CPUS="${SLURM_CPUS_PER_TASK:-16}"
READ_LEN=150

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
fasta_length() {
    seqtk comp "$1" | awk '{s+=$2} END{print s}'
}

run_art() {
    local genome="$1"
    local cov="$2"
    local mode="$3"
    local out_prefix="$4"
    local seed="$5"
    local log="$6"

    if [ "$mode" == "PE" ]; then
        art_illumina -ss HS25 -i "$genome" -p -l "$READ_LEN" -f "$cov" \
            -m 300 -s 30 -o "$out_prefix" -na -rs "$seed" >> "$log" 2>&1
    else
        art_illumina -ss HS25 -i "$genome" -l "$READ_LEN" -f "$cov" \
            -o "$out_prefix" -na -rs "$seed" >> "$log" 2>&1
    fi
}

# ---------------------------------------------------------------------------
# Prepare human genome once on local scratch
# ---------------------------------------------------------------------------
MAIN_WORKDIR="$LOCAL_SCRATCH/generate_all"
mkdir -p "$MAIN_WORKDIR"
HUMAN_FASTA="$MAIN_WORKDIR/human_genome.fasta"

if [ ! -f "$HUMAN_FASTA" ]; then
    echo "Decompressing human genome to local scratch..."
    if [[ "$HUMAN_GENOME" == *.gz ]]; then
        gunzip -c "$HUMAN_GENOME" > "$HUMAN_FASTA"
    else
        cp "$HUMAN_GENOME" "$HUMAN_FASTA"
    fi
fi
HUMAN_LEN=$(fasta_length "$HUMAN_FASTA")
echo "Human genome length: $HUMAN_LEN"

# ---------------------------------------------------------------------------
# Generate each dataset sequentially
# ---------------------------------------------------------------------------
N_TOTAL=${#DATASETS[@]}
N_DONE=0

for dataset_config in "${DATASETS[@]}"; do
    IFS=':' read -r DATASET_NAME TOTAL_READS HOST_PCT COMPLEXITY ABUNDANCE_DIST READ_MODE <<< "$dataset_config"
    DATASET_DIR="$DATA_DIR/$DATASET_NAME"
    LOG_FILE="$LOG_DIR/generate/${DATASET_NAME}.log"

    N_DONE=$((N_DONE + 1))
    echo ""
    echo "[$N_DONE/$N_TOTAL] Dataset: $DATASET_NAME"
    echo "  Reads: $TOTAL_READS | Host: $HOST_PCT | Complexity: $COMPLEXITY | Dist: $ABUNDANCE_DIST | Mode: $READ_MODE"
    echo "  Start: $(date -Iseconds)"

    if [ -f "$DATASET_DIR/completed.flag" ]; then
        echo "  Already generated. Skipping."
        continue
    fi

    mkdir -p "$DATASET_DIR"
    WORKDIR="$MAIN_WORKDIR/$DATASET_NAME"
    mkdir -p "$WORKDIR"
    > "$LOG_FILE"

    # -----------------------------------------------------------------------
    # Select microbial genomes and build abundance profile
    # -----------------------------------------------------------------------
    n_species=30
    case "$COMPLEXITY" in
        low) n_species=5 ;;
        med) n_species=30 ;;
        high) n_species=100 ;;
    esac

    mapfile -t raw_genomes < <(ls "$GENOME_DIR"/genomes_fasta/*.fasta 2>/dev/null || true)
    all_genomes=()
    for g in "${raw_genomes[@]}"; do
        glen=$(fasta_length "$g" 2>/dev/null || echo 0)
        [ -n "$glen" ] && [ "$glen" -gt 0 ] && all_genomes+=("$g")
    done
    n_avail=${#all_genomes[@]}
    if [ "$n_avail" -eq 0 ]; then
        echo "ERROR: No usable microbial genomes found in $GENOME_DIR/genomes_fasta" >&2
        exit 1
    fi

    SELECTED_LIST="$WORKDIR/selected_genomes.txt"
    > "$SELECTED_LIST"
    for i in $(seq 0 $((n_species - 1))); do
        idx=$((i % n_avail))
        echo "${all_genomes[$idx]}" >> "$SELECTED_LIST"
    done

    GENOME_ABUNDANCE="$WORKDIR/genome_abundance.txt"
    python3 - "$COMPLEXITY" "$ABUNDANCE_DIST" "$SELECTED_LIST" "$GENOME_ABUNDANCE" <<'PYEOF'
import sys
import numpy as np
np.random.seed(42)

complexity, distribution, selected_list, output_file = sys.argv[1:5]
n_target = {'low': 5, 'med': 30, 'high': 100}.get(complexity, 30)

with open(selected_list) as f:
    genome_files = [l.strip() for l in f if l.strip()]

n = min(n_target, len(genome_files))
genome_files = genome_files[:n]

if distribution == 'lognormal':
    abundances = np.random.lognormal(0, 2, n)
elif distribution == 'even':
    abundances = np.ones(n)
elif distribution == 'skewed':
    abundances = np.array([0.5] + [0.5/(n-1)] * (n-1))
else:
    abundances = np.random.lognormal(0, 2, n)

abundances = abundances / abundances.sum()

with open(output_file, 'w') as f:
    for gf, ab in zip(genome_files, abundances):
        f.write(f'{gf}\t{ab:.10f}\n')
PYEOF

    actual_n_species=$(wc -l < "$GENOME_ABUNDANCE")
    echo "  Prepared $actual_n_species species (requested $n_species) from $n_avail genomes."

    # -----------------------------------------------------------------------
    # Calculate host/microbe read counts
    # -----------------------------------------------------------------------
    HOST_READS=$(python3 -c "print(int($TOTAL_READS * $HOST_PCT))")
    MICROBE_READS=$(python3 -c "print(int($TOTAL_READS * (1 - $HOST_PCT)))")
    [ "$HOST_READS" -eq 0 ] && HOST_READS=0
    [ "$MICROBE_READS" -eq 0 ] && MICROBE_READS=0
    echo "  Host reads: $HOST_READS, Microbial reads: $MICROBE_READS"

    READ_BASES=$READ_LEN
    [ "$READ_MODE" == "PE" ] && READ_BASES=$((READ_LEN * 2))

    # -----------------------------------------------------------------------
    # Generate microbial reads with ART in parallel per genome
    # -----------------------------------------------------------------------
    if [ "$MICROBE_READS" -gt 0 ]; then
        echo "  Generating microbial reads..."
        idx=0
        while IFS=$'\t' read -r genome abundance; do
            [ -f "$genome" ] || continue
            gl=$(fasta_length "$genome" 2>/dev/null || echo 0)
            [ -n "$gl" ] && [ "$gl" -gt 0 ] || { idx=$((idx + 1)); continue; }
            cov=$(python3 -c "print($MICROBE_READS * $abundance * $READ_BASES / $gl)")
            # Skip negligible coverage
            if python3 -c "import sys; sys.exit(0 if float('$cov') >= 1e-6 else 1)"; then
                seed=$((42 + idx))
                run_art "$genome" "$cov" "$READ_MODE" "$WORKDIR/microbe_gen${idx}" "$seed" "$LOG_FILE" &
            fi
            idx=$((idx + 1))
        done < "$GENOME_ABUNDANCE"
        wait

        # Concatenate outputs
        if [ "$READ_MODE" == "PE" ]; then
            > "$WORKDIR/microbe_R1.fastq"
            > "$WORKDIR/microbe_R2.fastq"
            for i in $(seq 0 $((idx - 1))); do
                if [ -f "$WORKDIR/microbe_gen${i}1.fq" ]; then
                    cat "$WORKDIR/microbe_gen${i}1.fq" >> "$WORKDIR/microbe_R1.fastq"
                    cat "$WORKDIR/microbe_gen${i}2.fq" >> "$WORKDIR/microbe_R2.fastq"
                fi
            done
        else
            > "$WORKDIR/microbe_reads.fastq"
            for i in $(seq 0 $((idx - 1))); do
                if [ -f "$WORKDIR/microbe_gen${i}.fq" ]; then
                    cat "$WORKDIR/microbe_gen${i}.fq" >> "$WORKDIR/microbe_reads.fastq"
                fi
            done
        fi
    fi

    # -----------------------------------------------------------------------
    # Generate host reads with ART
    # -----------------------------------------------------------------------
    if [ "$HOST_READS" -gt 0 ]; then
        echo "  Generating host reads..."
        HOST_COV=$(python3 -c "print($HOST_READS * $READ_BASES / $HUMAN_LEN)")
        run_art "$HUMAN_FASTA" "$HOST_COV" "$READ_MODE" "$WORKDIR/host" 100 "$LOG_FILE"
        if [ "$READ_MODE" == "PE" ]; then
            mv "$WORKDIR/host1.fq" "$WORKDIR/host_R1.fastq"
            mv "$WORKDIR/host2.fq" "$WORKDIR/host_R2.fastq"
        else
            mv "$WORKDIR/host.fq" "$WORKDIR/host_reads.fastq"
        fi
    fi

    # -----------------------------------------------------------------------
    # Merge, label, compress, and copy to shared storage
    # -----------------------------------------------------------------------
    echo "  Merging and labeling..."
    LABEL_FILE="$WORKDIR/ground_truth_labels.txt"
    > "$LABEL_FILE"

    if [ "$READ_MODE" == "PE" ]; then
        > "$WORKDIR/reads_R1.fastq"
        > "$WORKDIR/reads_R2.fastq"
        [ -f "$WORKDIR/microbe_R1.fastq" ] && cat "$WORKDIR/microbe_R1.fastq" >> "$WORKDIR/reads_R1.fastq"
        [ -f "$WORKDIR/host_R1.fastq" ] && cat "$WORKDIR/host_R1.fastq" >> "$WORKDIR/reads_R1.fastq"
        [ -f "$WORKDIR/microbe_R2.fastq" ] && cat "$WORKDIR/microbe_R2.fastq" >> "$WORKDIR/reads_R2.fastq"
        [ -f "$WORKDIR/host_R2.fastq" ] && cat "$WORKDIR/host_R2.fastq" >> "$WORKDIR/reads_R2.fastq"

        [ -f "$WORKDIR/microbe_R1.fastq" ] && awk 'NR%4==1 {print substr($0, 2) "\tmicrobe"}' "$WORKDIR/microbe_R1.fastq" >> "$LABEL_FILE"
        [ -f "$WORKDIR/host_R1.fastq" ] && awk 'NR%4==1 {print substr($0, 2) "\thost"}' "$WORKDIR/host_R1.fastq" >> "$LABEL_FILE"

        pigz -p "$CPUS" "$WORKDIR/reads_R1.fastq"
        pigz -p "$CPUS" "$WORKDIR/reads_R2.fastq"
        cp "$WORKDIR/reads_R1.fastq.gz" "$WORKDIR/reads_R2.fastq.gz" "$DATASET_DIR/"
    else
        > "$WORKDIR/reads.fastq"
        [ -f "$WORKDIR/microbe_reads.fastq" ] && cat "$WORKDIR/microbe_reads.fastq" >> "$WORKDIR/reads.fastq"
        [ -f "$WORKDIR/host_reads.fastq" ] && cat "$WORKDIR/host_reads.fastq" >> "$WORKDIR/reads.fastq"

        [ -f "$WORKDIR/microbe_reads.fastq" ] && awk 'NR%4==1 {print substr($0, 2) "\tmicrobe"}' "$WORKDIR/microbe_reads.fastq" >> "$LABEL_FILE"
        [ -f "$WORKDIR/host_reads.fastq" ] && awk 'NR%4==1 {print substr($0, 2) "\thost"}' "$WORKDIR/host_reads.fastq" >> "$LABEL_FILE"

        pigz -p "$CPUS" "$WORKDIR/reads.fastq"
        cp "$WORKDIR/reads.fastq.gz" "$DATASET_DIR/"
    fi

    cp "$LABEL_FILE" "$DATASET_DIR/"

    cat > "$DATASET_DIR/metadata.json" <<EOF
{
    "dataset_name": "$DATASET_NAME",
    "total_reads": $TOTAL_READS,
    "host_percentage": $HOST_PCT,
    "host_reads": $HOST_READS,
    "microbial_reads": $MICROBE_READS,
    "complexity": "$COMPLEXITY",
    "abundance_distribution": "$ABUNDANCE_DIST",
    "read_mode": "$READ_MODE",
    "read_length": $READ_LEN,
    "simulator": "ART_illumina_HS25",
    "model": "hiseq2500"
}
EOF

    touch "$DATASET_DIR/completed.flag"
    rm -rf "$WORKDIR"

    echo "  End: $(date -Iseconds)"
    echo "[$N_DONE/$N_TOTAL] Dataset $DATASET_NAME completed."
done

# Final cleanup
rm -rf "$MAIN_WORKDIR" "$LOCAL_SCRATCH"

echo ""
echo "========================================"
echo "All $N_TOTAL datasets generated."
echo "========================================"
