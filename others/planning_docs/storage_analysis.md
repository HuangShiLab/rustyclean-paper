# RustyClean Benchmark — 存储空间分析

> 分析时间: 2026-07-17 | 基于 Gao et al. (2024) 论文和我们的 benchmark 方案

---

## 一、Gao et al. (2024) 的数据集规模

### 1. 基础参数

| 参数 | 数值 | 说明 |
|------|------|------|
| 数据集总数 | **1,080 个** | 3大小 × 3比例 × 2宿主 × 2复杂度 × 5重复 |
| 大小档位 | 10 / 30 / 60 **Gbps** | 每个数据集的总碱基量 |
| 宿主比例 | 10% / 50% / 90% | 宿主 vs 微生物 reads |
| 宿主类型 | Human / Rice | 人类 GRCh38, 水稻 GWHBFPX |
| 微生物复杂度 | SinBac / SynCom | 单菌 vs 30种合成群落 |
| 重复 | 5 次 | 每个条件的 5 次独立模拟 |
| 读长模式 | PE150 | 双端 150bp reads |

### 2. 存储需求估算

**关键换算**: 1 Gbps (gigabase pair) 的 PE150 FASTQ 数据，gzip 压缩后约 **0.25 GB**

```
10 Gbps  →  2.5 GB  (约 33M reads)
30 Gbps  →  7.5 GB  (约 100M reads)
60 Gbps  →  15 GB   (约 200M reads)
```

| 项目 | 计算 | 大小 |
|------|------|------|
| 原始模拟数据 (1,080个) | 360×2.5GB + 360×7.5GB + 360×15GB | **1,500 GB** (1.5 TB) |
| 数据库索引 | 人类 Bowtie2 (3GB) + 水稻 (1GB) + Kraken2 (100GB) + KrakenUniq (50GB) + KMCP (30GB) | **194 GB** |
| 清洁后输出数据 | 原始数据 × 1.5 (两种工具输出 + 中间) | **2,250 GB** (2.2 TB) |
| 下游分析 (组装/MAG/分类) | 原始数据 × 2 (组装扩展 3-10x) | **3,000 GB** (2.9 TB) |
| **总计** | | **~7 TB** |

> ⚠️ **7 TB** 是服务器级存储！普通工作站或笔记本电脑很难直接重复。

---

## 二、我们的 RustyClean Benchmark 方案

### 1. 基础数据集（4个）— 约 50 GB

| 数据集 | Reads | 压缩后大小 | 说明 |
|--------|-------|-----------|------|
| 10M_10pct | 10M | ~0.75 GB | 低污染小数据 |
| 30M_50pct | 30M | ~2.25 GB | 中等污染 |
| 60M_90pct | 60M | ~4.5 GB | 高污染大数据 |
| 20M_PE_50pct | 20M | ~1.5 GB | 配对端测试 |
| **原始数据小计** | | **~9 GB** | |

### 2. 增强数据集（18个）— 约 200 GB

| 数据集 | Reads | 压缩后大小 |
|--------|-------|-----------|
| 5M_1pct / 5M_5pct | 5M × 2 | ~2.25 GB |
| 10M 系列 (1pct, 5pct, 10pct, 30pct, 0pct, 100pct) | 10M × 6 | ~4.5 GB |
| 20M 系列 (PE: 10pct, 50pct, 90pct) | 20M × 3 | ~4.5 GB |
| 30M 系列 (50pct, 70pct, 90pct) | 30M × 3 | ~6.75 GB |
| 60M 系列 (90pct, 99pct) | 60M × 2 | ~9 GB |
| 100M 系列 (50pct, 90pct) | 100M × 2 | ~15 GB |
| **原始数据小计** | | **~42 GB** |

### 3. 完整存储预算（增强方案 + 下游分析）

| 项目 | 大小 | 说明 |
|------|------|------|
| **原始模拟数据** | ~42 GB | 18个增强数据集 |
| **工具输出** | ~250 GB | 3次重复 × 2工具 × 1.5x中间文件 |
| **数据库** | 65 GB | 详见下方 |
| 　MiniKraken2 v1 | 8 GB | 快速测试 |
| 　Kraken2 Standard | 50 GB | 最终报告（可选） |
| 　KneadData Human Bowtie2 | 3 GB | 去宿主 |
| 　GRCh38 人类基因组 | 3 GB | 模拟数据宿主来源 |
| 　30种微生物基因组 | 1 GB | 模拟数据微生物来源 |
| **下游分析** | ~100 GB | 组装、分类、多样性、MAG |
| 　Taxonomy (Kraken2/Bracken) | ~30 GB | 分类报告 |
| 　Assembly (MEGAHIT) | ~40 GB | 组装 contigs |
| 　CheckM2 | ~10 GB | MAG 质量评估 |
| 　Diversity/PCoA | ~5 GB | 多样性分析 |
| 　其他中间文件 | ~15 GB | |
| **准确性分析** | ~15 GB | Ground truth 标签、比对 |
| **总计** | **~470 GB** | **(约 0.5 TB)** |

