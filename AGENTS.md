# RustyClean Benchmark Suite — AI Agent Guide

> 本文件面向不了解本项目的 AI coding agent。阅读后可快速掌握项目结构、技术栈、构建/运行方式、代码风格与常见注意事项。
> 项目内注释与文档主要使用中文，因此本指南采用中文撰写。

---

## 1. 项目概述

本项目是一个**基准测试（Benchmark）套件**，用于对比两个 metagenome 宿主污染去除流程：

- **RustyClean**：基于 Rust 编写的高性能 pipeline，串联 `fastp`（QC）+ `Kraken2`（宿主/微生物分类）。
- **KneadData**：基于 Python 的成熟 pipeline，串联 `Trimmomatic`（QC）+ `Bowtie2`（比对去宿主）。

项目本身**不包含 RustyClean 的源码**。RustyClean 会在环境初始化阶段从 GitHub 克隆并编译。

### 核心目标

- 证明 RustyClean 在保持可接受准确性的前提下，显著快于 KneadData。
- 生成模拟/增强数据集，记录运行时间、峰值内存、吞吐量、输出大小、准确性指标（Accuracy / Precision / Recall / F1）。
- 进行下游分析（Taxonomy、Assembly、Diversity、MAG quality），并生成投稿级可视化与 Markdown 报告。

### 关键参考

- Gao et al. (2024). *Benchmarking short-read metagenomics tools for removing host contamination*. iMeta.
- RustyClean 仓库：`https://github.com/HuangShiLab/rustyclean`

---

## 2. 仓库结构

```
rustyclean-paper/
├── manuscript/                    # 论文稿件
│   ├── RustyClean_Manuscript_Draft.md
│   └── RustyClean_Manuscript_Draft.docx
├── figures/                       # 投稿级图表（fig1–fig4 + figS1）
├── data/                          # 运行时生成的数据集与结果指标
│   ├── simulated/                 # 基础模拟数据集
│   ├── enhanced/                  # 增强模拟数据集
│   ├── results_100M_matched/      # 100M 匹配面板结果
│   ├── results_100M_skipqc_matched/
│   ├── benchmark_results/         # Hostile / KneadData 对比指标
│   └── analysis/                  # 汇总 CSV 与基础可视化
├── scripts/                       # 代码与流程脚本
│   ├── main/                      # 标准/完整方案脚本
│   │   ├── setup_env.sh
│   │   ├── generate_simulated_data.sh
│   │   ├── generate_enhanced_data.sh
│   │   ├── run_benchmark.sh
│   │   ├── analyze_accuracy.py
│   │   ├── analyze_performance.py
│   │   ├── plot_publication_figures_v2.py
│   │   ├── downstream_analysis.sh
│   │   └── generate_report.py
│   ├── hpc/                       # SLURM 集群提交脚本
│   ├── benchmark/                 # Hostile / KneadData 对比脚本
│   ├── minimal/                   # 极简验证方案
│   └── rustyclean_src/            # RustyClean 源码备份
├── others/                        # 早期探索与辅助文档
│   ├── old_manuscripts/
│   ├── planning_docs/
│   └── tmp_scripts/
├── README.md                      # 项目主文档
├── AGENTS.md                      # 本文件
└── LICENSE
```

> 注意：`data/` 下的 `simulated/`、`enhanced/`、`results/` 子目录以及 `minimal_env/` 均由脚本在运行时创建，不在 Git 中。

---

## 3. 技术栈

### 3.1 运行平台与语言

- **操作系统**：Linux / macOS（README 与脚本均声称支持；开发者主要在 macOS / Ubuntu 上测试）。
- **Shell**：Bash（所有 `.sh` 脚本均使用 `#!/bin/bash` + `set -e`）。
- **Python**：3.10（通过 conda 环境安装）。
- **Rust**：用于编译 RustyClean（需要 `cargo` 在 PATH 中）。

### 3.2 生物信息学工具（由 conda 安装）

- `fastp` — QC
- `kraken2`、`bracken` — 分类与物种丰度估计
- `kneaddata`、`bowtie2`、`trimmomatic` — KneadData 流程
- `samtools`、`seqtk`、`pigz`、`sra-tools`
- `insilicoseq` (`iss`) — 模拟数据生成
- `megahit` — 组装
- `checkm-genome` / `checkm2` — MAG 质量评估
- `humann` — 功能注释（downstream_analysis.sh 中仅检查，未强制调用）

