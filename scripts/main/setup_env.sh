#!/bin/bash
# =============================================================================
# RustyClean Benchmark - Environment Setup Script
# =============================================================================
# Usage: bash scripts/main/setup_env.sh [install_dir]
# Default install_dir: $HOME/benchmark_env

set -e

INSTALL_DIR="${1:-$HOME/benchmark_env}"
CONDA_ENV="rustyclean-benchmark"

echo "========================================"
echo "RustyClean Benchmark Environment Setup"
echo "========================================"
echo "Install directory: $INSTALL_DIR"
echo ""

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# ---------------------------------------------------------------------------
# 1. Check prerequisites
# ---------------------------------------------------------------------------
echo "[1/7] Checking prerequisites..."

command -v conda >/dev/null 2>&1 || {
    echo "ERROR: conda is required but not installed."
    echo "Please install Miniconda/Anaconda first:"
    echo "  https://docs.conda.io/en/latest/miniconda.html"
    exit 1
}

command -v cargo >/dev/null 2>&1 || {
    echo "WARNING: Rust/cargo not found. RustyClean compilation will be skipped."
    echo "Please install Rust: https://rustup.rs/"
}

command -v git >/dev/null 2>&1 || {
    echo "ERROR: git is required but not installed."
    exit 1
}

# ---------------------------------------------------------------------------
# 2. Create conda environment
# ---------------------------------------------------------------------------
echo ""
echo "[2/7] Creating conda environment: $CONDA_ENV"

if conda env list | grep -q "^$CONDA_ENV "; then
    echo "Environment $CONDA_ENV already exists. Updating..."
    conda activate "$CONDA_ENV"
else
    conda create -n "$CONDA_ENV" -y python=3.10
    echo "conda environment created. Please activate it:"
    echo "  conda activate $CONDA_ENV"
fi

echo ""
echo "Installing bioinformatics tools via conda..."

# Install tools (using mamba if available for speed)
if command -v mamba >/dev/null 2>&1; then
    PKG_MGR="mamba"
else
    PKG_MGR="conda"
fi

$PKG_MGR install -y -c bioconda -c conda-forge \
    kneaddata \
    fastp \
    kraken2 \
    bracken \
    bowtie2 \
    trimmomatic \
    samtools \
    bwa \
    megahit \
    checkm-genome \
    seqtk \
    pigz \
    sra-tools \
    insilicoseq \
    multiqc \
    matplotlib \
    seaborn \
    pandas \
    numpy \
    scipy \
    scikit-learn \
    biopython \
    tqdm \
    pysam

echo "Conda packages installed."

# ---------------------------------------------------------------------------
# 3. Install RustyClean
# ---------------------------------------------------------------------------
echo ""
echo "[3/7] Installing RustyClean"

if command -v cargo >/dev/null 2>&1; then
    RUSTYCLEAN_DIR="$INSTALL_DIR/rustyclean"
    if [ -d "$RUSTYCLEAN_DIR" ]; then
        echo "RustyClean already cloned. Pulling latest..."
        cd "$RUSTYCLEAN_DIR" && git pull
    else
        git clone https://github.com/HuangShiLab/rustyclean.git "$RUSTYCLEAN_DIR"
        cd "$RUSTYCLEAN_DIR"
    fi
    
    echo "Building RustyClean (release mode)..."
    cargo build --release
    
    # Add to PATH
    echo "export PATH=\"$RUSTYCLEAN_DIR/target/release:\$PATH\"" >> "$HOME/.bashrc"
    echo "RustyClean installed at: $RUSTYCLEAN_DIR/target/release/rustyclean"
else
    echo "Skipping RustyClean build (cargo not available)"
fi

cd "$INSTALL_DIR"

# ---------------------------------------------------------------------------
# 4. Download Kraken2 Database
# ---------------------------------------------------------------------------
echo ""
echo "[4/7] Downloading Kraken2 Database"
echo "NOTE: This requires ~50GB for Standard DB or ~8GB for MiniKraken2"

DB_DIR="$INSTALL_DIR/databases"
mkdir -p "$DB_DIR"

cd "$DB_DIR"

# Option 1: MiniKraken2 (8GB) - good for quick testing
if [ ! -d "minikraken2_v1_8GB" ]; then
    echo "Downloading MiniKraken2 v1 (8GB)..."
    wget -c https://genome-idx.s3.amazonaws.com/kraken/minikraken2_v1_8GB_201904.tgz
    tar -xzf minikraken2_v1_8GB_201904.tgz
    rm minikraken2_v1_8GB_201904.tgz
    echo "MiniKraken2 downloaded."
else
    echo "MiniKraken2 already exists."
fi

echo ""
echo "Database location: $DB_DIR"

# ---------------------------------------------------------------------------
# 5. Download Human Reference for KneadData
# ---------------------------------------------------------------------------
echo ""
echo "[5/7] Setting up Human Reference Database for KneadData"

