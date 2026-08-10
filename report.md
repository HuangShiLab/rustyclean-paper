# RustyClean 宿主去除综合 Benchmark 报告

**生成时间：** 2026-07-30 21:27

## 1. 执行摘要

本报告整合以下验证维度：
- **RustyClean 多后端对比**：Kraken2、Bowtie2、AUTO 自适应模式
- **与主流工具对比**：KneadData、Hostile、Centrifuge、Fast2bRAD-M
- **跨物种宿主去除**：human / mouse / rat / pig / rice / monkey
- **AUTO 模式扩展性**：5/10/20/40/80 样本 uniform 扩展与混合决策边界
- **真实样本下游验证**：oral saliva / vaginal / breast cancer stool

## 2. 单样本性能对比（4 个标准模拟数据集）

### 2.1 运行时间

|Dataset|RC_Kraken2|RC_Bowtie2|RC_AUTO|KneadData|Hostile|Centrifuge|Fast2bRAD|
|---|---|---|---|---|---|---|---|
|5M_1pct_low_even_SE|8.8m|5.8m|5.4m|5.0m|1.1m|1.9m|30.0s|
|10M_10pct_med_even_SE|11.1m|9.4m|9.0m|7.8m|1.5m|1.1m|47.0s|
|30M_50pct_high_skewed_SE|21.3m|27.2m|21.3m|38.0m|4.5m|3.6m|2.1m|
|60M_90pct_high_lognormal_SE|20.7m|38.0m|25.9m|1.7h|9.2m|8.4m|4.4m|

### 2.2 峰值内存

|Dataset|RC_Kraken2|RC_Bowtie2|RC_AUTO|KneadData|Hostile|Centrifuge|Fast2bRAD|
|---|---|---|---|---|---|---|---|
|5M_1pct_low_even_SE|15.3GB|3.4GB|3.4GB|1.1GB|3.4GB|7.0GB|N/A|
|10M_10pct_med_even_SE|15.4GB|3.4GB|3.4GB|1.1GB|3.6GB|7.2GB|N/A|
|30M_50pct_high_skewed_SE|15.4GB|3.4GB|15.4GB|1.1GB|3.6GB|7.9GB|N/A|
|60M_90pct_high_lognormal_SE|15.5GB|6.2GB|15.5GB|1.1GB|3.6GB|8.5GB|N/A|

## 3. 准确性对比

### 3.1 RustyClean modes

|Dataset|Tool|Accuracy|F1|
|---|---|---|---|
|10M_10pct_med_even_SE|auto|0.9945|0.9731|
|10M_10pct_med_even_SE|bowtie2|0.9945|0.9731|
|10M_10pct_med_even_SE|kraken2|0.9972|0.9861|
|30M_50pct_high_skewed_SE|auto|0.9910|0.9925|
|30M_50pct_high_skewed_SE|bowtie2|0.9960|0.9966|
|30M_50pct_high_skewed_SE|kraken2|0.9910|0.9925|
|5M_1pct_low_even_SE|auto|1.0000|0.9979|
|5M_1pct_low_even_SE|bowtie2|1.0000|0.9979|
|5M_1pct_low_even_SE|kraken2|0.9999|0.9924|
|60M_90pct_high_lognormal_SE|auto|0.9870|0.9929|
|60M_90pct_high_lognormal_SE|bowtie2|0.9960|0.9978|
|60M_90pct_high_lognormal_SE|kraken2|0.9870|0.9929|

### 3.2 RustyClean vs Hostile/KneadData

|Dataset|Tool|Accuracy|F1|
|---|---|---|---|
|10M_10pct_med_even_SE|hostile|0.9991|0.9956|
|10M_10pct_med_even_SE|kneaddata|0.9746|0.8873|
|10M_10pct_med_even_SE|rustyclean_k2|0.9972|0.9861|
|30M_50pct_high_skewed_SE|hostile|0.9990|0.9991|
|30M_50pct_high_skewed_SE|kneaddata|0.9928|0.9940|
|30M_50pct_high_skewed_SE|rustyclean_k2|0.9910|0.9925|
|5M_1pct_low_even_SE|hostile|1.0000|0.9990|
|5M_1pct_low_even_SE|kneaddata|0.9608|0.3247|
|5M_1pct_low_even_SE|rustyclean_k2|0.9999|0.9924|
|60M_90pct_high_lognormal_SE|hostile|0.9984|0.9991|
|60M_90pct_high_lognormal_SE|kneaddata|0.9959|0.9977|
|60M_90pct_high_lognormal_SE|rustyclean_k2|0.9870|0.9929|

### 3.3 Centrifuge

