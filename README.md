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

- **Runtime scope**: On the six-dataset simulated panel, Deacon/AUTO used 16
  threads whereas KneadData and fastp + Hostile used 8 threads; KneadData also
  performed extra trimming, repeat masking and identifier reformatting. The
  panel is therefore a workflow-scope comparison, not a controlled speed
  benchmark. AUTO took 90--2,397 s versus 420--8,271 s for KneadData.
- **Controlled paired runtime**: In the same-node 16-thread 100M/90%
  validation, optimized RustyClean took 428 ± 76 s versus 1,032 ± 37 s for
  fastp + Hostile and was faster in all three replicates (2.12--3.01×).
- **Observational optimized panel**: With fastp compression 1, node-local
  scratch and a Deacon server, all-replicate speedups versus historical Hostile
  runs were 1.99--6.36×. These runs are unpaired except at 100M/90%; warm-
  server values are reported separately and are not mixed into the headline
  range.
- **Batch parallelization**: In one unreplicated 24-library benchmark,
  RustyClean reached 7.30× speedup from 1 to 8 workers, Hostile+fastp reached
  3.77×, and RustyClean was 1.89× faster at eight workers.
- **Memory**: AUTO peaked at 4.54 GiB for the largest measured process. The
  sample-level benchmark kept per-process RSS approximately flat, while
  aggregate sampled RSS increased with active workers; this is not unique
  physical-memory accounting.
- **Accuracy**: On the four high-host datasets, AUTO had F1 ≥ 0.998, lost at
  most 0.310% of true microbial reads, and retained at most 0.0000105% of true
  host input (at most nine host reads). Deacon alone retained
  0.0035--0.0037% of true host input before verification.
- **Adaptive strategy**: AUTO runs fastp, Deacon Tier-1 depletion, then Bowtie2
  verification only when Deacon reports that at least 30% of reads were
  removed. The 0.3 cutoff is an empirical default, not a threshold sweep
  optimum.
- **Cross-host use**: The default human panhuman-1 index is unsuitable for the
  tested non-human datasets. Species-matched indexes for human (T2T), monkey,
  mouse, pig, rat and rice are a six-host proof of concept, not a validated
  universal pan-host index.

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
python3 scripts/main/plot_main_figures.py
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

### Profile fastp and Deacon I/O

The standalone fastp profiler compares gzip compression levels and records
wall/CPU time, cgroup I/O, compressed bytes and fastp logical bases:

```bash
REPS=2 THREADS=16 COMPRESSION_LEVELS="1 2 4 6" \
bash scripts/hpc/profile_fastp_io.sh \
  /path/to/reads.fastq.gz runs/fastp_io_profile
```

For paired-end data, set `R2=/path/to/reads_R2.fastq.gz`.

`benchmark_fastp_deacon_io.sh` profiles the actual `fastp -> Deacon` handoff.
It uses node-local scratch through RustyClean's `--work-dir`, disables Bowtie2
verification by default, and reads the new `stage_metrics.json` emitted by
RustyClean:

```bash
sbatch scripts/hpc/benchmark_fastp_deacon_io.sh
```

Override `RUSTYCLEAN`, `DEACON_INDEX`, `HOST_INDEX`, `DATA_DIR`, or
`RESULTS_DIR` for a different cluster. The CSV records stage wall time, GNU
time CPU/RSS, cgroup CPU, Deacon counters, and the unaccounted difference is
therefore easy to inspect from `wall_s - (fastp_ms + deacon_ms + finalize_ms)/1000`.

The RustyClean binary also exposes independent tuning controls:

```bash
rustyclean \
  --work-dir /scratch/job/rustyclean \
  --fastp-threads 8 \
  --fastp-compression 2 \
  --deacon-compression-level 2 \
  --deacon-compression-threads 2
```

Use a low compression level for intermediates on local scratch; keep stronger
compression for archival final output only if downstream I/O or storage makes
that worthwhile.

---

## Figures

Current publication assets live under `figures/`.

| Figure file | Manuscript figure | Content |
|-------------|-------------------|---------|
| `fig1_four_way_runtime_memory.*` | Figure 1 | Four-way runtime and memory comparison |
| `fig2_accuracy_verification.*` | Figure 2 | Accuracy and verification-tier comparison |
| `fig3_cross_species_index.*` | Figure 3 | Species-matched versus human index depletion |
| `fig4_parallel_scaling.*` | Figure 4 | Sample-level throughput and flat per-worker memory |
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
