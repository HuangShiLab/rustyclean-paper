# RustyClean vs KneadData Benchmark 方案

## 1. 项目背景

**RustyClean**: Rust 编写的高性能 metagenome QC 和去宿主流程，串联 `fastp` + `Kraken2`。
**KneadData**: Python 编写的成熟流程，串联 `Trimmomatic` + `Bowtie2`（非常慢）。

**目标**: 证明 RustyClean 在保持可接受准确性的前提下，显著快于 KneadData。

---

## 2. 参考文献

Gao et al. (2024) *Benchmarking short-read metagenomics tools for removing host contamination*. 该论文系统比较了 6 个工具（KneadData, Bowtie2, BWA, KMCP, Kraken2, KrakenUniq），为我们的 benchmark 设计提供了重要参考：

| 工具 | 运行时间 (min) | 内存 (Gb) | 准确率 | 特点 |
|------|---------------|----------|--------|------|
| Kraken2 | 29.34 | 2.47 | 0.9891 | **最快，低资源** |
| KneadData | 501.38 | 15.17 | 0.9997 | **慢，高资源，高准确** |
| Bowtie2 | 209.00 | 1.95 | 0.9997 | 比对-based |
| BWA | 582.26 | 3.995 | 0.9989 | 比对-based |
| KrakenUniq | 59.23 | 22.41 | 0.9998 | k-mer based |
| KMCP | 156.10 | 14.45 | 0.8947 | k-mer based |

**关键发现**:
- KneadData 比 Kraken2 **慢 17 倍**，内存高 **6 倍**
- KneadData 假阳性更高（误杀微生物 reads），Kraken2 假阴性更高（残留宿主 reads）
- 高宿主污染率 (90%) 时，比对工具显著变慢（KneadData 变慢 5.36 倍）

---

## 3. Benchmark 设计

### 3.1 测试数据集

#### A. 增强模拟数据 (Enhanced Simulated Data) — 18+ 数据集

使用 **InsilicoSeq** 生成含已知成分的 metagenome 数据，覆盖更全面的参数空间。

**宿主污染比例** (0% — 100%): 测试极端场景
| 比例 | 目的 |
|------|------|
| 0% | 零污染负对照 (测试假阳性) |
| 1%, 5% | 低污染 (临床样本常见) |
| 10%, 30% | 中等污染 |
| 50%, 70% | 高污染 |
| 90%, 99% | 极高污染 (测试假阴性) |
| 100% | 纯宿主负对照 |

**数据集大小** (5M — 100M reads):
| 大小 | 用途 |
|------|------|
| 5M | 小数据快速验证 |
| 10M, 20M | 标准测试 |
| 30M, 60M | 中等规模 |
| 100M | 大规模扩展性测试 |

**微生物复杂度**:
| 级别 | 物种数 | 代表场景 |
|------|--------|---------|
| Low | 5 | 简单群落 |
| Medium | 30 | 人类肠道标准 (Gao et al.) |
| High | 100 | 复杂群落 |

**群落分布类型**:
| 类型 | 特征 | 适用场景 |
|------|------|---------|
| Even | 均匀分布 | 合成群落 |
| Lognormal | 对数正态 (1-2 主导) | 真实肠道菌群 |
| Skewed | 单一主导 | 特定病原感染 |

**读段模式**: Single-end (SE) + Paired-end (PE)

**增强数据集示例**:
| 数据集名称 | 大小 | 宿主% | 复杂度 | 分布 | 模式 | 特殊用途 |
|-----------|------|-------|--------|------|------|---------|
| 5M_1pct_low_even_SE | 5M | 1% | 低 | 均匀 | SE | 低污染假阳性 |
| 10M_10pct_med_lognormal_SE | 10M | 10% | 中 | 对数正态 | SE | 标准测试 |
| 20M_50pct_med_lognormal_PE | 20M | 50% | 中 | 对数正态 | PE | 配对端测试 |
| 30M_90pct_med_lognormal_SE | 30M | 90% | 中 | 对数正态 | SE | 高污染假阴性 |
| 60M_99pct_med_lognormal_SE | 60M | 99% | 中 | 对数正态 | SE | 极端场景 |
| 100M_50pct_high_lognormal_SE | 100M | 50% | 高 | 对数正态 | SE | 扩展性测试 |
| 10M_0pct_med_lognormal_SE | 10M | 0% | 中 | 对数正态 | SE | 零污染对照 |
| 10M_100pct_med_lognormal_SE | 10M | 100% | 中 | 对数正态 | SE | 纯宿主对照 |