HUMAN_DB="$DB_DIR/kneaddata_human_db"
mkdir -p "$HUMAN_DB"
cd "$HUMAN_DB"

# KneadData can download its own database
if [ ! -f "Homo_sapiens_hg37_and_human_contamination_Bowtie2_v0.1.1.tar.gz" ]; then
    echo "Downloading KneadData human reference database..."
    kneaddata_database --download human_genome bowtie2 "$HUMAN_DB"
else
    echo "KneadData human DB already exists."
fi

# ---------------------------------------------------------------------------
# 6. Prepare Microbial Genomes for Simulation
# ---------------------------------------------------------------------------
echo ""
echo "[6/7] Preparing Microbial Genomes for Simulation"

GENOME_DIR="$INSTALL_DIR/genomes"
mkdir -p "$GENOME_DIR"
cd "$GENOME_DIR"

# 30 common human gut bacteria (from Gao et al.)
cat > genome_list.txt << 'EOF'
# species_name\tNCBI_accession
Bacteroides_thetaiotaomicron	AE015928.1
Bacteroides_vulgatus	CP000139.1
Bacteroides_uniformis	CP001273.1
Bacteroides_fragilis	CR626927.1
Bacteroides_caccae	CP001108.1
Prevotella_copri	CP002109.1
Parabacteroides_distasonis	CP001325.1
Alistipes_finegoldii	FP929047.1
Alistipes_shahii	FP929032.1
Phascolarctobacterium_succinatutens	CP002403.1
Faecalibacterium_prausnitzii	FP929045.1
Roseburia_intestinalis	CP001893.1
Eubacterium_rectale	CP001107.1
Coprococcus_comes	CP003052.1
Ruminococcus_bromii	CP003333.1
Blautia_obeum	FP929060.1
Dorea_longicatena	FP929061.1
Clostridium_leptum	FP929049.1
Anaerostipes_hadrus	FP929053.1
Streptococcus_salivarius	CP000130.1
Streptococcus_parasanguinis	FR871419.1
Streptococcus_mitis	AP013083.1
Enterococcus_faecalis	AE016830.1
Lactobacillus_gasseri	AP009512.1
Bifidobacterium_longum	AE014295.3
Bifidobacterium_adolescentis	AP009256.1
Escherichia_coli	U00096.3
Akkermansia_muciniphila	CP001071.1
Methanobrevibacter_smithii	CP000678.1
Desulfovibrio_desulfuricans	CP000138.1
EOF

echo "Genome list prepared at: $GENOME_DIR/genome_list.txt"

# Download script
cat > download_genomes.sh << 'EOF'
#!/bin/bash
set -e
mkdir -p genomes_fasta

echo "Downloading microbial genomes from NCBI..."
while IFS=	 read -r species accession; do
    [ -z "$species" ] && continue
    [[ "$species" =~ ^# ]] && continue
    echo "Downloading $species ($accession)..."
    
    if command -v ncbi-acc-download >/dev/null 2>&1; then
        ncbi-acc-download -o "genomes_fasta/${accession}.fasta" "$accession"
    else
        URL="https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nuccore&id=${accession}&rettype=fasta&retmode=text"
        curl -s "$URL" > "genomes_fasta/${accession}.fasta"
        if [ ! -s "genomes_fasta/${accession}.fasta" ]; then
            echo "WARNING: Failed to download $accession"
        fi
    fi
    sleep 0.5
done < genome_list.txt
echo "Genome download complete."
EOF
chmod +x download_genomes.sh

# ---------------------------------------------------------------------------
# 7. Download Human Genome (GRCh38)
# ---------------------------------------------------------------------------
echo ""
echo "[7/7] Preparing Human Genome Reference (GRCh38)"

if [ ! -f "$DB_DIR/GRCh38.fa.gz" ] && [ ! -f "$DB_DIR/GRCh38.fa" ]; then
    echo "Downloading GRCh38 human genome..."
    cd "$DB_DIR"
    wget -c ftp://ftp.ncbi.nlm.nih.gov/refseq/H_sapiens/annotation/GRCh38_latest/refseq_identifiers/GRCh38_latest_genomic.fna.gz
    mv GRCh38_latest_genomic.fna.gz GRCh38.fa.gz
    echo "Human genome downloaded."
else
    echo "Human genome already exists."
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo "Setup Complete!"
echo "========================================"
echo "Environment: $INSTALL_DIR"
echo "Conda env: $CONDA_ENV"
echo ""
echo "Next steps:"
echo "  1. conda activate $CONDA_ENV"
echo "  2. cd $GENOME_DIR && bash download_genomes.sh"
echo "  3. bash scripts/main/generate_simulated_data.sh"
echo "  4. bash scripts/main/run_benchmark.sh"
echo ""
