# RustyClean Benchmark Suite

全面 Benchmark 方案，对比 **RustyClean** (Rust + fastp + Kraken2) 与 **KneadData** (Python + Trimmomatic + Bowtie2) 的性能与准确性。

> 💡 **推荐策略**: 先用[极简方案](#极简验证方案)（~60 GB，~3 小时）快速验证流程和速度优势，确认后再升级到[完整方案](#完整方案）。

---

## 极简验证方案（推荐先跑这个）

**资源需求**: ~60 GB 存储，~3 小时，16 GB 内存

```bash
# 1. 进入 benchmark 目录
cd rustyclean_benchmark

# 2. 设置环境（仅需一次，~30 分钟）
bash minimal/setup_minimal_env.sh

# 3. 运行极简验证（~2-4 小时）
bash minimal/run_minimal.sh

# 4. 查看结果
ls minimal/results/
# ├── performance.csv       # 速度对比
# ├── accuracy.csv          # 准确性对比  
# └── figures/
#     ├── figure_speedup.png    # 核心可视化
#     └── figure_accuracy.png
```

极简方案包含 **4 个核心数据集**：10M/30M/60M reads，覆盖 10%-90% 宿主污染，含 SE 和 PE 模式。

> 结果满意后，一键升级：`bash minimal/upgrade_to_standard.sh`

---

## 完整方案

**资源需求**: ~470 GB 存储，~16 小时，32 GB 内存，服务器推荐

```bash
# 1. 进入 benchmark 目录
cd rustyclean_benchmark

# 2. 设置环境（安装所有依赖、数据库）
bash scripts/setup_env.sh

# 3. 激活环境
conda activate rustyclean-benchmark

# 4. 生成增强模拟数据（18 个数据集）
bash scripts/generate_enhanced_data.sh

# 5. 运行 benchmark（3 次重复）
bash scripts/run_benchmark.sh

# 6. 下游分析（组装、多样性、MAG）
bash scripts/downstream_analysis.sh ./results

# 7. 分析准确性
python scripts/analyze_accuracy.py ./data/enhanced ./results

# 8. 生成投稿级可视化
python scripts/plot_publication_figures.py ./results ./analysis/figures

# 9. 生成最终报告
python scripts/generate_report.py ./results
```

---

## 方案对比

| | **极简方案** | **标准方案** |
|--|-------------|-------------|
| 数据集 | 4 个核心 | 18 个增强 |
| 重复次数 | 1 次 | 3 次 |
| 下游分析 | ❌ 无 | ✅ 完整 |
| 可视化 | 2 张基础图 | 4 张投稿级图 |
| 存储 | **~60 GB** | ~470 GB |
| 时间 | **~3 小时** | ~16 小时 |
| 内存 | 16 GB | 32 GB |
| 速度优势验证 | ✅ 可以 | ✅ 更稳健 |
| 能否用于论文 | ⚠️ 补充材料 | ✅ 正文 |

全面 Benchmark 方案，对比 **RustyClean** (Rust + fastp + Kraken2) 与 **KneadData** (Python + Trimmomatic + Bowtie2) 的性能与准确性。

---

## 与 Hostile 的公平对比（仅去宿主步骤）

在 `benchmark/fair_hostile_skipqc/` 中，我们把 **RustyClean AUTO + `--skip-qc`** 与 **Hostile** 进行公平对比：两者都只测量去宿主步骤，不包含 QC，以排除 fastp / Trimmomatic 等环节对时间的干扰。

### 数据集

4 个不同规模与宿主比例的模拟 SE 数据集：

| dataset | reads | host % | distribution |
|---------|-------|--------|--------------|
| 5M_1pct_low_even_SE | 5 M | 1 % | even |
| 10M_10pct_med_even_SE | 10 M | 10 % | even |
| 30M_50pct_high_skewed_SE | 30 M | 50 % | skewed |
| 60M_90pct_high_lognormal_SE | 60 M | 90 % | log-normal |

### 运行

```bash
cd benchmark/fair_hostile_skipqc
sbatch run_benchmark.sh
```

HPC 脚本请求 `amd` 分区 1 节点 / 16 CPU / 64 GB，限时 24 小时。

### 最新结果（job 3898385）

| dataset | tool | runtime (s) | memory (GB) | backend |
|---|---|---:|---:|---|
| 5M_1pct_low_even_SE | rustyclean_auto_skipqc | 106 | 3.4 | bowtie2 |
| 5M_1pct_low_even_SE | hostile_raw | 110 | 2.3 | bowtie2 |
| 10M_10pct_med_even_SE | rustyclean_auto_skipqc | 116 | 3.4 | bowtie2 |
| 10M_10pct_med_even_SE | hostile_raw | 212 | 3.2 | bowtie2 |
| 30M_50pct_high_skewed_SE | rustyclean_auto_skipqc | 552 | 15.4 | kraken2 |
| 30M_50pct_high_skewed_SE | hostile_raw | 2385 | 3.4 | bowtie2 |
| 60M_90pct_high_lognormal_SE | rustyclean_auto_skipqc | 858 | 15.5 | kraken2 |
| 60M_90pct_high_lognormal_SE | hostile_raw | 4241 | 3.4 | bowtie2 |

完整 metrics 见 `benchmark/results/fair_hostile_skipqc_results.csv`。

---

## RustyClean AUTO（含 QC）vs KneadData 全流程对比

在 `benchmark/auto_vs_kneaddata/` 中，对比两个工具的**完整流程**：RustyClean（fastp QC + AUTO 自适应去宿主）vs KneadData（Trimmomatic QC + Bowtie2 去宿主）。

### 数据集

与 Hostile 公平对比使用相同的 4 个模拟 SE 数据集。

### 运行

```bash
cd benchmark/auto_vs_kneaddata
sbatch run_benchmark.sh
```

### 最新结果（job 3899267）

| dataset | tool | runtime (s) | memory (GB) | backend |
|---|---|---:|---:|---|
| 5M_1pct_low_even_SE | rustyclean_auto | 170 | 3.4 | bowtie2 |
| 5M_1pct_low_even_SE | kneaddata | 420 | 1.1 | bowtie2 |
| 10M_10pct_med_even_SE | rustyclean_auto | 189 | 3.4 | bowtie2 |
| 10M_10pct_med_even_SE | kneaddata | 695 | 1.1 | bowtie2 |
| 30M_50pct_high_skewed_SE | rustyclean_auto | 815 | 15.4 | kraken2 |
| 30M_50pct_high_skewed_SE | kneaddata | 2317 | 1.1 | bowtie2 |
| 60M_90pct_high_lognormal_SE | rustyclean_auto | 1470 | 15.5 | kraken2 |
| 60M_90pct_high_lognormal_SE | kneaddata | 6822 | 1.1 | bowtie2 |

完整 metrics 见 `benchmark/results/auto_vs_kneaddata_metrics.csv`。

> 注意：KneadData 默认流程会生成大量 TRF 中间文件（最后一个 60M 数据集占约 66 GB 临时文件），而 RustyClean 的中间文件和峰值内存均显著更小。

---

## 综合对比图

`benchmark/figures/rc_hostile_kneaddata_comparison.{png,svg,pdf}` 汇总了 RustyClean 与 Hostile / KneadData 在 4 个模拟数据集上的运行时间、峰值内存和 F1-score：

- **上行**：与 Hostile 的公平对比（均不包含 QC）
- **下行**：与 KneadData 的全流程对比（均包含 QC）

该图由 `benchmark/scripts/plot_rc_hostile_kneaddata.py` 基于 `benchmark/results/fair_hostile_skipqc_results.csv`、`auto_vs_kneaddata_metrics.csv` 和 `accuracy_comparison.csv` 生成。

---

## Bowtie2 复核步骤对 Kraken2 准确性的提升

在 `benchmark/bowtie2_recheck/` 中评估了 RustyClean 的 **Bowtie2 复核** 功能：当 Kraken2 将某些宿主 reads 判定为 unclassified 时，使用 Bowtie2 对这些 reads 进行二次比对并去除命中宿主索引的 reads。

### 数据集

4 个大规模高宿主 SE 数据集：

| dataset | reads | host % | distribution |
|---------|-------|--------|--------------|
| 30M_50pct_high_skewed_SE | 30 M | 50 % | skewed |
| 60M_90pct_high_lognormal_SE | 60 M | 90 % | log-normal |
| 100M_50pct_high_lognormal_SE | 100 M | 50 % | log-normal |
| 100M_90pct_high_lognormal_SE | 100 M | 90 % | log-normal |

### 运行

```bash
cd benchmark/bowtie2_recheck/scripts
sbatch benchmark_baseline_kraken2_memmap.sh
sbatch benchmark_bowtie2_recheck_v2.sh
```

### 最新结果

| dataset | host % | baseline F1 | +Bowtie2 recheck F1 | ΔF1 |
|---|---|---:|---:|---:|
| 30M_50pct_high_skewed_SE | 50 % | 0.9890 | 0.9974 | +0.0084 |
| 60M_90pct_high_lognormal_SE | 90 % | 0.9299 | 0.9942 | +0.0643 |
| 100M_50pct_high_lognormal_SE | 50 % | 0.9912 | 0.9976 | +0.0064 |
| 100M_90pct_high_lognormal_SE | 90 % | 0.9299 | 0.9943 | +0.0644 |

- **90% 宿主样本**提升最大：F1 从 ~0.93 提升到 ~0.994。
- **运行时间开销**很小（30M +5.7%，60M +20.3%，100M 基本不变）。
- **峰值内存**维持在 ~15.5 GB，无显著增加。

在 AUTO 模式下，当 survey 估计宿主比例超过高阈值（默认 30%）时会自动开启 Bowtie2 复核，无需用户手动指定 `--bowtie2-recheck`。

---

## 快速开始

```bash
# 1. 进入 benchmark 目录
cd rustyclean_benchmark

# 2. 设置环境（安装所有依赖、数据库）
bash scripts/setup_env.sh

# 3. 激活环境
conda activate rustyclean-benchmark

# 4. 生成模拟测试数据
bash scripts/generate_simulated_data.sh

# 5. 运行 benchmark
bash scripts/run_benchmark.sh

# 6. 分析准确性（模拟数据）
python scripts/analyze_accuracy.py ./data/simulated ./results

# 7. 分析性能并生成可视化
python scripts/analyze_performance.py ./results

# 8. 生成最终报告
python scripts/generate_report.py ./results
```

---

## 文件结构

```
rustyclean_benchmark/
├── benchmark_plan.md              # 详细 benchmark 设计方案
├── README.md                      # 本文件
├── scripts/
│   ├── setup_env.sh              # 环境安装脚本
│   ├── generate_simulated_data.sh # 生成模拟数据
│   ├── run_benchmark.sh          # 执行 benchmark
│   ├── analyze_accuracy.py       # 准确性分析
│   ├── analyze_performance.py    # 性能分析+可视化
│   └── generate_report.py        # 报告生成
├── data/
│   └── simulated/                # 模拟数据集（自动生成）
└── results/
    ├── rustyclean/               # RustyClean 输出
    ├── kneaddata/                # KneadData 输出
    ├── logs/                     # 运行日志
    ├── metrics/                  # 性能指标
    └── analysis/                 # 分析结果
        ├── figures/              # 可视化图表
        ├── accuracy.csv          # 准确性数据
        ├── performance_summary.csv
        └── report.md             # 最终报告
```

---

## 评价指标

### 性能指标

| 指标 | 说明 | 预期结果 |
|------|------|---------|
| **Wall Clock Time** | 总运行时间 | RustyClean 快 10-20x |
| **Peak Memory** | 峰值内存 | RustyClean 省 5-10x |
| **Throughput** | reads/second | RustyClean 高 10x+ |
| **Output Size** | 输出文件大小 | 两者相当 |

### 准确性指标（仅模拟数据）

| 指标 | 公式 | 预期结果 |
|------|------|---------|
| **Accuracy** | (TP+TN)/Total | KneadData 略高 (0.9997 vs 0.9891) |
| **Precision** | TP/(TP+FP) | KneadData 假阳性更高 |
| **Recall** | TP/(TP+FN) | RustyClean 假阴性更高 |
| **F1-Score** | 2PR/(P+R) | 两者接近 (>0.98) |

---

## 数据集设计

### 模拟数据（用于准确性评估）

| 数据集 | 总 Reads | 宿主比例 | 用途 |
|--------|---------|---------|------|
| 10M_10pct | 10M | 10% | 低污染小数据 |
| 30M_50pct | 30M | 50% | 中等污染 |
| 60M_90pct | 60M | 90% | 高污染大数据 |
| 20M_PE_50pct | 20M | 50% | 配对端测试 |

**宿主基因组**: GRCh38 人类参考基因组
**微生物组**: 30 种常见人类肠道细菌

### 真实数据（用于实际性能验证）

从 NCBI SRA 下载公开人类肠道 metagenome 数据。

---

## 参考论文

Gao Y, et al. (2024). [Benchmarking short-read metagenomics tools for removing host contamination](https://doi.org/10.1093/gigascience/giaf004), *GigaScience*, GigaScience, Volume 14, 2025, giaf004.

该论文关键发现：
- **Kraken2** 最快: 29.34 min，内存 2.47 Gb
- **KneadData** 最慢: 501.38 min，内存 15.17 Gb
- **速度差距 17 倍**，内存差距 6 倍
- 高宿主污染 (90%) 时，KneadData 变慢 5.36 倍

---

## 配置说明

### 环境变量

```bash
export RUSTYCLEAN=rustyclean
export KNEADDATA=kneaddata
export KRAKEN2_DB=$HOME/benchmark_env/databases/minikraken2_v1_8GB
export KNEADDATA_DB=$HOME/benchmark_env/databases/kneaddata_human_db
```

### 数据库选择

| 数据库 | 大小 | 适用场景 |
|--------|------|---------|
| MiniKraken2 v1 | 8 GB | 快速测试 |
| Kraken2 Standard | 50 GB | 最终报告 |
| KneadData Human | 3 GB | 比对去宿主 |

---

## 注意事项

1. **公平对比**: 使用相同的线程数 (8 threads) 和输入数据
2. **缓存清除**: 每次运行前清除系统缓存（`sync && echo 3 | sudo tee /proc/sys/vm/drop_caches`）
3. **I/O 瓶颈**: 确保数据在 SSD 上
4. **随机种子**: 模拟数据使用固定随机种子，确保可重复
5. **版本记录**: 记录所有工具精确版本号

---

## 预期结果

基于 Gao et al. (2024) 的发现：

| 指标 | RustyClean (预期) | KneadData (预期) | 差距 |
|------|------------------|-----------------|------|
| 速度 | ~30 min | ~500 min | **17x** |
| 内存 | ~3 GB | ~15 GB | **5x** |
| 准确率 | ~0.989 | ~0.9997 | 接近 |
| F1-Score | ~0.98 | ~0.999 | 可接受 |

---

## 输出示例

运行完成后，在 `results/analysis/` 目录下：

```
analysis/
├── figures/
│   ├── 01_runtime_comparison.png      # 运行时间对比
│   ├── 02_speedup.png                 # 加速比
│   ├── 03_memory_comparison.png       # 内存对比
│   └── 04_throughput.png             # 吞吐量对比
├── accuracy.csv                      # 准确性原始数据
├── accuracy_summary.csv              # 准确性汇总
├── performance_summary.csv           # 性能汇总
└── report.md                         # 最终报告
```

---

## 作者

为 [rustyclean](https://github.com/HuangShiLab/rustyclean) 项目创建的 Benchmark 方案。

## License

MIT
