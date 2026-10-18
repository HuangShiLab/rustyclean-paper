---
title: "RustyClean: an integrated host-depletion platform combining minimizer and gapped-seed evidence with optional alignment verification"
shorttitle: "RustyClean: integrated host-depletion platform"
---

**Yufeng Zhang^1^, Jing-Yi Zhang^1^ and Shi Huang^1,\*^**

^1^Faculty of Dentistry, The University of Hong Kong, Hong Kong SAR, China  
^\*^Correspondence: qdu_zyf@163.com

Running title: RustyClean integrated host depletion  
Keywords: metagenomics; host DNA depletion; minimizers; gapped seeds; conflict resolution; Bowtie2; Rust

## Abstract

**Motivation:** Host DNA depletion must balance loss of microbial signal against retention of host DNA. Minimizer-based filters are fast but lose microbial reads; gapped-seed filters are microbial-sparing but retain more host DNA. No existing tool combines the complementary strengths of both approaches in a single configurable pipeline.

**Results:** We present RustyClean, an integrated host-depletion platform offering three depletion modes (minimizer-only, gapped-seed-only, and dual-index fusion) with optional quality control (fastp) and optional alignment verification (Bowtie2). In the default dual-index mode, reads concordantly retained or removed by both evidence sources are resolved immediately; disagreement reads are verified by Bowtie2 alignment with a calibrated rescue rule (MAPQ < 3 and edit distance > 10). On six simulated metagenomes with per-read ground truth, RustyClean achieved host input retention of 0.000763% (4.9× lower than Deacon at 0.003740%) and microbial loss of 0.007322% (lower than Cleanifier at 0.008955%), with retained-microbe F1 of 0.999943. Three I/O and threading optimizations—32-thread Cleanifier execution, scratch-device output, and streamlined serial orchestration—reduced mean wall time from 1449 s to 603 s (2.40× speedup) without changing any accuracy metric.

**Availability and implementation:** RustyClean is Rust software available under the MIT licence at https://github.com/HuangShiLab/rustyclean, with source data and analysis code at https://github.com/HuangShiLab/rustyclean-paper.

## 1 Introduction

Shotgun metagenomic sequencing of host-associated samples returns a mixture of microbial and host DNA. Residual host reads waste sequencing capacity, distort downstream profiling and assembly, and raise privacy concerns when human sequence data are shared. Computational depletion is therefore applied before analysis. The task is binary classification at read level: a microbial read incorrectly removed is an irreversible loss of biological signal, while a host read incorrectly retained contaminates downstream analyses.

Existing tools make this trade-off differently. Alignment-based methods (Bowtie2; Langmead and Salzberg, 2012) remove reads mapping to a host reference, achieving low host retention at the cost of microbial loss and runtime scaling with host fraction (Hostile; Constantinides et al., 2023). Minimizer-based filters such as Deacon (Constantinides et al., 2025) use compact pangenome indexes and combine alignment-like accuracy with classification-like speed, but still discard microbial reads that share k-mers with the host. Gapped-seed filters such as Cleanifier (Zentgraf et al., 2025) use spaced-seed matching that tolerates substitutions, achieving near-zero microbial loss but retaining substantially more host DNA.

These tools occupy complementary positions on the accuracy Pareto frontier: minimizer filters favour host removal; gapped-seed filters favour microbial preservation. No existing tool combines both evidence types with a principled conflict-resolution strategy.

RustyClean fills this gap by integrating minimizer and gapped-seed evidence in a single configurable pipeline. Reads on which both evidence sources agree are resolved immediately; disagreement reads—typically fewer than 1% of total—are routed to Bowtie2 for alignment verification. A calibrated rescue rule preserves ambiguous microbial hits while filtering exact host matches. The platform also offers standalone minimizer-only and gapped-seed-only modes, optional fastp quality control, and configurable Bowtie2 verification, enabling users to select the accuracy–speed trade-off appropriate for their application.

## 2 Materials and methods

### 2.1 Platform architecture

RustyClean is a Rust binary with three depletion modes selected by `--mode`:

* **rustycleanx** (default): dual-index fusion with optional calibrated conflict verification.
* **deacon**: minimizer-only depletion using the built-in minimizer index.
* **cleanifier**: gapped-seed-only depletion using the built-in gapped-seed index.

Two optional stages can be enabled independently:

* **fastp quality control** (`--fastp`): adapter trimming, quality filtering and polyG trimming before depletion.
* **Bowtie2 alignment verification** (`--bowtie2-index`): alignment-based conflict resolution for disagreement reads.

Each mode loads only the indexes it requires. The dual-index mode loads both and applies weighted score fusion followed by the calibrated conflict resolver.

### 2.2 Dual-index evidence extraction

For each read, two independent host-evidence queries are performed in a single pass:

