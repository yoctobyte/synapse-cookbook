# Introduction

*The Synapse Cookbook — articles about network programming with the Ararat
Synapse TCP/IP library for Object Pascal.*

This cookbook began as a community wiki that later went offline; version 0.1 was
reconstructed from the Internet Archive. It was always meant as a practical,
example-first companion to the library — not a formal reference.

Brand new to this? Start with **[Getting Started](01-getting-started.md)** — it
assumes no networking knowledge and has you talking to the internet in a few
minutes. From there, the **Appendix — [Synapse in Two Hours](../99-appendix-tutorials/synapse-in-two-hours.md)**
goes deeper (HTTP, a threaded server, TLS). Readers who want to understand *why*
the library is shaped the way it is should read **[The Architecture of
Synapse](../01-architecture/00-index.md)** — it is the heart of this cookbook,
and the reason the recipes are so short.

> **Status (2026 revival):** this Markdown edition is being migrated,
> section-by-section, from the recovered 0.1 text
> (`releases/synapsecookbook-0.1.txt`). Code examples are to be re-verified
> against current FPC + Ararat Synapse.

## About Synapse

[Ararat Synapse](https://synapse.ararat.cz/) is a lightweight, blocking (and
optionally non-blocking) TCP/IP library for Object Pascal — Delphi, Kylix, and
Free Pascal / Lazarus — by **Lukas Gebauer**. It provides socket classes and a
range of client protocol implementations without visual components or external
dependencies. This cookbook teaches how to use it; all credit for the library
belongs to its author.
