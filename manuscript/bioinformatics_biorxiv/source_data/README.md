# Main-figure source data

This directory contains the audited summary tables used to generate
Figures 1–5 and Supplementary Figure S1.

For Figures 1 and 2:

- `microbial_loss_pct` = lost true microbial reads / true microbial input.
- `host_input_retained_pct` = retained true host reads / true host input.
- `runtime_sd_s` is present for replicated Deacon and RustyClean AUTO arms and
  is empty for single-measurement comparator arms.
- Host input retention is distinct from host output fraction, which would use
  retained reads as the denominator.

Figure 3 and `fig3_cross_species_index.csv` retain the archived column names.
Their counts were audited in `data/metric_audit/`: the large panhuman-1 values
are retained non-human host reads, not microbial loss.

`figS1_backend_comparison.csv` uses the archived removed-host schema:

- TP = removed host read
- FP = lost microbial read
- FN = retained host read
- TN = retained microbial read

The biological rates in the CSV use microbial input and host input
denominators. The historical run is exploratory and was not rerun with the
Deacon-based production CLI.

Memory values are converted from GNU-time max-RSS KiB by dividing by
1,048,576. They describe the largest measured process, not process-tree or
unique physical memory.

## Reviewer-control source data

`unresolved_controls/` contains summaries and raw count-level tables for the
equal-thread, Cleanifier, threshold-sweep, no/always-recheck and mock-truth
controls. Key files:

- `equal_thread_pairs.csv` and `equal_thread_statistics.json`: all 18
  exclusive-node runtime pairs and pair-level/dataset-level statistics.
- `equal_thread_run_manifest.csv`: SLURM job, node, partition, CPU allocation,
  start/end time and exclusivity for the primary equal-thread panel.
- `equal_thread_amd_sensitivity_pairs.csv` and
  `equal_thread_amd_sensitivity_statistics.json`: the retained non-exclusive
  AMD resource-contention sensitivity data. They are not pooled with the
  primary panel.
- `benchmark_parameter_manifest.yml`: tool versions, indexes, command flags,
  validation settings and provenance warnings for the historical panel.
- `threshold_sweep_compact.csv`: accuracy, retention, loss, exploratory median
  runtime and recheck rate by threshold.
- `mock_truth/`: exact mock manifest, generation metadata, replicate seeds and
  SHA256 checksums. Synthetic FASTA/FASTQ are not redistributed.
- `cross_species/host_reference_provenance.csv`: preserved taxids/source
  basenames and the explicit absence of surviving accession/strain metadata.

`fig5_equal_thread_cleanifier.csv` contains the primary equal-thread comparison used by Figure 5 and Table 4. Cleanifier is depletion only; RustyClean AUTO includes QC and conditional verification; fastp + Hostile is a multi-stage pipeline.
