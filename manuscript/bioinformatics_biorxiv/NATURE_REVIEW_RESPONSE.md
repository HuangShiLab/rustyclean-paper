# Response to Nature-style review

This note maps the remaining review concerns to manuscript and artifact changes.

## Comparator provenance and main Table 2

- Table 2 is now explicitly a historical, descriptive workflow-scope comparison.
- The caption states that it is not the primary controlled comparator or speed evidence.
- Hostile rows are footnoted for the separate `hostile_raw` accuracy arm and `fastp + Hostile` runtime arm.
- KneadData rows are footnoted for unequal threads, workflow scope, host index and absent 100M counts.
- The controlled Hostile comparison is now the exclusive-node equal-thread panel in Table S4.

## Runtime claims and statistics

- The abstract now states that equal-thread runtime evidence was not statistically significant.
- Results and Discussion describe the equal-thread panel as the primary controlled comparison.
- New dataset-level statistics avoid treating three technical replicates as independent datasets.
- Reported analyses include pair-level t/Wilcoxon/sign tests, dataset-level tests, cluster bootstrap CIs and median paired differences.
- Replicate-level pairs and AMD sensitivity pairs are in `source_data/unresolved_controls/`.

## Hardware and run provenance

- The primary panel is now described as exclusive Intel-partition nodes.
- The runner now uses `--partition=intel`.
- `equal_thread_run_manifest.csv` records SLURM jobs, array tasks, datasets, nodes, exclusivity, CPU allocation and timing windows.
- The earlier non-exclusive AMD panel is retained only as resource-contention sensitivity data.

## Memory accounting

- Methods and Results state that memory is largest-process max RSS.
- Results and Discussion explicitly state that process-tree memory was not measured.
- Conclusions are limited to the reported single-process footprint.

## Adaptive validation

- Methods now defines the diagnostic contamination metric and the exact formula.
- The text states that `--max-contamination 100.0` disabled rejection in benchmarked AUTO commands.
- Paired-end Bowtie2 retention semantics are described: fragments were retained only when both mates were unmapped.
- Exact settings are in `benchmark_parameter_manifest.yml`.

## Threshold sweep

- The abstract and Results now describe an accuracy plateau, not a runtime plateau.
- Table S6 marks runtime as descriptive, unreplicated and not used for threshold selection.
- The Discussion states that the result is limited to the six tested libraries.

## Cleanifier comparison

- Methods and Results now state that Cleanifier was depletion only, whereas RustyClean included QC and verification.
- The manuscript avoids describing the comparison as like-for-like runtime.
- Table S5 records Cleanifier worker and compression threads.

## Cross-species and host diversity

- Section 3.2 and its heading are narrowed to a proof-of-concept panel.
- The incorrect matched host-retention range is corrected to 0.00182–0.00596%.
- Abstract and Discussion no longer state that species-specific indexes are universally essential.
- Taxids and source FASTA basenames are provided; absent accession/strain provenance is explicitly disclosed.
- Mock-panel accessions, seeds, metadata and checksums are included.

## Reproducibility and availability

Added a direct production-index benchmark. Deacon v0.17.0 used its released
panhuman-1 minimizer index and Cleanifier v1.3.2 used its released human
pangenome spaced-seed index. Both were run on the full six simulated FASTQs,
three replicates per dataset, 16 threads, with GNU-time runtime and max-RSS
capture. Per-run TP/FP/FN/TN counts and runtime/RSS metrics are in
`source_data/unresolved_controls/production_index_comparison/`.

- Added run and parameter manifests.
- Added Figure S3 and equal-thread statistics scripts.
- Added tool versions for RustyClean, Deacon, fastp, Hostile, Bowtie2, samtools, Cleanifier and KneadData.
- Added repository license, source-data explanation, LU cohort request path and no-new-human-data statement.
- Added competing-interests statement.
