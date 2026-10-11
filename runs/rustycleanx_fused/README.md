# RustyClean-X fused single-pass benchmark (reference-derived sparse indices)

Run date: 2026-10-10  
Scope: six full simulated metagenomes, all FASTQ records, single-end.

## Index provenance

Indices were generated from reference FASTA rather than Cleanifier/Deacon production index formats:

- host: GRCh38 primary assembly
- microbial witness: first 100 sorted GTDB r202 reference genomes
- sparse sampled hashes:
  - gapped: 50,000,000
  - minimizer: 20,000,000
  - witness: 79,575,520

These are not the production Cleanifier or Deacon index formats.

## Per-read outputs

Each dataset directory contains:

- `per_read_report.tsv.gz`: per-read truth, decision, retained flag, raw fractions, fused host score, microbe score, and normalized components.
- `score_histogram.tsv`: 0.05-wide host/microbe score histogram stratified by truth.
- `metrics.tsv`: full-read accuracy and runtime.

## Training/validation split

Training datasets:

- 5M_1pct_low_even_SE
- 10M_10pct_med_even_SE
- 30M_50pct_high_skewed_SE

Held-out validation datasets:

- 60M_90pct_high_lognormal_SE
- 100M_50pct_high_lognormal_SE
- 100M_90pct_high_lognormal_SE

Threshold sweep used every 1,000th read from training reports (43,933 rows).

## Calibration result

The constrained search required host retention <= 0.05%. No threshold pair reached that target. The unconstrained objective therefore minimized training microbial loss and selected:

- host_score_remove = 0.90
- host_score_confident = 0.95
- microbe_score_rescue = 0.40

On held-out validation this made host retention worse (about 66.25%) while reducing microbial loss to about 0.080%. Therefore these thresholds must not be promoted to defaults.

## Same-panel comparator summary

Mean over all available full-run observations:

| Tool | Runs | Runtime s | Host retention % | Microbial loss % | F1 |
|---|---:|---:|---:|---:|---:|
| RustyClean-X fused prototype | 6 | 14241.2 | 62.06 | 0.322 | 0.673 |
| Deacon | 18 | 128.4 | 0.00374 | 0.0998 | 0.9994 |
| Cleanifier | 18 | 634.7 | 0.0362 | 0.00896 | 0.9992 |
| fastp + Hostile | 18 | 759.9 | 0.179 | 0.0326 | 0.9964 |
| KneadData | 0 | NA | NA | NA | NA |

KneadData has no full six-panel same-version runs available in the archived comparator outputs, so it is not numerically comparable here.

## Conclusion

The current single-pass fused prototype does **not** outperform Deacon, Cleanifier, or Hostile on this six-panel benchmark. The likely limiting factor is sparse reference-derived hash-index sensitivity and lack of direct production-index import. These results should not be used to claim superiority over Cleanifier/Deacon.

Next engineering step is production-index compatibility or a much higher-sensitivity compact index, followed by fresh held-out calibration.
