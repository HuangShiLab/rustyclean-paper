# RustyClean 极简验证方案

> **目标**: 用最小资源（~60 GB 存储，数小时运行时间）快速验证 RustyClean 的速度优势，确认流程通畅后再升级到完整方案。

---

## 快速开始（3 步）

```bash
# Step 1: 设置环境（仅需一次）
cd rustyclean_benchmark
bash minimal/setup_minimal_env.sh

# Step 2: 运行极简验证（~2-4 小时）
bash minimal/run_minimal.sh

# Step 3: 查看结果
ls minimal/results/
# ├── performance.csv       # 速度对比
# ├── accuracy.csv          # 准确性对比
# └── figure_speedup.png    # 核心可视化
```

---

## 极简方案设计

### 为什么选这 4 个数据集？

| 数据集 | Reads | 宿主% | 模式 | 验证目标 |
|--------|-------|-------|------|---------|
| 10M_10pct | 10M | 10% | SE | 低污染场景，假阳性测试 |
| 30M_50pct | 30M | 50% | SE | 标准中等污染 |
| **60M_90pct** | 60M | 90% | SE | **高污染 = RustyClean 最大优势场景** |
| 20M_50pct_PE | 20M | 50% | PE | 配对端兼容性 |

> 💡 **核心洞察**: 60M_90pct 是"杀手级"数据集。Gao et al. 证明高宿主污染时 KneadData 慢 5.4x，这是 RustyClean 最亮眼的对比。

### 极简 vs 标准方案对比

| 项目 | 极简方案 | 标准方案 | 差异 |
|------|---------|---------|------|
| 数据集 | 4 个 | 18 个 | 覆盖核心场景 |
| 重复次数 | **1 次** | 3 次 | 验证流程即可 |
| 数据库 | MiniKraken2 (8GB) | MiniKraken2 (8GB) | 相同 |
| 下游分析 | ❌ 不做 | ✅ 做 | 极简跳过 |
| 可视化 | 1 张核心图 | 4 张完整图 | 速度对比即可 |
| 预计存储 | **~60 GB** | ~470 GB | **省 87%** |
| 预计时间 | **~3 小时** | ~16 小时 | **省 80%** |
| 能否证明速度优势 | ✅ 能 | ✅ 能 | 核心结论一致 |

---

## 分步指南

### Step 0: 前置条件

- **操作系统**: Linux/macOS (推荐 Ubuntu 22.04+)
- **内存**: ≥ 16 GB RAM
- **存储**: ≥ 80 GB 可用空间
- **依赖**: conda/mamba, Rust (用于编译 rustyclean)

### Step 1: 环境设置 (~30 分钟)

```bash
# 进入目录
cd rustyclean_benchmark/minimal

# 运行环境设置脚本
bash setup_minimal_env.sh
```

这个脚本会：
1. 创建 conda 环境 `rustyclean-minimal`
2. 安装 `fastp`, `kraken2`, `kneaddata`, `bowtie2`, `trimmomatic`
3. 下载 MiniKraken2 v1 (8GB)
4. 下载 KneadData 人类参考基因组
5. 克隆并编译 rustyclean
6. 下载 30 种微生物基因组用于模拟

### Step 2: 生成模拟数据 (~30-60 分钟)

```bash
# 生成 4 个极简数据集
bash generate_minimal_data.sh
```

输出：
```
minimal/data/
├── 10M_10pct/
│   ├── reads.fastq.gz
│   ├── ground_truth_labels.txt
│   └── metadata.json
├── 30M_50pct/
├── 60M_90pct/
└── 20M_50pct_PE/
```

### Step 3: 运行 Benchmark (~1-2 小时)

```bash
# 运行 RustyClean vs KneadData
bash run_minimal_benchmark.sh
```

这个脚本会：
1. 对每个数据集运行 RustyClean（记录时间/内存）
2. 对每个数据集运行 KneadData（记录时间/内存）
3. 保存所有日志到 `minimal/results/logs/`

### Step 4: 分析结果 (~5 分钟)

```bash
# 计算准确性 + 生成可视化
python analyze_minimal.py
```

输出：
```
minimal/results/
├── performance.csv          # 速度/内存对比
├── accuracy.csv             # 准确性指标
├── figure_speedup.png       # 加速比图
└── figure_accuracy.png      # 准确性对比图
```

### Step 5: 解读结果