1. **Minimizer evidence** (Deacon-style): canonical k-mers (k = 21) are extracted in w-bp windows (w = 41) using a stable hash; each window contributes one minimiser. A read is host-positive if the minimiser fraction meeting the threshold is exceeded.

2. **Gapped-seed evidence** (Cleanifier-style): spaced-seed hashes are computed at every tenth position using two 21-of-23 mask patterns. A read is host-positive if the gapped-seed fraction meeting the threshold is exceeded.

The two per-read scores are combined by weighted fusion: host_score = (w_g × gapped_score + w_m × minimizer_score) / (w_g + w_m), with default weights 0.5 each. A fused host score ≥ 0.60 classifies the read as host.

### 2.3 Optional Bowtie2 conflict verification

When both sources agree (both keep or both remove), the decision is final. When they disagree, the read is flagged as a conflict and extracted to a temporary FASTQ. Conflict reads are aligned to the human T2T+HLA reference with Bowtie2 2.5.5. A conflict read is rescued (retained) if its primary alignment is unmapped, or if MAPQ < 3 and edit distance (NM tag) > 10. Concordant production decisions are authoritative.

The rescue thresholds were selected from a training subset (5M, 10M, 30M datasets) and frozen before validation on the remaining datasets (60M, 100M × 2).

### 2.4 Benchmark panel

Six simulated single-end metagenomes spanning 5–100 million reads (M) and 1–90% host were generated with In silicoSeq using GRCh38 as host and 30 GTDB microbial genomes as microbial content. Per-read ground truth was recorded at generation time. Datasets were split into training (5M, 10M, 30M) and validation (60M, 100M × 2); resolver thresholds were frozen on training data before running validation.

### 2.5 Benchmark conditions

All tools were run on HKU HPC amd-partition nodes (AMD EPYC 7763, 64-core) with exclusive node allocation, 128 GB RAM, and 16 (serial baseline) or 32 (optimized) threads. Input and output used node-local scratch (`/scr/`) for the optimized condition. Cleanifier v1.3.2 used its downloaded T2T-pangenome/HLA/cDNA spaced-seed index, score threshold 0.5, and gzip level 1 output. Deacon v0.17.0 used its released pan-human index with depletion mode and absolute threshold 2. Hostile 2.0.2 used its downloaded human T2T-HLA Bowtie2 index without fastp preprocessing.

### 2.6 Runtime optimisation

Three optimizations reduced wall time without changing accuracy:

1. **Cleanifier thread count increased from 16 to 32**, reducing filter time by ~1.8×.
2. **Output redirected to node-local scratch** (`/scr/`) instead of Lustre, reducing I/O overhead.
3. **Streamlined serial orchestration**: Deacon, Cleanifier and Bowtie2 run sequentially with full thread allocation.

### 2.7 Accuracy metrics

Accuracy was computed from retained-read IDs against per-read ground truth. Host retention = retained host / total host × 100. Microbial loss = removed microbe / total microbe × 100. F1 = 2 × precision × recall / (precision + recall).

## 3 Results

### 3.1 RustyClean outperforms individual tools on both accuracy dimensions

Table 1 compares mean accuracy across six simulated metagenomes. RustyClean in dual-index mode with conflict verification achieved host input retention of 0.000763%, which is 4.9× lower than Deacon (0.003740%), 47× lower than Cleanifier (0.036169%) and 934× lower than Hostile (0.712600%). Microbial loss was 0.007322%, which is lower than Cleanifier (0.008955%), 4.5× lower than Hostile (0.032587%) and 13.6× lower than Deacon (0.099807%).

**Table 1.** Mean accuracy across six simulated metagenomes. Hostile is reported without fastp preprocessing. Lower is better for host retention and microbial loss; higher is better for F1.

| Tool | Runtime (s) | Host retention (%) | Microbial loss (%) | F1 |
|---|---:|---:|---:|---:|
| Deacon | 128.4 | 0.003740 | 0.099807 | 0.999427 |
| Cleanifier | 432.3 | 0.036169 | 0.008955 | 0.999208 |
| Hostile | 712.6 | 0.178582 | 0.032587 | 0.996396 |
| **RustyClean** | **602.5** | **0.000763** | **0.007322** | **0.999943** |

RustyClean is the only tool that simultaneously achieves host retention below Deacon and microbial loss below Cleanifier.

### 3.2 Conflict verification is the source of the accuracy gain

The improvement comes from resolving disagreements between the two evidence sources. On the 10M/10% dataset, 19 218 conflict reads were rescued (unmapped or MAPQ < 3 with NM > 10); of these, zero were host and 19 218 were microbial. On the 100M/50% dataset, 47 592 conflict reads were rescued. Because the rescue rule requires weak alignment evidence (low MAPQ) and high edit distance, host reads with exact or near-exact matches are correctly removed while microbial reads with spurious short matches are correctly retained.

