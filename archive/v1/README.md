# Archive — v1 benchmark round

The results reported in the manuscript draft up to August 2026, together with a
snapshot of the scripts that produced them. Kept for provenance and superseded by
the rerun driven from `RUN_ALL.md` in the repository root.

```
archive/v1/
  data/      results as committed (accuracy, performance, matched panels)
  figures/   fig1-fig4 + figS1 generated from those results
  scripts/   the scripts as they were when the results were produced
```

Nothing here should be regenerated. If a number in the manuscript needs
checking, check it against the rerun, not against this directory.

## What was run

| # | Experiment | Compared | Datasets | Reps |
|---|---|---|---|---|
| 1 | Error profile and accuracy | Hostile, KneadData | 4 SE | 1 |
| 2 | Auto routing, full pipeline runtime | KneadData | 4 SE | 1 |
| 3 | Depletion-only runtime | Hostile (`--skip-qc` both sides) | 4 SE | 1 |
| 4 | Bowtie2 verification ablation | itself (Kraken2 only) | 4 SE | 3 |
| 5 | Backend comparison | bowtie2 / minimap2 / centrifuge | 4 SE | 1 |
| 6 | 100M matched panel | Hostile, KneadData | 2 SE | 3/1/1 |
| 7 | 100M depletion-only matched | Hostile | 2 SE | 3/1 |

All simulated, with per-read ground truth. Host reads were simulated from
GRCh38 and depleted against T2T-CHM13v2.0.

## Why it is superseded

Each of these is fixed in the rerun; see "Carry these fixes into the rerun" in
`RUN_ALL.md`.

1. **The index does not match the Methods.** Every experiment above used
   `kraken16`, a mixed multi-taxon Kraken2 database, and `hg_39` for Bowtie2 —
   not the human-only T2T index and the T2T+HLA index the manuscript describes.
   Because Kraken2 assigns the LCA of a read's k-mer hits, a mixed library lets a
   host read be assigned to an ancestor of *Homo sapiens*, where host detection
   did not remove it. This plausibly accounts for much of the measured host
   carry-over on the classification path.

2. **Replicates may not have run.** RustyClean skips a sample whose checkpoint
   records completion and whose input fingerprint is unchanged. These runs shared
   one checkpoint directory across replicates, so replicates 2 and 3 could return
   without doing any work. Verify before quoting any mean runtime from
   `data/benchmark_results/`.

3. **Two irreconcilable Hostile runtimes.** Hostile took 71 min on the 60M
   dataset but 22 min on the larger 100M dataset. A bigger library cannot be
   faster, so those runs did not use the same configuration.

4. **Mixed class conventions.** `data/results_100M_skipqc_matched/accuracy.csv`
   stores Hostile with host as the positive class while RustyClean rows use
   microbe, which makes the F1 columns incomparable as tabulated.

5. **Malformed rows.** KneadData and Hostile rows in
   `data/results_100M_matched/performance.csv` omit the `rep` field, shifting
   every later column when read as a dictionary.

6. **Asymmetric work.** KneadData ran with tandem-repeat masking, which
   RustyClean does not perform, so part of the runtime difference is work not
   done rather than work done faster.

7. **The Methods names the wrong simulator.** The draft states InSilicoSeq
   v2.0.0, but the generator the SLURM driver runs is `art_illumina`, and its
   own header says it exists because InSilicoSeq "is too slow for hundreds of
   millions of reads". Whichever produced these results, the manuscript and the
   code disagree, and the claim needs checking before it is published.

8. **Narrow panel.** Four to six datasets, all single-end, host fractions
   clustered at the extremes, nothing between 10% and 30% where the routing rule
   actually decides, and no real cohort.

## Provenance

The scripts in `scripts/` are a snapshot, not the live pipeline: the
`--bowtie2-recheck` calls are the bare form these runs used, before the flag was
changed to carry the index it verifies against. They will not run against a
current RustyClean binary, which is intentional — they document what was run.
