# RustyClean Benchmark Paper

本仓库为 **RustyClean** 的 benchmark 论文配套资料库，包含：

- 投稿级论文稿件（`manuscript/`）
- 投稿级图表（`figures/`，fig1–fig4 + figS1）
- 模拟数据集生成、benchmark、准确性分析、可视化所需的全部代码（`scripts/`）
- 已生成的关键结果指标（`data/`）
- 早期探索性分析与旧版稿件（`others/`）

> RustyClean 是一个基于 Rust 的高性能宏基因组宿主污染去除流程，串联 `fastp`（QC）与 `Kraken2`/`Bowtie2`（宿主去除）。本 benchmark 证明其在保持与 KneadData / Hostile 可比拟准确性的同时，速度提升一个数量级以上。

---

## 主要结论

- **速度**：RustyClean AUTO 在 4 个标准 SE 数据集上比 KneadData 全流程平均快 **~5–40×**，高宿主（≥50%）场景优势更明显。
- **内存**：RustyClean 峰值内存与 KneadData 相当或更低；T2T-only Kraken2 索引约 **15.5 GB**。
- **准确性**：在 18 个增强数据集上，RustyClean 与 KneadData 的 F1-score 差距 **< 0.02**；对 Hostile 的公平对比（均不含 QC）F1 差距 **< 0.01**。
- **自适应策略**：AUTO 模式通过轻量 survey 估计宿主比例，低宿主走 Kraken2-only，高宿主自动启用 Bowtie2 复核，兼顾速度与准确性。
- **默认数据库**：T2T-CHM13v2.0 人源专用 Kraken2 索引；混合 Kraken2 索引（如 kraken16）作为可选 taxonomy-aware 模式。

详细结果与讨论见 `manuscript/RustyClean_Manuscript_Draft.md`。

---

## 仓库结构

```
rustyclean-paper/
├── manuscript/                    # 论文稿件
│   ├── RustyClean_Manuscript_Draft.md
│   └── RustyClean_Manuscript_Draft.docx
├── figures/                       # 投稿级图表（fig1–fig4 + figS1，png/svg/pdf）
├── data/                          # 结果数据与指标
│   ├── results_100M_matched/      # 100M 匹配面板（vs Hostile / KneadData）
│   ├── results_100M_skipqc_matched/
│   ├── benchmark_results/         # 公平对比指标
│   └── *.csv                      # 汇总 accuracy / performance 表格
├── scripts/                       # 代码与流程脚本
│   ├── main/                      # 主流程：数据生成、benchmark、分析、可视化
│   ├── hpc/                       # SLURM 集群提交脚本
│   ├── benchmark/                 # 与 Hostile / KneadData 对比脚本
│   ├── minimal/                   # 极简验证方案
│   └── rustyclean_src/            # RustyClean 源码本地备份（gitignore）
├── others/                        # 早期探索与辅助文档
│   ├── old_manuscripts/           # 旧版 manuscript / paper_draft
│   ├── planning_docs/             # benchmark_plan、competitiveness_analysis 等
│   └── tmp_scripts/               # 临时/废弃脚本
├── README.md                      # 本文件
├── AGENTS.md                      # AI Agent 指南
└── LICENSE
```

---

## 快速开始

### 极简验证方案（推荐先跑）

资源需求：~60 GB 存储，~3 小时，16 GB 内存。

```bash
# 1. 安装环境（仅需一次，~30 分钟）
bash scripts/minimal/setup_minimal_env.sh

# 2. 运行极简验证（~2–4 小时）
bash scripts/minimal/run_minimal.sh

# 3. 查看结果
ls scripts/minimal/results/
# ├── metrics/performance.csv
# ├── accuracy.csv
# └── figures/*.png
```

极简方案包含 4 个核心数据集（10M/30M/60M reads，10%–90% 宿主污染，含 SE/PE）。

> 结果满意后，一键升级到标准方案：`bash scripts/minimal/upgrade_to_standard.sh`

### 完整标准方案

