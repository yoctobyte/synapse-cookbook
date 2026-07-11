# Visual Synapse

Where Synapse gives you socket classes and protocol *clients*, **Visual Synapse**
is one project *implemented on* Synapse that provides two things Synapse itself
does not: **RAD components** and **protocol servers**. It is not an extension of
Synapse — just an application of it. It is a separate project; this chapter
explains how it relates to the library the rest of this cookbook covers.

> **Live project:** <https://github.com/yoctobyte/visualsynapse>

## What it adds over raw Synapse

1. **RAD components.** Thin, drop-on-form wrappers around Synapse's client
   protocols (HTTP, UDP, DNS, ICMP, TCP, SMTP), with Object-Inspector-editable
   properties and event callbacks. Commands run on a background thread and a
   callback fires per result — the [blocking-plus-threads
   model](../01-architecture/01-blocking-and-threads.md) packaged as visual
   components.

2. **Servers.** Synapse ships clients; Visual Synapse adds hand-written protocol
   *server* implementations — HTTP, FTP, SMTP, telnet, and a SQL server
   component. Each is a listener that accepts connections and hands every one to
   its own handler thread, speaking the protocol in straight-line code over a
   `TTCPBlockSocket` — exactly the pattern the architecture section describes.

It also historically carried **`TPastella`**, an experimental content-addressed
peer-to-peer gossip layer built on the same socket foundation.

## How it uses Synapse

Visual Synapse depends on Synapse; it does not replace it. The components and
servers are built *on* `TBlockSocket` and friends, and they inherit Synapse's
seams for free — including the [SSL plugin](../01-architecture/03-ssl-plugin-seam.md):
a Visual Synapse server gains TLS the same way any Synapse socket does, by which
`ssl_*` unit is in `uses`.

## Status & caveats

Visual Synapse is a 2004–2008 project, revived for preservation. Treat its
servers as historical: the 0.60 HTTP server has a known, unpatched
directory-traversal, and the code predates modern transport hardening. See the
project's own `SECURITY.md` before running anything. For learning the underlying
library, the rest of this cookbook — grounded directly in Synapse — is the better
guide; this chapter exists to place Visual Synapse in the map.
