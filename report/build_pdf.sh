#!/bin/bash
# =============================================================================
# Render the status report to PDF
# =============================================================================
#   bash report/build_pdf.sh
#
# report/rustyclean-status.html is the same file published as the Artifact, and
# an Artifact is a fragment: the host wraps it in <!doctype html><head><body> at
# publish time. Printing it directly would render an unstyled fragment, so this
# script wraps it, adds a print stylesheet, and renders with headless Chrome —
# the only renderer here that handles the inline SVG, the CSS custom properties
# and the webfonts together.
# =============================================================================

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/rustyclean-status.html"
OUT="$DIR/RustyClean_测试报告.pdf"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[ -f "$SRC" ] || { echo "ERROR: not found: $SRC" >&2; exit 1; }

CHROME=""
for c in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
         "/Applications/Chromium.app/Contents/MacOS/Chromium" \
         "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" \
         "$(command -v google-chrome || true)" \
         "$(command -v chromium || true)"; do
    [ -n "$c" ] && [ -x "$c" ] && { CHROME="$c"; break; }
done
[ -n "$CHROME" ] || { echo "ERROR: no Chrome/Chromium found for PDF rendering." >&2; exit 1; }

# The print sheet pins the light palette — a PDF has no viewer theme, and the
# dark tokens would otherwise win whenever the renderer reports a dark OS — and
# keeps figures, tables and stage cards from splitting across a page break.
cat > "$WORK/page.html" <<'HTMLEOF'
<!doctype html>
<html lang="zh-CN" data-theme="light">
<head>
<meta charset="utf-8">
<style>
  @page { size: A4 landscape; margin: 12mm 14mm; }
  html, body { background: #FFFFFF !important; }
  .wrap { max-width: 100% !important; padding: 0 !important; gap: 30px !important; }
  figure, .stage, .flag, .scroll, .tally { break-inside: avoid; page-break-inside: avoid; }
  section { break-inside: auto; }
  h1, h2, h3 { break-after: avoid; page-break-after: avoid; }
  table { font-size: 11px !important; }
  th, td { padding: 5px 8px !important; }
  figure svg { min-width: 0 !important; }
  .scroll { overflow-x: visible !important; }
  * { -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }
</style>
</head>
<body>
HTMLEOF
cat "$SRC" >> "$WORK/page.html"
printf '\n</body>\n</html>\n' >> "$WORK/page.html"

echo "Rendering with: $(basename "$CHROME")"
"$CHROME" --headless=new --disable-gpu --no-sandbox \
    --no-pdf-header-footer \
    --virtual-time-budget=20000 \
    --print-to-pdf="$OUT" \
    "file://$WORK/page.html" >/dev/null 2>&1

[ -s "$OUT" ] || { echo "ERROR: no PDF was produced." >&2; exit 1; }
echo "Wrote $OUT ($(du -h "$OUT" | cut -f1))"
