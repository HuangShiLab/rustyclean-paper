# RustyClean 工作汇报 PPT 提纲

> 面向实验室内部汇报 / 审稿答辩。建议总页数 12–15 页，每页突出 1 个核心信息，图表直接取自 `figures/`。

---

## Slide 1. 标题页

- **标题：** RustyClean：自适应宿主污染去除流程
- **副标题：** 基于样本宿主比例动态选择 Kraken2 / Bowtie2 后端，兼顾速度与精度
- **作者：** Yufeng Zhang, Shi Huang 等
- **单位：** Faculty of Dentistry, The University of Hong Kong
- **链接：** https://github.com/HuangShiLab/rustyclean

---

## Slide 2. 研究动机：宿主污染是宏基因组分析的必经之路

- 宿主相关样本中，宿主 DNA 比例差异巨大：
  - 粪便：约 1–2% 人源
  - 唾液、牙菌斑、皮肤、活检：常达 50–90% 人源
- 宿主 reads 浪费测序深度，扭曲下游物种组成、组装和 MAG 结果
- 去宿主是标准前处理步骤，但速度和精度常常不可兼得

**演讲要点：** 先说明“为什么要做”，强调不同样本宿主比例差异大。

---

## Slide 3. 现有工具的两类失败模式

- **比对法（KneadData / Hostile / Bowtie2）：**
  - 优点：假阴性低，宿主残留少
  - 缺点：假阳性高，会误删真实微生物 reads
- **k-mer 分类法（Kraken2 等）：**
  - 优点：速度快，高通量友好
  - 缺点：假阴性高，会保留部分宿主 reads
- 现有流程通常为所有样本固定一种策略，继承其中一种失败模式

**演讲要点：** 引用 Gao et al. 的 benchmark 结论，引出“两类方法互为优缺点”。

---

## Slide 4. RustyClean 核心思想：把去宿主当成路由问题

- **不替用户做一次全局选择**，而是逐个样本决定用哪种后端
- 对高宿主样本：用 Kraken2 快速分类 + Bowtie2 复核
- 对低宿主样本：直接用 Bowtie2 比对
- 通过 10 万 reads 的快速比对 survey 估计宿主比例，再路由

**演讲要点：** 强调“routing not replacement”，这是与现有工具的本质区别。

---

## Slide 5. 流程架构（4 个阶段）

1. **QC：** fastp 去接头、质量修剪、过滤
2. **宿主比例估计：** 10 万 reads 快速 Bowtie2 survey
3. **去宿主：**
   - ĥ < 10% → Bowtie2 比对路径
   - ĥ > 30% 且 reads > 20M → Kraken2 + Bowtie2 复核
4. **校验门：** 输出大小、残留宿主比例自动检查，失败不进入结果目录

**演讲要点：** 突出 checkpoint、bounded concurrency、validation gate 等工程细节。

---

## Slide 6. 模拟数据 Benchmark 设计

- 参考 Gao et al. 设计，覆盖真实场景变量：
  - 宿主比例：0%, 1%, 5%, 10%, 30%, 50%, 70%, 90%, 99%, 100%
  - 样本大小：5M–100M reads
  - 分布：even / skewed / lognormal
  - 测序模式：SE / PE
- 共 18 个增强数据集，每个 3 次重复，带 per-read ground truth

**演讲要点：** 说明测试面板的代表性，避免“只在有利条件上测试”的质疑。

---

## Slide 7. 精度：两种错误方向分开看（Figure 1 / Table 2）

- **微生物误删（false positive，不可逆信号丢失）：**
  - KneadData 平均 2.58%，最高 3.96%
  - RustyClean 平均 0.20%，低 13 倍
- **宿主残留（false negative，可恢复污染）：**
  - KneadData 平均 0.26%
  - RustyClean 平均 0.90%，略高于 KneadData
- F1 差距很小：RustyClean 0.9790 vs KneadData 0.9831

**演讲要点：** 强调“微生物误删”比“宿主残留”对下游影响更严重；RustyClean 更适合 profiling。

---

## Slide 8. 速度与内存：匹配面板对比（Figure 2 / Table 4）

- 4 个 SE 数据集：30M/50%、60M/90%、100M/50%、100M/90%
- RustyClean `--skip-qc` 与 Hostile 头对头比去宿主步骤：
  - 30M/50%：4.5 min vs 5.8 min（1.3×）
  - 60M/90%：8.2 min vs 11.9 min（1.45×）
  - 100M/50%：14.9 min vs 27.8 min（1.86×）
  - 100M/90%：13.4 min vs 22.5 min（1.68×）
- 与 KneadData 相比：6.6–10.7× 更快
- 内存：RustyClean ~15.5 GB（Kraken2 库），Hostile ~3.6 GB，KneadData ~1.1 GB

