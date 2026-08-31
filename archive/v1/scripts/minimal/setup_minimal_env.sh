#!/bin/bash
# =============================================================================
# RustyClean 极简验证 — 环境设置脚本
# =============================================================================
# 一键设置极简验证所需的所有环境和依赖
# Usage: bash setup_minimal_env.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
INSTALL_DIR="${PROJECT_DIR}/minimal_env"
CONDA_ENV="rustyclean-minimal"

echo "========================================"
echo "RustyClean 极简验证 — 环境设置"
echo "========================================"
echo "安装目录: $INSTALL_DIR"
echo ""

mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/databases"
mkdir -p "$INSTALL_DIR/genomes"

# ---------------------------------------------------------------------------
# 1. 检查前置条件
# ---------------------------------------------------------------------------
echo "[1/6] 检查前置条件..."

command -v conda >/dev/null 2>&1 || {
    echo "ERROR: conda 未安装"
    echo "请安装 Miniconda: https://docs.conda.io/en/latest/miniconda.html"
    exit 1
}

# 检查可用空间（兼容 Linux/macOS）
if df -BG "$INSTALL_DIR" >/dev/null 2>&1; then
    AVAILABLE_GB=$(df -BG "$INSTALL_DIR" | tail -1 | awk '{print $4}' | tr -d 'G')
else
    AVAILABLE_GB=$(df -g "$INSTALL_DIR" | tail -1 | awk '{print $4}')
fi
if [ "$AVAILABLE_GB" -lt 80 ]; then
    echo "WARNING: 可用空间仅 ${AVAILABLE_GB}GB，建议至少 80GB"
    read -p "是否继续? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# 2. 创建 conda 环境
# ---------------------------------------------------------------------------
echo ""
echo "[2/6] 创建 conda 环境: $CONDA_ENV"

if conda env list | grep -q "^$CONDA_ENV "; then
    echo "环境 $CONDA_ENV 已存在，跳过创建"
else
    conda create -n "$CONDA_ENV" -y python=3.10
    echo "环境创建完成"
fi

# 使用 conda run 安装包（避免激活环境）
echo "安装生物信息学工具..."
conda run -n "$CONDA_ENV" conda install -y -c bioconda -c conda-forge \
    fastp \
    kraken2 \
    kneaddata \
    bowtie2 \
    trimmomatic \
    samtools \
    seqtk \
    pigz \
    insilicoseq \
    matplotlib \
    seaborn \
    pandas \
    numpy \
    biopython \
    2>&1 | tail -20

echo "工具安装完成"

# ---------------------------------------------------------------------------
# 3. 下载 MiniKraken2 数据库
# ---------------------------------------------------------------------------
echo ""
echo "[3/6] 下载 MiniKraken2 数据库 (~8GB)..."

DB_DIR="$INSTALL_DIR/databases"
if [ -d "$DB_DIR/minikraken2_v1_8GB" ]; then
    echo "MiniKraken2 已存在，跳过下载"
else
    cd "$DB_DIR"
    if [ ! -f "minikraken2_v1_8GB_201904.tgz" ]; then
        echo "下载中..."
        wget -c --progress=bar:force https://genome-idx.s3.amazonaws.com/kraken/minikraken2_v1_8GB_201904.tgz
    fi
    echo "解压中..."
    tar -xzf minikraken2_v1_8GB_201904.tgz
    rm -f minikraken2_v1_8GB_201904.tgz
    echo "MiniKraken2 准备完成"
fi

# ---------------------------------------------------------------------------
# 4. 下载 KneadData 人类参考基因组
# ---------------------------------------------------------------------------
echo ""
echo "[4/6] 设置 KneadData 人类参考基因组..."

KNEADDATA_DB="$DB_DIR/kneaddata_human_db"
mkdir -p "$KNEADDATA_DB"

