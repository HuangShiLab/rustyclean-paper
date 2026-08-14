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
| 30M_50pct_high_skewed_SE | 50 | RustyClean auto | T2T-only + T2T+HLA, `--skip-qc --auto-survey`, 8 threads | 🔄 Running | `t2t_only_matched_panel/metrics/performance.csv` |
| 30M_50pct_high_skewed_SE | 50 | Hostile | `--aligner bowtie2`, T2T+HLA, 8 threads | 🔄 Running | `t2t_only_matched_panel/metrics/performance.csv` |
| 30M_50pct_high_skewed_SE | 50 | KneadData | hg_39 DB, 8 threads | 🔄 Running | `t2t_only_matched_panel/metrics/performance.csv` |
| 60M_90pct_high_lognormal_SE | 90 | RustyClean auto | T2T-only + T2T+HLA, `--skip-qc --auto-survey`, 8 threads | 🔄 Running | `t2t_only_matched_panel/metrics/performance.csv` |
| 60M_90pct_high_lognormal_SE | 90 | Hostile | `--aligner bowtie2`, T2T+HLA, 8 threads | 🔄 Running | `t2t_only_matched_panel/metrics/performance.csv` |
| 60M_90pct_high_lognormal_SE | 90 | KneadData | hg_39 DB, 8 threads | 🔄 Running | `t2t_only_matched_panel/metrics/performance.csv` |

---

## 2. Large matched panel (single-end, T2T-only)

| Dataset | Host % | Tool / mode | Key parameters | Status | Result location |
|---------|--------|-------------|----------------|--------|-----------------|
| 100M_50pct_high_lognormal_SE | 50 | RustyClean auto | T2T-only + T2T+HLA, `--skip-qc --auto-survey`, 8 threads | 🔄 Running | `t2t_only_matched_panel/metrics/performance.csv` |
| 100M_50pct_high_lognormal_SE | 50 | Hostile | `--aligner bowtie2`, T2T+HLA, 8 threads | 🔄 Running | `t2t_only_matched_panel/metrics/performance.csv` |
| 100M_50pct_high_lognormal_SE | 50 | KneadData | hg_39 DB, 8 threads | 🔄 Running | `t2t_only_matched_panel/metrics/performance.csv` |
| 100M_90pct_high_lognormal_SE | 90 | RustyClean auto | T2T-only + T2T+HLA, `--skip-qc --auto-survey`, 8 threads | 🔄 Running | `t2t_only_matched_panel/metrics/performance.csv` |
| 100M_90pct_high_lognormal_SE | 90 | Hostile | `--aligner bowtie2`, T2T+HLA, 8 threads | 🔄 Running | `t2t_only_matched_panel/metrics/performance.csv` |
| 100M_90pct_high_lognormal_SE | 90 | KneadData | hg_39 DB, 8 threads | 🔄 Running | `t2t_only_matched_panel/metrics/performance.csv` |

---

## 3. Extended decision-region panel (single-end, T2T-only)

| Dataset | Host % | Tool / mode | Key parameters | Status | Result location |
|---------|--------|-------------|----------------|--------|-----------------|
| 5M_1pct_low_even_SE | 1 | RustyClean auto | T2T-only + T2T+HLA, `--skip-qc --auto-survey`, 8 threads | 📋 Ready | `t2t_only_extended_panel/` (script ready) |
| 5M_1pct_low_even_SE | 1 | Hostile | `--aligner bowtie2`, T2T+HLA, 8 threads | 📋 Ready | `t2t_only_extended_panel/` (script ready) |
| 5M_1pct_low_even_SE | 1 | KneadData | hg_39 DB, 8 threads | 📋 Ready | `t2t_only_extended_panel/` (script ready) |
| 10M_10pct_med_even_SE | 10 | RustyClean auto | T2T-only + T2T+HLA, `--skip-qc --auto-survey`, 8 threads | 📋 Ready | `t2t_only_extended_panel/` (script ready) |
| 10M_10pct_med_even_SE | 10 | Hostile | `--aligner bowtie2`, T2T+HLA, 8 threads | 📋 Ready | `t2t_only_extended_panel/` (script ready) |
| 10M_10pct_med_even_SE | 10 | KneadData | hg_39 DB, 8 threads | 📋 Ready | `t2t_only_extended_panel/` (script ready) |
| 10M_30pct_med_lognormal_SE | 30 | RustyClean auto | T2T-only + T2T+HLA, `--skip-qc --auto-survey`, 8 threads | 📋 Ready | `t2t_only_extended_panel/` (script ready) |
| 10M_30pct_med_lognormal_SE | 30 | Hostile | `--aligner bowtie2`, T2T+HLA, 8 threads | 📋 Ready | `t2t_only_extended_panel/` (script ready) |
| 10M_30pct_med_lognormal_SE | 30 | KneadData | hg_39 DB, 8 threads | 📋 Ready | `t2t_only_extended_panel/` (script ready) |

---

## 4. Paired-end panel (T2T-only)

