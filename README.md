# RustyClean Benchmark Paper

This repository contains the benchmark paper materials for **RustyClean**, a high-performance host decontamination pipeline for metagenomic shotgun sequencing data.

The repository provides:

- The manuscript draft (`manuscript/`)
- Publication-ready figures (`figures/`, fig1–fig4 + figS1)
- All scripts for data generation, benchmarking, accuracy analysis, and visualization (`scripts/`)
- Key result metrics and summary tables (`data/`)
- Early exploratory analyses and outdated manuscript versions (`others/`)

> RustyClean is implemented in Rust and combines `fastp` (QC) with `Kraken2`/`Bowtie2` (host depletion). The benchmark demonstrates that RustyClean achieves comparable accuracy to KneadData and Hostile while being one to two orders of magnitude faster.

---

## Key findings

- **Speed**: RustyClean AUTO is ~5–40× faster than KneadData across four standard SE datasets, with the largest gains at high host contamination (≥50%).
- **Memory**: Peak memory is comparable to or lower than KneadData; the default T2T-only Kraken2 index is ~15.5 GB.
- **Accuracy**: On 18 enhanced simulated datasets, the F1-score difference between RustyClean and KneadData is <0.02. In the fair skip-QC comparison against Hostile, the F1 difference is <0.01.
- **Adaptive strategy**: AUTO mode uses a lightweight survey to estimate host fraction. Low-host samples use Kraken2-only; high-host samples automatically enable Bowtie2 recheck, balancing speed and accuracy.
- **Default database**: A human-only Kraken2 index built from T2T-CHM13v2.0; mixed Kraken2 indexes (e.g., kraken16) are available as an optional taxonomy-aware mode.

Detailed results and discussion are in `manuscript/RustyClean_Manuscript_Draft.md`.

---

## Repository structure

```
rustyclean-paper/
├── manuscript/                    # Manuscript draft
│   ├── RustyClean_Manuscript_Draft.md
│   └── RustyClean_Manuscript_Draft.docx
├── figures/                       # Publication-quality figures (fig1–fig4 + figS1)
├── data/                          # Result data and metrics
│   ├── results_100M_matched/      # 100M matched panel (vs Hostile / KneadData)
│   ├── results_100M_skipqc_matched/
│   ├── benchmark_results/         # Fair comparison metrics
│   └── *.csv                      # Aggregated accuracy / performance tables
├── scripts/                       # Code and workflow scripts
│   ├── main/                      # Main pipeline: data generation, benchmark, analysis, figures
│   ├── hpc/                       # SLURM cluster submission scripts
│   ├── benchmark/                 # Scripts for comparison against Hostile / KneadData
│   ├── minimal/                   # Minimal validation workflow
│   └── rustyclean_src/            # Local RustyClean source backup (gitignored)
├── others/                        # Early exploration and auxiliary documents
│   ├── old_manuscripts/           # Previous manuscript versions
│   ├── planning_docs/             # benchmark_plan, competitiveness_analysis, etc.
│   └── tmp_scripts/               # Temporary / deprecated scripts
├── README.md                      # This file
├── AGENTS.md                      # AI agent guide (in Chinese)
└── LICENSE
```

---

## Quick start

### Full rerun from scratch

To rebuild every database and rerun every experiment, see **[RUN_ALL.md](RUN_ALL.md)**:

```bash
bash scripts/run_all.sh --dry-run   # inspect the plan
bash scripts/run_all.sh             # submit it
```

Stages are chained with SLURM dependencies, and all database paths come from
`scripts/hpc/config.sh`. Budget ~500 GB storage, 200 GB RAM for the Kraken2
build, and 60–80 h of compute.

### Minimal validation workflow (recommended first step)

Requirements: ~60 GB storage, ~3 hours, 16 GB RAM.

```bash
# 1. Install the environment (once, ~30 min)
bash scripts/minimal/setup_minimal_env.sh

# 2. Run the minimal benchmark (~2–4 hours)
bash scripts/minimal/run_minimal.sh

# 3. Inspect results
ls scripts/minimal/results/
# ├── metrics/performance.csv
# ├── accuracy.csv
# └── figures/*.png
```

