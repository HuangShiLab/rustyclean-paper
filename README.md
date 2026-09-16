# RustyClean Benchmark Paper

This repository contains the benchmark paper materials for **RustyClean**, a high-performance host decontamination pipeline for metagenomic shotgun sequencing data.

The repository provides:

- The manuscript draft (`manuscript/`)
- Publication-ready figures (`figures/`)
- All scripts for data generation, benchmarking, accuracy analysis, and visualization (`scripts/`)
- Key result metrics and summary tables (`data/`)
- Early exploratory analyses and outdated manuscript versions (`others/`)

> RustyClean is implemented in Rust and combines `fastp` (QC), deacon-based
> minimizer depletion, and conditional Bowtie2 verification. The current
> benchmark focuses on this two-tier design rather than on a fixed
> Kraken2-versus-Bowtie2 comparison.

---

## Key findings

- **Speed**: On the current simulated panel, deacon depletion alone is
  44–130× faster than the complete KneadData pipeline; the complete
  RustyClean AUTO pipeline is 3.7–10× faster than KneadData and 1.3–2.3×
  faster than fastp + Hostile.
- **Memory**: AUTO peaks at 4.8 GB. The deacon workers share a read-only
  memory-mapped index, so per-worker RSS stays flat as sample-level
  concurrency increases.
- **Accuracy**: AUTO keeps host carry-over at 0.0000% of retained output on
  every high-host dataset tested while discarding at most 0.31% of microbial
  reads. Its F1 is at least 0.998 on those samples and is equal to or better
  than KneadData on the panel.
- **Adaptive strategy**: AUTO runs fastp, deacon Tier-1 depletion, then
  Bowtie2 verification only when deacon reports that at least 30% of reads
  were removed.
- **Cross-host use**: The default human panhuman-1 index is not interchangeable
  across species. Species-matched indexes for human (T2T), monkey, mouse, pig,
  rat and rice are evaluated in the manuscript.

Detailed results and discussion are in `manuscript/RustyClean_Manuscript_Draft.md`.

---

## Repository structure

```
rustyclean-paper/
├── RUN_ALL.md                     # Full rerun from scratch — start here
├── scripts/
│   ├── run_all.sh                 # Submits every stage in dependency order
│   ├── hpc/config.sh              # Single source of truth for all database paths
│   ├── main/                      # Index builds, data generation, analysis, figures
│   ├── benchmark/                 # Comparisons against Hostile / KneadData
│   └── minimal/                   # Minimal validation workflow
├── data/                          # Tracked result summaries for the current run
├── figures/                       # Current publication figures
├── manuscript/                    # Manuscript draft and status deck
├── archive/v1/                    # Previous round: results, figures and the
│   │                              # scripts that produced them. Superseded.
│   └── README.md                  # What was run, and why it is superseded
├── others/                        # Early exploration and auxiliary documents
├── README.md                      # This file
├── AGENTS.md                      # Agent guide (in Chinese)
└── LICENSE
```

Large FASTQ and intermediate benchmark trees remain outside Git. The tracked
summaries in `data/deacon_panel/` and `runs/**/metrics/`, together with
`figures/`, reproduce the manuscript assets. The previous round is preserved
under `archive/v1/`; its README explains why it was superseded.

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

### Legacy minimal validation

The standalone minimal workflow is retained from the original project
validation. It is not the 18-dataset panel behind the current manuscript and
should not be mixed with current results.

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

> For the current manuscript workflow, use `scripts/run_all.sh` and follow
> `RUN_ALL.md`.

### Regenerate current publication figures

After updating a CSV under `data/deacon_panel/`, regenerate the deacon figures:

```bash
python3 scripts/main/plot_deacon_figures.py data/deacon_panel figures
```

After editing `manuscript/RustyClean_Manuscript_Draft.md`, regenerate the
distribution DOCX from the repository root so the relative figure paths
resolve:

```bash
pandoc manuscript/RustyClean_Manuscript_Draft.md \
  --from markdown --to docx \
  --resource-path=.:manuscript \
  -o manuscript/RustyClean_Manuscript_Draft.docx
```

### Rerun comparisons against Hostile and KneadData

| Comparison | Description | Script |
|-----------|-------------|--------|
| vs Hostile (host removal only) | RustyClean `--skip-qc` vs Hostile, QC excluded | `scripts/benchmark/fair_hostile_skipqc_run_benchmark.sh` |
| vs KneadData (full pipeline) | RustyClean AUTO (with fastp QC) vs KneadData (with Trimmomatic QC) | `scripts/benchmark/run_benchmark.sh` |

Result files:
- `runs/` metric tables collected by the benchmark scripts;
- `archive/v1/data/` for the superseded comparison outputs referenced by the
  supplementary backend table.

---

## Figures

Current publication assets live under `figures/`.

| Figure file | Manuscript figure | Content |
|-------------|-------------------|---------|
| `fig2_deacon_panel.*` | Figure 1 | Four-way runtime and memory comparison |
| `fig3_deacon_accuracy.*` | Figure 2 | Four-way accuracy comparison |
| `fig5_cross_species.*` | Figure 4 | Species-matched versus human index depletion |
| `fig6_verification.*` | Figure 3 | Deacon-only versus AUTO host carry-over |
| `fig7_parallel_scaling.*` | Figure 5 | Sample-level throughput and flat per-worker memory |
| `figS1_backend_comparison.*` | Figure S1 | Bowtie2, minimap2 and Centrifuge comparison |

---

## Databases and reference data

The active configuration uses a **T2T-CHM13v2.0 human-only Kraken2 index** for
the rerun arms in `RUN_ALL.md`. The manuscript's default Tier-1 arm instead uses
the deacon panhuman-1 index; Bowtie2 verification and the alternative-backend
experiments use the alignment indexes below.

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
export HOST_INDEX=/path/to/rustyclean_human_t2t_only/bowtie2/t2t_only
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
