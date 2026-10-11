This directory contains the corrected summary tables used to generate
`figures/fig1_four_way_runtime_memory.*` through
`figures/fig4_parallel_scaling.*`.

The revised `fig1_four_way_runtime_memory.csv` and
`fig2_accuracy_verification.csv` use these definitions:

- `microbial_loss_pct` = discarded true microbial reads / true microbial input.
- `host_input_retained_pct` = retained true host reads / true host input.
- `runtime_sd_s` is present for replicated Deacon and RustyClean AUTO arms.
  It is empty for single-measurement comparator arms.

A count-level audit confirmed that the original comparator labels were
correct: `microbial_loss_pct` is FN divided by microbial input, and
`host_carry_pct` is FP divided by host input. The field has been renamed
`host_input_retained_pct` to make that denominator explicit. Deacon and
AUTO values were recomputed from exact TP/FP/FN/TN counts. The full audit is
in `data/metric_audit/`.

| File | Main figure | Contents |
|---|---|---|
| `fig1_four_way_runtime_memory.csv` | Figure 1 | Runtime, peak memory, F1, microbial loss and host input retention for all four tools and six datasets. |
| `fig2_accuracy_verification.csv` | Figure 2 | Same four-way summary used by the accuracy panels; the high-host subset is used by the verification-effect panel. |
| `fig3_cross_species_index.csv` | Figure 3 | Per-run cross-species depletion measurements with species-matched and panhuman-1 indexes. Its archived error columns require formula-based interpretation (see Methods). |
| `fig4_parallel_scaling.csv` | Figure 4 | Wall time, peak RSS and speedup for W = 1, 2, 4 and 8. |
| `fig4_parallel_scaling_rss_samples.csv` | Figure 4 | Active per-sample RSS samples; medians are plotted, and transient maxima are reported in the manuscript text. |

Memory columns ending in `_gib` are converted from GNU-time/max-RSS KiB by
dividing by 1,048,576. Peak memory is the largest measured process, not
summed pipeline or unique physical memory.
