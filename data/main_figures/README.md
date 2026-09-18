# Main-figure source data

This directory contains the exact summary tables used to generate
`figures/fig1_four_way_runtime_memory.*` through
`figures/fig4_parallel_scaling.*`.

| File | Main figure | Contents |
|---|---|---|
| `fig1_four_way_runtime_memory.csv` | Figure 1 | Runtime, peak memory, F1, microbial loss and host carry-over for all four tools and six datasets. |
| `fig2_accuracy_verification.csv` | Figure 2 | Same four-way summary used by the accuracy panels; the high-host subset is used by the verification-effect panel. |
| `fig3_cross_species_index.csv` | Figure 3 | Per-run cross-species depletion measurements with species-matched and panhuman-1 indexes. |
| `fig4_parallel_scaling.csv` | Figure 4 | Wall time, peak RSS and speedup for W = 1, 2, 4 and 8. |
| `fig4_parallel_scaling_rss_samples.csv` | Figure 4 | Active per-sample RSS measurements from the W-specific samplers; zero rows collected before/after processing are removed. |

Memory columns ending in `_gib` are converted from GNU-time/max-RSS KiB by
dividing by 1,048,576. The CSVs are derived from the replicate and comparator
tables under `runs/deacon_panel/metrics/`; `fill_100m_comparators.csv` contains
the added single-run 100M KneadData and fastp + Hostile measurements.
