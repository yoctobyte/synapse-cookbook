#!/usr/bin/env bash
# Assemble the ordered book/ Markdown into a single document.
#
# Reading order = lexical order of paths, so numeric prefixes on folders and
# files (00-, 01-, ...) define the sequence.
#
# This script is dependency-tolerant:
#   * ALWAYS produces build/synapsecookbook.md  (concatenated, no deps)
#   * if `pandoc` is present: also build/synapsecookbook.html (no LaTeX needed)
#   * if `pandoc` + a LaTeX engine: also build/synapsecookbook.pdf
#
# Usage: tools/build-pdf.sh
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p build
mapfile -t files < <(find book -name '*.md' | sort)
if [ "${#files[@]}" -eq 0 ]; then
  echo "no markdown found under book/"; exit 1
fi
echo "found ${#files[@]} chapters"

# 1. Always: concatenate into one Markdown file (pure shell, zero deps).
combined="build/synapsecookbook.md"
{
  echo "% The Synapse Cookbook"
  echo "% Community (CC0). Ararat Synapse by Lukas Gebauer."
  echo
} > "$combined"
for f in "${files[@]}"; do
  cat "$f" >> "$combined"
  printf '\n\n---\n\n' >> "$combined"
done
echo "wrote $combined ($(wc -l < "$combined") lines)"

# 2. If pandoc is available, build HTML (self-contained, no LaTeX required).
if command -v pandoc >/dev/null 2>&1; then
  pandoc "$combined" --standalone --toc --toc-depth=3 \
    --metadata title="The Synapse Cookbook" \
    -o build/synapsecookbook.html
  echo "wrote build/synapsecookbook.html"

  # 3. PDF. Prefer a Unicode-native LaTeX engine (xelatex/lualatex) for best
  #    typography; the doc uses ★ · → and box-drawing, so pdflatex is unsuitable.
  #    Fall back to headless Chrome on any LaTeX failure — it renders the HTML
  #    and handles all Unicode. Result: a PDF is produced whenever possible.
  rm -f build/synapsecookbook.pdf
  uni_engine=""
  for e in lualatex xelatex; do command -v "$e" >/dev/null 2>&1 && { uni_engine="$e"; break; }; done
  if [ -n "$uni_engine" ]; then
    # DejaVu covers the ★ · → and box-drawing glyphs; hyperref/colorlinks give a
    # clickable TOC + PDF bookmarks. Requires: lmodern + texlive-fonts-recommended
    # (base metrics) and texlive-latex-recommended (hyperref). See BUILDING.md.
    if pandoc "$combined" --pdf-engine="$uni_engine" --toc --toc-depth=3 \
        --metadata title="The Synapse Cookbook" \
        -V documentclass=report -V geometry:margin=1in \
        -V mainfont="DejaVu Serif" -V monofont="DejaVu Sans Mono" -V sansfont="DejaVu Sans" \
        -V colorlinks=true -V linkcolor=blue -V toccolor=blue -V urlcolor=blue \
        -o build/synapsecookbook.pdf 2>build/pdf-latex.log; then
      echo "wrote build/synapsecookbook.pdf (via $uni_engine — clickable TOC + bookmarks)"
    else
      echo "note: $uni_engine failed (see build/pdf-latex.log — often missing"
      echo "      fonts: install 'lmodern texlive-fonts-recommended'). Falling back to Chrome."
    fi
  fi
  if [ ! -s build/synapsecookbook.pdf ]; then
    chrome=""
    for c in google-chrome chromium chromium-browser; do
      command -v "$c" >/dev/null 2>&1 && { chrome="$c"; break; }
    done
    if [ -n "$chrome" ]; then
      "$chrome" --headless=new --disable-gpu --no-sandbox \
        --virtual-time-budget=30000 --run-all-compositor-stages-before-draw \
        --print-to-pdf=build/synapsecookbook.pdf --print-to-pdf-no-header \
        "file://$PWD/build/synapsecookbook.html" >/dev/null 2>&1
      [ -s build/synapsecookbook.pdf ] \
        && echo "wrote build/synapsecookbook.pdf (via $chrome)" \
        || echo "note: Chrome PDF render failed — HTML is available."
    else
      echo "note: no working PDF engine — build/synapsecookbook.html is available."
    fi
  fi
else
  echo "note: pandoc not found — produced the combined Markdown only."
  echo "      install 'pandoc' (+ a LaTeX engine) for HTML/PDF output."
fi
echo "done."