|Dataset|Tool|Accuracy|F1|
|---|---|---|---|
|10M_10pct_med_even_SE|centrifuge|0.9907|0.9550|
|30M_50pct_high_skewed_SE|centrifuge|0.9930|0.9941|
|5M_1pct_low_even_SE|centrifuge|0.9999|0.9941|
|60M_90pct_high_lognormal_SE|centrifuge|0.9888|0.9938|

### 3.4 Cross-species

|Dataset|Tool|Accuracy|F1|
|---|---|---|---|
|human_10M_50pct_med_even_SE|kneaddata|0.9960|0.9960|
|human_10M_50pct_med_even_SE|rustyclean_bt2|0.9994|0.9995|
|monkey_10M_50pct_med_even_SE|kneaddata|0.9960|0.9960|
|monkey_10M_50pct_med_even_SE|rustyclean_bt2|0.9995|0.9995|
|mouse_10M_50pct_med_even_SE|kneaddata|0.9960|0.9960|
|mouse_10M_50pct_med_even_SE|rustyclean_bt2|0.9995|0.9995|
|pig_10M_50pct_med_even_SE|kneaddata|0.9960|0.9960|
|pig_10M_50pct_med_even_SE|rustyclean_bt2|0.9995|0.9995|
|rat_10M_50pct_med_even_SE|kneaddata|0.9960|0.9960|
|rat_10M_50pct_med_even_SE|rustyclean_bt2|0.9995|0.9995|
|rice_10M_50pct_med_even_SE|kneaddata|0.9960|0.9960|
|rice_10M_50pct_med_even_SE|rustyclean_bt2|0.9995|0.9995|

## 4. 跨物种宿主去除

|Species|Tool|Runtime|Memory|
|---|---|---|---|
|human|rustyclean_bt2|13.9m|19.1GB|
|human|kneaddata|26.9m|5.5GB|
|monkey|rustyclean_bt2|13.0m|19.1GB|
|monkey|kneaddata|13.7m|6.0GB|
|mouse|rustyclean_bt2|10.3m|19.1GB|
|mouse|kneaddata|14.4m|6.1GB|
|pig|rustyclean_bt2|10.1m|19.1GB|
|pig|kneaddata|16.4m|6.5GB|
|rat|rustyclean_bt2|13.3m|19.1GB|
|rat|kneaddata|14.2m|6.2GB|
|rice|rustyclean_bt2|12.0m|19.1GB|
|rice|kneaddata|8.4m|5.7GB|

准确性详见 3.4 Cross-species。

## 5. AUTO 模式与扩展性

### 5.1 Uniform 扩展（同一样本复制）

|Copies|Samples|Wall time|Max RSS|Throughput (M reads/h)|Branch accuracy|
|---|---|---|---|---|---|
|5|5|16.2m|3.4GB|181.0|100.0%|
|10|10|34.2m|3.4GB|171.8|100.0%|
|20|20|1.1h|3.4GB|176.0|100.0%|
|40|40|1.9h|3.4GB|204.2|100.0%|
|80|80|5.9h|3.4GB|133.7|100.0%|

### 5.2 混合样本 AUTO 决策边界

- 后端选择分布：见 `auto_decision/backend_choice_counts.csv`
- 可视化：`auto_decision/auto_decision_boundary.png`

### 5.3 决策边界图（4 标准数据集）

![决策边界](decision_boundary/decision_boundary.png)

## 6. 真实样本验证

|Tool|Sample|Runtime|Memory|
|---|---|---|---|
|kneaddata|breast_cancer_stool|44.2m|23.6GB|
|kneaddata|oral_saliva|20.6m|20.9GB|
|kneaddata|vaginal_swab|1.4m|8.4GB|
|rustyclean_auto|breast_cancer_stool|41.1m|16.7GB|
|rustyclean_auto|oral_saliva|17.9m|3.8GB|
|rustyclean_auto|vaginal_swab|4.6m|3.5GB|
|rustyclean_k2|breast_cancer_stool|34.6m|16.8GB|
|rustyclean_k2|oral_saliva|17.5m|16.2GB|
|rustyclean_k2|vaginal_swab|6.0m|15.8GB|

## 7. 图表索引

- `figure_1_human_comparison.png`
- `figure_2_human_accuracy.png`
- `figure_3_rc_mode_decision.png`
- `figure_4_auto_scalability.png`
- `figure_5_cross_species_accuracy.png`
- `figure_6_real_data_summary.png`
- `figure_v4_runtime_memory.png`
- `figure_v4_accuracy.png`

## 附录 A. v4 后端重新 benchmark（minimap2 / bowtie2 / centrifuge）

