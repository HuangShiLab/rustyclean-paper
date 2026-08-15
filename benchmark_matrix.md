# RustyClean benchmark matrix: datasets × tools × parameters

This table summarises every dataset / configuration combination that is intended for the manuscript, and whether it has been run.

Legend:
- ✅ **Done** — results exist on HPC and are ready for analysis/figures.
- 🔄 **Running** — submitted and currently executing on HPC.
- 📋 **Ready** — script exists, waiting for HPC quota or another dependency.
- ❌ **Not done** — no results and no script yet.

---

## 1. Simulated human datasets (single-end)

| Dataset | Host % | Tool / mode | Key parameters | Status | Result location |
|---------|--------|-------------|----------------|--------|-----------------|
| 5M_1pct_low_even_SE | 1 | RustyClean kraken2 | T2T-only DB, `--skip-qc`, 8 threads | ❌ Not done | — |
| 5M_1pct_low_even_SE | 1 | RustyClean bowtie2 | T2T+HLA index, `--skip-qc`, 8 threads | ❌ Not done | — |
| 5M_1pct_low_even_SE | 1 | RustyClean auto | T2T-only + T2T+HLA, `--skip-qc --auto-survey`, 8 threads | ❌ Not done | — |
| 5M_1pct_low_even_SE | 1 | Hostile | `--aligner bowtie2`, T2T+HLA, 8 threads | ✅ Done | `results_v2/metrics/performance_hostile.csv` |
| 5M_1pct_low_even_SE | 1 | KneadData | hg_39 DB, 8 threads | ✅ Done | `results_v2/metrics/performance.csv` |
| 5M_1pct_low_even_SE | 1 | Centrifuge | human_t2t_hla_cf, 8 threads | ✅ Done | `results_v2/metrics/performance_centrifuge.csv` |
| 5M_1pct_low_even_SE | 1 | fast2bRAD-M | 16 enzymes | ✅ Done | `results_v2/metrics/performance_fast2brad.csv` |
| 10M_10pct_med_even_SE | 10 | RustyClean kraken2 | T2T-only DB, `--skip-qc`, 8 threads | ❌ Not done | — |
| 10M_10pct_med_even_SE | 10 | RustyClean bowtie2 | T2T+HLA index, `--skip-qc`, 8 threads | ❌ Not done | — |
| 10M_10pct_med_even_SE | 10 | RustyClean auto | T2T-only + T2T+HLA, `--skip-qc --auto-survey`, 8 threads | ❌ Not done | — |
| 10M_10pct_med_even_SE | 10 | Hostile | `--aligner bowtie2`, T2T+HLA, 8 threads | ✅ Done | `results_v2/metrics/performance_hostile.csv` |
| 10M_10pct_med_even_SE | 10 | KneadData | hg_39 DB, 8 threads | ✅ Done | `results_v2/metrics/performance.csv` |
| 10M_10pct_med_even_SE | 10 | Centrifuge | human_t2t_hla_cf, 8 threads | ✅ Done | `results_v2/metrics/performance_centrifuge.csv` |
| 10M_10pct_med_even_SE | 10 | fast2bRAD-M | 16 enzymes | ✅ Done | `results_v2/metrics/performance_fast2brad.csv` |
| 30M_50pct_high_skewed_SE | 50 | RustyClean auto | T2T-only + T2T+HLA, `--skip-qc --auto-survey`, 8 threads | ✅ Done | `t2t_only_matched_panel/metrics/performance.csv` |
| 30M_50pct_high_skewed_SE | 50 | Hostile | `--aligner bowtie2`, T2T+HLA, 8 threads | ✅ Done | `t2t_only_matched_panel/metrics/performance.csv` |
| 30M_50pct_high_skewed_SE | 50 | KneadData | hg_39 DB, 8 threads | ✅ Done | `t2t_only_matched_panel/metrics/performance.csv` |
| 60M_90pct_high_lognormal_SE | 90 | RustyClean auto | T2T-only + T2T+HLA, `--skip-qc --auto-survey`, 8 threads | ✅ Done | `t2t_only_matched_panel/metrics/performance.csv` |
| 60M_90pct_high_lognormal_SE | 90 | Hostile | `--aligner bowtie2`, T2T+HLA, 8 threads | ✅ Done | `t2t_only_matched_panel/metrics/performance.csv` |
| 60M_90pct_high_lognormal_SE | 90 | KneadData | hg_39 DB, 8 threads | ✅ Done | `t2t_only_matched_panel/metrics/performance.csv` |