**演讲要点：** 用对数坐标 runtime 图强调数量级差异；说明内存主要来源于 Kraken2 数据库，可由 `--host-removal-mode bowtie2` 降低。

---

## Slide 9. 加速比汇总（Figure 4）

- RustyClean vs Hostile：1.27–1.87×
- RustyClean vs KneadData：8.35–17.99×
- 优势在 100M 大样本上最显著

**演讲要点：** 这是最容易被记住的一页，放一张图即可。

---

## Slide 10. AUTO 模式路由验证

- 100k reads survey 估计宿主比例：
  - 5M/1%：估计 0.93%（真实 0.95%）→ 走 Bowtie2
  - 10M/10%：估计 10.13%（真实 10.02%）→ 走 Bowtie2
  - 30M/50%：估计 48.95%（真实 59.73%，低估）→ 仍正确走 Kraken2
  - 60M/90%：估计 89.43% → 走 Kraken2
- 路由决策只要求“落在阈值正确一侧”，不要求估计绝对准确

**演讲要点：** 强调 survey 的容错性，解释为什么低估 10% 也没导致错误路由。

---

## Slide 11. Bowtie2 复核的效果

- 在 Kraken2 路径上，默认对保留 reads 再做一次 Bowtie2 复核
- 宿主残留从平均 1.41% 降至 0.07%（19.7 倍）
- 微生物误删从 0.12% 升至 0.40%，仍远低于 KneadData
- 运行时间成本约 6.7%，内存不变

**演讲要点：** 说明复核不是简单 trade-off，而是以很小代价换回大量宿主去除。

---

## Slide 12. 跨物种去宿主（Figure 3b / Table 5）

- 人、猴、小鼠、大鼠、猪、水稻 6 种宿主，50% 宿主比例
- RustyClean F1 ≥ 0.9997（水稻 0.9997）
- KneadData 需要为每种宿主单独建 Bowtie2 index，F1 ≈ 0.996
- 说明自适应策略不局限于人源数据

**演讲要点：** 强调通用性和多宿主场景。

---

## Slide 13. 真实数据表现

- 11 例 LU 队列人口腔微生物组样本（PE，5–45M reads）
- 全部默认 auto 模式成功完成
- 单样本运行时间：9–46 min（中位 13.6 min）
- 峰值内存：3.4–6.5 GB（中位 3.6 GB）
- 11 个样本总 wall-clock：3.4 h

**演讲要点：** 真实数据证明模拟面板的结论可迁移。

---

## Slide 14. 讨论：什么时候用 RustyClean？

- **Profiling 为主、宿主比例变化大：** RustyClean 自适应路由更优
- **对宿主残留极度敏感（如公开数据、隐私场景）：** 可选 `--host-removal-mode bowtie2` 或启用复核
- **内存受限环境：** 强制 Bowtie2 路径，内存 < 4 GB
- **当前局限：** Kraken2 路径内存高于 Hostile；99% 宿主样本 F1 降至 0.980

**演讲要点：** 诚实说出 trade-off 和适用边界，避免被问到时被动。

---

## Slide 15. 结论与可用性

- RustyClean 是单文件 Rust 二进制，集成 QC + 自适应去宿主
- 在速度与精度之间做样本级自适应选择
- 对 Hostile 更快，对 KneadData 更快且精度更高
- 代码与文档：https://github.com/HuangShiLab/rustyclean
- 论文相关数据与图表：https://github.com/HuangShiLab/rustyclean-paper

**演讲要点：** 一句话总结： faster than Hostile, more accurate than KneadData, adaptive per sample。

---

## 附录建议

- **备用页 A：** sylph / Centrifuge / minimap2 后端评估结果（Figure S1）
- **备用页 B：** 18 个数据集完整精度曲线（Figure 3a）
- **备用页 C：** AUTO survey 阈值参数可配置性
- **备用页 D：** 与 KneadData full pipeline（含 QC）的对比（Table 3）

---

## 图表使用清单

| 页 | 推荐图表 | 文件名 |
|---|---|---|
| 7 | 误差剖面 | `figures/fig1_error_profile.png` |
| 8 | 匹配面板 runtime + memory | `figures/fig2_matched_panel.png` |
| 9 | 加速比 | `figures/fig4_speedup.png` |
| 12 | 跨物种 + 精度曲线 | `figures/fig3_accuracy.png` |
| 备用 | 后端比较 | `figures/figS1_backend_comparison.png` |

---

## 演讲时间建议

- 15 分钟汇报：每页 1 分钟，重点讲 Slide 3–5、7–9、12–15
- 25 分钟汇报：加入 Slide 6、10、11 和附录中的方法细节