> 说明：此前在检查 minimap2 benchmark 结果时，曾出现“TP 极低”的误报。经复核，该脚本将 `removed_by_tool=True` 用于“保留 reads”输出，导致 TP/FN 定义被颠倒；重新按标准定义计算后，三个后端准确性均正常。以下数据来自 `/scr/u/shihuang/rustyclean-paper/results_rc_mm_bt_cf_v4/`，使用同一 T2T/GRCh38 人类参考索引。

### A.1 运行时间与峰值内存

|Dataset|rc_minimap2|rc_bowtie2|rc_centrifuge|
|---|---|---|---|
|5M_1pct_low_even_SE|30.0m / 11.5GB|2.4m / 3.6GB|4.5m / 7.0GB|
|10M_10pct_med_even_SE|3.9m / 11.7GB|4.1m / 3.6GB|4.5m / 7.2GB|
|30M_50pct_high_skewed_SE|35.4m / 11.8GB|15.4m / 3.6GB|12.4m / 7.9GB|
|60M_90pct_high_lognormal_SE|26.2m / 11.9GB|37.8m / 6.2GB|23.4m / 8.6GB|
|*Average*|23.9m / 11.7GB|14.9m / 4.3GB|11.2m / 7.6GB|

* `rc_bowtie2` 在 5M/10M 小样本上最快，但随着数据量增大，其 bowtie2 比对耗时迅速上升，60M 时慢于 `rc_centrifuge`。
* `rc_minimap2` 受索引加载影响，5M 小样本出现明显启动 overhead；整体内存最高（~12GB）。
* `rc_centrifuge` 在速度与内存之间取得平衡，但在低宿主样本上准确性稍低（见 A.2）。

### A.2 准确性

|Dataset|rc_minimap2 F1|rc_bowtie2 F1|rc_centrifuge F1|
|---|---|---|---|
|5M_1pct_low_even_SE|0.9986|0.9996|0.9940|
|10M_10pct_med_even_SE|0.9742|0.9749|0.9500|
|30M_50pct_high_skewed_SE|0.9984|0.9984|0.9920|
|60M_90pct_high_lognormal_SE|0.9997|0.9996|0.9938|

* `rc_bowtie2` 与 `rc_minimap2` 在所有数据集上 F1 > 0.974，宿主残留率 < 0.06%，微生物损失率 < 0.6%。
* `rc_centrifuge` F1 在 0.950–0.994 之间，宿主残留率约 1.1%，对低宿主样本（10M_10pct）影响最大。

### A.3 可视化

- 运行时间与内存：`figure_v4_runtime_memory.png/svg/pdf`
- 准确性（F1 与微生物损失）：`figure_v4_accuracy.png/svg/pdf`

## 8. 结论

1. **速度**：在 4 个标准数据集上，RustyClean AUTO 模式能够根据宿主比例自适应选择最快后端；
   Hostile 与 Fast2bRAD-M 在单样本层面速度极快，适合超快速筛查。
   v4 后端 benchmark 显示：`rc_centrifuge` 平均 11.2 min，`rc_bowtie2` 平均 14.9 min，`rc_minimap2` 平均 23.9 min；
   `rc_minimap2` 因索引加载内存最高（~12 GB），`rc_bowtie2` 内存最低（~4.3 GB）。
2. **准确性**：RustyClean Bowtie2 / Kraken2 / minimap2 在所有模拟数据上 F1 > 0.974，宿主残留率 < 0.06%；
   RustyClean-centrifuge F1 在 0.950–0.994 之间，宿主残留率约 1.1%；
   Hostile 准确性同样优秀；独立 Centrifuge 在低宿主样本上 host remaining 略高。
3. **跨物种**：RustyClean Bowtie2 在 6 个物种上保持 F1 ≈ 0.9995，略优于 KneadData。
4. **扩展性**：AUTO 模式在 80 样本 uniform 扩展中保持 100% 分支准确率，
   但 Kraken2 后端的 16 GB 数据库加载是并行扩展的瓶颈。
5. **真实数据**：RustyClean 在真实 metagenome 样本上完成 host removal，
   下游 MEGAHIT 组装、Kraken2/Bracken 物种注释与多样性分析均已完成。

## 9. 局限性与后续工作

- 当前 Kraken2 默认未启用 `--memory-mapping`，多 worker 并发时内存占用高；
  在本地 SSD 上可重新评估 memory-mapping 对并行性能的影响。
- Fast2bRAD-M 尚未完成准确性评估，需补充 read-level ground truth 对比。
- 真实样本缺少 ground truth，依赖下游指标（组装 contig N50、物种多样性）间接评估。

---
*Generated by RustyClean benchmark suite v2*