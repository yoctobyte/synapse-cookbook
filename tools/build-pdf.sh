#!/usr/bin/env bash
# Assemble the ordered book/ Markdown into a single PDF.
#
# Reading order = lexical order of paths, so numeric prefixes on folders and
# files (00-, 01-, ...) define the sequence. Requires pandoc + a LaTeX engine
# (e.g. texlive-xetex).
#
# Usage: tools/build-pdf.sh [output.pdf]
set -euo pipefail
cd "$(dirname "$0")/.."

out="${1:-build/synapsecookbook.pdf}"
mkdir -p "$(dirname "$out")"

mapfile -t files < <(find book -name '*.md' | sort)
if [ "${#files[@]}" -eq 0 ]; then
  echo "no markdown found under book/"; exit 1
fi

echo "assembling ${#files[@]} files -> $out"
pandoc "${files[@]}" \
  --metadata title="The Synapse Cookbook" \
  --metadata author="Community (CC0). Ararat Synapse by Lukas Gebauer." \
  --toc --toc-depth=3 \
  -V documentclass=report \
  -o "$out"
echo "done: $out"