---

## 三、三种方案对比

| 方案 | 数据集 | 数据库 | 下游分析 | 总存储 | 适用场景 |
|------|--------|--------|---------|--------|---------|
| **极简** | 4个基础 (9 GB) | MiniKraken2 (8 GB) | 无 | **~60 GB** | 快速验证，只用真实数据 |
| **标准** | 18个增强 (42 GB) | MiniKraken2 (8 GB) | 有 | **~470 GB** | 完整 benchmark |
| **完整** | 18增强 + 3真实 (~60 GB) | Standard DB (50 GB) | 有 | **~600 GB** | 投稿级报告 |
| **Gao参考** | 1,080个 (1.5 TB) | 全套 (~200 GB) | 有 | **~7 TB** | 服务器集群 |

---

## 四、存储优化建议

如果你的存储空间有限，可以按以下策略优化：

### 1. 存储 < 100 GB — 极简方案

```bash
# 只生成 4 个基础数据集
bash scripts/generate_simulated_data.sh

# 使用 MiniKraken2 (8GB)
export KRAKEN2_DB=$HOME/benchmark_env/databases/minikraken2_v1_8GB

# 只跑 benchmark，不做下游分析
bash scripts/run_benchmark.sh
python scripts/analyze_accuracy.py ./data/simulated ./results
python scripts/analyze_performance.py ./results
```

**预期存储**: 60-80 GB

### 2. 存储 100-500 GB — 标准方案

```bash
# 生成 18 个增强数据集（但跳过最大的 100M 系列）
# 修改 generate_enhanced_data.sh 中注释掉 100M 系列
bash scripts/generate_enhanced_data.sh

# 使用 MiniKraken2
# 跑 benchmark + 下游分析
bash scripts/run_benchmark.sh
bash scripts/downstream_analysis.sh ./results
```

**预期存储**: 200-400 GB

### 3. 存储 500 GB-1 TB — 完整方案

```bash
# 全量 18 个数据集 + 3 个真实样本 + Standard DB + 下游分析
bash scripts/generate_enhanced_data.sh
bash scripts/run_benchmark.sh
bash scripts/downstream_analysis.sh ./results
```

**预期存储**: 500-700 GB

---

## 五、关键发现

### Gao et al. 为什么需要 7 TB？

1. **1,080 个数据集** — 这是一个非常大规模的系统性比较，不是单一工具的评价
2. **60 Gbps 大数据集** — 每个数据集 15 GB，是常规 metagenome 的上限规模
3. **6 个工具对比** — 每个工具需要独立的索引和输出
4. **全套下游分析** — 组装、MAG binning、GTDBtk、dRep、HUMAnN3、eggNOG

### 我们的方案为什么只需要 ~500 GB？

1. **仅 18 个数据集** — 聚焦 RustyClean vs KneadData，不需要对比 6 个工具
2. **最大 100M reads (~30 Gbps)** — 足够证明扩展性，不需要 60 Gbps
3. **两个工具对比** — 不需要 KMCP、KrakenUniq、BWA 的额外索引
4. **精简下游分析** — 只评估物种组成、多样性、组装质量，不做完整 MAG pipeline

---

## 六、Gao et al. 数据是否可下载？

论文中提到：
> "All simulated data were generated using CAMISIM..."

这意味着他们的数据是**用 CAMISIM 现场生成的**，不是提供预下载的数据集。因此，如果你想重复他们的分析，需要：
1. 安装 CAMISIM
2. 下载所有参考基因组（人类、水稻、30+ 微生物）
3. 运行 CAMISIM 生成 1,080 个数据集（需要数天计算时间）

但好消息是：
- **他们的 GitHub 提供了生成脚本** — 可以按他们的参数生成一致的数据
- **GitHub 仓库**: `https://github.com/YunyunGao374/HostPurge`
- **脚本**: `HostPurge-SoftwareComparison/1HostDecontaminationSoftwareComparison.sh`

---

## 七、总结

| 问题 | 答案 |
|------|------|
| Gao et al. 数据集多大？ | **1,080 个数据集，总计约 1.5 TB 原始数据，完整分析需 7 TB** |
| 我们的方案需要多少？ | **极简 60 GB / 标准 470 GB / 完整 600 GB** |
| 他们能提供数据下载吗？ | **不能直接下载，但提供 CAMISIM 生成脚本** |
| 普通笔记本能跑吗？ | **可以跑极简或标准方案，外接 1TB 移动硬盘即可** |
| 需要服务器吗？ | **完整方案建议工作站/服务器，至少 32GB 内存 + 500GB 存储** |

> 💡 **建议**: 如果你的存储有限，先用**极简方案**（60 GB）验证流程，确认速度优势后，再在服务器上跑**标准方案**生成完整数据用于论文。