---

## 2. Large matched panel (single-end, T2T-only)

| Dataset | Host % | Tool / mode | Key parameters | Status | Result location |
|---------|--------|-------------|----------------|--------|-----------------|
| 100M_50pct_high_lognormal_SE | 50 | RustyClean auto | T2T-only + T2T+HLA, `--skip-qc --auto-survey`, 8 threads | ✅ Done | `t2t_only_matched_panel/metrics/performance.csv` |
| 100M_50pct_high_lognormal_SE | 50 | Hostile | `--aligner bowtie2`, T2T+HLA, 8 threads | ✅ Done | `t2t_only_matched_panel/metrics/performance.csv` |
| 100M_50pct_high_lognormal_SE | 50 | KneadData | hg_39 DB, 8 threads | ✅ Done | `t2t_only_matched_panel/metrics/performance.csv` |
| 100M_90pct_high_lognormal_SE | 90 | RustyClean auto | T2T-only + T2T+HLA, `--skip-qc --auto-survey`, 8 threads | 🔄 Running | `t2t_only_matched_panel/metrics/performance.csv` |
| 100M_90pct_high_lognormal_SE | 90 | Hostile | `--aligner bowtie2`, T2T+HLA, 8 threads | 🔄 Running | `t2t_only_matched_panel/metrics/performance.csv` |
| 100M_90pct_high_lognormal_SE | 90 | KneadData | hg_39 DB, 8 threads | 🔄 Running | `t2t_only_matched_panel/metrics/performance.csv` |

---

## 3. Extended decision-region panel (single-end, T2T-only)

| Dataset | Host % | Tool / mode | Key parameters | Status | Result location |
|---------|--------|-------------|----------------|--------|-----------------|
| 5M_1pct_low_even_SE | 1 | RustyClean auto | T2T-only + T2T+HLA, `--skip-qc --auto-survey`, 8 threads | 🔄 Running | `t2t_only_extended_panel/metrics/performance.csv` |
| 5M_1pct_low_even_SE | 1 | Hostile | `--aligner bowtie2`, T2T+HLA, 8 threads | 🔄 Running | `t2t_only_extended_panel/metrics/performance.csv` |
| 5M_1pct_low_even_SE | 1 | KneadData | hg_39 DB, 8 threads | 🔄 Running | `t2t_only_extended_panel/metrics/performance.csv` |
| 10M_10pct_med_even_SE | 10 | RustyClean auto | T2T-only + T2T+HLA, `--skip-qc --auto-survey`, 8 threads | 🔄 Running | `t2t_only_extended_panel/metrics/performance.csv` |
| 10M_10pct_med_even_SE | 10 | Hostile | `--aligner bowtie2`, T2T+HLA, 8 threads | 🔄 Running | `t2t_only_extended_panel/metrics/performance.csv` |
| 10M_10pct_med_even_SE | 10 | KneadData | hg_39 DB, 8 threads | 🔄 Running | `t2t_only_extended_panel/metrics/performance.csv` |
| 10M_30pct_med_lognormal_SE | 30 | RustyClean auto | T2T-only + T2T+HLA, `--skip-qc --auto-survey`, 8 threads | 🔄 Running | `t2t_only_extended_panel/metrics/performance.csv` |
| 10M_30pct_med_lognormal_SE | 30 | Hostile | `--aligner bowtie2`, T2T+HLA, 8 threads | 🔄 Running | `t2t_only_extended_panel/metrics/performance.csv` |
| 10M_30pct_med_lognormal_SE | 30 | KneadData | hg_39 DB, 8 threads | 🔄 Running | `t2t_only_extended_panel/metrics/performance.csv` |

---

## 4. Paired-end panel (T2T-only)

