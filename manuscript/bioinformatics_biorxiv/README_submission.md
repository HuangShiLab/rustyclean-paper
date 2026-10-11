# bioRxiv/Bioinformatics submission package

This directory is the clean submission version of the manuscript. It is separate from `manuscript/RustyClean_Manuscript_Draft.*`, which remains the longer working draft.

## Files

- `RustyClean_Bioinformatics_biorxiv.md` — Bioinformatics-style manuscript source.
- `RustyClean_Bioinformatics_biorxiv.docx` — editable submission manuscript.
- `RustyClean_Bioinformatics_biorxiv.html` — standalone print source.
- `RustyClean_Bioinformatics_biorxiv.pdf` — formatted PDF for bioRxiv review.
- `NATURE_REVIEW_RESPONSE.md` — reviewer-concern-to-change map for the latest revision.
- `source_data/unresolved_controls/production_index_comparison/` — direct Cleanifier-versus-Deacon production-index benchmark metrics.
- `figures/` — Figure 1–5 and Supplementary Figures S1–S3 in PNG, PDF and SVG.
- `source_data/` — exact CSV summary tables used to generate the main figures, plus optimized-runtime, paired-validation and parallel-demo summaries.
- `assets/manuscript.css` — formatting used for the PDF.

## Bioinformatics-style checks completed

- Structured abstract: Motivation, Results, Availability and implementation, Supplementary information.
- Abstract length: 150 words excluding headings and URLs.
- Alphabetical author-year reference list.
- Main figures numbered 1–5; Supplementary Figures S1–S3 are retained.
- Internal target-journal and peer-review response sections removed.
- Competing-interests statement included.
- Figure legends, tables and source-data references included.
- Host retention is defined as retained host reads divided by true host input; host output fraction is reported separately where needed. The metric audit is in `data/metric_audit/`.
- Figure 4 includes Deacon backend scaling and the full-pipeline RustyClean-versus-Hostile batch comparison.

## Versions cited in the manuscript

- Benchmark research source: RustyClean commit `7ab1a4b`.
- Streamlined AUTO interface: RustyClean commit `55f93af`.

## Rebuild commands

From this repository root:

```bash
pandoc manuscript/bioinformatics_biorxiv/RustyClean_Bioinformatics_biorxiv.md \
  --from=markdown+pipe_tables+implicit_figures+subscript+superscript \
  --to=docx --standalone \
  --resource-path=manuscript/bioinformatics_biorxiv \
  --output=manuscript/bioinformatics_biorxiv/RustyClean_Bioinformatics_biorxiv.docx

pandoc manuscript/bioinformatics_biorxiv/RustyClean_Bioinformatics_biorxiv.md \
  --from=markdown+pipe_tables+implicit_figures+subscript+superscript \
  --to=html5 --standalone --embed-resources \
  --css=manuscript/bioinformatics_biorxiv/assets/manuscript.css \
  --resource-path=manuscript/bioinformatics_biorxiv \
  --output=manuscript/bioinformatics_biorxiv/RustyClean_Bioinformatics_biorxiv.html

"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless \
  --disable-gpu --no-pdf-header-footer \
  --print-to-pdf=manuscript/bioinformatics_biorxiv/RustyClean_Bioinformatics_biorxiv.pdf \
  "file://$PWD/manuscript/bioinformatics_biorxiv/RustyClean_Bioinformatics_biorxiv.html"
```

## Before final upload

- Confirm the final co-author list and any ORCID/competing-interest requirements with the co-author.
- Replace the two commit identifiers with released tags if tag publication is preferred.
- Upload source data separately if bioRxiv requests CSVs as separate files.
