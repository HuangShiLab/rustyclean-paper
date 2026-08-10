#!/bin/bash
# =============================================================================
# RustyClean Benchmark — HPC Environment Setup (Fast Path)
# =============================================================================
# Uses existing tool-specific conda envs on HKU HPC and creates a lightweight
# rustyclean-benchmark env for Python packages + InsilicoSeq.
#
# Run on the login node (requires internet):
#   bash hpc/setup_hpc_env.sh

set -euo pipefail

PROJECT_DIR="/lustre1/g/aos_shihuang/rustyclean-paper"
cd "$PROJECT_DIR"

CONDA_BASE="/group/aos_shihuang/conda"
CONDA_ENV="rustyclean-benchmark"
CONDA_PREFIX="$PROJECT_DIR/.conda_envs/$CONDA_ENV"
RUSTYCLEAN_DIR="/lustre1/g/aos_shihuang/rustyclean"

echo "========================================"
echo "RustyClean Benchmark — HPC Setup"
echo "========================================"
echo "Project:      $PROJECT_DIR"
echo "Conda env:    $CONDA_PREFIX"
echo "RustyClean:   $RUSTYCLEAN_DIR"
echo ""

source "$CONDA_BASE/etc/profile.d/conda.sh"

# ---------------------------------------------------------------------------
# 1. Create lightweight benchmark env (Python packages + insilicoseq)
# ---------------------------------------------------------------------------
if [ -d "$CONDA_PREFIX" ]; then
    echo "Conda env exists. Updating..."
else
    echo "Creating lightweight benchmark env..."
    conda create --prefix "$CONDA_PREFIX" -y python=3.10
fi

mamba install --prefix "$CONDA_PREFIX" -y -c bioconda -c conda-forge \
    insilicoseq pigz seqtk \
    matplotlib seaborn pandas numpy scipy scikit-learn biopython tqdm pysam \
    2>&1 | tail -30

# ---------------------------------------------------------------------------
# 2. Verify existing tool envs
# ---------------------------------------------------------------------------
echo ""
echo "Checking existing tool environments..."
for env in kneaddata kraken2 bracken megahit checkm2 fastp; do
    if [ -d "$CONDA_BASE/envs/$env" ]; then
        echo "  OK: $env"
    else
        echo "  MISSING: $env"
    fi
done

# ---------------------------------------------------------------------------
# 3. Build RustyClean
# ---------------------------------------------------------------------------
if [ ! -d "$RUSTYCLEAN_DIR" ]; then
    echo "ERROR: RustyClean source not found at $RUSTYCLEAN_DIR"
    echo "Please clone on login node: git clone https://github.com/HuangShiLab/rustyclean.git $RUSTYCLEAN_DIR"
    exit 1
fi

cd "$RUSTYCLEAN_DIR"
if [ ! -f "target/release/rustyclean" ]; then
    echo ""
    echo "Building RustyClean..."
    cargo build --release 2>&1 | tail -20
else
    echo "RustyClean already built."
fi

# ---------------------------------------------------------------------------
# 4. Create combined activation helper
# ---------------------------------------------------------------------------
mkdir -p "$PROJECT_DIR/.conda_envs"
cat > "$PROJECT_DIR/.conda_envs/activate_benchmark.sh" <<EOF
# Activate rustyclean-benchmark env and prepend existing tool envs to PATH
conda activate "$CONDA_PREFIX"
export PATH="$CONDA_BASE/envs/kneaddata/bin:\$PATH"
export PATH="$CONDA_BASE/envs/kraken2/bin:\$PATH"
export PATH="$CONDA_BASE/envs/bracken/bin:\$PATH"
export PATH="$CONDA_BASE/envs/megahit/bin:\$PATH"
export PATH="$CONDA_BASE/envs/checkm2/bin:\$PATH"
export PATH="$CONDA_BASE/envs/fastp/bin:\$PATH"
export PATH="$CONDA_BASE/envs/seqtk/bin:\$PATH"
EOF

# ---------------------------------------------------------------------------
# 5. Prepare microbial genomes
# ---------------------------------------------------------------------------
GENOME_DIR="$PROJECT_DIR/genomes"
mkdir -p "$GENOME_DIR"
cd "$GENOME_DIR"

cat > genome_list.txt <<'EOF'
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

cat > download_genomes.sh <<'EOF'
#!/bin/bash
set -e
mkdir -p genomes_fasta
cd genomes_fasta
while IFS=$'\t' read -r species accession; do
    [ -z "$species" ] && continue
    echo "Downloading $species ($accession)..."
    URL="https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nuccore&id=${accession}&rettype=fasta&retmode=text"
    curl -s "$URL" > "${accession}.fasta"
    if [ ! -s "${accession}.fasta" ]; then
        echo "WARNING: Failed to download $accession"
    fi
    sleep 0.5
done < ../genome_list.txt
echo "Download complete."
EOF
chmod +x download_genomes.sh

# ---------------------------------------------------------------------------
# 6. Download human genome for simulation
# ---------------------------------------------------------------------------
DB_DIR="$PROJECT_DIR/databases"
mkdir -p "$DB_DIR"
if [ ! -f "$DB_DIR/GRCh38.fa.gz" ] && [ ! -f "$DB_DIR/GRCh38.fa" ]; then
    echo ""
    echo "Downloading GRCh38 human genome..."
    cd "$DB_DIR"
    wget -c ftp://ftp.ncbi.nlm.nih.gov/refseq/H_sapiens/annotation/GRCh38_latest/refseq_identifiers/GRCh38_latest_genomic.fna.gz
    mv GRCh38_latest_genomic.fna.gz GRCh38.fa.gz
else
    echo "Human genome already exists."
fi

# ---------------------------------------------------------------------------
# 7. Done
# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo "HPC setup base complete."
echo "========================================"
echo ""
echo "Next steps:"
echo "  1. Download microbial genomes:"
echo "     cd $GENOME_DIR && bash download_genomes.sh"
echo "  2. Submit benchmark:"
echo "     cd $PROJECT_DIR && bash hpc/submit_all.sh"