### 3.3 Python 依赖（由 conda 安装）

- `pandas`、`numpy`、`scipy`、`scikit-learn`
- `matplotlib`、`seaborn`
- `biopython`、`tqdm`、`pysam`

### 3.4 数据库与参考数据

- **MiniKraken2 v1**（约 8 GB）：快速测试与标准方案默认数据库。
- **Kraken2 Standard**（约 50 GB）：可选，用于最终报告（默认不使用）。
- **KneadData Human Bowtie2 DB**（约 3 GB）：去宿主比对数据库。
- **GRCh38 人类基因组**：模拟数据宿主来源。
- **微生物基因组**：15–30 种常见人类肠道菌，用于模拟数据微生物来源。

---

## 4. 构建与运行流程

### 4.1 极简方案（推荐首次验证）

```bash
# 1. 安装环境（仅需一次，约 30 分钟）
bash scripts/minimal/setup_minimal_env.sh

# 2. 加载环境配置
source minimal_env/env.sh

# 3. 下载微生物基因组（约 15 分钟）
cd minimal_env/genomes && bash download_genomes.sh
cd /Users/macstudio/Projects/rustyclean_benchmark

# 4. 运行极简验证（约 2–4 小时）
bash scripts/minimal/run_minimal.sh

# 5. 查看结果
ls scripts/minimal/results/
# ├── metrics/performance.csv
# ├── accuracy.csv
# └── figures/figure_speedup.png
```

### 4.2 完整（标准）方案

```bash
# 1. 安装完整环境
bash scripts/main/setup_env.sh

# 2. 激活 conda 环境
conda activate rustyclean-benchmark

# 3. 生成增强模拟数据（18 个数据集）
bash scripts/main/generate_enhanced_data.sh

# 4. 运行 benchmark（3 次重复）
bash scripts/main/run_benchmark.sh ./data/enhanced ./results

# 5. 下游分析
bash scripts/main/downstream_analysis.sh ./results ./data/enhanced

# 6. 准确性分析
python scripts/main/analyze_accuracy.py ./data/enhanced ./results ./data/analysis

# 7. 性能分析与基础可视化
python scripts/main/analyze_performance.py ./results ./data/analysis

# 8. 投稿级可视化
python scripts/main/plot_publication_figures_v2.py ./results ./figures

# 9. 生成报告
python scripts/main/generate_report.py ./results ./manuscript/report.md
```

### 4.3 从极简方案升级

```bash
bash scripts/minimal/upgrade_to_standard.sh
```

该脚本会：
1. 备份 `scripts/minimal/results/` 到 `results/minimal_baseline/`。
2. 调用 `scripts/main/generate_enhanced_data.sh` 生成剩余数据集。
3. 调用 `scripts/main/run_benchmark.sh` 对 18 个数据集跑 3 次重复。
4. 调用 `scripts/main/downstream_analysis.sh`。
5. 调用分析、可视化、报告脚本。

---

## 5. 代码组织与主要模块

### 5.1 Shell 脚本（编排层）

| 脚本 | 职责 |
|------|------|
| `scripts/minimal/setup_minimal_env.sh` | 创建 `rustyclean-minimal` conda 环境、安装基础工具、下载 MiniKraken2、设置 KneadData DB、克隆/编译 RustyClean、准备微生物基因组列表、生成 `env.sh`。 |
| `scripts/main/setup_env.sh` | 创建 `rustyclean-benchmark` conda 环境、安装完整工具集、下载数据库、准备基因组列表。 |
| `scripts/minimal/run_minimal.sh` | 生成 4 个核心数据集、运行 RustyClean vs KneadData、记录性能、调用 `analyze_minimal.py`、打印摘要。 |
| `scripts/main/generate_simulated_data.sh` | 生成 4 个基础模拟数据集（InsilicoSeq）。 |
| `scripts/main/generate_enhanced_data.sh` | 生成 18+ 个增强数据集，覆盖不同宿主比例、大小、复杂度、分布、SE/PE。 |
| `scripts/main/run_benchmark.sh` | 扫描 `data_dir/*/completed.flag`，对每个数据集跑 3 次重复，记录 `performance.csv` 与 `file_sizes.csv`。 |
| `scripts/main/downstream_analysis.sh` | 依次执行 Taxonomy（Kraken2/Bracken）、Assembly（MEGAHIT）、CheckM2、Diversity 分析。 |

