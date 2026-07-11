# The Synapse Cookbook

Articles and recipes for network programming with the
[Ararat Synapse](https://synapse.ararat.cz/) TCP/IP library for Object Pascal —
socket classes, protocol classes, worked examples, and multithreading tutorials.

> Community teaching material about Ararat Synapse — **not** official upstream
> documentation. Ararat Synapse is by **Lukas Gebauer**, now on GitHub at
> [geby/synapse](https://github.com/geby/synapse). All credit for the library
> belongs there.

## What this is

A cookbook that teaches Synapse (and, through it, practical network programming):
`TBlockSocket` / `TTCPBlockSocket` / `TUDPBlockSocket` / `TSocksBlockSocket`, the
protocol classes (POP3, LDAP, …), a Visual Synapse section, and Appendix
tutorials including *"Synapse in two hours"* — an elementary-code kickstart into
multi-threaded applications.

## History

Originally a community wiki (version 0.1, Creative-Commons licensed) that went
offline. **Version 0.1 — the only release ever published — was reconstructed
from the Internet Archive** and is preserved here verbatim under
[`releases/`](releases/), with landing-page snapshots (2006 and 2019) alongside.

Moved to GitHub and revived in **2026** as living documentation. This is
maintained for the community, for the future — no ownership is claimed over it.

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
  01-architecture/        ★ the heart — why Synapse is shaped as it is
     blocking model & threads · synsock OS seam · SSL plugin · own crypto
  02-socket-classes/      TBlockSocket, TTCPBlockSocket, TUDPBlockSocket, TSocksBlockSocket
  03-protocol-classes/    TPOP3Send, LDAP, …
  04-visual-synapse/
  99-appendix-tutorials/  "Synapse in two hours", multithreading
```

**Synapse itself is the primary subject.** The architecture section leads,
celebrating the design — one blocking socket for every transport (incl. serial),
the `synsock` cross-platform seam, the link-time TLS plugin (SSL bolted on
mid-stream), and the hand-rolled crypto/encoding with zero external
dependencies.

### Roadmap
- [ ] Migrate each 0.1 section from the recovered text into structured Markdown
- [ ] Verify every code example compiles against current FPC + Ararat Synapse
- [ ] Fill the gaps the 0.1 wiki left incomplete
- [ ] `build-pdf.sh` → reproducible PDF from the ordered Markdown (pandoc)

## Related

- [Ararat Synapse](https://synapse.ararat.cz/) · [geby/synapse](https://github.com/geby/synapse) — the library this teaches (© Lukas Gebauer)
- [Visual Synapse](https://github.com/yoctobyte/visualsynapse) — component/server superset built on Synapse

## Provenance & authenticity

The recovered 0.1 material is human-written history; the modern revived chapters
are **largely AI-generated** from the upstream source, after two decades of
neglect. No edition is authenticated — one physical copy will be, and only once
**Lukas Gebauer** signs it by hand, in person. See [`NOTES.md`](NOTES.md).

## License

Released to the public domain under **[CC0 1.0](LICENSE)** — no rights reserved,
use it for anything. Credit for **Ararat Synapse itself belongs to Lukas
Gebauer**; this cookbook only teaches its use.
