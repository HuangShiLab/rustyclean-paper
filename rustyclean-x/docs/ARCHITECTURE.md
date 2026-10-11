# RustyClean-X framework draft

## Goal

Combine Cleanifier-style gapped-seed evidence with Deacon-style minimizer
evidence in one streaming pass, then use calibrated thresholds to reduce
host retention without reproducing RustyClean AUTO's high microbial loss.

## Current framework

```text
FASTQ R1/R2
  -> paired record reader
  -> one-pass feature extractor
       + gapped-seed host evidence
       + minimizer host evidence
       + optional microbial witness evidence
  -> calibrated classifier
  -> keep/remove/boundary decision
  -> FASTQ writer + TSV evidence report
```

## Decision stack

The decision path is now separated into three stages:

```text
EvidenceFeatures
  Raw counts and fractions from minimizer, gapped-seed, witness and quality
  evidence.  One merged feature object represents the paired fragment.

FusedScores
  Normalized gapped/minimizer components, their weighted host score, and the
  normalized microbial-witness score.

Decision
  Keep, Remove or Boundary, produced by the score-fusion resolver.  Boundary
  reads are retained in the keep FASTQ and duplicated into the boundary FASTQ.
```

The default decision backend is `fused`.  It replaces hard OR/AND votes with
a weighted score:

```text
host_score =
  (W_gapped * min(gapped_fraction / T_gapped, 1)
   + W_minimizer * min(minimizer_hits / T_minimizer, 1))
   / (W_gapped + W_minimizer)
```

A microbial-witness score at or above its threshold can rescue a moderate
host signal, but cannot rescue a fragment whose fused host score reaches the
confident-host threshold.  Discordant mate host evidence is sent to
`Boundary`.  The original hard OR/AND decision remains available with
`--decision-mode hard` for ablation.

Default score weights and thresholds are implementation defaults.  They must
be recalibrated on held-out training data before reporting calibrated
probabilities or claiming optimized accuracy.

## One-pass evidence extraction

Yes. Gapped-seed and minimizer evidence can be extracted in one pass because
both consume the same parsed read. The shared work is:

1. read/quality parsing;
2. sequence encoding;
3. candidate enumeration;
4. evidence filter lookup;
5. per-read feature aggregation.

They are not the same seed object:

- minimizers select representative exact k-mers from windows;
- gapped seeds evaluate selected positions across a mask.

But the scanning can be fused, avoiding a second FASTQ decompression, parse,
quality conversion and allocation pass.

Expected runtime model:

```text
T_fused  = T_IO
         + N * (C_parse + C_encode + C_gapped + C_minimizer + C_score)
         + f * N * C_boundary_alignment
```

Naive two-tool model:

```text
T_two_tool = 2 * T_IO
           + 2 * T_parse
           + N * C_gapped
           + N * C_minimizer
           + merge + intermediate I/O
```

So fused extraction should be closer to 1.2-1.6x one evidence method than 2x,
depending on seed density and cache locality.

## Next implementation milestones

1. Replace draft hash-set indexes with memory-mapped Cuckoo/Bloom structures.
2. Use 2-bit encoding and SIMD/word-parallel seed evaluation.
3. Add paired-end fragment reconciliation.
4. Add calibrated threshold training from mock/ground-truth data.
5. Add boundary FASTQ output for optional external alignment.
6. Add process-tree RSS and CPU-time reporting.
7. Benchmark Cleanifier-only, Deacon-only, fused, and ablations.

See `PSEUDOCODE.md` for the algorithm invariants and smoke-test expectations.

## Synthetic benchmark

`src/bin/benchmark.rs` measures parse-only, gapped-seed-only, minimizer-only,
fused gapped+minimizer, and fused+microbial-witness feature extraction.

Example:

```bash
cargo run --release --bin benchmark -- \
  --reads 20000 --length 150 --index-kmers 50000 \
  --replicates 3 --output benchmark/results_synthetic_20k.tsv
```

The 2026-10-03 local draft result is stored in
`benchmark/results_synthetic_20k.tsv`. This benchmark uses synthetic random
sequences and synthetic hash indexes. It measures implementation overhead, not
final performance against the real human pangenome indexes.

## Simulated-metagenome FASTQ benchmark (2026-10-03)

We benchmarked the fused RustyClean-X evidence extraction on the six previous
InSilicoSeq/ART simulated metagenome FASTQs. For stable cross-dataset timing,
each job used the first 200,000 FASTQ records (30,000,000 bp) from each dataset,
three replicates per mode, and 1,000,000 synthetic evidence hashes. This measures
parsing plus gapped/minimizer/witness query overhead on real simulated reads. It
does not benchmark the full Cleanifier or Deacon production index formats.

Median seconds for 200,000 reads:

| Dataset | Parse only | Gapped only | Minimizer only | Fused gapped+minimizer | Fused + witness |
|---|---:|---:|---:|---:|---:|
| 5M / 1% | 0.242 | 4.710 | 28.824 | 33.358 | 37.548 |
| 10M / 10% | 0.247 | 4.765 | 29.022 | 33.545 | 37.648 |
| 30M / 50% | 0.248 | 4.732 | 29.011 | 33.540 | 37.651 |
| 60M / 90% | 0.240 | 4.696 | 28.419 | 32.930 | 36.982 |
| 100M / 50% | 0.241 | 4.633 | 28.487 | 32.971 | 36.998 |
| 100M / 90% | 0.244 | 4.736 | 28.324 | 32.898 | 36.817 |

The fused gapped+minimizer pass was slightly faster than the sum of separate
passes because parsing, decompression and record allocation are shared. Adding
the microbial witness query increased runtime by about 12-14%, while retaining
the third evidence source needed for microbial rescue.
