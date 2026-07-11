# Building the cookbook

The book is ordered Markdown under [`book/`](book/). One script assembles it:

```sh
tools/build-pdf.sh
```

It is **dependency-tolerant** — it always produces the combined Markdown, and adds
HTML/PDF when the tools are available:

| Output | Requires |
|--------|----------|
| `build/synapsecookbook.md` | nothing (pure shell) |
| `build/synapsecookbook.html` | `pandoc` |
| `build/synapsecookbook.pdf` | see below |

## PDF: getting a *proper* one (clickable TOC + bookmarks)

A good PDF has a **clickable table of contents and PDF bookmarks/outline** (so it
navigates under GitHub's viewer and any reader). That requires a LaTeX build via
`hyperref` — a browser "print to PDF" does **not** produce clickable internal
links.

The book uses `★ · →` and box-drawing characters, so it needs a **Unicode-native
engine** (`lualatex`/`xelatex`, not `pdflatex`) plus a font that has those glyphs
(**DejaVu**, which the script selects via `fontspec`).

### Install (Debian/Ubuntu)

```sh
sudo apt install texlive-luatex texlive-latex-recommended texlive-fonts-recommended lmodern
```

- `texlive-luatex` — the `lualatex` engine (Unicode-native).
- `texlive-latex-recommended` — `hyperref` (clickable TOC + bookmarks), `geometry`.
- `texlive-fonts-recommended` + `lmodern` — base font metrics; without them
  lualatex fails with `lmroman ... metric data not found` before `fontspec` can
  load DejaVu.
- DejaVu fonts are normally already present (via `fonts-dejavu-core`); install
  `fonts-dejavu` if `fc-list | grep -i dejavu` is empty.

Then:

```sh
tools/build-pdf.sh          # -> build/synapsecookbook.pdf via lualatex
```

### Fallback (no LaTeX)

If no working LaTeX engine is found, the script falls back to headless
**Chrome/Chromium** (`google-chrome --headless --print-to-pdf`) rendering the
HTML. This yields a correct, complete PDF — but its TOC is **not clickable** and
it has no bookmarks. Use the LaTeX path for the real thing.

## The committed PDF

A built snapshot lives at the repo root as
[`synapsecookbook.pdf`](synapsecookbook.pdf) so the README can link it directly.
Rebuild and re-commit it after substantive content changes:

```sh
tools/build-pdf.sh && cp build/synapsecookbook.pdf ./synapsecookbook.pdf
```

`build/` itself is git-ignored; only the root snapshot is tracked.
