#!/bin/bash
#SBATCH --job-name=rustyclean_generate
#SBATCH --output=logs/%x-%A_%a.out
#SBATCH --error=logs/%x-%A_%a.err
#SBATCH --array=1-18
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=4:00:00
#SBATCH --partition=amd

# =============================================================================
# RustyClean Benchmark — HPC Enhanced Data Generation (SLURM array)
# =============================================================================
# Generates one enhanced dataset per array task.
#
# Usage:
#   sbatch scripts/hpc/generate_data_slurm.sh
#
# Adjust --array above to match the number of datasets (default 18, max 6 concurrent).

set -euo pipefail

PROJECT_DIR="/lustre1/g/aos_shihuang/rustyclean-paper"
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

# Activate conda environment
activate_conda

# Resolve tools
ISS_BIN=$(resolve_tool "$ISS" "iss")

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

# SLURM_ARRAY_TASK_ID is 1-based
TASK_ID=${SLURM_ARRAY_TASK_ID:-1}
DATASET_CONFIG="${DATASETS[$((TASK_ID - 1))]}"

IFS=':' read -r DATASET_NAME TOTAL_READS HOST_PCT COMPLEXITY ABUNDANCE_DIST READ_MODE <<< "$DATASET_CONFIG"

DATASET_DIR="$DATA_DIR/$DATASET_NAME"
LOG_FILE="$LOG_DIR/generate/${DATASET_NAME}.log"

mkdir -p "$DATASET_DIR"

# ---------------------------------------------------------------------------
# Checkpoint: skip if already completed
# ---------------------------------------------------------------------------
if [ -f "$DATASET_DIR/completed.flag" ]; then
    echo "[$TASK_ID] Dataset $DATASET_NAME already generated. Skipping."
    exit 0
fi

echo "[$TASK_ID] Generating dataset: $DATASET_NAME"
echo "  Reads: $TOTAL_READS | Host: $HOST_PCT | Complexity: $COMPLEXITY | Dist: $ABUNDANCE_DIST | Mode: $READ_MODE"
echo "  Start: $(date -Iseconds)"

# Use local scratch for intermediate FASTQ files to reduce shared-filesystem I/O
WORKDIR="$LOCAL_SCRATCH/generate_$DATASET_NAME"
mkdir -p "$WORKDIR"

# ---------------------------------------------------------------------------
# Prepare human genome
# ---------------------------------------------------------------------------
HUMAN_FASTA="$WORKDIR/human_genome.fasta"
if [ ! -f "$HUMAN_FASTA" ]; then
    if [ -f "$HUMAN_GENOME" ]; then
        if [[ "$HUMAN_GENOME" == *.gz ]]; then
            gunzip -c "$HUMAN_GENOME" > "$HUMAN_FASTA"
        else
            cp "$HUMAN_GENOME" "$HUMAN_FASTA"
        fi
    else
        echo "ERROR: Human genome not found at $HUMAN_GENOME" >&2
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Prepare microbial genome subset
# ---------------------------------------------------------------------------
MICROBIAL_FA="$WORKDIR/microbial_input.fasta"

n_species=30
case "$COMPLEXITY" in
    low) n_species=5 ;;
    med) n_species=30 ;;
    high) n_species=100 ;;
esac

# Use a deterministic subset of available genomes to avoid unrealistic replication
# MICROBIAL_GENOME_DIR may hold .fasta, .fa or .fna, plain or gzipped, so that an
# existing genome collection can be used without renaming anything.
MICROBE_SRC="${MICROBIAL_GENOME_DIR:-$GENOME_DIR/genomes_fasta}"
if [ ! -d "$MICROBE_SRC" ]; then
    echo "ERROR: Microbial genome directory not found: $MICROBE_SRC" >&2
    echo "       Set MICROBIAL_GENOME_DIR (or GENOME_DIR) to a directory of genome FASTAs." >&2
    exit 1
fi

mapfile -t all_genomes < <(find "$MICROBE_SRC" -maxdepth 1 \
    \( -name '*.fasta' -o -name '*.fa' -o -name '*.fna' \
       -o -name '*.fasta.gz' -o -name '*.fa.gz' -o -name '*.fna.gz' \) | sort)