#### B. 真实数据 (Real Data) — 用于验证实际性能

从 NCBI SRA 下载公开的人类肠道 metagenome 数据:

| 数据集 | SRA ID | 大小 | 来源 |
|--------|--------|------|------|
| Real-1 | SRR15489010 | ~2GB | Human gut (Gehrig et al.) |
| Real-2 | SRR15489011 | ~2GB | Human gut (Gehrig et al.) |
| Real-3 | ERRXXXXXXX | ~5GB | Human gut (IBD study) |

### 3.2 对比配置

| 工具 | 版本 | 配置 |
|------|------|------|
| **RustyClean** | latest | fastp + Kraken2 (Standard DB) |
| **KneadData** | 0.12.0 | Trimmomatic + Bowtie2 (Human DB) |
| **Fastp+Kraken2** | - | 单独运行，分解 RustyClean 性能 |
| **KneadData-Trimmomatic** | - | 仅 QC 步骤 |

**参数控制**:
- 所有工具使用 **8 threads**（除非另有说明）
- 内存限制: 观察 peak memory
- 重复: **3 次**（对时间取平均）

### 3.3 评价指标

#### 性能指标 (Performance)
| 指标 | 说明 | 测量方法 |
|------|------|---------|
| Wall Clock Time | 总运行时间 | `time` command |
| CPU Time | CPU 占用时间 | `time` command |
| Peak Memory | 峰值内存 | `/usr/bin/time -v` |
| 输出文件大小 | 清洗后数据大小 | `du -sh` |
| 吞吐量 | reads/second | 总 reads / 时间 |

#### 准确性指标 (Accuracy) - 仅模拟数据
| 指标 | 公式 | 说明 |
|------|------|------|
| **Accuracy** | (TP + TN) / (TP + TN + FP + FN) | 总体正确率 |
| **Precision** | TP / (TP + FP) | 宿主 reads 中被正确去除的比例 |
| **Recall** | TP / (TP + FN) | 实际宿主 reads 中被去除的比例 |
| **F1-Score** | 2 * Precision * Recall / (Precision + Recall) | 综合指标 |
| **Host Remaining Rate** | FN / (TP + FN) | 残留宿主比例 |
| **Microbiome Loss Rate** | FP / (TN + FP) | 误杀微生物比例 |

其中:
- **TP**: 正确去除的宿主 reads
- **TN**: 正确保留的微生物 reads
- **FP**: 误杀的微生物 reads（false positive）
- **FN**: 残留的宿主 reads（false negative）

#### 下游分析指标 (Downstream)
| 指标 | 说明 | 工具 | 参考文献 |
|------|------|------|---------|
| Taxonomic Profile | 物种组成 (Bracken) | Kraken2 + Bracken | Wood et al. 2019 |
| Alpha Diversity | Shannon, Simpson, Chao1 | Custom Python/R | Hill 1973 |
| Beta Diversity / PCoA | Bray-Curtis 距离 | scikit-bio | Lozupone & Knight 2005 |
| Assembly Quality | 组装 N50, 总 contigs | MEGAHIT | Li et al. 2015 |
| MAG Quality | Completeness, Contamination | CheckM2 | Chklovski et al. 2023 |
| MAG Count | 高质量/中等质量 MAG 数量 | MetaWRAP + dRep | Uritskiy et al. 2018 |
| Functional Profile | GO term 富集 | eggNOG-mapper | Huerta-Cepas et al. 2019 |

---

## 4. 执行流程

