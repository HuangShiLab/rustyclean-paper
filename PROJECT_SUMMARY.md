# RustyClean Benchmark 项目总结

> **项目**: 为 rustyclean (Rust metagenome host removal pipeline) 设计 benchmark 方案，对比 KneadData
> **位置**: `/Users/shihuang/Documents/kimi/workspace/rustyclean_benchmark/`
> **时间**: 2026-07-17
> **下一步**: 在 Mac Studio 上运行极简验证方案（~60 GB，~3 小时）

---

## 1. 项目背景

**rustyclean**: https://github.com/HuangShiLab/rustyclean — Rust 编写的高性能 metagenome QC + 去宿主 pipeline，串联 `fastp` + `Kraken2`。  
**目标**: 证明可以替代 KneadData（Python + Trimmomatic + Bowtie2，非常慢）。

**关键参考论文**: Gao et al. (2024). *Benchmarking short-read metagenomics tools for removing host contamination*. iMeta, 4(1): e70005.  
- **GitHub**: `https://github.com/YunyunGao374/HostPurge`
- 该论文比较了 6 个工具，发现 Kraken2 比 KneadData 快 **17x**、内存省 **6x**
- 但 Gao 比较的是**现有独立工具**，我们是**开发新 pipeline**（目的不同）

---

## 2. 已交付文件清单

### 2.1 项目根目录

| 文件 | 说明 |
|------|------|
| `benchmark_plan.md` | 完整 benchmark 设计方案（数据集、指标、流程、引用） |
| `competitiveness_analysis.md` | RustyClean 竞争力分析（4 个胜出维度、1 个劣势、应对策略） |
| `storage_analysis.md` | 存储空间分析（Gao 7 TB vs 我们 470 GB / 极简 60 GB） |
| `distinction_from_gao.md` | 与 Gao et al. 的 5 个关键区别（含论文段落示例） |
| `README.md` | 项目主文档（含极简和完整方案对比） |

### 2.2 极简验证方案（`minimal/`）— 推荐先在 Mac Studio 上运行

| 文件 | 说明 |
|------|------|
| `minimal/README.md` | 极简方案指南（3 步完成验证） |
| `minimal/setup_minimal_env.sh` | 环境设置：conda 环境 + MiniKraken2 (8GB) + KneadData DB + rustyclean |
| `minimal/run_minimal.sh` | 一键运行：生成 4 个数据集 + 运行 RustyClean vs KneadData + 记录性能 |
| `minimal/generate_one_dataset.py` | 单数据集生成（InsilicoSeq） |
| `minimal/analyze_minimal.py` | 结果分析：速度对比 + 准确性 + 生成 figure_speedup.png |
| `minimal/upgrade_to_standard.sh` | 确认极简结果后，一键扩展到完整方案 |

### 2.3 标准方案脚本（`scripts/`）— 后续扩展用

| 文件 | 说明 |
|------|------|
| `scripts/setup_env.sh` | 完整环境安装（所有工具 + 数据库） |
| `scripts/generate_simulated_data.sh` | 基础 4 个数据集生成 |
| `scripts/generate_enhanced_data.sh` | 增强 18 个数据集生成（多宿主比例、复杂度、分布） |
| `scripts/run_benchmark.sh` | 完整 benchmark（3 次重复） |
| `scripts/analyze_accuracy.py` | 准确性分析（F1/Precision/Recall） |
| `scripts/analyze_performance.py` | 性能分析 + 基础可视化 |
| `scripts/plot_publication_figures.py` | **投稿级可视化**（Nature/Cell 风格，4 张多面板图） |
| `scripts/downstream_analysis.sh` | 下游分析：Taxonomy + Assembly + CheckM2 + Diversity |
| `scripts/generate_report.py` | 自动报告生成 |

---

## 3. 关键决策记录

### 3.1 数据集选择（为什么选这 4 个）

| 数据集 | Reads | 宿主% | 模式 | 验证目标 |
|--------|-------|-------|------|---------|
| 10M_10pct | 10M | 10% | SE | 低污染假阳性测试 |
| 30M_50pct | 30M | 50% | SE | 标准中等污染 |
| **60M_90pct** | 60M | **90%** | SE | **杀手级场景** — KneadData 高污染时慢 5.4x，RustyClean 优势最大 |
| 20M_50pct_PE | 20M | 50% | PE | 配对端兼容性 |

### 3.2 数据库选择

- **MiniKraken2 v1** (8 GB): 极简和标准方案先用这个，速度快
- **Kraken2 Standard** (50 GB): 最终论文时升级，精度更高
- **KneadData Human Bowtie2** (~3 GB): 去宿主比对用
- **人类基因组** (GRCh38 chr1, ~250 MB): 模拟数据宿主来源
- **15 种微生物基因组** (~1 GB): 模拟数据微生物来源

### 3.3 竞争策略

**4 个胜出维度**:
1. **速度** — 预期 10-20x（高污染时 30-50x），因为 Kraken2 比 Bowtie2 快 17x + fastp 比 Trimmomatic 快 2-5x
2. **内存** — 预期 5-10x，因为 Kraken2 仅需 2.5 GB vs KneadData 15 GB
3. **高宿主污染** — 优势放大，Kraken2 速度不受污染率影响，Bowtie2 线性变慢
4. **假阳性更低** — Kraken2 误杀微生物 reads 更少，保留更多稀有物种信息

**1 个劣势（可接受）**:
- 假阴性（残留宿主）略高 — 但残留宿主可在下游 Kraken2 分类中过滤，而被误杀的微生物是永久性数据丢失