n_avail=${#all_genomes[@]}
if [ "$n_avail" -eq 0 ]; then
    echo "ERROR: No microbial genomes found in $MICROBE_SRC" >&2
    exit 1
fi

# Reusing genomes to reach the species target puts identical sequence in the
# community more than once, which is not a realistic metagenome. Say so loudly.
if [ "$n_avail" -lt "$n_species" ]; then
    echo "WARNING: only $n_avail genomes available for a $n_species-species community;" >&2
    echo "         genomes will be reused, so the community contains duplicates." >&2
fi

# Draw the community as a SEEDED RANDOM SAMPLE, not the first n_species entries
# in sort order. Taking a sorted prefix makes community membership a function of
# filename, and accession-sorted collections cluster by submission batch, so the
# "100-species" community would be far less diverse than it claims. The seed is
# derived from the complexity label alone, so every dataset at a given complexity
# draws the SAME community (comparable across depths and host fractions) while the
# draw itself is unbiased. The manifest below records exactly what was used.
SAMPLE_SEED="rustyclean-community-${complexity}"
if shuf --random-source=<(yes "$SAMPLE_SEED") -n 1 </dev/null >/dev/null 2>&1; then
    mapfile -t picked < <(printf '%s\n' "${all_genomes[@]}" \
        | shuf -n "$n_species" --random-source=<(yes "$SAMPLE_SEED"))
else
    # Older shuf without --random-source: order by a hash of seed+path instead.
    mapfile -t picked < <(printf '%s\n' "${all_genomes[@]}" \
        | awk -v s="$SAMPLE_SEED" '{ h=0; t=s $0
                                     for (i=1;i<=length(t);i++) h=(h*31+index(" " t, substr(t,i,1)))%1000003
                                     printf "%06d\\t%s\\n", h, $0 }' \
        | sort -k1,1n | cut -f2 | head -n "$n_species")
fi

# A human genome hiding in the "microbial" source would be simulated as microbial
# read yet is genuinely host, silently corrupting every accuracy number downstream.
# Refuse rather than produce a benchmark whose ground truth is wrong.
human_hits=$(printf '%s\n' "${picked[@]}" \
    | grep -Eic 'human|homo_?sapiens|GRCh3[78]|chm13|hg19|hg38|T2T|GCF_009914755|GCF_000001405' || true)
if [ "$human_hits" -gt 0 ]; then
    echo "ERROR: $human_hits of the sampled genomes look human:" >&2
    printf '%s\n' "${picked[@]}" \
        | grep -Ei 'human|homo_?sapiens|GRCh3[78]|chm13|hg19|hg38|T2T|GCF_009914755|GCF_000001405' >&2
    echo "       Host sequence in the microbial pool makes the ground truth wrong." >&2
    echo "       Point MICROBIAL_GENOME_DIR at a host-free collection." >&2
    exit 1
fi

> "$MICROBIAL_FA"
n_picked=${#picked[@]}
for i in $(seq 0 $((n_species - 1))); do
    g="${picked[$((i % n_picked))]}"
    case "$g" in
        *.gz) zcat "$g" >> "$MICROBIAL_FA" ;;
        *)    cat  "$g" >> "$MICROBIAL_FA" ;;
    esac
done

# Record the community so a reader can reproduce or audit it.
printf '%s\n' "${picked[@]}" > "${MICROBIAL_FA%.*}.genomes.txt"
echo "  Prepared $n_species microbial genomes (sampled from $n_avail, seed=$SAMPLE_SEED)."
echo "  Community manifest: ${MICROBIAL_FA%.*}.genomes.txt"

# ---------------------------------------------------------------------------
# Generate abundance profile
# ---------------------------------------------------------------------------
ABUNDANCE_FILE="$WORKDIR/abundance.txt"
python3 - "$COMPLEXITY" "$ABUNDANCE_DIST" "$ABUNDANCE_FILE" <<'PYEOF'
import sys
import numpy as np
np.random.seed(42)

complexity, distribution, output_file = sys.argv[1:4]
n = {'low': 5, 'med': 30, 'high': 100}.get(complexity, 30)

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
    for i, ab in enumerate(abundances):
        f.write(f"species_{i+1}\t{ab:.8f}\n")
PYEOF

# ---------------------------------------------------------------------------
# Calculate host/microbe read counts
# ---------------------------------------------------------------------------
HOST_READS=$(python3 -c "print(int($TOTAL_READS * $HOST_PCT))")
MICROBE_READS=$(python3 -c "print(int($TOTAL_READS * (1 - $HOST_PCT)))")
[ "$HOST_READS" -eq 0 ] && HOST_READS=0
[ "$MICROBE_READS" -eq 0 ] && MICROBE_READS=0

echo "  Host reads: $HOST_READS, Microbial reads: $MICROBE_READS"

# ---------------------------------------------------------------------------
# Generate reads with InsilicoSeq
# ---------------------------------------------------------------------------
# Without a seed the panel cannot be regenerated, so a reviewer could never
# reproduce these datasets. Probe for the flag instead of assuming it: passing
# an unsupported option would fail every array task at once.
if ! "$ISS_BIN" generate --help 2>&1 | grep -q -- '--seed'; then
    echo "ERROR: this InSilicoSeq build does not support --seed." >&2
    echo "       Refusing to generate 540 M reads that could never be regenerated." >&2
    echo "       Install a newer InSilicoSeq, or set ISS_ALLOW_UNSEEDED=1 to override." >&2
    [ "${ISS_ALLOW_UNSEEDED:-0}" = "1" ] || exit 1
    ISS_SEED_ARGS=""
else
    ISS_SEED_ARGS="--seed $(( ${SIM_SEED:-42} + ${SLURM_ARRAY_TASK_ID:-0} ))"
    echo "  ISS seed: ${ISS_SEED_ARGS#--seed }"
fi

