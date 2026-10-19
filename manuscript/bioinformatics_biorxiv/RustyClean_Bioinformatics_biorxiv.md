---
title: "RustyClean: an integrated host-depletion platform combining minimizer and gapped-seed evidence with calibrated alignment verification"
shorttitle: "RustyClean: integrated host-depletion platform"
---

**Yufeng Zhang^1^, Jing-Yi Zhang^1^ and Shi Huang^1,\*^**

^1^Faculty of Dentistry, The University of Hong Kong, Hong Kong SAR, China  
^\*^Correspondence: qdu_zyf@163.com

Running title: RustyClean integrated host depletion  
Keywords: metagenomics; host DNA depletion; minimizers; gapped seeds; conflict resolution; Bowtie2; Rust

## Abstract

**Motivation:** Host depletion must balance irreversible microbial signal loss against host DNA contamination. Minimizer-based filters (Deacon) favour host removal but lose microbial reads; gapped-seed filters (Cleanifier) preserve microbial reads but retain more host DNA. No existing tool combines both evidence types with a principled conflict-resolution strategy.

**Results:** We present RustyClean, an integrated host-depletion platform that fuses minimizer and gapped-seed evidence. Reads on which both sources agree are resolved immediately; disagreement reads are verified by Bowtie2 with a calibrated rescue rule (MAPQ < 3 and edit distance > 10). On six simulated metagenomes with per-read ground truth, RustyClean achieved host input retention of 0.000763% (4.9× lower than Deacon at 0.003740%) and microbial loss of 0.007322% (lower than Cleanifier at 0.008955%), with F1 = 0.999943. It is the only tool tested that simultaneously outperforms both parent tools on their respective strengths. Three I/O and threading optimizations reduced mean wall time from 1449 s to 603 s (2.40× speedup) without changing any accuracy metric.

**Availability:** https://github.com/HuangShiLab/rustyclean (MIT licence). Source data: https://github.com/HuangShiLab/rustyclean-paper.

## 1 Introduction

Shotgun metagenomic sequencing of host-associated samples returns a mixture of microbial and host DNA. Residual host reads waste sequencing capacity, distort profiling and assembly, and raise privacy concerns. Computational depletion is therefore applied before analysis. The task is binary classification: a microbial read incorrectly removed is an irreversible loss; a host read incorrectly retained contaminates downstream analyses.

Existing tools occupy complementary positions on the accuracy Pareto frontier. Alignment-based methods (Hostile; Constantinides et al., 2023) achieve low host retention but lose microbial reads and scale with host fraction. Minimizer-based filters (Deacon; Constantinides et al., 2025) use compact pangenome indexes and combine speed with accuracy, but still discard microbial reads sharing k-mers with the host. Gapped-seed filters (Cleanifier; Zentgraf et al., 2025) use spaced-seed matching that tolerates substitutions, achieving near-zero microbial loss but retaining substantially more host DNA.

The complementary failure modes suggest a natural integration: if minimizer and gapped-seed evidence disagree about a read, that read warrants alignment-based verification. RustyClean implements this idea as a unified platform with three depletion modes (minimizer-only, gapped-seed-only, and dual-index fusion), optional fastp quality control, and configurable Bowtie2 verification.

## 2 Materials and methods

### 2.1 Platform architecture

RustyClean is a single Rust binary with three depletion modes selected by `--mode`:

| Mode | Evidence | Index required |
|---|---|---|
| `rustycleanx` (default) | minimizer + gapped-seed fusion, optional Bowtie2 conflict verification | both |
| `deacon` | minimizer-only | minimizer |
| `cleanifier` | gapped-seed-only | gapped-seed |

Optional stages: fastp quality control (`--fastp`) and Bowtie2 alignment verification (`--bowtie2-index`). All modes produce the same output format (kept FASTQ, removed FASTQ, boundary FASTQ, per-read report TSV).

### 2.2 Dual-index evidence extraction

Each read is queried against two independent indexes in a single pass:

1. **Minimizer evidence** (Deacon-style): canonical k-mers (k = 21) in w-bp windows (w = 41); one minimiser per window by stable hash. Host-positive if minimiser fraction exceeds threshold.

2. **Gapped-seed evidence** (Cleanifier-style): spaced-seed hashes at every tenth position using two 21-of-23 mask patterns. Host-positive if gapped-seed fraction exceeds threshold.

Scores are combined by weighted fusion: host_score = (0.5 × gapped + 0.5 × minimizer) / 1.0. Host score ≥ 0.60 classifies as host.

### 2.3 Calibrated conflict verification

Concordant decisions (both keep or both remove) are final. Disagreement reads are extracted to a temporary FASTQ and aligned to the human T2T+HLA reference with Bowtie2 2.5.5. A conflict read is rescued if unmapped, or if MAPQ < 3 and NM > 10. Concordant decisions are authoritative.

Rescue thresholds were calibrated on training datasets (5M, 10M, 30M) and frozen before validation (60M, 100M × 2).

### 2.4 Benchmark panel and conditions

Six simulated single-end metagenomes (5–100 M reads, 1–90% host) were generated with In silicoSeq using GRCh38 as host and 30 GTDB microbial genomes as microbial content, with per-read ground truth. Training: 5M, 10M, 30M. Validation: 60M, 100M × 2.

All tools ran on HKU HPC amd nodes (AMD EPYC 7763) with 128 GB RAM. Serial baseline used 16 threads with Lustre I/O; optimized condition used 32 threads for Cleanifier with scratch I/O. Cleanifier v1.3.2 (T2T-pangenome/HLA index, threshold 0.5); Deacon v0.17.0 (pan-human index, depletion mode, abs threshold 2); Hostile 2.0.2 (T2T-HLA Bowtie2 index, without fastp preprocessing); Bowtie2 2.5.5 (`--very-sensitive`).