### 5.2 Python 脚本（分析层）

| 脚本 | 职责 |
|------|------|
| `scripts/minimal/generate_one_dataset.py` | 被 `run_minimal.sh` 调用，使用 `iss` 生成单个数据集的宿主/微生物 reads、合并、生成 ground truth 标签与 `metadata.json`。 |
| `scripts/minimal/analyze_minimal.py` | 解析 `performance.csv`，计算速度/内存对比；读取 ground truth 与工具输出 FASTQ，计算 Accuracy/Precision/Recall/F1；生成 `figure_speedup.png/svg` 与 `figure_accuracy.png`。 |
| `scripts/main/analyze_accuracy.py` | 标准方案准确性分析：遍历所有数据集与 3 次重复，输出 `data/analysis/accuracy.csv` 与 `data/analysis/accuracy_summary.csv`。 |
| `scripts/main/analyze_performance.py` | 标准方案性能分析：输出 `01_runtime_comparison.png`、`02_speedup.png`、`03_memory_comparison.png`、`04_throughput.png` 与 `performance_summary.csv`；进行 Wilcoxon 统计检验。 |
| `scripts/main/plot_publication_figures_v2.py` | 投稿级可视化：生成 4 张多面板图（figure_1_runtime、figure_2_memory_throughput、figure_3_accuracy、figure_4_comprehensive），导出 SVG/PDF/TIFF/PNG。 |
| `scripts/main/generate_report.py` | 读取 `performance_summary.csv`、`accuracy_summary.csv`、原始 `performance.csv` 与图表目录，生成 Markdown 报告。 |

---

## 6. 关键约定与实现细节

### 6.1 数据集约定

- 每个数据集目录下需包含 `completed.flag`，表示数据生成完成。
- FASTQ 文件命名：
  - SE：`reads.fastq.gz`
  - PE：`reads_R1.fastq.gz`、`reads_R2.fastq.gz`
- Ground truth：`ground_truth_labels.txt`，每行格式为 `<read_id>\t<host|microbe>`。
- 元数据：`metadata.json`，包含 reads 数、宿主比例、模式、模拟器等信息。

### 6.2 Benchmark 输出约定

- 结果目录结构：`results/{rustyclean,kneaddata}/{dataset}_rep{N}/`。
- 性能指标写入 `results/metrics/performance.csv`，列名为：
  `tool,dataset,rep,runtime_seconds,max_memory_kb,timestamp`。
- `runtime_seconds` 来自 GNU `/usr/bin/time -v` 的 `Elapsed (wall clock) time`。
- `max_memory_kb` 来自 `Maximum resident set size`。
- macOS 的 `/usr/bin/time` 不支持 `-v`，脚本会 fallback 到内置 `time`，此时指标记为 `unknown`。

### 6.3 工具输出识别

- RustyClean 输出：在结果目录中查找任意 `.fastq.gz`。
- KneadData 输出：在结果目录中查找文件名包含 `clean` 的 `.fastq.gz`。

### 6.4 可视化风格

- 所有图表采用近似 **Nature/Cell** 风格：
  - 字体 Arial/Helvetica，字号 7 pt
  - 只保留左下边框
  - 图例无边框
  - RustyClean 颜色：`#4A90A4`（Steel Blue）
  - KneadData 颜色：`#C75B5B`（Muted Red）
- 投稿级图表导出：SVG、PDF、TIFF（600 dpi）、PNG（300 dpi）。

---

## 7. 代码风格指南

- **Shell 脚本**：
  - 使用 `#!/bin/bash` + `set -e`。
  - 使用 `"${VAR:-default}"` 提供默认路径。
  - 使用 `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` 获取脚本位置。
  - 命令执行前检查依赖是否存在（`command -v`）。
  - 日志输出使用 `echo "[Step X/Y] ..."` 形式。

