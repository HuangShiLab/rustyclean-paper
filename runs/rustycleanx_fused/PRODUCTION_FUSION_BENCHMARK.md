# RustyClean-X production-query fusion benchmark

Date: 2026-10-11  
Scope: six full simulated metagenomes plus one unlabeled real vaginal swab.

## Important definition

`RustyClean-X production fusion` uses the official Deacon and Cleanifier
query/filter engines, imports their read-level retained-ID results, then applies:

1. concordant-remove: remove;
2. concordant-keep: keep;
3. disagreement: keep only if the independent GTDB microbial witness passes
   its threshold, otherwise remove.

The end-to-end runtime therefore includes official Deacon query + official
Cleanifier query + ID import + witness scan + fusion resolver.

## Six simulated metagenomes

Means over six datasets. Deacon and Cleanifier query runtimes are the means of
three replicates per dataset. For RustyClean-X production fusion, runtime is the
complete Deacon + Cleanifier + fusion/importer chain.

| Tool | Runtime (s) | Host retention (%) | Microbial loss (%) | Retained-microbe F1 |
|---|---:|---:|---:|---:|
| RustyClean-X production fusion | 11,263.8 | **0.000623** | 0.088208 | **0.999546** |
| Deacon 0.17.0 | 128.4 | 0.003740 | 0.099807 | 0.999427 |
| Cleanifier 1.3.2 | 432.3 | 0.036169 | **0.008955** | 0.999208 |
| fastp + Hostile | 759.9 | 0.178582 | 0.032587 | 0.996396 |
| KneadData | NA | NA | NA | NA |

Interpretation:

- Versus Deacon, production fusion retained **6.0-fold fewer host reads** and
  reduced microbial loss by **11.5% relative**.
- Versus Cleanifier, production fusion retained **58-fold fewer host reads**
  and improved F1, but had **9.85-fold higher microbial loss**.
- Therefore production fusion dominates Deacon on both accuracy axes in this
  panel, but does **not** dominate Cleanifier because Cleanifier preserves
  microbes better.
- It is not an efficiency win: it is substantially slower because both
  production queries are executed and the fusion stage adds ID import,
  witness scanning and resolver overhead.

## Threshold calibration

Training datasets:

- 5M / 1%
- 10M / 10%
- 30M / 50%

Held-out validation datasets:

- 60M / 90%
- 100M / 50%
- 100M / 90%

The calibration target was host retention <= 0.05%. No tested threshold pair
reached that target. The objective therefore selected the minimum-microbial-
loss point:

- `host_score_remove = 0.90`
- `host_score_confident = 0.95`
- `microbe_score_rescue = 0.00`

Held-out means:

| Mode | Host retention (%) | Microbial loss (%) |
|---|---:|---:|
| Default witness rescue 0.30 | 0.000806 | 0.099130 |
| Calibrated rescue 0.00 | 0.040270 | 0.005568 |

Thus calibration improves microbial preservation but sacrifices host cleanup.
For the stated host-clean objective, the default witness rescue threshold
0.30 remains preferable.

## Real vaginal swab performance-only run

No per-read truth is available, so this is not an accuracy benchmark.

| Metric | Value |
|---|---:|
| Input reads | 3,537,448 |
| Deacon retained | 158 |
| Cleanifier retained | 3,537,287 |
| RustyClean-X production fusion retained | 11,321 |
| RustyClean-X production fusion removed | 3,526,127 |
| Fusion retained / input | 0.320% |

The fusion output is 99.68% smaller than Cleanifier output and includes 11,163
additional retained reads versus Deacon, which were rescued by the microbial
witness. Accuracy cannot be inferred without truth.

## Files

- End-to-end summary: `runs/unresolved_controls/summary/rustycleanx_production_fusion_end_to_end_summary.tsv`
- Per-dataset fusion metrics: `runs/rustycleanx_fused/production_fusion_runs/<dataset>/metrics.tsv`
- Per-read reports: `runs/rustycleanx_fused/production_fusion_runs/<dataset>/per_read_report.tsv.gz`
- Score histograms: `runs/rustycleanx_fused/production_fusion_runs/<dataset>/score_histogram.tsv`
- Calibration manifest: `runs/rustycleanx_fused/production_fusion_runs/calibration/calibration_manifest.json`
- Calibration validation: `runs/rustycleanx_fused/production_fusion_runs/calibration/validation_metrics.tsv`
- Real vaginal summary: `runs/rustycleanx_fused/real_vaginal_swab/real_performance_summary.json`