| Dataset | Host % | Tool / mode | Key parameters | Status | Result location |
|---------|--------|-------------|----------------|--------|-----------------|
| 20M_10pct_med_even_PE | 10 | RustyClean auto | T2T-only + T2T+HLA, `--skip-qc --auto-survey`, 8 threads | 🔄 Running | `t2t_only_pe_panel/metrics/performance.csv` |
| 20M_10pct_med_even_PE | 10 | Hostile | `--aligner bowtie2`, T2T+HLA, PE, 8 threads | 🔄 Running | `t2t_only_pe_panel/metrics/performance.csv` |
| 20M_10pct_med_even_PE | 10 | KneadData | hg_39 DB, PE, 8 threads | 🔄 Running | `t2t_only_pe_panel/metrics/performance.csv` |
| 20M_50pct_med_lognormal_PE | 50 | RustyClean auto | T2T-only + T2T+HLA, `--skip-qc --auto-survey`, 8 threads | 🔄 Running | `t2t_only_pe_panel/metrics/performance.csv` |
| 20M_50pct_med_lognormal_PE | 50 | Hostile | `--aligner bowtie2`, T2T+HLA, PE, 8 threads | 🔄 Running | `t2t_only_pe_panel/metrics/performance.csv` |
| 20M_50pct_med_lognormal_PE | 50 | KneadData | hg_39 DB, PE, 8 threads | 🔄 Running | `t2t_only_pe_panel/metrics/performance.csv` |
| 20M_90pct_med_lognormal_PE | 90 | RustyClean auto | T2T-only + T2T+HLA, `--skip-qc --auto-survey`, 8 threads | 🔄 Running | `t2t_only_pe_panel/metrics/performance.csv` |
| 20M_90pct_med_lognormal_PE | 90 | Hostile | `--aligner bowtie2`, T2T+HLA, PE, 8 threads | 🔄 Running | `t2t_only_pe_panel/metrics/performance.csv` |
| 20M_90pct_med_lognormal_PE | 90 | KneadData | hg_39 DB, PE, 8 threads | 🔄 Running | `t2t_only_pe_panel/metrics/performance.csv` |

---

## 5. AUTO mode decision boundary

| Dataset | Host % | Tool / mode | Key parameters | Status | Result location |
|---------|--------|-------------|----------------|--------|-----------------|
| 10M_0pct_med_lognormal_SE | 0 | RustyClean bowtie2 | T2T+HLA, `--skip-qc`, 8 threads | ✅ Done | `auto_decision_boundary/metrics/performance.csv` |
| 10M_0pct_med_lognormal_SE | 0 | RustyClean kraken2 | T2T-only, `--skip-qc`, 8 threads | ✅ Done | `auto_decision_boundary/metrics/performance.csv` |
| 10M_1pct_med_lognormal_SE | 1 | RustyClean bowtie2 | T2T+HLA, `--skip-qc`, 8 threads | ✅ Done | `auto_decision_boundary/metrics/performance.csv` |
| 10M_1pct_med_lognormal_SE | 1 | RustyClean kraken2 | T2T-only, `--skip-qc`, 8 threads | ✅ Done | `auto_decision_boundary/metrics/performance.csv` |
| 10M_5pct_med_lognormal_SE | 5 | RustyClean bowtie2 | T2T+HLA, `--skip-qc`, 8 threads | ✅ Done | `auto_decision_boundary/metrics/performance.csv` |
| 10M_5pct_med_lognormal_SE | 5 | RustyClean kraken2 | T2T-only, `--skip-qc`, 8 threads | ✅ Done | `auto_decision_boundary/metrics/performance.csv` |
| 10M_10pct_med_even_SE | 10 | RustyClean bowtie2 | T2T+HLA, `--skip-qc`, 8 threads | ✅ Done | `auto_decision_boundary/metrics/performance.csv` |
| 10M_10pct_med_even_SE | 10 | RustyClean kraken2 | T2T-only, `--skip-qc`, 8 threads | ✅ Done | `auto_decision_boundary/metrics/performance.csv` |
| 10M_30pct_med_lognormal_SE | 30 | RustyClean bowtie2 | T2T+HLA, `--skip-qc`, 8 threads | ✅ Done | `auto_decision_boundary/metrics/performance.csv` |
| 10M_30pct_med_lognormal_SE | 30 | RustyClean kraken2 | T2T-only, `--skip-qc`, 8 threads | ✅ Done | `auto_decision_boundary/metrics/performance.csv` |
| 10M_100pct_med_lognormal_SE | 100 | RustyClean bowtie2 | T2T+HLA, `--skip-qc`, 8 threads | ✅ Done | `auto_decision_boundary/metrics/performance.csv` |
| 10M_100pct_med_lognormal_SE | 100 | RustyClean kraken2 | T2T-only, `--skip-qc`, 8 threads | ✅ Done | `auto_decision_boundary/metrics/performance.csv` |