The minimal workflow includes 4 core datasets (10M/30M/60M reads, 10%–90% host contamination, SE and PE).

> To upgrade to the full workflow: `bash scripts/minimal/upgrade_to_standard.sh`

### Full standard workflow

Requirements: ~470 GB storage, ~16 hours, 32 GB RAM.

```bash
# 1. Install the environment
bash scripts/main/setup_env.sh
conda activate rustyclean-benchmark

# 2. Generate enhanced simulated data (18 datasets)
bash scripts/main/generate_enhanced_data.sh

# 3. Run the benchmark (3 replicates)
bash scripts/main/run_benchmark.sh ./data/enhanced ./results

# 4. Downstream analysis (taxonomy / assembly / CheckM2 / diversity)
bash scripts/main/downstream_analysis.sh ./results ./data/enhanced

# 5. Accuracy analysis
python scripts/main/analyze_accuracy.py ./data/enhanced ./results ./data/analysis

# 6. Performance analysis and basic visualizations
python scripts/main/analyze_performance.py ./results ./data/analysis

# 7. Publication-quality figures
python scripts/main/plot_publication_figures_v2.py ./results ./figures

# 8. Generate report
python scripts/main/generate_report.py ./results ./manuscript/report.md
```

### Fair comparisons against Hostile and KneadData

| Comparison | Description | Script |
|-----------|-------------|--------|
| vs Hostile (host removal only) | RustyClean `--skip-qc` vs Hostile, QC excluded | `scripts/benchmark/fair_hostile_skipqc_run_benchmark.sh` |
| vs KneadData (full pipeline) | RustyClean AUTO (with fastp QC) vs KneadData (with Trimmomatic QC) | `scripts/benchmark/run_benchmark.sh` |

Result files:
- `data/benchmark_results/fair_hostile_skipqc_results.csv`
- `data/benchmark_results/auto_vs_kneaddata_metrics.csv`

---

## Figures

| Figure | Content | Files |
|--------|---------|-------|
| fig1 | Simulated data error and contamination profiles | `figures/fig1_error_profile.*` |
| fig2 | Matched-panel comparison against Hostile / KneadData (runtime, memory, F1) | `figures/fig2_matched_panel.*` |
| fig3 | Accuracy across 18 enhanced simulated datasets | `figures/fig3_accuracy.*` |
| fig4 | Relative speedup and memory efficiency | `figures/fig4_speedup.*` |
| figS1 | Backend comparison (Kraken2 / Bowtie2 / minimap2) | `figures/figS1_backend_comparison.*` |

---

## Databases and reference data

The default configuration uses a **T2T-CHM13v2.0 human-only index**:

| Index | Tool | Size | Example path |
|-------|------|------|--------------|
| T2T-only human | Kraken2 | ~15.5 GB | `/lustre1/g/aos_shihuang/databases/rustyclean_human_t2t_only/kraken2/t2t_only` |
| T2T + HLA | Bowtie2 | ~3.3 GB | `/lustre1/g/aos_shihuang/databases/rustyclean_human_t2t_only/bowtie2/t2t_hla` |
| KneadData human | Bowtie2 | ~4.1 GB | `/lustre1/g/aos_shihuang/databases/kneaddata/hg_39` |

Build scripts are provided in `scripts/main/build_kraken2_t2t_only.sh` and related `build_*` scripts.

---

## Environment variables

```bash
export RUSTYCLEAN=rustyclean
export KNEADDATA=kneaddata
export KRAKEN2_DB=/path/to/rustyclean_human_t2t_only/kraken2/t2t_only
export KNEADDATA_DB=/path/to/kneaddata/hg_39
```

---

## Citation

If you use data or code from this repository, please cite the RustyClean benchmark paper (in preparation).

Reference benchmark study:

Gao Y, et al. (2024). [Benchmarking short-read metagenomics tools for removing host contamination](https://doi.org/10.1093/gigascience/giaf004), *GigaScience*, Volume 14, 2025, giaf004.

---

## Authors and license

Benchmark paper repository for the [rustyclean](https://github.com/HuangShiLab/rustyclean) project.

License: MIT