if [ "$MICROBE_READS" -gt 0 ]; then
    echo "  Generating microbial reads..."
    "$ISS_BIN" generate \
        --genomes "$MICROBIAL_FA" \
        --abundance_file "$ABUNDANCE_FILE" \
        --model "${ISS_MODEL:-miseq}" \
        --n_reads "$MICROBE_READS" \
        --output "$WORKDIR/microbe" \
        --cpus "$SLURM_CPUS_PER_TASK" \
        $ISS_SEED_ARGS \
        2>&1 | tee -a "$LOG_FILE"
fi

if [ "$HOST_READS" -gt 0 ]; then
    echo "  Generating host reads..."
    "$ISS_BIN" generate \
        --genomes "$HUMAN_FASTA" \
        --model "${ISS_MODEL:-miseq}" \
        --n_reads "$HOST_READS" \
        --output "$WORKDIR/host" \
        --cpus "$SLURM_CPUS_PER_TASK" \
        $ISS_SEED_ARGS \
        2>&1 | tee -a "$LOG_FILE"
fi

# ---------------------------------------------------------------------------
# Merge, label, and compress
# ---------------------------------------------------------------------------
echo "  Merging and labeling..."

merge_and_label() {
    local out_fastq="$1"
    local microbe_file="$2"
    local host_file="$3"
    local microbe_count="$4"
    local mode="$5"

    > "$out_fastq"

    if [ "$mode" == "PE" ]; then
        # For PE, microbe_R1 then host_R1
        [ -f "$microbe_file" ] && cat "$microbe_file" >> "$out_fastq"
        [ -f "$host_file" ] && cat "$host_file" >> "$out_fastq"

        # Ground truth: microbe reads first
        local label_file="$WORKDIR/ground_truth_labels.txt"
        > "$label_file"
        if [ -f "$microbe_file" ]; then
            awk 'NR%4==1 {print substr($0, 2) "\tmicrobe"}' "$microbe_file" >> "$label_file"
        fi
        if [ -f "$host_file" ]; then
            awk 'NR%4==1 {print substr($0, 2) "\thost"}' "$host_file" >> "$label_file"
        fi
    else
        # SE: microbe reads first
        [ -f "$microbe_file" ] && cat "$microbe_file" >> "$out_fastq"
        [ -f "$host_file" ] && cat "$host_file" >> "$out_fastq"

        local label_file="$WORKDIR/ground_truth_labels.txt"
        > "$label_file"
        if [ -f "$microbe_file" ]; then
            awk 'NR%4==1 {print substr($0, 2) "\tmicrobe"}' "$microbe_file" >> "$label_file"
        fi
        if [ -f "$host_file" ]; then
            awk 'NR%4==1 {print substr($0, 2) "\thost"}' "$host_file" >> "$label_file"
        fi
    fi
}

if [ "$READ_MODE" == "PE" ]; then
    merge_and_label "$WORKDIR/reads_R1.fastq" \
        "$WORKDIR/microbe_R1.fastq" "$WORKDIR/host_R1.fastq" \
        "$MICROBE_READS" "PE"

    merge_and_label "$WORKDIR/reads_R2.fastq" \
        "$WORKDIR/microbe_R2.fastq" "$WORKDIR/host_R2.fastq" \
        "$MICROBE_READS" "PE"

    pigz -p "$SLURM_CPUS_PER_TASK" "$WORKDIR/reads_R1.fastq"
    pigz -p "$SLURM_CPUS_PER_TASK" "$WORKDIR/reads_R2.fastq"
else
    merge_and_label "$WORKDIR/reads.fastq" \
        "$WORKDIR/microbe_reads.fastq" "$WORKDIR/host_reads.fastq" \
        "$MICROBE_READS" "SE"

    pigz -p "$SLURM_CPUS_PER_TASK" "$WORKDIR/reads.fastq"
fi

# Copy results back to shared storage
cp "$WORKDIR/ground_truth_labels.txt" "$DATASET_DIR/"
if [ "$READ_MODE" == "PE" ]; then
    cp "$WORKDIR/reads_R1.fastq.gz" "$DATASET_DIR/"
    cp "$WORKDIR/reads_R2.fastq.gz" "$DATASET_DIR/"
else
    cp "$WORKDIR/reads.fastq.gz" "$DATASET_DIR/"
fi

# Metadata. Read length is measured from the reads actually produced rather than
# asserted: it is set by the ISS error model, so a hardcoded value silently goes
# stale the moment the model changes, and the Methods quote this file.
if [ "$READ_MODE" = "PE" ]; then
    _first_read=$(zcat "$DATASET_DIR/reads_R1.fastq.gz" | sed -n 2p)
else
    _first_read=$(zcat "$DATASET_DIR/reads.fastq.gz" | sed -n 2p)
fi
OBSERVED_READ_LENGTH=${#_first_read}

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
    "read_length": $OBSERVED_READ_LENGTH,
    "simulator": "InSilicoSeq",
    "model": "${ISS_MODEL:-novaseq}",
    "seed": "${ISS_SEED_ARGS#--seed }"
}
EOF

touch "$DATASET_DIR/completed.flag"

# Clean up local scratch
rm -rf "$WORKDIR"

echo "  End: $(date -Iseconds)"
echo "[$TASK_ID] Dataset $DATASET_NAME completed."