---

## 6. Backend comparison (uniform T2T/GRCh38 index)

| Dataset | Host % | Tool / mode | Key parameters | Status | Result location |
|---------|--------|-------------|----------------|--------|-----------------|
| 5M_1pct_low_even_SE | 1 | RustyClean bowtie2 | T2T+HLA, `--skip-qc` | ✅ Accuracy done | `results_rc_mm_bt_cf_v4/accuracy_rc_mm_bt_cf_v4.csv` |
| 5M_1pct_low_even_SE | 1 | RustyClean minimap2 | T2T+HLA `.mmi`, `--skip-qc` | ✅ Accuracy done | `results_rc_mm_bt_cf_v4/accuracy_rc_mm_bt_cf_v4.csv` |
| 5M_1pct_low_even_SE | 1 | RustyClean centrifuge | human_t2t_hla_cf, `--skip-qc` | ✅ Accuracy done | `results_rc_mm_bt_cf_v4/accuracy_rc_mm_bt_cf_v4.csv` |
| 10M_10pct_med_even_SE | 10 | RustyClean bowtie2 / minimap2 / centrifuge | as above | ✅ Accuracy done | `results_rc_mm_bt_cf_v4/accuracy_rc_mm_bt_cf_v4.csv` |
| 30M_50pct_high_skewed_SE | 50 | RustyClean bowtie2 / minimap2 / centrifuge | as above | ✅ Accuracy done | `results_rc_mm_bt_cf_v4/accuracy_rc_mm_bt_cf_v4.csv` |
| 60M_90pct_high_lognormal_SE | 90 | RustyClean bowtie2 / minimap2 / centrifuge | as above | ✅ Accuracy done | `results_rc_mm_bt_cf_v4/accuracy_rc_mm_bt_cf_v4.csv` |
| Above | — | Runtime / memory for bowtie2/minimap2/centrifuge | 8 threads | 🔄 Running | `backend_runtime_v2/metrics/performance.csv` |

---

## 7. Cross-species host removal

| Dataset | Host | Tool / mode | Key parameters | Status | Result location |
|---------|------|-------------|----------------|--------|-----------------|
| human_10M_50pct_med_even_SE | human | RustyClean bowtie2 | species-specific index, `--skip-qc` | 🔄 Running | `cross_species_results/metrics/performance.csv` |
| mouse_10M_50pct_med_even_SE | mouse | RustyClean bowtie2 | species-specific index, `--skip-qc` | 🔄 Running | `cross_species_results/metrics/performance.csv` |
| rat_10M_50pct_med_even_SE | rat | RustyClean bowtie2 | species-specific index, `--skip-qc` | 🔄 Running | `cross_species_results/metrics/performance.csv` |
| pig_10M_50pct_med_even_SE | pig | RustyClean bowtie2 | species-specific index, `--skip-qc` | 🔄 Running | `cross_species_results/metrics/performance.csv` |
| monkey_10M_50pct_med_even_SE | monkey | RustyClean bowtie2 | species-specific index, `--skip-qc` | 🔄 Running | `cross_species_results/metrics/performance.csv` |
| rice_10M_50pct_med_even_SE | rice | RustyClean bowtie2 | species-specific index, `--skip-qc` | 🔄 Running | `cross_species_results/metrics/performance.csv` |
| All above | — | KneadData | species-specific index | 🔄 Running | `cross_species_results/metrics/performance.csv` |

*Datasets exist at `data/cross_species_v2/`. Need benchmark scripts and runs.*

---

## 8. Real-data validation

