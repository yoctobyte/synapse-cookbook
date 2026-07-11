# Recipes

This is the section you copy from. Each recipe is a **single common task** —
download a file, send a mail, resolve a hostname — answered with a minimal but
complete `pascal` snippet you can drop into a program, compile, and adjust. No
narrative build-up; just problem, code, and the one gotcha that bites people.

## How to use this section

- **Each recipe is self-contained.** The snippet names every unit it needs in
  `uses` and checks status the Synapse way (`LastError` / a `Boolean` result /
  `ResultCode`). Paste it, change the host and data, compile.
- **HTTPS/TLS is a `uses` line.** Wherever a recipe talks to an `https://` URL or
  a TLS mail server, add `ssl_openssl` (or `ssl_openssl3`) to `uses` — that one
  line registers the SSL plugin globally and nothing else in the code changes.
  See [the SSL plugin seam](../01-architecture/03-ssl-plugin-seam.md).
- **Snippets are trimmed for clarity.** Error handling is shown once per pattern,
  not belt-and-braces on every line. For the *why* behind a class, and its full
  property surface, follow the cross-link to its chapter.
- **The Synapse rhythm.** Create the object, call one method, check status, read
  the results off properties, free the object. Every recipe is a variation on
  that.

## The recipes

**[Web](01-web.md)** — HTTP with `THTTPSend` and the `httpsend` one-liners.
- Download a URL to a file
- POST form data
- Fetch JSON over HTTPS

**[Email](02-email.md)** — sending with `TSMTPSend`/`TMimeMess`, reading with `TPOP3Send`.
- Send a plain-text mail
- Send a mail with a file attachment
- Fetch and list an inbox

**[Network tools](03-network-tools.md)** — DNS, ICMP, and raw sockets.
- Resolve a hostname (`TDNSSend`)
- Ping a host (`TPINGSend` / `PingHost`)
- A minimal TCP client and a threaded echo server

**[Serial](04-serial.md)** — talking to a serial port with `TBlockSerial`.
- Open a port and do a request/response

## Where the depth lives

These recipes are the fast path. When you need the full API — headers, cookies,
keep-alive, streaming receives, the blocking model — the chapters have it:

- [HTTP — THTTPSend](../03-protocol-classes/04-thttpsend.md)
- [SMTP — TSMTPSend](../03-protocol-classes/03-tsmtpsend.md)
- [POP3 — TPOP3Send](../03-protocol-classes/01-tpop3send.md)
- [MIME messages](../04-mime-messages/00-index.md)
- [Socket classes](../02-socket-classes/00-index.md)
- [Serial ports](../05-serial-ports/)
- [Synapse in Two Hours](../99-appendix-tutorials/synapse-in-two-hours.md) — the guided on-ramp
