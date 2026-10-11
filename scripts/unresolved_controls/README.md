# Unresolved-control experiment suite

This directory contains reproducible runners for the five remaining review
blockers. It separates **completed evidence** from **compute-pending evidence**:
no numeric result should be added to the manuscript until the standardized CSVs
below exist.

## Current status (2026-10-02)

All five controls are complete. The canonical HPC summaries are under
`/lustre1/g/aos_shihuang/rustyclean-paper/runs/unresolved_controls/summary/`;
`status.json` reports `analysis_ready` with no blocking work. Local copies used
by the revised manuscript are in `data/unresolved_controls_hpc/` and
`manuscript/bioinformatics_biorxiv/source_data/unresolved_controls/`.

| Blocker | Status | Evidence |
|---|---|---|
| Equal-thread runtime | **Complete** | Six datasets × three replicates × two arms on exclusive 16-thread nodes. RustyClean was faster in 12/18 pairs; median speedup 1.72×, paired distribution heterogeneous. |
| Cleanifier comparison | **Complete** | Cleanifier v1.3.2, human index, default threshold 0.5, 16 threads, six datasets × three replicates. |
| Threshold sweep | **Complete** | 13 thresholds × six datasets, including 0.00, 0.30 and 1.01; one deterministic accuracy observation per cell. |
| No-/always-recheck controls | **Complete** | Archived no-recheck plus new always-recheck with three replicates per dataset. |
| Real/mock ground truth | **Complete (mock)** | Three exact-ground-truth 2M-pair replicates with divergent GRCh38 host, five GTDB genomes, RustyClean, Hostile and Cleanifier. A population-diverse real cohort remains a useful future addition. |

## Metric convention

All newly produced counts use the audited definitions:

- `tp`: retained true microbe read/pair
- `fp`: retained true host read/pair
- `fn`: removed true microbe read/pair
- `tn`: removed true host read/pair
- host input retention = `100 * fp / (fp + tn)`
- microbial loss = `100 * fn / (tp + fn)`
- host fraction of output = `100 * fp / (tp + fp)`
- F1 is retained-microbe F1.

The scorer writes counts and rates. The summarizer recomputes rates from counts,
so a future relabeling cannot silently change an old rate.

## Cluster prerequisites

The runners expect the same cluster tool/index locations as the existing HPC
scripts, but every path is environment-overridable:

```bash
export THREADS=16
export REPS=3
export DATA_DIR=/scr/u/$USER/rustyclean-paper/data/enhanced
export RESULTS_ROOT=/lustre1/g/aos_shihuang/rustyclean-paper/runs/unresolved_controls
export RUSTYCLEAN=/lustre1/g/aos_shihuang/rustyclean/target/release/rustyclean
export DEACON_INDEX=/lustre1/g/aos_shihuang/databases/deacon/panhuman-1.k31w15.idx
export HOSTILE_INDEX=$HOME/.local/share/hostile/human-t2t-hla
```

Prepare Cleanifier separately (Python >=3.12):

```bash
pip install cleanifier
mkdir -p /lustre1/g/aos_shihuang/databases/cleanifier
cleanifier download --checksum --dir /lustre1/g/aos_shihuang/databases/cleanifier
export CLEANIFIER_BIN=cleanifier
export CLEANIFIER_INDEX=/lustre1/g/aos_shihuang/databases/cleanifier/human
```

The runner accepts either `human.filter`/`human.info` or discovers one
downloaded `*.filter`/`*.hash` under the index directory. Index download/build
is never included in timing.

## Run the pending experiments

Submit from the repository root after `mkdir -p logs`:

```bash
# Six datasets x three replicates x two arms; both arms use exactly 16 threads.
sbatch scripts/unresolved_controls/run_equal_thread_panel.sh

# Always recheck: six datasets x three replicates at threshold 0.00.
sbatch scripts/unresolved_controls/run_always_recheck.sh

# Full threshold sweep (13 thresholds x six datasets; one deterministic scoring replicate).
sbatch scripts/unresolved_controls/run_recheck_threshold_sweep.sh

# Cleanifier default threshold on the six datasets.
sbatch scripts/unresolved_controls/run_cleanifier_benchmark.sh
```

For a short threshold pilot (not manuscript-final), use:

```bash
sbatch --export=ALL,THRESHOLDS='0.00 0.30 1.01' \
  scripts/unresolved_controls/run_recheck_threshold_sweep.sh
```

To submit all four standardized panels at once:

```bash
scripts/unresolved_controls/submit_pending.sh
```

### Mock/real spike-in ground truth

Prepare a manifest using `mock_manifest_template.csv`:

```csv
class,label,path,abundance
host,human_spike_in,"/path/host_R1.fastq.gz,/path/host_R2.fastq.gz",1
microbe,species_A,/path/species_A.fna,1
```

For real human spike-in, provide two paired FASTQs. For simulated host genetic
diversity, provide a host FASTA. Microbial FASTA inputs are simulated with a
uniform substitution model; this simple model is recorded in
`metadata.json` and must not be described as an ART/Neuf-model simulation.

A production run (2M read pairs/reads, 20% host, three independent seeds) is:

```bash
sbatch --export=ALL,MANIFEST=/path/to/mock_manifest.csv,READS=2000000,HOST_FRACTION=0.20,PAIRED=1,REPLICATES=3 \
  scripts/unresolved_controls/run_mock_ground_truth_validation.sh
```

The runner keeps generated truth under
`${RESULTS_ROOT}/mock_truth_data/` and includes `metadata.json` plus
`manifest.sha256`. Run at least three independent community seeds; do not treat
three technical timing replicates of one simulated community as biological
validation.

## Summarize after compute

```bash
python3 scripts/unresolved_controls/summarize_controls.py \
  --controls-root runs/unresolved_controls \
  --legacy-paired data/paired_triplicate/100M_90pct_high_lognormal_SE/paired_runtime_corrected.csv \
  --norecheck runs/deacon_auto_norecheck \
  --output-dir data/unresolved_controls
```

Before summarizing, check every scored row with:

```bash
python3 scripts/unresolved_controls/validate_smoke_outputs.py \
  runs/unresolved_controls/threshold_sweep/metrics/accuracy.csv
```

Outputs are `combined_accuracy.csv`, `combined_performance.csv`,
`accuracy_summary.csv`, `runtime_summary.csv`,
`equal_thread_paired_summary.csv`, `threshold_tradeoff.csv`, and
`status.json`. `status.json` reports `compute_pending` until all expected
dataset/replicate cells are present.

## Local smoke tests already performed

- Python syntax compilation for all scripts and shell syntax checks passed.
- Cleanifier 1.3.2 was installed in an isolated Python 3.12 environment.
- Synthetic SE and PE host/microbe datasets were generated with exact labels.
- Cleanifier index/filter and `score_retained_reads.py` were run end to end.
- SE and PE retained-ID recovery matched synthetic IDs; PE output was resolved
  as `*_1_keep.fastq.gz` plus `*_2_keep.fastq.gz` and unioned for scoring.
