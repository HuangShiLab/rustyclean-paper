# RustyClean-X evidence status against Deacon, Cleanifier, Hostile, Kraken2 and KneadData

## Important distinction

RustyClean-X is the new dual-evidence prototype. Its current implementation has
been tested with synthetic gapped-seed/minimizer/witness hash sets. It has not
yet been run against the real Cleanifier or Deacon production index formats.
Therefore, there is currently no direct RustyClean-X-versus-production-tool
accuracy benchmark.

The available comparative evidence below is for RustyClean AUTO, the parent
workflow, or for individual comparator arms. These data support the design
hypothesis but cannot be presented as RustyClean-X validation.

## Implementation evidence for RustyClean-X

Current tests:

- 16 unit tests pass.
- 2 end-to-end smoke tests pass.
- Host control is classified as REMOVE.
- Microbial control is classified as KEEP.
- Evidence-free control is classified as BOUNDARY.
- Paired host/microbe mates remain consistent.

Synthetic FASTQ performance used the previous six simulated metagenome datasets,
the first 200,000 records per dataset and three replicates per mode. Median
runtimes for 200,000 records / 30 Mbp were approximately:

| Mode | Median seconds |
|---|---:|
| FASTQ parse only | 0.242 |
| Gapped-seed evidence only | 4.721 |
| Minimizer evidence only | 28.723 |
| Fused gapped + minimizer | 33.199 |
| Fused + microbial witness | 37.323 |

These are algorithmic overhead measurements using synthetic hash sets, not
accuracy measurements and not real Cleanifier/Deacon production indexes.

## Related RustyClean AUTO evidence

### Deacon production index

Source: 6 datasets x 3 replicates, Deacon v0.17.0 panhuman-1 index.

| Metric | Value |
|---|---:|
| Median runtime | 77.045 s |
| Mean runtime | 128.417 s |
| Mean F1 | 0.999427 |
| Mean host input retention | 0.003740% |
| Mean microbial loss | 0.099807% |
| Mean max RSS | 4.541 GiB |

### Cleanifier production index

Source: 6 datasets x 3 replicates, Cleanifier v1.3.2 human pangenome index.

| Metric | Value |
|---|---:|
| Median runtime | 582.895 s |
| Mean runtime | 634.681 s |
| Mean F1 | 0.999208 |
| Mean host input retention | 0.036169% |
| Mean microbial loss | 0.008955% |
| Mean max RSS | 6.581 GiB |

### Hostile

Exclusive-node equal-thread panel: 6 datasets x 3 replicates.

| Metric | RustyClean AUTO | fastp + Hostile |
|---|---:|---:|
| Mean F1 | 0.999000 | 0.996396 |
| Mean host input retention | 0.001323% | 0.178582% |
| Mean microbial loss | 0.199515% | 0.032587% |

RustyClean was faster in 12/18 pairs. The median paired speedup was 1.72x, but
paired t-test, Wilcoxon and sign tests were not significant.

### Kraken2-backed RustyClean baseline

This is not standalone Kraken2. It is a RustyClean baseline using a memory-mapped
Kraken2 backend.

| Dataset | Replicates | Mean runtime | Mean F1 | Mean host retention | Mean microbial loss | Mean max RSS |
|---|---:|---:|---:|---:|---:|---:|
| 30M / 50% | 3 | 517.70 s | 0.998222 | 0.265947% | 0.089874% | 4.812 GiB |
| 60M / 90% | 3 | 775.31 s | 0.988383 | 0.250704% | 0.092184% | 6.711 GiB |
| 100M / 50% | 4 | 1614.87 s | 0.998385 | 0.230450% | 0.092719% | 9.605 GiB |
| 100M / 90% | 3 | 1366.94 s | 0.986403 | 0.295649% | 0.093351% | 12.312 GiB |

### KneadData

Historical main-panel evidence exists, but it is not a controlled same-thread
comparison and some comparator counts are incomplete.

Examples from audited count-level data:

| Dataset | KneadData microbial loss | KneadData host retention |
|---|---:|---:|
| 5M / 1% | 3.956% | 0.268829% |
| 10M / 10% | 2.791% | 0.255497% |
| 60M / 90% | 2.154% | 0.249644% |

Historical runtime examples from Table 2:

| Dataset | KneadData runtime |
|---|---:|
| 5M / 1% | 420.3 s |
| 10M / 10% | 694.5 s |
| 60M / 90% | 6822.0 s |
| 100M / 90% | 8271.0 s |

The 100M KneadData/Hostile comparator cells lack archived TP/FP/FN/TN counts.

## Required direct RustyClean-X benchmark

To provide the requested direct evidence, RustyClean-X must first load the real
Cleanifier and Deacon production index formats, then run on the same six
ground-truth datasets. The required comparison arms are:

1. RustyClean-X gapped-seed evidence only.
2. RustyClean-X minimizer evidence only.
3. RustyClean-X fused evidence.
4. RustyClean-X fused + microbial witness.
5. RustyClean-X fused + boundary alignment.
6. Deacon production index.
7. Cleanifier production index.
8. Hostile production workflow.
9. KneadData production workflow.
10. Kraken2-backed RustyClean baseline.

Each arm needs per-read or per-fragment TP/FP/FN/TN, runtime, CPU seconds,
max process RSS and process-tree peak RSS.
