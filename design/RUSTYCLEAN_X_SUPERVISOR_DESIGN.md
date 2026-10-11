# RustyClean-X: calibrated cascade host depletion

## 1. Supervisor verdict

Build a new implementation, but not as a simple rewrite of RustyClean or Cleanifier.
The current data show that neither tool is dominant. Cleanifier preserves microbial
reads extremely well, while RustyClean AUTO removes host DNA much more aggressively.
The new target should be a calibrated evidence cascade that gets Cleanifier-like
microbial preservation and RustyClean-like host removal.

Current equal-thread observations used for the design:

| Tool | Median runtime | F1 | Host input retained | Microbial loss | Max RSS |
|---|---:|---:|---:|---:|---:|
| RustyClean AUTO | 476.3 s | 0.999000 | 0.001323% | 0.199515% | 4.540 GiB |
| fastp + Hostile | 514.8 s | 0.996396 | 0.178582% | 0.032587% | 3.651 GiB |
| Cleanifier | 219.6 s | 0.999208 | 0.036169% | 0.008955% | 6.583 GiB |

On the divergent-host mock panel:

| Tool | F1 | Host input retained | Microbial loss |
|---|---:|---:|---:|
| RustyClean AUTO | 0.996897 | 0.0211% | 0.6135% |
| fastp + Hostile | 0.996649 | 0.2200% | 0.6134% |
| Cleanifier | 0.989587 | 8.4143% | 0.0000% |

Cleanifier is therefore not globally best. It is best for microbial preservation,
but it retains much more human sequence, especially in the divergent-host mock.
RustyClean is better for privacy and host removal, but loses too many microbial reads.

## 2. Core idea

Build RustyClean-X as a calibrated, multi-evidence cascade rather than a single
classifier or a post hoc pipeline.

### Evidence 1: Cleanifier-style gapped-seed pangenome filter

Use the Cleanifier idea directly. Query gapped k-mers, or spaced seeds, against a
human pangenome seed table or Cuckoo filter. This gives cheap, broad human evidence
and is the best current starting point for microbial preservation.

### Evidence 2: Deacon-style minimizer density

Run a compact minimizer index as a second human evidence source. Cleanifier is
sensitive to seeds present in the pangenome; Deacon is fast and can detect reads
that contain clusters of host-like minimizers. Agreement increases confidence.
Disagreement identifies boundary reads.

### Evidence 3: microbial witness index

Add a small GTDB/microbial witness sketch. Before discarding a read, ask whether
the read has strong non-host evidence. A read with many microbial witness hits
should be retained even if it has a few human seed matches. This is the main
mechanism intended to reduce RustyClean-style microbial loss.


### Evidence 4: gapped x-mer anchors for divergent or repetitive regions

The X-Mapper paper, Gaston, Alm and Zhang, Genome Biology 2025, proposes
dynamic-length x-mers and gapped x-mers. Unlike a fixed k-mer, an x-mer can adapt
seed length to local sequence complexity. Unlike a contiguous seed, a gapped
x-mer can tolerate mismatches at don't-care positions. This is attractive for two
hard host-depletion cases:

1. divergent human or primate reads that fail exact spaced-seed evidence; and
2. repetitive host regions where short seeds are non-specific.

It should not replace the fast Cleanifier or Deacon first pass, but it is well
suited to the boundary/rescue stage and to a future host x-mer anchor index.


### Boundary rescue

Only reads with intermediate evidence enter a local-alignment rescue stage. This
bucket should be small. Use Bowtie2 `--very-fast-local`, Winnowmap2, a Rust-native gapped x-mer anchor
search, or an index-graph aligner. The output is not a full alignment pass; it is
a targeted second opinion.

### Pair-aware decisions

Paired-end reads are scored as fragments, not as independent mates. The default
is conservative for privacy: remove a fragment when either mate is confidently
human. The microbial-preservation profile can rescue a pair when the other mate
has strong microbial witness evidence.

## 3. Scoring model

For each read or fragment, compute normalized features:

- `s_clean`: fraction of gapped seeds found in the human pangenome.
- `s_deacon`: density and clustering of Deacon minimizer host hits.
- `s_xmer`: gapped x-mer anchor density and offset consistency from a host pangenome x-mer index.
- `s_align`: local alignment score or anchor score for boundary reads.
- `s_micro`: microbial witness density from GTDB or a user-supplied microbial panel.
- `q`: quality-weighted evidence.
- `pair`: mate agreement or disagreement.
- `rep`: evidence from repeats and conserved mammalian/primate elements.

A calibrated model converts these features to host and microbial probabilities:

```text
P_host      = f(s_clean, s_deacon, s_xmer, s_align, q, pair, rep)
P_microbial = g(s_micro, low_host_evidence, q, pair)
```

Use three decision regions:

```text
P_host high and P_microbial low       => remove
P_microbial high and P_host low       => keep
both intermediate or contradictory    => boundary rescue
```

Thresholds are profile-specific rather than fixed:

| Profile | Goal | Threshold behaviour |
|---|---|---|
| privacy | minimize host retention | remove ambiguous reads aggressively |
| microbiome | preserve taxa | rescue reads with microbial witnesses |
| MAG / assembly | minimize misclassification | boundary alignment required |
| clinical privacy | strict audit | no keep unless both mates are non-host |