if [ -f "$KNEADDATA_DB"/*.1.bt2 ] || [ -f "$KNEADDATA_DB"/*.rev.1.bt2 ]; then
    echo "KneadData 数据库已存在"
else
    echo "下载 KneadData 人类数据库 (~3GB)..."
    cd "$KNEADDATA_DB"
    # 使用 kneaddata 自带的下载命令
    conda run -n "$CONDA_ENV" kneaddata_database --download human_genome bowtie2 . 2>&1 || {
        echo "WARNING: kneaddata_database 下载失败，尝试手动下载..."
        # 备用下载链接
        wget -c ftp://public-ftp.hmpdacc.org/Illumina/human_genome_Bowtie2_v0.1.tar.gz 2>/dev/null || true
        if [ -f human_genome_Bowtie2_v0.1.tar.gz ]; then
            tar -xzf human_genome_Bowtie2_v0.1.tar.gz
            rm -f human_genome_Bowtie2_v0.1.tar.gz
        fi
    }
fi

# ---------------------------------------------------------------------------
# 5. 安装 RustyClean
# ---------------------------------------------------------------------------
echo ""
echo "[5/6] 安装 RustyClean..."

RUSTYCLEAN_DIR="$INSTALL_DIR/rustyclean"
if [ -d "$RUSTYCLEAN_DIR" ]; then
    echo "RustyClean 已克隆，更新中..."
    cd "$RUSTYCLEAN_DIR" && git pull
else
    git clone https://github.com/HuangShiLab/rustyclean.git "$RUSTYCLEAN_DIR"
    cd "$RUSTYCLEAN_DIR"
fi

# 检查 cargo
if command -v cargo >/dev/null 2>&1; then
    echo "编译 RustyClean (release 模式)..."
    cargo build --release
    echo "编译完成"
else
    echo "WARNING: cargo (Rust) 未安装，跳过编译"
    echo "请安装 Rust: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
fi

# ---------------------------------------------------------------------------
# 6. 准备微生物基因组
# ---------------------------------------------------------------------------
echo ""
echo "[6/6] 准备微生物基因组 (~1GB)..."

GENOME_DIR="$INSTALL_DIR/genomes"
cd "$GENOME_DIR"

# 创建基因组列表（30种常见肠道菌）
cat > genome_list.txt << 'EOF'
Bacteroides_thetaiotaomicron	AE015928.1
Bacteroides_vulgatus	CP000139.1
Bacteroides_uniformis	CP001273.1
Bacteroides_fragilis	CR626927.1
Prevotella_copri	CP002109.1
Faecalibacterium_prausnitzii	FP929045.1
Roseburia_intestinalis	CP001893.1
Eubacterium_rectale	CP001107.1
Ruminococcus_bromii	CP003333.1
Akkermansia_muciniphila	CP001071.1
Escherichia_coli	U00096.3
Bifidobacterium_longum	AE014295.3
Streptococcus_salivarius	CP000130.1
Lactobacillus_gasseri	AP009512.1
Enterococcus_faecalis	AE016830.1
EOF

# 下载脚本
cat > download_genomes.sh << 'EOF'
#!/bin/bash
set -e
mkdir -p genomes_fasta
cd genomes_fasta

echo "下载微生物基因组..."
while IFS=	 read -r species accession; do
    [ -z "$species" ] && continue
    echo "  $species ($accession)..."
    
    # 使用 NCBI efetch 下载
    URL="https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nuccore&id=${accession}&rettype=fasta&retmode=text"
    curl -s "$URL" > "${accession}.fasta"
    
    if [ ! -s "${accession}.fasta" ]; then
        echo "    WARNING: 下载失败 $accession"
    fi
    sleep 0.5  # 礼貌请求
done < ../genome_list.txt

echo "下载完成"
EOF
chmod +x download_genomes.sh

# 下载人类基因组（chr1 作为简化版）
if [ ! -f "GRCh38_chr1.fa" ]; then
    echo "下载人类基因组 chr1 (~250MB)..."
    curl -s "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nuccore&id=NC_000001.11&rettype=fasta&retmode=text" > "GRCh38_chr1.fa"
    echo "下载完成"
fi

# ---------------------------------------------------------------------------
# 7. 创建环境配置
# ---------------------------------------------------------------------------
echo ""
echo "创建环境配置文件..."

cat > "$INSTALL_DIR/env.sh" << EOF
# RustyClean 极简验证环境配置
# 使用: source env.sh

export RUSTYCLEAN="$RUSTYCLEAN_DIR/target/release/rustyclean"
export KRAKEN2_DB="$DB_DIR/minikraken2_v1_8GB"
export KNEADDATA_DB="$KNEADDATA_DB"
export HUMAN_GENOME="$GENOME_DIR/GRCh38_chr1.fa"
export GENOME_DIR="$GENOME_DIR"

# 将 conda 环境 bin 加入 PATH
export PATH="\$(conda run -n $CONDA_ENV sh -c 'echo \$PATH'):\$PATH"

echo "环境已加载:"
echo "  RUSTYCLEAN:  \$RUSTYCLEAN"
echo "  KRAKEN2_DB:  \$KRAKEN2_DB"
echo "  KNEADDATA_DB: \$KNEADDATA_DB"
EOF

# ---------------------------------------------------------------------------
# 完成
# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo "极简验证环境设置完成！"
echo "========================================"
echo ""
echo "安装位置: $INSTALL_DIR"
echo "conda 环境: $CONDA_ENV"
echo ""
echo "重要路径:"
echo "  RustyClean:     $RUSTYCLEAN_DIR/target/release/rustyclean"
echo "  Kraken2 DB:     $DB_DIR/minikraken2_v1_8GB"
echo "  KneadData DB:   $KNEADDATA_DB"
echo "  基因组目录:     $GENOME_DIR"
echo ""
echo "下一步:"
echo "  1. 加载环境: source $INSTALL_DIR/env.sh"
echo "  2. 下载基因组: cd $GENOME_DIR && bash download_genomes.sh"
echo "  3. 运行验证:  bash scripts/minimal/run_minimal.sh"
echo ""