**论文定位**:
> "不是追求绝对最高精度，而是追求最佳的速度-精度 trade-off，尤其适用于大规模 metagenome 研究。"

---

## 4. 下一步：在 Mac Studio 上运行极简方案

### 4.1 前置要求

- macOS (你的 Mac Studio 已满足)
- **conda** 或 **miniconda** 已安装
- **Rust** (cargo) 已安装 — 用于编译 rustyclean
- **可用存储**: ≥ 80 GB
- **内存**: ≥ 16 GB
- **建议**: 使用 SSD 外接硬盘（避免 I/O 瓶颈）

### 4.2 执行步骤（按顺序）

```bash
# 1. 进入项目目录
cd /Users/shihuang/Documents/kimi/workspace/rustyclean_benchmark

# 2. 设置环境 (~30 分钟，仅需一次)
bash minimal/setup_minimal_env.sh

# 3. 加载环境配置
source minimal_env/env.sh

# 4. 下载微生物基因组 (~15 分钟)
cd minimal_env/genomes && bash download_genomes.sh

# 5. 运行极简验证 (~2-4 小时，可离开电脑)
cd /Users/shihuang/Documents/kimi/workspace/rustyclean_benchmark
bash minimal/run_minimal.sh

# 6. 查看结果
cat minimal/results/metrics/performance.csv
open minimal/results/figures/figure_speedup.png
```

### 4.3 预期输出

```
速度对比:
  10M_10pct      : RustyClean   0.3 min vs KneadData    5.1 min →  17.0x 加速
  30M_50pct      : RustyClean   0.8 min vs KneadData   15.3 min →  19.1x 加速
  60M_90pct      : RustyClean   1.5 min vs KneadData   81.2 min →  54.1x 加速  ⭐
  20M_50pct_PE   : RustyClean   0.6 min vs KneadData   10.2 min →  17.0x 加速

准确性对比 (F1-Score):
  RustyClean  : 0.9876
  KneadData   : 0.9994
  差距        : 0.0118 (可接受)
```

### 4.4 决策检查点

跑完后检查：
- ✅ 速度优势 ≥ 10x → 正常，继续升级到标准方案
- ✅ 速度优势 ≥ 20x 且 60M_90pct > 30x → 优秀，立即升级
- ⚠️ 速度优势 < 5x → 检查配置（线程数、I/O 瓶颈、数据库路径）

升级到标准方案：
```bash
bash minimal/upgrade_to_standard.sh
```

---

## 5. 与 Gao et al. 的核心区别（审稿人会问）

| 维度 | Gao et al. | RustyClean |
|------|-----------|-----------|
| **目的** | 评估 6 个现有工具 | 验证新开发的 pipeline |
| **范围** | 广度优先（6 工具 × 1,080 数据集） | 深度优先（2 工具 × 18 数据集 + 下游分析） |
| **方法** | 调用官方 CLI | 自研 Rust 框架（async I/O + checkpoint + 配置驱动） |
| **规模** | ~7 TB（服务器级） | ~470 GB（极简 60 GB，工作站级） |
| **下游分析** | 无 | Assembly + Diversity + MAG quality |

**一句话回答审稿人**:
> "Gao et al. 回答了'哪个现有工具最好'，我们回答了'我们开发的新 pipeline 能否替代行业标准 KneadData'——两者目的互补，不是重复。"

---

## 6. 可视化规范（投稿用）

已配置 Nature/Cell 风格的 matplotlib rcParams：
- 字体：Arial, 7pt
- 边框：仅左下（无右上）
- 图例：无边框
- 色彩：Steel Blue (#4A90A4) for RustyClean, Muted Red (#C75B5B) for KneadData
- 导出格式：SVG + PDF + TIFF (600 dpi) + PNG (300 dpi)

4 张投稿级图表：
1. `figure_1_runtime.svg` — 运行时间对比 + 加速比
2. `figure_2_memory_throughput.svg` — 内存 + 吞吐量
3. `figure_3_accuracy.svg` — Precision / Recall / F1
4. `figure_4_comprehensive.svg` — 6 面板综合评估（速度-精度 trade-off、污染率影响、综合评分）

---

## 7. 联系方式 / 资源

- **rustyclean GitHub**: https://github.com/HuangShiLab/rustyclean
- **Gao et al. GitHub**: https://github.com/YunyunGao374/HostPurge
- **Gao et al. 论文**: https://pmc.ncbi.nlm.nih.gov/articles/PMC11878760/
- **MiniKraken2 下载**: https://genome-idx.s3.amazonaws.com/kraken/minikraken2_v1_8GB_201904.tgz

---

## 8. 可能的坑和注意事项

1. **KneadData 人类数据库下载可能失败** — 如果 `kneaddata_database` 命令失败，脚本会尝试手动下载，但可能需要手动去官网下载
2. **InsilicoSeq 安装** — 如果 conda 安装失败，尝试 `pip install insilicoseq`
3. **Rust 编译** — 确保 `cargo` 在 PATH 中，rustyclean 编译需要 ~5 分钟
4. **时间记录** — macOS 的 `/usr/bin/time` 可能不支持 `-v` 参数，脚本已做 fallback 处理
5. **内存监控** — macOS 没有 `/proc` 文件系统，peak memory 通过 GNU time 的 `Maximum resident set size` 获取
6. **I/O 瓶颈** — 如果跑在机械硬盘上，速度优势可能被 I/O 掩盖。建议 SSD。
7. **线程数** — 默认 8 threads，Mac Studio 可以调高到 16-24，但确保两个工具用相同线程数

---

*本总结由 Kimi 生成，可直接作为技术备忘录使用。*