资源需求：~470 GB 存储，~16 小时，32 GB 内存。

```bash
# 1. 安装环境
bash scripts/main/setup_env.sh
conda activate rustyclean-benchmark

# 2. 生成增强模拟数据（18 个数据集）
bash scripts/main/generate_enhanced_data.sh

# 3. 运行 benchmark（3 次重复）
bash scripts/main/run_benchmark.sh ./data/enhanced ./results

# 4. 下游分析（Taxonomy / Assembly / CheckM2 / Diversity）
bash scripts/main/downstream_analysis.sh ./results ./data/enhanced

# 5. 准确性分析
python scripts/main/analyze_accuracy.py ./data/enhanced ./results ./data/analysis

# 6. 性能分析与基础可视化
python scripts/main/analyze_performance.py ./results ./data/analysis

# 7. 投稿级可视化
python scripts/main/plot_publication_figures_v2.py ./results ./figures

# 8. 生成报告
python scripts/main/generate_report.py ./results ./manuscript/report.md
```

### 与 Hostile / KneadData 的公平对比

| 对比类型 | 说明 | 脚本位置 |
|---------|------|---------|
| vs Hostile（仅去宿主） | RustyClean `--skip-qc` vs Hostile，排除 QC 干扰 | `scripts/benchmark/fair_hostile_skipqc_run_benchmark.sh` |
| vs KneadData（完整流程） | RustyClean AUTO（含 fastp QC）vs KneadData（含 Trimmomatic QC） | `scripts/benchmark/run_benchmark.sh` |

完整 metrics：
- `data/benchmark_results/fair_hostile_skipqc_results.csv`
- `data/benchmark_results/auto_vs_kneaddata_metrics.csv`

---

## 核心图表

| 图表 | 内容 | 文件 |
|------|------|------|
| fig1 | 模拟数据错误/污染特征 | `figures/fig1_error_profile.*` |
| fig2 | 与 Hostile / KneadData 的匹配面板对比（时间、内存、F1） | `figures/fig2_matched_panel.*` |
| fig3 | 18 个增强数据集准确性 | `figures/fig3_accuracy.*` |
| fig4 | 相对加速比与内存效率 | `figures/fig4_speedup.*` |
| figS1 | 后端（Kraken2 / Bowtie2 / minimap2）对比 | `figures/figS1_backend_comparison.*` |

---

## 数据库与参考数据

当前默认使用 **T2T-CHM13v2.0 人源专用索引**：

| 索引 | 工具 | 大小 | 路径示例 |
|------|------|------|---------|
| T2T-only human | Kraken2 | ~15.5 GB | `/lustre1/g/aos_shihuang/databases/rustyclean_human_t2t_only/kraken2/t2t_only` |
| T2T + HLA | Bowtie2 | ~3.3 GB | `/lustre1/g/aos_shihuang/databases/rustyclean_human_t2t_only/bowtie2/t2t_hla` |
| KneadData human | Bowtie2 | ~4.1 GB | `/lustre1/g/aos_shihuang/databases/kneaddata/hg_39` |

构建脚本见 `scripts/main/build_kraken2_t2t_only.sh` 与相关 `build_*` 脚本。

---

## 环境变量

```bash
export RUSTYCLEAN=rustyclean
export KNEADDATA=kneaddata
export KRAKEN2_DB=/path/to/rustyclean_human_t2t_only/kraken2/t2t_only
export KNEADDATA_DB=/path/to/kneaddata/hg_39
```

---

## 引用

若使用本仓库数据或代码，请引用 RustyClean benchmark 论文（准备中）。

参考基准研究：

Gao Y, et al. (2024). [Benchmarking short-read metagenomics tools for removing host contamination](https://doi.org/10.1093/gigascience/giaf004), *GigaScience*, Volume 14, 2025, giaf004.

---

## 作者与许可

为 [rustyclean](https://github.com/HuangShiLab/rustyclean) 项目创建的 Benchmark 论文资料库。

License: MIT