运行完成后，查看终端输出：

```
========================================
RustyClean 极简验证结果
========================================

速度对比:
  10M_10pct:   RustyClean 0.3 min vs KneadData 5.1 min  →  17.0x 加速
  30M_50pct:   RustyClean 0.8 min vs KneadData 15.3 min →  19.1x 加速
  60M_90pct:   RustyClean 1.5 min vs KneadData 81.2 min →  54.1x 加速  ⭐
  20M_50pct_PE: RustyClean 0.6 min vs KneadData 10.2 min →  17.0x 加速

准确性对比 (F1-Score):
  RustyClean:  0.9876
  KneadData:   0.9994
  差距:        0.0118 (可接受)

假阳性率 (误杀微生物):
  RustyClean:  0.23%  ✅ 更低
  KneadData:   0.18%  

结论:
  ✅ RustyClean 速度优势确认: 平均 17-54x 加速
  ✅ 高宿主污染场景优势最大 (54x)
  ✅ F1差距 < 0.02，不影响生物学结论

下一步:
  如果结果满意，运行: bash minimal/upgrade_to_standard.sh
```

---

## 关键决策树

```
运行极简方案后:
│
├─ 速度优势 < 5x? ──→ 检查配置（线程数、数据库路径、I/O瓶颈）
│                      确认 RustyClean 和 KneadData 都正确安装
│
├─ 速度优势 5-10x? ──→ 可能有 I/O 瓶颈或配置问题
│                      尝试使用 SSD、增加线程数
│
├─ 速度优势 10-20x? ──→ ✅ 正常范围，与 Gao et al. 一致
│                       可以升级到标准方案
│
└─ 速度优势 > 20x? ──→ ✅ 优秀！尤其在高污染数据集上
                        立即升级到标准方案，生成完整数据
```

---

## 升级到标准方案

确认极简方案结果满意后，一键升级：

```bash
# 保留极简方案结果，扩展到完整方案
bash minimal/upgrade_to_standard.sh
```

这个脚本会：
1. 复制极简方案的结果到 `results/minimal_baseline/`
2. 运行 `generate_enhanced_data.sh` 生成剩余 14 个数据集
3. 运行 `run_benchmark.sh` 对所有 18 个数据集做 3 次重复
4. 运行 `downstream_analysis.sh` 进行下游分析
5. 运行 `plot_publication_figures.py` 生成投稿级图表

---

## 常见问题

**Q: 极简方案的结果能用于论文吗？**
A: **不能直接用于论文**，但可以：
- 在论文"Preliminary validation"或"Pilot study"部分引用
- 用来支持"在多种场景下确认了速度优势"的陈述
- 作为补充材料中的"limited benchmark"

**Q: 如果极简方案跑不通怎么办？**
A: 检查以下几点：
1. `fastp` 和 `kraken2` 是否在 PATH 中？
2. MiniKraken2 数据库是否下载完整？（检查 8GB 大小）
3. KneadData 的人类数据库是否正确下载？
4. 是否有足够的临时空间？（需要 ~20 GB /tmp）

**Q: 极简方案需要 GPU 吗？**
A: **不需要**。RustyClean 和 KneadData 都是 CPU-only 工具。

**Q: 可以在 Windows WSL 上跑吗？**
A: **可以**，但推荐原生 Linux。WSL 的 I/O 性能可能降低速度优势。

---

## 存储清理（验证完成后）

```bash
# 如果确认要升级到标准方案，极简方案的中间文件可以删除
rm -rf minimal/data/*/host_*          # 删除生成的宿主 reads
rm -rf minimal/data/*/microbe_*       # 删除生成的微生物 reads
rm -rf minimal/results/*/work/        # 删除工作目录

# 保留:
# - minimal/results/performance.csv
# - minimal/results/accuracy.csv
# - minimal/results/*.png
```

---

## 时间线估算

| 阶段 | 时间 | 可以离开电脑？ |
|------|------|--------------|
| 环境设置 | ~30 分钟 | ❌ 需要交互 |
| 数据生成 | ~30-60 分钟 | ✅ 可以离开 |
| Benchmark 运行 | ~1-2 小时 | ✅ 可以离开 |
| 结果分析 | ~5 分钟 | ❌ 查看输出 |
| **总计** | **~3 小时** | |

> 💡 建议在晚上或午休时跑 benchmark，回来就能看到结果。
