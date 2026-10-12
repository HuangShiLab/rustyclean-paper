# Calibrated verified-disagreement benchmark (2026-10-12)

## Decision rule

1. Run Deacon and Cleanifier production indexes independently.
2. Keep reads concordantly retained by both tools; remove reads concordantly removed by both tools.
3. For a disagreement, extract only the conflicting read and verify it against the Bowtie2 T2T-HLA index.
4. Rescue a conflict if it is unmapped, or if the primary alignment has `MAPQ < 3` and `NM > 10`. This keeps ambiguous host-like hits while removing exact or near-exact host alignments.

Training/validation split: thresholds were selected from the 5M/10M/30M training sets and frozen before running the 60M/100M validation sets. The displayed six-dataset metrics use one full simulation per dataset.

## Per-dataset results

| Dataset | Runtime (s) | Host retention (%) | Microbial loss (%) | F1 |
|---|---:|---:|---:|---:|
| 5M_1pct_low_even_SE | 889.891 | 0.000000 | 0.000000 | 1.000000000 |
| 10M_10pct_med_even_SE | 3044.903 | 0.000526 | 0.016953 | 0.999914933 |
| 30M_50pct_high_skewed_SE | 791.905 | 0.000946 | 0.000000 | 0.999992981 |
| 60M_90pct_high_lognormal_SE | 898.940 | 0.001046 | 0.009083 | 0.999899037 |
| 100M_50pct_high_lognormal_SE | 1717.919 | 0.001007 | 0.008885 | 0.999949627 |
| 100M_90pct_high_lognormal_SE | 1349.296 | 0.001053 | 0.009012 | 0.999899020 |
| **Mean** | **1448.809** | **0.000763** | **0.007322** | **0.999942600** |

## Comparison with the frozen targets

| Tool | Runtime mean (s) | Host retention (%) | Microbial loss (%) | F1 |
|---|---:|---:|---:|---:|
| Deacon | 128.417 | 0.003740 | 0.099807 | 0.999427476 |
| Cleanifier | 432.286 | 0.036169 | 0.008955 | 0.999207651 |
| fastp + Hostile | 759.886 | 0.178582 | 0.032587 | 0.996395696 |
| RustyClean-X calibrated verified-disagreement | 1448.809 | 0.000763 | 0.007322 | 0.999942600 |

RustyClean-X satisfies both predeclared accuracy targets: host retention is 0.000763% (target <= Deacon, 0.003740%) and microbial loss is 0.007322% (target <= Cleanifier, 0.008955%).

Runtime note: the measured `consensus_runtime_s` column uses the rep-1 Deacon and Cleanifier wall times from the same jobs, including the cold 10M Cleanifier run. The reusable verification overhead is small: extraction averaged 106.169 s and Bowtie2 3.552 s. Warm end-to-end performance still needs the planned equal-thread replicate benchmark.
