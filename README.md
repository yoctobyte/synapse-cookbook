# The Synapse Cookbook

Articles and recipes for network programming with the
[Ararat Synapse](https://synapse.ararat.cz/) TCP/IP library for Object Pascal —
socket classes, protocol classes, worked examples, and multithreading tutorials.

> Community teaching material about Ararat Synapse — **not** official upstream
> documentation. Ararat Synapse itself is by Lukas Gebauer, now on GitHub at
> [geby/synapse](https://github.com/geby/synapse).

## What this is

A cookbook that teaches Synapse (and, through it, practical network programming):
`TBlockSocket` / `TTCPBlockSocket` / `TUDPBlockSocket` / `TSocksBlockSocket`, the
protocol classes (POP3, LDAP, …), a Visual Synapse section, and Appendix
tutorials including *"Synapse in two hours"* — an elementary-code kickstart into
multi-threaded applications.

## History

Originally a wiki at **`dubaron.com/synapsecookbook`**, authored by R.M. Tegel
(`artee`) with various contributors, Creative-Commons licensed. The wiki went
offline after a hosting miscommunication; **version 0.1 — the only release ever
published — was reconstructed from the Internet Archive** and is preserved here
verbatim under [`releases/`](releases/). Landing-page snapshots (2006 and 2019)
are kept alongside.

Migrated to GitHub in **2026**, and the way forward begins (below).

## The way forward

The cookbook is being rebuilt as **ordered, per-folder Markdown** under
[`book/`](book/), assembled into a PDF (and/or site) by
[`tools/build-pdf.sh`](tools/build-pdf.sh). Folder and file numeric prefixes
define reading order. The recovered 0.1 PDF text
([`releases/synapsecookbook-0.1.txt`](releases/synapsecookbook-0.1.txt)) is the
source to migrate section-by-section into clean Markdown.

```
book/
  00-introduction/
  01-socket-classes/      TBlockSocket, TTCPBlockSocket, TUDPBlockSocket, TSocksBlockSocket
  02-protocol-classes/    TPOP3Send, LDAP, …
  03-visual-synapse/
  99-appendix-tutorials/  "Synapse in two hours", multithreading
```

### Roadmap
- [ ] Migrate each 0.1 section from the recovered text into structured Markdown
- [ ] Verify every code example compiles against current FPC + Ararat Synapse
- [ ] Fill the gaps the 0.1 wiki left incomplete
- [ ] `build-pdf.sh` → reproducible PDF from the ordered Markdown (pandoc)

## Related

- [Ararat Synapse](https://synapse.ararat.cz/) · [geby/synapse](https://github.com/geby/synapse) — the library this teaches
- [Visual Synapse](https://github.com/yoctobyte/visualsynapse) — component/server superset (has its own cookbook section here)

## License

Creative Commons (as released with 0.1). Attribution: **R.M. Tegel and various
authors**. See [`LICENSE`](LICENSE).
