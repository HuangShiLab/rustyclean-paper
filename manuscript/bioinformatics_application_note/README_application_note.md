# Bioinformatics Application Note package

This directory contains a concise Bioinformatics-style Application Note for RustyClean. It is independent of the longer bioRxiv-ready benchmark manuscript and is suitable when the target article type is an Application Note rather than a full paper.

## Files

- `RustyClean_Application_Note.md` — Application Note source.
- `RustyClean_Application_Note.docx` — editable submission manuscript.
- `RustyClean_Application_Note.html` — standalone print source.
- `RustyClean_Application_Note.pdf` — formatted Application Note.
- `figures/` — runtime and memory figure in PNG, PDF and SVG.
- `source_data/` — exact CSV summary data underlying Figure 1.
- `assets/application_note.css` — formatting used for the PDF.
- `RustyClean_Application_Note_package.zip` — assembled submission package.

## Format checks

- Application Note label included above the author block.
- Structured abstract: Summary, Availability and implementation, Supplementary information, Contact.
- Abstract: 137 words including headings, excluding URLs.
- Total length: 846 words including references.
- Rendered PDF: 3 pages, within the 4-page Application Note limit.
- One figure and one compact table.
- Alphabetical author-year references; only cited references retained.
- No placeholders remaining.
- Host carry-over uses retained host reads divided by total retained output.

## Versions cited

- Benchmark research source: RustyClean commit `7ab1a4b`.
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