```
Stage 1: 环境准备
  ├── 安装 RustyClean, KneadData, fastp, Kraken2, Bowtie2, Trimmomatic
  ├── 下载/构建数据库 (Kraken2 Standard, Human reference for Bowtie2)
  └── 安装 benchmark 依赖 (Python, R, CAMISIM, InsilicoSeq)

Stage 2: 数据准备
  ├── 生成增强模拟数据 (18+ 数据集)
  │   ├── 宿主比例: 0%, 1%, 5%, 10%, 30%, 50%, 70%, 90%, 99%, 100%
  │   ├── 数据集大小: 5M, 10M, 20M, 30M, 60M, 100M reads
  │   ├── 微生物复杂度: 低(5sp), 中(30sp), 高(100sp)
  │   ├── 群落分布: even, lognormal, skewed
  │   └── 读段模式: SE, PE
  └── 下载真实数据 (SRA Toolkit)

Stage 3: 执行 Benchmark
  ├── Run RustyClean (3 replicates)
  ├── Run KneadData (3 replicates)
  └── 记录所有指标 (time, memory, I/O)

Stage 4: 准确性分析 (仅模拟数据)
  ├── 比对 reads 到来源基因组
  ├── 分类 reads 来源 (host vs microbiome)
  └── 计算 Accuracy, Precision, Recall, F1, Host Remaining, Microbe Loss

Stage 5: 下游分析
  ├── Taxonomic profiling (Kraken2/Bracken)
  ├── Alpha diversity (Shannon, Simpson, Chao1)
  ├── Beta diversity / PCoA (Bray-Curtis)
  ├── Metagenomic assembly (MEGAHIT)
  ├── MAG binning (MetaWRAP)
  ├── MAG quality (CheckM2)
  └── Functional profiling (eggNOG / HUMAnN3)

Stage 6: 统计分析与可视化
  ├── 生成多面板学术图表 (Nature/Cell style)
  ├── 导出 SVG + PDF + TIFF (600 dpi)
  ├── 统计检验 (Wilcoxon, Kruskal-Wallis, Bonferroni)
  └── 生成 Markdown + Word 报告
```

---

## 5. 预期结果

基于 Gao et al. (2024) 的发现，我们预期:

1. **速度**: RustyClean (Kraken2-based) 应该比 KneadData 快 **10-20 倍**
2. **内存**: RustyClean 应该比 KneadData 节省 **5-10 倍** 内存
3. **准确性**: 
   - KneadData 可能略高（0.9997 vs 0.9891）
   - 但 RustyClean 的 F1-score 应该在可接受范围 (>0.98)
   - RustyClean 的假阳性更低（保留更多微生物信息）
4. **高宿主污染**: RustyClean 的优势在高宿主污染样本中更明显

---

## 6. 文件结构

```
rustyclean_benchmark/
├── benchmark_plan.md              # 详细 benchmark 设计方案
├── README.md                      # 快速上手指南
├── scripts/
│   ├── setup_env.sh              # 环境安装
│   ├── generate_simulated_data.sh     # 基础模拟数据 (4 datasets)
│   ├── generate_enhanced_data.sh      # 增强模拟数据 (18+ datasets)
│   ├── run_benchmark.sh          # 执行 benchmark
│   ├── analyze_accuracy.py       # 准确性分析
│   ├── analyze_performance.py    # 性能分析 (基础可视化)
│   ├── plot_publication_figures.py    # 学术投稿级可视化
│   ├── downstream_analysis.sh    # 下游分析 (组装、多样性、MAG)
│   └── generate_report.py        # 报告生成
├── data/
│   ├── simulated/                # 基础模拟数据集
│   └── enhanced/                 # 增强模拟数据集
├── results/
│   ├── rustyclean/               # RustyClean 输出
│   ├── kneaddata/                # KneadData 输出
│   ├── logs/                     # 运行日志 + 时间/内存记录
│   ├── metrics/                  # 性能指标 CSV
│   └── downstream/               # 下游分析结果
│       ├── taxonomy/             # Kraken2/Bracken 分类
│       ├── assembly/             # MEGAHIT 组装
│       ├── checkm2/              # MAG 质量评估
│       └── diversity/            # 多样性分析 + 图表
└── analysis/
    ├── accuracy.csv
    ├── accuracy_summary.csv
    ├── performance_summary.csv
    ├── figures/                  # 投稿级图表 (svg, pdf, tiff, png)
    └── report.md                 # 最终报告
```

---

## 7. 可视化规范 (Nature/Cell Style)

### rcParams 配置

```python
import matplotlib as mpl

mpl.rcParams.update({
    "font.family": "sans-serif",
    "font.sans-serif": ["Arial", "Helvetica", "DejaVu Sans"],
    "font.size": 7,
    "axes.labelsize": 8,
    "axes.titlesize": 9,
    "axes.spines.right": False,
    "axes.spines.top": False,
    "axes.linewidth": 0.8,
    "legend.frameon": False,
    "svg.fonttype": "none",      # 可编辑文本
    "pdf.fonttype": 42,          # TrueType
})
```

