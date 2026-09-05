# 并行化对比实验

**问题**:同样给 16 个核,RustyClean 把它们变成吞吐量的效率,是否高于 KneadData 和 Hostile?

这是**吞吐量**实验,不是准确性实验。准确性由 enhanced panel 回答,那套数据刻意让深度、
复杂度、宿主比例同时变化;而吞吐量实验恰恰**不能**这样——每个样品的成本必须大致相等,
批处理总时长才反映调度效率,而不是反映"哪个大样品落到了哪个 worker"。

## 数据

120 个 fastq.gz,单端,每个 **1,000,000 条序列**,151 bp(InSilicoSeq `novaseq` 模型)。

| 宿主比例 | 重复 | 宿主序列 | 微生物序列 |
|---:|---:|---:|---:|
| 1 % | 20 | 10,000 | 990,000 |
| 5 % | 20 | 50,000 | 950,000 |
| 10 % | 20 | 100,000 | 900,000 |
| 50 % | 20 | 500,000 | 500,000 |
| 70 % | 20 | 700,000 | 300,000 |
| 90 % | 20 | 900,000 | 100,000 |

宿主序列模拟自 **GRCh38.p14**,而去宿主比对的是 **T2T-CHM13v2.0**——两者不同是有意为之,
这样去宿主面对的是真实的组装差异,而不是与自己来源相同的序列。微生物群落取自 GTDB r202,
每个重复 30 个基因组,**每个重复的群落各不相同**(种子为重复编号),所以同一宿主比例下的
20 个样品是 20 个不同的宏基因组,而不是同一个群落抽 20 次。

约 12 GB(压缩后),外加约 400 MB 的 ground-truth 标签。

### 为什么一个重复只跑两次 ISS

每个 array task 负责一个重复的全部六个宿主比例,只调用 **两次** InSilicoSeq——一次微生物、
一次宿主——然后从中切出**互不重叠**的片段。六次单独调用会把 3.1 Gbp 的人类基因组重复载入
六遍而毫无收益;切片的方式既只付一次载入代价,又保证任何一条序列不会出现在两个样品里。

## 五个测试臂

| 臂 | QC | 并行方式 |
|---|---|---|
| `kneaddata` | trimmomatic | `xargs -P W`,每样品一个进程 |
| `rustyclean_batch` | fastp | **单进程**,`--workers W` |
| `rustyclean_xargs` | fastp | `xargs -P W`,每样品一个进程 |
| `hostile` | 无 | `xargs -P W`,每样品一个进程 |
| `rustyclean_batch_skipqc` | 无 | **单进程**,`--workers W` |

`rustyclean_xargs` 是让结论站得住的关键对照。少了它,RustyClean 的任何优势都可能只是
"它的比对封装更快",而不是"它的调度更好";`batch` 对 `xargs` 固定了工具、只改变谁来调度。

QC 也是配对的:`kneaddata` 和两个 RustyClean batch/xargs 臂都做质控,`hostile` 和
`rustyclean_batch_skipqc` 都不做。跨组比较没有意义。

## 网格

每个 array task 拿 16 核,按 W × T = 16 划分:

| task | W(并发样品) | T(每样品线程) |
|---:|---:|---:|
| 0 | 1 | 16 |
| 1 | 2 | 8 |
| 2 | 4 | 4 |
| 3 | 8 | 2 |
| 4 | 16 | 1 |

测试作业用 `--exclusive` 独占节点。这不是优化,是前提:五个 array task 在同一时刻各自计时,
而这个分区的节点足够宽,可能把它们塞在一台机器上——那样整轮跑下来测的就是彼此的争用。
去掉它排队会更快,但测出来的数没有意义。

**同一个 W 下的五个臂跑在同一个节点上**,所以跨工具比较——也就是要回答的问题——不跨硬件。
W 之间会跨节点,这正是要固定 W × T、并且每个臂的加速比只跟**自己**的 W=1 比、
绝不跟别的工具比的原因。

## 一个必须写进报告的事实

1,000,000 条序列低于 RustyClean 的 `auto_reads_threshold`(20M),所以
`choose_auto_backend()` 对**全部六个宿主比例**都返回 bowtie2——包括 90 %。
这里是刻意如此:五个臂于是都在对同一类索引做比对,测的是并行效率而不是"选了哪个后端"。
survey 仍然照跑、照样花时间,这部分开销会如实记录。

## 内存怎么测

`/usr/bin/time` 报告的是进程树里**最大单个进程**的峰值 RSS,这在并发实验里是错的量:
要问的是"同时跑 W 个需要多少内存"。所以这里改为采样作业自己的 cgroup,取
`memory.stat` 的 `anon` 峰值——整个作业所有进程的匿名(不可回收)内存总和。

`memory.current` 同时记录,因为那是 `sacct` 报的数;本集群上它还把可回收的 page cache
算了进去,大致等于读过的 FASTQ 体积,并不是内存需求。这与报告里已有的内存口径结论一致。

## 输出是否随并发改变

每个臂、每个 W 跑完后都记录每样品的**保留序列数**。对确定性工具,这个数不应随 worker 数
变化。这是并发 bug 唯一会露头的地方:批处理时间会好看得毫无异样,而输出已经不一样了。
`rustyclean_batch` 与 `rustyclean_xargs` 更必须逐样品完全一致。

分析脚本里,这项不通过的优先级高于任何时间数字。设 `PARALLEL_DIGEST=1` 可进一步比对
read-id 集合本身(更强,但慢很多)。

## 运行

```bash
bash scripts/run_parallel_scaling.sh --dry-run
```

```bash
bash scripts/run_parallel_scaling.sh
```

两个阶段,共 25 个 array task(20 生成 + 5 测试),在本集群 `MaxSubmitJobPerUser=50`
之内,可以和常规 panel 并存。

**投入 24 小时之前,先用几分钟验证接线:**

```bash
PARALLEL_DRY_RUN=1 bash scripts/main/benchmark_parallel_scaling.sh
```

```bash
PARALLEL_LIMIT=6 sbatch --array=2 scripts/main/benchmark_parallel_scaling.sh
```

后者是真正重要的那一步:它用 6 个样品把五个臂全跑一遍,证明每个工具确实把输出写在了
指纹步骤去找的位置——这一点没有别的办法能验证。

分析:

```bash
python3 scripts/main/analyze_parallel_scaling.py
```

## 改参数

`scripts/hpc/config.sh` 里的 `PARALLEL_*`。注意 `--array` 是 SLURM 在任何 shell 之前
按字面解析的,跟不了变量:改 `PARALLEL_N_REPS` 必须同时改
`generate_parallel_data.sh` 的 `#SBATCH --array`。

`PARALLEL_ARMS` 可以只跑其中几个臂。

## 文件

| 文件 | 说明 |
|---|---|
| `generate_parallel_data.sh` | 20 个 array task,生成 120 个样品 + 标签 + 清单 |
| `benchmark_parallel_scaling.sh` | 5 个 array task,每个是曲线上的一个 W |
| `analyze_parallel_scaling.py` | 加速比、并行效率、头对头比较、输出不变性检查 |
| `../run_parallel_scaling.sh` | 按依赖顺序提交两个阶段 |
