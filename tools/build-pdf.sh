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

  # 3. If a LaTeX engine is present, build the PDF too.
  if command -v xelatex >/dev/null 2>&1 || command -v pdflatex >/dev/null 2>&1; then
    pandoc "$combined" --toc --toc-depth=3 \
      --metadata title="The Synapse Cookbook" \
      -V documentclass=report \
      -o build/synapsecookbook.pdf
    echo "wrote build/synapsecookbook.pdf"
  else
    echo "note: no LaTeX engine (xelatex/pdflatex) — skipped PDF."
    echo "      install e.g. 'texlive-xetex' to get build/synapsecookbook.pdf,"
    echo "      or convert build/synapsecookbook.html to PDF from a browser."
  fi
else
  echo "note: pandoc not found — produced the combined Markdown only."
  echo "      install 'pandoc' (+ a LaTeX engine) for HTML/PDF output."
fi
echo "done."