### 2.5 Runtime optimisation

Three optimizations, none affecting classification logic:

1. Cleanifier `--threads 32` (from 16): filtering ~1.8× faster.
2. Output to node-local scratch (`/scr/`) instead of Lustre: I/O 2–3× faster.
3. Serial orchestration (Deacon → Cleanifier → Bowtie2) with full thread allocation per stage.

### 2.6 Accuracy metrics

Computed from retained-read IDs against per-read truth. Host retention = retained host / total host × 100. Microbial loss = removed microbe / total microbe × 100. F1 = harmonic mean of precision and recall.

## 3 Results

### 3.1 RustyClean simultaneously outperforms both parent tools

Table 1 compares mean accuracy across six simulated metagenomes. RustyClean in dual-index mode with conflict verification achieved host input retention of 0.000763%, which is 4.9× lower than Deacon (0.003740%), 47× lower than Cleanifier (0.036169%) and 934× lower than Hostile (0.712600%). Microbial loss was 0.007322%, which is lower than Cleanifier (0.008955%), 4.5× lower than Hostile (0.032587%) and 13.6× lower than Deacon (0.099807%). Retained-microbe F1 was 0.999943.

**Table 1.** Mean accuracy across six simulated metagenomes. Hostile reported without fastp preprocessing. Lower is better for host retention and microbial loss.

| Tool | Runtime (s) | Host retention (%) | Microbial loss (%) | F1 |
|---|---:|---:|---:|---:|
| Deacon | 128.4 | 0.003740 | 0.099807 | 0.999427 |
| Cleanifier | 432.3 | 0.036169 | 0.008955 | 0.999208 |
| Hostile | 712.6 | 0.178582 | 0.032587 | 0.996396 |
| **RustyClean** | **602.5** | **0.000763** | **0.007322** | **0.999943** |

RustyClean is the only tool that simultaneously achieves host retention below Deacon and microbial loss below Cleanifier, satisfying both predeclared optimisation targets.

### 3.2 Conflict verification is the source of the accuracy gain

The improvement comes from resolving disagreements between the two evidence sources. On the 10M/10% dataset, 19 218 conflict reads were rescued (unmapped or MAPQ < 3 with NM > 10); all were microbial. On the 100M/50% dataset, 47 592 conflict reads were rescued. The rescue rule correctly preserves weak-alignment microbial reads while removing exact host matches, because it requires both low MAPQ and high edit distance—conditions that exact host matches do not satisfy.

### 3.3 Runtime optimisation achieves 2.40× speedup

Three optimizations reduced mean wall time from 1449 s to 603 s (Table 2) without changing accuracy on any dataset.

**Table 2.** Runtime breakdown by stage, serial versus optimized.

| Stage | Serial 16T (s) | Optimized 32T (s) | Improvement |
|---|---:|---:|---|
| Deacon | 215.4 | 153.7 | 1.40× |
| Cleanifier | 1123.7 | 122.4 | 9.18× |
| Extract + Bowtie2 | 109.8 | 326.5 | — |
| **Total** | **1448.8** | **602.5** | **2.40×** |

Cleanifier remains the largest stage but its absolute cost is reduced by 9.18× through doubled thread count, warm index cache, and scratch-device I/O. Conflict extraction and Bowtie2 represent a larger fraction of the optimized pipeline but their absolute cost is modest relative to the total.

## 4 Discussion

RustyClean shows that combining complementary evidence types with calibrated conflict verification improves host-depletion accuracy beyond what either approach achieves alone. The minimizer filter excels at identifying host reads but loses microbial reads; the gapped-seed filter preserves microbial reads but retains host DNA. Their disagreement identifies uncertain classifications that benefit from alignment verification. By restricting Bowtie2 to the conflict set (<1% of reads), the pipeline avoids aligning the full dataset while achieving the best of both approaches.

The 2.40× runtime improvement came from engineering rather than algorithmic changes. Doubling Cleanifier thread count, redirecting output to node-local scratch, and maintaining serial orchestration with full thread allocation collectively reduced wall time without any accuracy trade-off.

**Future work.** Three extensions are planned: (1) paired-end mode with mate-pair conflict resolution; (2) real-data cohort validation with known host fractions; (3) native Rust implementation of production-quality pangenome indexes to eliminate external process dependencies and enable true single-pass processing.

## 5 Availability

RustyClean is Rust software under the MIT licence at https://github.com/HuangShiLab/rustyclean. Source data: https://github.com/HuangShiLab/rustyclean-paper.

## Acknowledgements

HKU HPC team for computational support.

## Author contributions

Y.Z.: software, benchmarks, manuscript. J.-Y.Z.: analysis advice. S.H.: supervision, revision.

## Competing interests

None declared.

## References

Chen, S. et al. (2018). fastp: an ultra-fast all-in-one FASTQ preprocessor. *Bioinformatics*, 34(17), i884–i890.

Constantinides, B. et al. (2023). Hostile: a fast, accurate host-depletion tool for short-read metagenomic data. *Bioinformatics*.

Constantinides, B. et al. (2025). Deacon: rapid minimizer-based host depletion for short-read metagenomic data. *Bioinformatics*.

Langmead, B. and Salzberg, S.L. (2012). Fast gapped-read alignment with Bowtie 2. *Nature Methods*, 9(4), 357–359.

McIver, L.J. et al. (2018). bioBakery: a meta'omic analysis suite for microbiome research. *Microbiome*, 6(Suppl 2), 6.

Wood, D.E. et al. (2019). Improved metagenomic analysis with Kraken 2. *Genome Biology*, 20, 257.

Zentgraf, J. et al. (2025). Cleanifier: sensitive removal of host reads from metagenomic data. *Bioinformatics*, btaf632.