## 4. How this can beat Cleanifier

Cleanifier's main strength is that it almost never discards microbial reads. Its
weakness in the current tests is retained divergent human signal. RustyClean-X
should therefore add three mechanisms that Cleanifier does not have.

1. **Second human evidence source.**  
   Cleanifier-style seed evidence is not accepted alone. Deacon minimizer density
   and boundary alignment can reject reads that Cleanifier leaves ambiguous.

2. **Microbial witness rescue.**  
   A read with strong microbial evidence is retained before a host-only filter
   discards it. This is designed to beat RustyClean's microbial-loss problem.

3. **Calibrated decision regions.**  
   The tool does not use one global k-mer threshold. It learns thresholds for
   privacy, taxonomy and MAG profiles from user-supplied or built-in calibration
   data.

Target acceptance criteria for the first implementation:

| Metric | Target |
|---|---|
| Microbial loss on six-dataset SE panel | below 0.05% |
| Host retention on six-dataset SE panel | below 0.005% |
| Divergent-host mock retention | below 1.0% |
| Divergent-host mock microbial loss | below 0.10% |
| Runtime | no more than 1.5 times Cleanifier |
| Peak RSS | below 8 GiB at 16 threads |

These are engineering targets, not observed results.

## 5. Rust implementation plan

Use Rust and streaming stages.

```text
reader
  -> parsed record queues
  -> feature extractor
  -> calibrated classifier
  -> boundary aligner
  -> pair reconciler
  -> compressed writer
```

Recommended crates and components:

- `needletail` or `seq_io` for FASTQ parsing.
- `flate2` or `zstd-rs` for compression.
- `memmap2` for immutable indexes.
- `crossbeam-channel` or `rayon` for bounded work queues.
- `wide` or explicit AVX2/NEON paths for 2-bit sequence encoding.
- `clap` for a RustyClean-compatible CLI.
- `polars` or CSV output for metrics.
- optional `wasm-bindgen` not required; focus on native HPC.

The key performance rule is that no full second pass may be launched unless the
boundary bucket exceeds a user-specified fraction, for example 10%. The tool should
emit the boundary-bucket size and threshold profile in its report.

## 6. Index plan

Four evidence stores should be shipped separately:

1. **Human spaced-seed filter**  
   Compatible with the Cleanifier human pangenome index or generated from the same
   source FASTAs. Store a Cuckoo or Bloom-like filter with metadata and checksum.

2. **Human minimizer index**  
   Deacon-compatible or Rust-native compact minimizer table. This is the fast
   second human opinion.

3. **Host gapped x-mer anchor index**  
   A Rust-native dynamic/gapped x-mer index inspired by X-Mapper. Build it from
   the human pangenome and conserved primate/mammalian repeat content. Use it for
   divergent-host and ambiguous-read rescue, not as the first-pass filter.

4. **Microbial witness sketch**  
   A small GTDB representative sketch. This is optional for privacy-only runs and
   recommended for microbiome/MAG runs.

All indexes must expose version, k, mask, source accessions, build command and
SHA256 checksums.

## 7. Validation plan

Run the same six-dataset SE panel and the divergent-host mock panel used above.
Then add the missing tests that current data do not cover.

### Required panels

1. Current six-dataset SE panel.
2. Current divergent-host mock panel.
3. Paired-end main panel.
4. Host-diversity panel: GRCh38 plus multiple human individuals and divergent
   simulated hosts at 0.1%, 0.5%, 1%, 2% and 4% divergence.
5. Microbial-community panel: even, lognormal and gut-like compositions.
6. Downstream panel: taxonomy, assembly, MAG recovery and gene profiling.

### Required ablations

- Cleanifier seed filter alone.
- Deacon minimizer alone.
- Cleanifier + Deacon without microbial witness.
- Cleanifier + Deacon + microbial witness.
- Cleanifier + Deacon + gapped x-mer anchors.
- Full cascade with boundary alignment.
- Full cascade without boundary alignment.
- Paired-aware decisions disabled.

### Required statistics

Use per-fragment paired tests where the fragment is the unit. Use dataset-level
cluster bootstrap or mixed-effects models. Report host retention, microbial loss,
host output fraction, F1, F2 for microbial preservation, precision, recall,
runtime, CPU seconds, peak process RSS and process-tree peak RSS.

## 8. Risks

- A microbial witness index can bias toward known taxa. It must be optional.
- Too much Cleanifier-style sensitivity may retain divergent host reads.
- Too much Deacon/Bowtie2 stringency may reproduce RustyClean microbial loss.
- Boundary alignment can erase runtime gains if the ambiguous bucket is large.
- Human-diversity claims require real individual genomes, not only simulated
  substitutions.

## 9. First implementation slice

1. Parse paired FASTQ streams.
2. Integrate Cleanifier seed scores as a library or parse its per-read output.
3. Implement a host score and a simple threshold.
4. Add GTDB microbial witness sketch.
5. Implement three decision regions.
6. Benchmark against Cleanifier on the six datasets and mock panel.
7. Add boundary alignment only after proving that the ambiguous bucket is small.
