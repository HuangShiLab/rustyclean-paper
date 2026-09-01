# Full rerun from scratch

Everything from an empty database directory to the final accuracy tables.

```bash
bash scripts/run_all.sh --dry-run   # see the plan
bash scripts/run_all.sh             # submit it
bash scripts/run_all.sh --from 3    # resume at a stage
```

`scripts/run_all.sh` chains the stages with `--dependency=afterok:`, so each one
starts only after what it needs has succeeded. Every path comes from
`scripts/hpc/config.sh` — change a database location there, not in the scripts.

**Budget:** ~500 GB scratch, 200 GB RAM for the Kraken2 build (32 GB for
everything else), ~60–80 h of compute. Wall clock is far less because stages 3–5
run in parallel.

### Where the output goes

Two settings control it, both in `scripts/hpc/config.sh` or the environment:

| | default | holds |
|---|---|---|
| `SCRATCH_DIR` | `$PROJECT_DIR/scratch` | simulated reads (~65 GB) |
| `RUNS_DIR` | `$PROJECT_DIR/runs` | per-experiment outputs (~200 GB) |

Both default to the project filesystem, which on this cluster has several TB
spare against the ~265 GB a full panel needs. To use a different filesystem:

```bash
export SCRATCH_DIR=/somewhere/with/room/scratch
export RUNS_DIR=/somewhere/with/room/runs
bash scripts/preflight.sh      # re-checks space at whichever paths are set
```

`runs/`, `data/` and `figures/` are gitignored, so output written under the
project directory never reaches `git status`. Before this change 22 scripts wrote
their results straight into the repository root.

### If neither filesystem has room

Indexes live under `$DB_ROOT` on the shared filesystem and do not consume
scratch. Scratch holds the simulated reads and the run outputs:

| | gzipped input | notes |
|---|---|---|
| all 19 datasets | ~65 GB | plus ~150–200 GB of outputs |
| without the two 100M datasets | ~43 GB | loses the largest scalability point |
| without 100M and 60M | ~30 GB | loses the high-host extreme, where the routing rule matters most |

To trim, comment the unwanted lines out of the `DATASETS` array in
`scripts/main/generate_enhanced_data.sh` and the matching arrays in the
benchmark scripts. Dropping the 100M datasets is the cheapest cut that keeps the
argument intact, since 60M/90% already covers the high-host regime.

The other lever is to clean as you go: each stage's outputs are only needed by
its own accuracy job, so `results/<experiment>/` can be removed once stage 6 has
written that experiment's CSV. Run stages 3, 4 and 5 in sequence rather than in
parallel if you take this route, since the driver otherwise has them running at
the same time.

---

## Stage 1 — references and indexes

| Script | Builds | Peak RAM |
|---|---|---|
| `main/prepare_grch38_t2t_fasta.sh` | combined T2T + HLA FASTA | 16 GB |
| `main/build_kraken2_t2t_only.sh` | Kraken2 human-only (~15.5 GB) | **200 GB** |
| `main/build_bowtie2_grch38_t2t_v2.sh` | Bowtie2 T2T+HLA (~3.3 GB) | 64 GB |
| `main/build_aux_indexes.sh` | minimap2, sylph, centrifuge | 128 GB |

The Kraken2 build sets the memory requirement for the whole project. Nothing
else needs more than 128 GB.

`build_aux_indexes.sh` is new: the minimap2, sylph and centrifuge indexes had no
build script, so those three backends were not reproducible. All four indexes now
derive from the same T2T + HLA FASTA, which keeps the backend comparison a test
of the algorithms rather than of differing reference content.

**Not built here**, because each tool should be run as its own users would:

- KneadData — `kneaddata_database --download human_genome bowtie2 $DIR`
  (`Homo_sapiens_hg39_T2T_Bowtie2_v0.1`, GCF_009914755.1, ~3.6 GB)
- Hostile — `hostile fetch --name human-t2t-hla`
  (T2T-CHM13v2.0 + IPD-IMGT/HLA v3.51, ~3.3 GB)

Both are T2T-based, so all three tools are compared on the same assembly.

## Stage 2 — simulated datasets

`hpc/generate_data_sequential_slurm.sh` — 19 datasets, 600 M read records,
~65 GB gzipped, with per-read ground-truth labels. This is the longest
unmeasured step; budget 15–25 h.