| Sample type | Source | Tool / mode | Key parameters | Status | Result location |
|-------------|--------|-------------|----------------|--------|-----------------|
| Oral saliva | SRR39545334 | RustyClean auto | T2T-only + T2T+HLA, 8 threads | 🔄 Running | `real_data_results/metrics/performance.csv` |
| Vaginal swab | ERR17406228 | RustyClean auto | T2T-only + T2T+HLA, 8 threads | 🔄 Running | `real_data_results/metrics/performance.csv` |
| Breast-cancer stool | SRR34833940 | RustyClean auto | T2T-only + T2T+HLA, 8 threads | 🔄 Running | `real_data_results/metrics/performance.csv` |
| All above | — | KneadData | hg_39, 8 threads | 🔄 Running | `real_data_results/metrics/performance.csv` |
| All above | — | Downstream: MEGAHIT assembly + Bracken profiling + diversity | — | 📋 Ready | `run_post_processing.sh` depends on real-data job |

---

## 9. Parallel scalability / memory-aware worker cap

| Test | Tool / mode | Key parameters | Status | Result location |
|------|-------------|----------------|--------|-----------------|
| 4 samples in parallel (5M/1%, 10M/10%, 30M/50%, 60M/90%) | RustyClean auto vs KneadData | default worker count | ✅ Done | `results_v2/metrics/performance_parallel_v8.csv` |
| Memory-aware worker cap validation | RustyClean kraken2 / auto | new binary, default workers on 64 GB node | 📋 Ready to test | — |

---

## 10. sylph + Bowtie2 backend

| Dataset | Host % | Tool / mode | Key parameters | Status | Result location |
|---------|--------|-------------|----------------|--------|-----------------|
| 5M_1pct_low_even_SE | 1 | RustyClean sylph | T2T sylph DB + Hostile T2T+HLA bowtie2 index, `--skip-qc`, 8 threads | ✅ Done | `results_sylph_standard/metrics/` |
| 10M_10pct_med_even_SE | 10 | RustyClean sylph | T2T sylph DB + Hostile T2T+HLA bowtie2 index, `--skip-qc`, 8 threads | ✅ Done | `results_sylph_standard/metrics/` |
| 30M_50pct_high_skewed_SE | 50 | RustyClean sylph | T2T sylph DB + Hostile T2T+HLA bowtie2 index, `--skip-qc`, 8 threads | ✅ Done | `results_sylph_standard/metrics/` |
| 60M_90pct_high_lognormal_SE | 90 | RustyClean sylph | T2T sylph DB + Hostile T2T+HLA bowtie2 index, `--skip-qc`, 8 threads | ✅ Done | `results_sylph_standard/metrics/` |

*sylph 0.9.x is used as a sample-level prefilter; host-positive samples are passed to Bowtie2 for read-level removal. Host-negative samples skip Bowtie2 entirely.*

**Summary (3 reps per dataset):**

| Dataset | Runtime (mean ± SD) | Memory (mean ± SD) | F1 (mean) |
|---------|---------------------|--------------------|-----------|
| 5M_1pct_low_even_SE | 41.4 ± 8.8 s | ~3.08 GB | 1.0000 |
| 10M_10pct_med_even_SE | 73.4 ± 3.6 s | ~3.55 GB | 0.9971 |
| 30M_50pct_high_skewed_SE | 277.1 ± 10.1 s | ~3.64 GB | 0.9996 |
| 60M_90pct_high_lognormal_SE | 654.7 ± 25.7 s | ~3.66 GB | 0.9959 |

---

## Summary counts

| Status | Count |
|--------|-------|
| ✅ Done | ~46 entries |
| 🔄 Running | ~44 entries |
| 📋 Ready (script exists) | ~4 entries |
| ❌ Not done | ~4 entries (QC mode comparison, some legacy mixed-host RustyClean modes) |

---

## Recommended next actions

1. Wait for all running jobs to complete (t2t matched panel, extended panel, PE panel, backend runtime, cross-species, real data).
2. Post-processing job (3907605) will run automatically after real-data and cross-species finish, producing integrated results.
3. Once integrated results are available, update manuscript figures/tables and regenerate docx.
4. Optionally add QC-mode vs skip-qc-mode comparison for 1–2 representative datasets.
