# Bioinformatics Application Note package

This directory contains a concise Bioinformatics-style Application Note for RustyClean. It is independent of the longer bioRxiv-ready benchmark manuscript and is suitable when the target article type is an Application Note rather than a full paper.

## Files

- `RustyClean_Application_Note.md` — Application Note source.
- `RustyClean_Application_Note.docx` — editable submission manuscript.
- `RustyClean_Application_Note.html` — standalone print source.
- `RustyClean_Application_Note.pdf` — formatted Application Note.
- `figures/` — combined performance and parallel-scaling figure in PNG, PDF and SVG.
- `source_data/` — five-tool runtime/memory summary, no-recheck summary, Hostile runtime decomposition and parallel-scaling data.
- `assets/application_note.css` — compact formatting used for the PDF.
- `RustyClean_Application_Note_package.zip` — assembled submission package.

## Format checks

- Application Note label included above the author block.
- Structured abstract: Summary, Availability and implementation, Supplementary information, Contact.
- Abstract: 165 words including headings, excluding URLs.
- Total length: 1277 words including references.
- Rendered PDF: 4 pages of main text plus a references page.
- Two figures and three compact tables.
- Alphabetical author-year references; only cited references retained.
- No placeholders remaining.
- Figure 1 contains the original four-tool performance panels (a,b) above the parallel-scaling panels (c–e).
- Hostile + fastp runtimes are the sum of independently timed fastp and Hostile stages; the decomposition is in `source_data/hostile_runtime_components.csv`.
- Includes a measured RustyClean AUTO no-recheck arm (fastp + Deacon).
- Host carry-over uses retained host reads divided by total retained output.
- Figure 2 adds the I/O-optimized runtime panel and the full-pipeline batch-parallelization comparison against Hostile + fastp.
- `source_data/` now includes optimized-runtime, paired-validation and completed parallel-demo summaries.
- CSS compacted to retain a four-page main-text layout after adding Figure 2d (memory).

## Figure regeneration

From the repository root:

```bash
python3 scripts/main/plot_application_note_merged_figures.py \
  data/main_figures \
  manuscript/bioinformatics_application_note/figures
```

Figure 2c–d reads the completed batch comparison from
`data/parallel_demo/parallel_demo_completed.csv` and the peak-process memory
from `data/parallel_demo/parallel_demo.csv`.

## Versions cited

- Benchmark research source: RustyClean commit `7ab1a4b`.
- No-recheck arm: three replicates per dataset, run on HPC2021; summary in `runs/deacon_auto_norecheck/metrics/summary.csv` in the paper repository.
- Streamlined AUTO interface: RustyClean commit `55f93af`.

## Rebuild commands

```bash
pandoc manuscript/bioinformatics_application_note/RustyClean_Application_Note.md \
  --from=markdown+pipe_tables+implicit_figures+subscript+superscript \
  --to=docx --standalone \
  --resource-path=manuscript/bioinformatics_application_note \
  --output=manuscript/bioinformatics_application_note/RustyClean_Application_Note.docx

pandoc manuscript/bioinformatics_application_note/RustyClean_Application_Note.md \
  --from=markdown+pipe_tables+implicit_figures+subscript+superscript \
  --to=html5 --standalone --embed-resources \
  --css=assets/application_note.css \
  --resource-path=manuscript/bioinformatics_application_note \
  --output=manuscript/bioinformatics_application_note/RustyClean_Application_Note.html

"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless \
  --disable-gpu --no-pdf-header-footer \
  --print-to-pdf=manuscript/bioinformatics_application_note/RustyClean_Application_Note.pdf \
  "file://$PWD/manuscript/bioinformatics_application_note/RustyClean_Application_Note.html"
```