| Dataset | Host % | Tool / mode | Key parameters | Status | Result location |
|---------|--------|-------------|----------------|--------|-----------------|
| 20M_10pct_med_even_PE | 10 | RustyClean auto | T2T-only + T2T+HLA, `--skip-qc --auto-survey`, 8 threads | 📋 Ready | `t2t_only_pe_panel/` (script ready) |
| 20M_10pct_med_even_PE | 10 | Hostile | `--aligner bowtie2`, T2T+HLA, PE, 8 threads | 📋 Ready | `t2t_only_pe_panel/` (script ready) |
| 20M_10pct_med_even_PE | 10 | KneadData | hg_39 DB, PE, 8 threads | 📋 Ready | `t2t_only_pe_panel/` (script ready) |
| 20M_50pct_med_lognormal_PE | 50 | RustyClean auto | T2T-only + T2T+HLA, `--skip-qc --auto-survey`, 8 threads | 📋 Ready | `t2t_only_pe_panel/` (script ready) |
| 20M_50pct_med_lognormal_PE | 50 | Hostile | `--aligner bowtie2`, T2T+HLA, PE, 8 threads | 📋 Ready | `t2t_only_pe_panel/` (script ready) |
| 20M_50pct_med_lognormal_PE | 50 | KneadData | hg_39 DB, PE, 8 threads | 📋 Ready | `t2t_only_pe_panel/` (script ready) |
| 20M_90pct_med_lognormal_PE | 90 | RustyClean auto | T2T-only + T2T+HLA, `--skip-qc --auto-survey`, 8 threads | 📋 Ready | `t2t_only_pe_panel/` (script ready) |
| 20M_90pct_med_lognormal_PE | 90 | Hostile | `--aligner bowtie2`, T2T+HLA, PE, 8 threads | 📋 Ready | `t2t_only_pe_panel/` (script ready) |
| 20M_90pct_med_lognormal_PE | 90 | KneadData | hg_39 DB, PE, 8 threads | 📋 Ready | `t2t_only_pe_panel/` (script ready) |

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
| Above | — | Runtime / memory for bowtie2/minimap2/centrifuge | 8 threads | ⚠️ Partial | `results_rc_mm_bt_cf_v4/performance_rc_mm_bt_cf_v4_corrected.csv` has runtime="unknown" (macOS time); needs re-run on HPC for reliable runtime/memory |

---

## 7. Cross-species host removal

| Dataset | Host | Tool / mode | Key parameters | Status | Result location |
|---------|------|-------------|----------------|--------|-----------------|
| human_10M_50pct_med_even_SE | human | RustyClean bowtie2 | species-specific index, `--skip-qc` | ❌ Not done | — |
| mouse_10M_50pct_med_even_SE | mouse | RustyClean bowtie2 | species-specific index, `--skip-qc` | ❌ Not done | — |
| rat_10M_50pct_med_even_SE | rat | RustyClean bowtie2 | species-specific index, `--skip-qc` | ❌ Not done | — |
| pig_10M_50pct_med_even_SE | pig | RustyClean bowtie2 | species-specific index, `--skip-qc` | ❌ Not done | — |
| monkey_10M_50pct_med_even_SE | monkey | RustyClean bowtie2 | species-specific index, `--skip-qc` | ❌ Not done | — |
| rice_10M_50pct_med_even_SE | rice | RustyClean bowtie2 | species-specific index, `--skip-qc` | ❌ Not done | — |
| All above | — | KneadData | species-specific index | ❌ Not done | — |

*Datasets exist at `data/cross_species_v2/`. Need benchmark scripts and runs.*

---

## 8. Real-data validation

| Sample type | Source | Tool / mode | Key parameters | Status | Result location |
|-------------|--------|-------------|----------------|--------|-----------------|
| Oral saliva | SRR39545334 | RustyClean auto | T2T-only + T2T+HLA, 8 threads | ❌ Not done | `real_data/oral_saliva_prefetch/` has raw data only |
| Vaginal swab | ERR17406228 | RustyClean auto | T2T-only + T2T+HLA, 8 threads | ❌ Not done | `real_data/vaginal_swab_prefetch/` has raw data only |
| Breast-cancer stool | SRR34833940 | RustyClean auto | T2T-only + T2T+HLA, 8 threads | ❌ Not done | `real_data/breast_cancer_stool_prefetch/` has raw data only |
| All above | — | KneadData | hg_39, 8 threads | ❌ Not done | — |
| All above | — | Downstream: MEGAHIT assembly + Bracken profiling + diversity | — | ❌ Not done | — |

---

## 9. Parallel scalability / memory-aware worker cap

| Test | Tool / mode | Key parameters | Status | Result location |
|------|-------------|----------------|--------|-----------------|
| 4 samples in parallel (5M/1%, 10M/10%, 30M/50%, 60M/90%) | RustyClean auto vs KneadData | default worker count | ✅ Done | `results_v2/metrics/performance_parallel_v8.csv` |
| Memory-aware worker cap validation | RustyClean kraken2 / auto | new binary, default workers on 64 GB node | 📋 Ready to test | — |

---

## Summary counts

| Status | Count |
|--------|-------|
| ✅ Done | ~40 entries |
| 🔄 Running | 6 entries (T2T-only large matched panel) |
| 📋 Ready (script exists) | ~24 entries |
| ❌ Not done | ~25 entries (cross-species, real data, some low-host T2T-only, QC mode) |
| ⚠️ Partial | 1 entry (backend runtime/memory needs HPC re-run) |

---

## Recommended next actions

1. Wait for `t2t_only_matched_panel` job (3906475) to finish, then run unified accuracy analysis (`run_accuracy_t2t_only_panels.sh`).
2. Submit `t2t_only_extended_panel.sh` and `t2t_only_pe_panel.sh` to fill low-host / 30% / PE gaps.
3. Re-run backend comparison (bowtie2/minimap2/centrifuge) on HPC with GNU time for reliable runtime/memory.
4. Create and run cross-species benchmark scripts for human/mouse/rat/pig/rice/monkey.
5. Process real-data samples with RustyClean auto and KneadData, then run MEGAHIT + Bracken + diversity analysis.
