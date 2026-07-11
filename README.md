# The Synapse Cookbook

📖 Read online at **[yoctobyte.github.io/synapse-cookbook](https://yoctobyte.github.io/synapse-cookbook/)** · download the [PDF](synapsecookbook.pdf) (~144 pp) · or browse the [contents](SUMMARY.md).

Articles and recipes for network programming with the
[Ararat Synapse](https://synapse.ararat.cz/) TCP/IP library for Object Pascal —
socket classes, protocol classes, worked examples, and multithreading tutorials.
The PDF above is a built snapshot (~138 pp); rebuild any time with
[`tools/build-pdf.sh`](tools/build-pdf.sh) — see [BUILDING.md](BUILDING.md) for
the toolchain that produces a clickable, bookmarked PDF.

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

## The book

The cookbook is **ordered, per-folder Markdown** under [`book/`](book/),
assembled into a single document by [`tools/build-pdf.sh`](tools/build-pdf.sh).
Folder and file numeric prefixes define reading order. Start from
**[`SUMMARY.md`](SUMMARY.md)** for the full table of contents.

```
book/
  00-introduction/
  01-architecture/        ★ the heart — why Synapse is shaped as it is
     blocking model & threads · synsock OS seam · SSL plugin · own crypto
  02-socket-classes/      TBlockSocket · TTCP/TUDP/TSocks
  03-protocol-classes/    SMTP · POP3 · IMAP · HTTP · FTP · LDAP · DNS · +survey
  04-mime-messages/       building & parsing MIME mail
  05-serial-ports/        TBlockSerial — the block model over RS-232
  06-encoding-and-crypto/ hashing/HMAC · transfer encodings · charsets
  07-utilities/           synautil · asn1util · IP & host helpers
  08-recipes/             task-oriented: web · email · net tools · serial
  09-visual-synapse/      components & servers built on Synapse
  99-appendix-tutorials/  "Synapse in Two Hours"
```

**Synapse itself is the primary subject.** The architecture section leads,
celebrating the design — one blocking socket for every transport (incl. serial),
the `synsock` cross-platform seam, the link-time TLS plugin (SSL bolted on
mid-stream), and the hand-rolled crypto/encoding with zero external
dependencies. ~40 chapters, all grounded in the upstream `geby/synapse` source.

### Building the document

```sh
tools/build-pdf.sh
```

Dependency-tolerant: always writes a combined `build/synapsecookbook.md`; adds
`build/synapsecookbook.html` if `pandoc` is installed, and
`build/synapsecookbook.pdf` if a LaTeX engine (`xelatex`/`pdflatex`) is present
too.

### Status & roadmap
- [x] Synapse-first architecture section (the design, from the source)
- [x] Socket, protocol, MIME, serial, encoding, utility, and recipe chapters
- [x] "Synapse in Two Hours" tutorial
- [x] Dependency-tolerant build (Markdown → HTML/PDF)
- [ ] Verify every code example compiles against current FPC + Ararat Synapse
- [ ] Fill remaining gaps from the recovered 0.1 text; optional synacrypt/IMAP-depth chapters

## Related

- [Ararat Synapse](https://synapse.ararat.cz/) · [geby/synapse](https://github.com/geby/synapse) — the library this teaches (© Lukas Gebauer)
- [Visual Synapse](https://github.com/yoctobyte/visualsynapse) — components & servers implemented on Synapse

## Provenance & authenticity

The recovered 0.1 material is human-written history; the modern revived chapters
are **largely AI-generated** from the upstream source, after two decades of
neglect. No edition is authenticated — one physical copy will be, and only once
**Lukas Gebauer** signs it by hand, in person. See [`NOTES.md`](NOTES.md).

## License

Released to the public domain under **[CC0 1.0](LICENSE)** — no rights reserved,
use it for anything. Credit for **Ararat Synapse itself belongs to Lukas
Gebauer**; this cookbook only teaches its use.
