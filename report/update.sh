#!/bin/bash
# =============================================================================
# Regenerate the status report end to end
# =============================================================================
#   bash report/update.sh
#
# Charts are redrawn from the current CSVs, embedded into the report, and the
# PDF is re-rendered. Run this after new results land so the figures and the PDF
# never drift from the measurements they describe.
#
# The prose — stage statuses, the readings under each table, the open items —
# is written by hand in rustyclean-status.html and is NOT touched here. Only
# the figures and the PDF are rebuilt.
# =============================================================================

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$DIR")"

echo "1/3  Redrawing figures from the CSVs"
python3 "$DIR/make_charts.py" "$REPO"

echo "2/3  Embedding them in the report"
python3 "$DIR/embed_charts.py"

echo "3/3  Rendering the PDF"
bash "$DIR/build_pdf.sh"