**Host reads are simulated from GRCh38 while depletion runs against T2T.** Keep
it that way. Simulating from the depletion reference would make host removal a
self-match and the benchmark would measure nothing.

## Stage 3 — main comparisons

| Script | Compares |
|---|---|
| `benchmark/run_benchmark.sh` | RustyClean auto vs KneadData, full pipeline |
| `benchmark/fair_hostile_skipqc_run_benchmark.sh` | RustyClean `--skip-qc` vs Hostile, depletion only |
| `main/benchmark_backend_runtime.sh` | bowtie2 / minimap2 / sylph / centrifuge |

## Stage 4 — verification pass and index ablation

| Script | Arm |
|---|---|
| `benchmark/benchmark_baseline_kraken2_memmap.sh` | Kraken2, no verification |
| `benchmark/benchmark_bowtie2_recheck_v2.sh` | Kraken2 + `--bowtie2-recheck` |
| `benchmark/benchmark_k2_index_ablation.sh` | mixed `kraken16` index, everything else held identical |

Every database and index path comes from `scripts/hpc/config.sh`, which the
driver exports and SLURM propagates into each job. `KRAKEN2_DB` defaults to the
human-only T2T index, so the first two scripts run the shipped default.

The ablation runs the same thing against the mixed `kraken16` library instead.
It exists because every previously committed result used that mixed database,
not the human-only index the manuscript describes. Kraken2 assigns the LCA of a
read's k-mer hits, so a mixed library lets a host read be assigned to an ancestor
of *Homo sapiens*, where host detection did not remove it. Comparing the two
arms measures how much of the observed host carry-over is the index rather than
the method.

## Stage 5 — previously unmeasured

| Script | Fills |
|---|---|
| `main/benchmark_auto_decision_boundary.sh` | runtime of **both** backends across a host gradient — the only empirical support for the default routing thresholds |
| `main/benchmark_t2t_only_pe_panel.sh` | paired-end libraries, which no published result covers |

Neither has ever produced a committed result. The decision-boundary curve is the
higher priority: the Methods asserts the thresholds follow measured runtime
behaviour, and no figure yet shows it.

## Stage 6 — accuracy

`run_compute_accuracy.sh`, `run_accuracy_bowtie2_recheck_v2.sh`,
`run_accuracy_k2_index_ablation.sh`. Depletion is deterministic, so accuracy is
identical across replicates; replication applies to timing only.

## After the run

```bash
python scripts/main/analyze_performance.py  "$RESULTS_DIR" "$ANALYSIS_DIR"
python scripts/main/analyze_accuracy.py     "$DATA_DIR" "$RESULTS_DIR" "$ANALYSIS_DIR"
python scripts/benchmark/compare_k2_index_ablation.py
python scripts/main/plot_updated_paper_figures.py
python scripts/main/make_status_deck.py
```

---

## Carry these fixes into the rerun

Problems in the existing results that a rerun should not reproduce.

1. **Give every replicate its own checkpoint directory.** RustyClean skips a
   sample whose checkpoint says it finished and whose input fingerprint is
   unchanged, so replicates sharing a directory silently return without doing
   any work. Pass `--checkpoint-dir` per replicate; the benchmark scripts here
   already do.
2. **Cap workers by memory, not cores.** Worker count defaults to half the core
   count, and each worker loads its own copy of the Kraken2 index. With a
   15.5 GB index that is 15.5 GB per worker. Set `-w` explicitly.
3. **Keep one class convention.** `results_100M_skipqc_matched/accuracy.csv`
   stored Hostile with host as the positive class and RustyClean with microbe as
   the positive class, which makes the F1 columns incomparable as written.
   Positive = retained microbial read, everywhere.
4. **Emit the `rep` column for every tool.** KneadData and Hostile rows in
   `results_100M_matched/performance.csv` omit it, which shifts every later
   column when the file is read as a dictionary.
5. **Run each tool on one node with one setting.** Hostile took 71 min on the 60M
   dataset but 22 min on the larger 100M dataset. A bigger library cannot be
   faster; those two runs did not use the same configuration.
6. **Report KneadData with `--bypass-trf` as well.** RustyClean does no
   repeat masking, so the like-for-like comparison needs KneadData without it.
7. **Stage the Kraken2 database on node-local storage.** `--memory-mapping`
   against Lustre is pathologically slow — every page fault is a network round
   trip. The benchmark scripts copy the index to `/tmp` first.
