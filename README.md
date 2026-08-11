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