- **Python 脚本**：
  - 使用 `#!/usr/bin/env python3`。
  - 命令行参数通过 `sys.argv` 解析（未使用 argparse）。
  - 非交互式绘图前设置 `matplotlib.use('Agg')`。
  - 函数与模块顶部使用英文/中文 docstring 说明用途与用法。
  - 使用 `pandas`/`numpy` 进行数据处理，使用 `matplotlib`/`seaborn` 绘图。

- **文档**：
  - 项目级 Markdown 文档使用中文。
  - 脚本内注释中英混用，以可读性为主。

---

## 8. 测试与验证

### 8.1 没有单元测试

本项目**没有 pytest / unittest 等自动化单元测试**。验证方式是端到端运行完整流程：

1. 环境能否安装成功（`setup_minimal_env.sh` 或 `setup_env.sh`）。
2. 数据能否生成（检查 `completed.flag` 与 FASTQ 文件）。
3. 两个工具是否能成功运行（检查 `results/logs/*.log`）。
4. 性能 CSV 是否包含有效时间与内存。
5. 准确性 CSV 的 F1 是否落在预期范围（RustyClean ~0.98–0.99，KneadData ~0.999）。
6. 可视化文件是否生成（`figures/`）。

### 8.2 验证指标预期

- 速度：RustyClean 应比 KneadData 快 **10–20 倍**，高宿主污染（90%）场景可达 **30–50 倍**。
- 内存：RustyClean 应比 KneadData 节省 **5–10 倍**。
- 准确性：F1 差距应 < 0.02，处于可接受范围。

---

## 9. 安全与风险提示

- **外部下载**：脚本会通过 `wget`/`curl`/`ftp` 从 NCBI、AWS、conda 仓库下载数据库与基因组；会通过 `git clone` 拉取 RustyClean 仓库。请确保网络与来源可信。
- **Conda 环境隔离**：依赖安装限制在 `rustyclean-minimal` 或 `rustyclean-benchmark` 环境中，不会直接修改系统 Python。
- **无特权操作**：脚本本身不调用 `sudo`。README 提到“手动清除系统缓存”需要 root，但该命令未写入任何脚本。
- **大文件生成**：完整方案可能生成 **~470 GB** 数据，运行前请确认磁盘空间。
- **数据隐私**：本项目处理的是公开/模拟数据，不涉及真实人类敏感数据；若用于真实样本，请遵守相应伦理与数据保护规定。

---

## 10. 常见坑与注意事项

1. **RustyClean CLI 参数**：脚本假设 RustyClean 支持 `--r1`、`--r2`、`--kraken2-db`、`-o`、`-t`。如果 RustyClean 版本更新导致参数变化，需要同步修改 `run_minimal.sh` 与 `run_benchmark.sh`。
2. **macOS `/usr/bin/time`**：不支持 `-v`，峰值内存与时间可能记录为 `unknown`。可用 GNU time 替代。
3. **KneadData 数据库下载**：`kneaddata_database --download` 可能失败，脚本内有 fallback 手动下载逻辑。
4. **InsilicoSeq**：conda 安装失败时可尝试 `pip install insilicoseq`。
5. **线程数**：默认 8 线程，确保 RustyClean 与 KneadData 使用相同线程数以公平对比。
6. **I/O 瓶颈**：建议在 SSD 上运行，机械硬盘可能掩盖速度优势。
7. **内存要求**：极简方案 ≥ 16 GB，标准方案建议 ≥ 32 GB，下游分析建议 ≥ 64 GB。

---

## 11. 没有的配置文件

- 项目根目录**没有** `pyproject.toml`、`setup.py`、`requirements.txt`、`Cargo.toml`、`package.json`、`Makefile`、CI/CD 配置文件或 Docker 文件。
- 依赖与版本完全由 conda 环境文件（`setup_env.sh` / `setup_minimal_env.sh` 中的 `conda install` 列表）管理。

---

## 12. 后续可改进方向（仅供参考）

- 为 Python 脚本增加 `argparse` 或统一入口 CLI。
- 增加 `pytest` 对时间解析、指标计算、FASTQ ID 读取等函数的单元测试。
- 增加 `Snakemake` / `Nextflow` 版本，提升可扩展性与断点续跑能力。
- 将 conda 依赖列表导出为 `environment.yml`，便于复现与版本锁定。

---

*本 AGENTS.md 基于项目实际文件内容编写，未包含任何未经验证的假设。*