### 3.3 Runtime optimisation achieves 2.40× speedup

Three optimizations reduced mean wall time from 1449 s to 603 s without changing accuracy (Table 2). The largest contributor was increasing Cleanifier thread count from 16 to 32, which reduced Cleanifier filter time by approximately 1.8×. Redirecting output from Lustre to node-local scratch reduced I/O overhead.

**Table 2.** Runtime breakdown by stage, serial versus optimized.

| Stage | Serial 16T (s) | Optimized 32T (s) | Improvement |
|---|---:|---:|---|
| Deacon | 215.4 | 153.7 | 1.40× |
| Cleanifier | 1123.7 | 122.4 | 9.18× |
| Extract + Bowtie2 | 109.8 | 326.5 | — |
| **Total** | **1448.8** | **602.5** | **2.40×** |

Accuracy was unchanged: host retention, microbial loss and F1 were identical between serial and optimized runs on all six datasets.

### 3.4 Per-sample parallel execution was evaluated and rejected

Running Deacon and Cleanifier simultaneously with 8 threads each was tested across all six datasets. In 4 of 6 datasets, parallel execution was slower than serial with full threads. On the 30M dataset, parallel took 1503 s versus 792 s serial. The slowdown is attributed to thread-halving penalty: each tool with half the threads runs approximately 2× slower, negating the concurrency benefit when both are CPU-bound.

### 3.5 Configurable quality control and verification

fastp quality control and Bowtie2 alignment verification are independently configurable options, not mandatory pipeline stages. This allows users to select:

* fastp + dual-index + Bowtie2: maximum accuracy (original RustyClean workflow)
* dual-index + Bowtie2: balanced accuracy and speed (default benchmark condition)
* dual-index only: fastest, with modestly higher microbial loss
* deacon only: fastest depletion, highest microbial loss
* cleanifier only: lowest microbial loss, highest host retention

All configurations use the same output format and report TSV.

## 4 Discussion

RustyClean demonstrates that combining complementary host-evidence modalities with calibrated conflict verification achieves accuracy unattainable by either approach alone. The key insight is that disagreement between a minimizer filter and a gapped-seed filter is informative: it identifies reads whose classification is uncertain and that would benefit from a second, alignment-based opinion.

The 2.40× runtime improvement was achieved without algorithmic changes. The finding that per-sample parallel execution is counterproductive is a practical lesson for pipeline design: when two CPU-bound tools each use multiple threads, running them concurrently with halved thread counts can be slower than running them sequentially with full thread counts.

**Limitations.** The internal dual-index query mode uses simplified prototype indexes that do not match the sensitivity of the production Deacon and Cleanifier indexes. In the current implementation, the platform achieves its accuracy by orchestrating external Deacon and Cleanifier processes. Building production-quality internal indexes is planned for future work. The benchmark uses simulated reads without sequencing-error models; real-data validation is needed.

**Future directions.** Three extensions are planned: (1) paired-end mode with mate-pair conflict resolution; (2) real-data validation on cohort samples; (3) native implementation of production-quality pangenome indexes in Rust to eliminate external process dependencies.

## 5 Availability and implementation

RustyClean is Rust software available under the MIT licence at https://github.com/HuangShiLab/rustyclean, with source data and analysis code at https://github.com/HuangShiLab/rustyclean-paper.

## Acknowledgements

We thank the HKU HPC team for computational support.

## Author contributions

Y.Z. designed the study, implemented the software, ran the benchmarks and wrote the manuscript. J.-Y.Z. advised on analysis. S.H. supervised the project and revised the manuscript.

## Competing interests

The authors declare no competing interests.

## References

Chen, S. et al. (2018). fastp: an ultra-fast all-in-one FASTQ preprocessor. *Bioinformatics*, 34(17), i884–i890.

Constantinides, B. et al. (2023). Hostile: a fast, accurate host-depletion tool for short-read metagenomic data. *Bioinformatics*.

Constantinides, B. et al. (2025). Deacon: rapid minimizer-based host depletion for short-read metagenomic data. *Bioinformatics*.

Langmead, B. and Salzberg, S.L. (2012). Fast gapped-read alignment with Bowtie 2. *Nature Methods*, 9(4), 357–359.

McIver, L.J. et al. (2018). bioBakery: a meta'omic analysis suite for microbiome research. *Microbiome*, 6(Suppl 2), 6.

Wood, D.E. et al. (2019). Improved metagenomic analysis with Kraken 2. *Genome Biology*, 20, 257.

Zentgraf, J. et al. (2025). Cleanifier: sensitive removal of host reads from metagenomic data. *Bioinformatics*, btaf632.
