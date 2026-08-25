# RustyClean Benchmark — HPC 运行指南

本目录包含在 SLURM 集群上大规模运行 RustyClean vs KneadData benchmark 的脚本。

---

## 目录结构

```
hpc/
├── config.sh                 # 统一配置（路径、线程数、数据库）
├── submit_all.sh             # 一键提交所有作业
├── generate_data_slurm.sh    # 生成模拟数据（SLURM array）
├── run_benchmark_slurm.sh    # 运行 benchmark（SLURM array）
├── run_single_benchmark.sh   # 单 dataset × replicate 运行脚本
├── downstream_slurm.sh       # 下游分析（taxonomy / assembly / diversity）
├── analyze_slurm.sh          # 结果分析与可视化
└── README.md                 # 本文件
```

---

## 前置要求

1. **SLURM 集群** 账号和提交权限。
2. **共享存储**（所有计算节点可见），建议 ≥ 500 GB。
3. **Conda 环境** 已安装所有依赖（参考 `scripts/main/setup_env.sh` 或 `scripts/minimal/setup_minimal_env.sh`）。
4. **数据库** 已下载到共享目录：
   - `minikraken2_v1_8GB`（或 `kraken2_standard`）
   - `kneaddata_human_db`
   - `GRCh38.fa.gz`
   - 微生物基因组 `genomes_fasta/*.fasta`
5. **RustyClean** 已编译并加入 `PATH`，或在 conda 环境中可调用。

---

## 快速开始

### 1. 修改配置

编辑 `scripts/hpc/config.sh`，设置你的实际路径：

```bash
export PROJECT_DIR="/scratch/$USER/rustyclean-paper"
export CONDA_BASE="$HOME/miniconda3"
export CONDA_ENV="rustyclean-benchmark"
export KRAKEN2_DB="$PROJECT_DIR/databases/minikraken2_v1_8GB"
export KNEADDATA_DB="$PROJECT_DIR/databases/kneaddata_human_db"
export HUMAN_GENOME="$PROJECT_DIR/databases/GRCh38.fa.gz"
export GENOME_DIR="$PROJECT_DIR/genomes"
export N_THREADS=16
```

### 2. 一键提交

```bash
cd /path/to/rustyclean-paper
bash scripts/hpc/submit_all.sh
```

该脚本会依次提交 4 个依赖作业：

1. **generate_data_slurm.sh**：生成 18 个增强数据集（array job，最多 6 并发）。
2. **run_benchmark_slurm.sh**：每个数据集跑 3 次重复，RustyClean + KneadData（array job，最多 12 并发）。
3. **downstream_slurm.sh**：Taxonomy、Assembly、CheckM2、Diversity。
4. **analyze_slurm.sh**：准确性、性能可视化、投稿级图表、报告。

### 3. 监控作业

```bash
squeue -u $USER
sacct -j <job_id>
```

### 4. 查看结果

```bash
ls $PROJECT_DIR/analysis/figures/
cat $PROJECT_DIR/analysis/report.md
```

---

## 分步提交

如果你不想一键提交，可以手动控制：

```bash
# 1. 生成数据
GEN_JOB=$(sbatch --parsable scripts/hpc/generate_data_slurm.sh)

# 2. 运行 benchmark（依赖数据生成）
BENCH_JOB=$(sbatch --parsable --dependency=afterok:$GEN_JOB scripts/hpc/run_benchmark_slurm.sh)

# 3. 下游分析
DOWN_JOB=$(sbatch --parsable --dependency=afterok:$BENCH_JOB scripts/hpc/downstream_slurm.sh)

# 4. 分析与可视化
sbatch --dependency=afterok:$DOWN_JOB scripts/hpc/analyze_slurm.sh
```

---

## 关键优化

相比本地脚本，HPC 版本做了以下改进：

1. **SLURM array jobs**：每个 dataset / replicate 独立调度，充分利用集群。
2. **节点本地 scratch**：中间 FASTQ 文件在 `$LOCAL_SCRATCH` 生成，减少共享存储 I/O 竞争。
3. **checkpoint/resume**：每个 dataset 生成后写入 `completed.flag`，失败后可单独重跑。
4. **依赖调度**：数据生成 → benchmark → 下游分析 → 图表，自动按顺序执行。
5. **统一配置**：`config.sh` 集中管理路径和参数，避免脚本间不一致。
6. **资源隔离**：每个任务独立 time/memory 记录，便于排查。

---

## 资源估算

| 步骤 | 任务数 | 单任务 CPU | 单任务内存 | 单任务时间 | 总时间（并发） |
|------|--------|-----------|-----------|-----------|---------------|
| 数据生成 | 18 | 8 | 32 GB | ≤ 4 h | ~12 h（6 并发） |
| Benchmark | 54 | 16 | 64 GB | ≤ 24 h | ~2–3 天（12 并发） |
| 下游分析 | 1 | 16 | 128 GB | ≤ 48 h | 2 天 |
| 分析作图 | 1 | 4 | 16 GB | ≤ 2 h | 2 h |

> 实际时间取决于集群负载、I/O 和 KneadData 的运行速度。

---

## 故障排查

### 数据生成失败

检查单个 array task 日志：

```bash
cat rustyclean_generate_<jobid>_<taskid>.err
```

重跑单个 dataset：

```bash
rm -rf $DATA_DIR/<dataset_name>/completed.flag
sbatch --array=<task_id> scripts/hpc/generate_data_slurm.sh
```

### Benchmark 失败

重跑单个 dataset/replicate：

```bash
bash scripts/hpc/run_single_benchmark.sh <dataset_name> <rep>
```

### KneadData 数据库找不到

确认 `KNEADDATA_DB` 目录下有 `*.bt2` 索引文件：

```bash
ls $KNEADDATA_DB/*.bt2
```

### RustyClean 输出为空

检查 RustyClean 命令行参数是否匹配当前版本：

```bash
rustyclean --help
```

---

## 与本地极简方案的关系

- `minimal/`：适合在 Mac Studio / 工作站上快速验证流程。
- `scripts/`：通用脚本，HPC 脚本会调用它们。
- `hpc/`：面向 SLURM 集群的调度和优化封装。

建议先在本地跑通 `minimal/run_minimal.sh`，确认流程无误后再上 HPC 跑完整 benchmark。