### 导出格式
| 格式 | 用途 | DPI |
|------|------|-----|
| SVG | 矢量编辑 (Illustrator/Inkscape) | — |
| PDF | 论文投稿 | — |
| TIFF | 期刊要求 (300-600 dpi) | 600 |
| PNG | 网页/演示 | 300 |

### 色彩方案
- **Steel Blue (#4A90A4)**: RustyClean
- **Muted Red (#C75B5B)**: KneadData
- **Sage Green (#8FA876)**: 基线/对照
- **Amber (#E8A838)**: 强调/高亮
- 统一色系，避免过多颜色干扰

---

## 8. 数据库要求

| 数据库 | 大小 | 用途 | 获取方式 |
|--------|------|------|---------|
| Kraken2 Standard | ~50 GB | RustyClean 分类 | `kraken2-build --standard` |
| Kraken2 Standard-8 | ~8 GB | 快速测试 | 使用 MiniKraken2 |
| Human GRCh38 | ~3 GB | KneadData 比对 | KneadData 自带或下载 |
| Human GRCh38 (Kraken2) | 包含在 Standard 中 | RustyClean 宿主去除 | Kraken2 Standard |

**建议**: 对于快速 benchmark，使用 **MiniKraken2 v1** (8GB) 数据库。
对于最终报告，使用 **Kraken2 Standard** (50GB) 数据库。

---

## 9. 资源估算

| 任务 | 时间 | 内存 | 存储 |
|------|------|------|------|
| 环境准备 + 数据库下载 | 2-4 hours | 64 GB | 100 GB |
| 模拟数据生成 (18 sets) | 2-4 hours | 16 GB | 100 GB |
| Benchmark 运行 (3 reps × 2 tools × 18 datasets) | 8-16 hours | 32 GB | 200 GB |
| 下游分析 (组装 + CheckM2) | 4-8 hours | 64 GB | 150 GB |
| 准确性分析 | 1-2 hours | 16 GB | 10 GB |
| 可视化与报告 | 10 min | 8 GB | 1 GB |
| **总计** | **16-34 hours** | **64 GB** | **~600 GB** |

---

## 10. 注意事项

1. **公平对比**: 确保两个工具使用相同的 thread 数，相同的输入输出格式
2. **缓存清除**: 每次运行前清除系统缓存 (`echo 3 > /proc/sys/vm/drop_caches`，需 root)
3. **I/O 瓶颈**: 确保输入数据在 SSD 上，避免 I/O 成为瓶颈
4. **随机种子**: 模拟数据生成使用固定随机种子，确保可重复
5. **版本记录**: 记录所有工具的精确版本号和数据库版本
6. **系统监控**: 使用 `vmstat`, `iostat` 等工具监控资源使用

---

## 11. Gao et al. (2024) 工具与数据

该论文提供了完整的 GitHub 仓库，可直接参考：

- **GitHub**: https://github.com/YunyunGao374/HostPurge
- **下游分析流程**: `HostPurge-DownstreamAnalysis`
- **软件对比 benchmark**: `HostPurge-SoftwareComparison`
- **论文图表代码**: `HostPurge-paper-figures`
- **许可证**: GNU GPL v3.0

论文使用了 **CAMISIM** 生成 1,080 个模拟数据集，覆盖：
- 3 种大小 (10Gbps, 30Gbps, 60Gbps)
- 3 种宿主比例 (10%, 50%, 90%)
- 2 种宿主类型 (Human GRCh38, Rice)
- 2 种微生物复杂度 (SinBac, SynCom)
- 5 次重复

---

## 12. 引用

1. Gao Y, et al. (2024). Benchmarking short-read metagenomics tools for removing host contamination. *iMeta*, 4(1): e70005.
2. Wood DE, Lu J, Langmead B. (2019). Improved metagenomic analysis with Kraken 2. *Genome Biol*, 20: 257.
3. Li D, et al. (2015). MEGAHIT: an ultra-fast single-node solution for large and complex metagenomics assembly. *Bioinformatics*, 31(10): 1674-1676.
4. Chklovski A, et al. (2023). CheckM2: a rapid, scalable and accurate tool for assessing microbial genome quality using machine learning. *Nat Methods*, 20: 1203-1212.
5. Fritz A, et al. (2019). CAMISIM: simulating metagenomes and microbial communities. *Microbiome*, 7: 17.
6. Langmead B, Salzberg SL. (2012). Fast gapped-read alignment with Bowtie 2. *Nat Methods*, 9(4): 357-359.
