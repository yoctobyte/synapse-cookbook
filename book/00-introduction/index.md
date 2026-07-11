# Introduction

*The Synapse Cookbook — various articles about programming using the Synapse
TCP/IP library for Object Pascal. Originated from the Synapse cookbook wiki.*

Most of this document was originally extracted from the Wayback Machine after an
unfortunate miscommunication with the hosting — the maintainer takes the blame.
The wiki experience taught a lesson: better not to run a wiki, or make sure it
sends email alerts on any change. A wiki is also hard to organize — any index
just becomes another wiki page. At least this document has a beginning and an
(open) end.

Version 0.1 was a quick release to make sure a document existed at all; not all
content was re-edited or checked for sanity. Beginners may want to start at the
**Appendix — Tutorials**: *"Synapse in two hours"* shows elementary code and
gives a kickstart in writing multi-threaded applications.

> **Status (2026 revival):** this Markdown edition is being migrated,
> section-by-section, from the recovered 0.1 PDF text
> (`releases/synapsecookbook-0.1.txt`). Code examples are to be re-verified
> against current FPC + Ararat Synapse.

## About Synapse

[Ararat Synapse](https://synapse.ararat.cz/) is a lightweight, blocking (and
optionally non-blocking) TCP/IP library for Object Pascal — Delphi, Kylix, and
Free Pascal / Lazarus — by Lukas Gebauer. It provides socket classes and a range
of client protocol implementations without visual components or external
dependencies. This cookbook teaches how to use it.
