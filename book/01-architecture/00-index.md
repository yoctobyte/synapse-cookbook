# The Architecture of Synapse

Before the recipes, the design — because Synapse's design is the reason the
recipes are so short. Ararat Synapse is a masterclass in doing a great deal with
very little: no visual components, no framework, no external runtime, and (for
the essentials) no external libraries at all. Just Object Pascal, a clean set of
classes, and a few genuinely clever seams.

It was written in an era when **`async` did not exist** as a language feature and
preemptive **timeslicing was still being researched and proven**. Synapse's
answer was not to wait for the future — it was to build a *blocking* socket
library with precise timeouts, designed from the start to be driven by threads.
That decision aged remarkably well: the code is linear and readable (no callback
spaghetti, no state machines), and concurrency is just "run another thread."

Four ideas carry the whole library:

1. **One blocking socket, every transport.** `TBlockSocket` and its descendants
   put TCP, UDP, raw IP — and even **serial ports** — behind a single blocking,
   timeout-driven API. Learn one class, use them all. → *[Blocking model &
   threads](01-blocking-and-threads.md)*

2. **A thin OS seam.** `synsock` isolates every platform difference (Winsock,
   Unix libc, Windows CE) behind one internal interface, so the socket classes
   above it are written **once** and compile everywhere. → *[Cross-platform:
   synsock](02-cross-platform-synsock.md)*

3. **TLS as a swappable plugin, bolted on mid-stream.** SSL/TLS is *not* baked
   into the socket. A single global metaclass (`SSLImplementation`) is overridden
   simply by which `ssl_*` unit you place in `uses`. Any block socket can be
   upgraded to TLS on a live connection (STARTTLS-style). This is the library's
   most elegant hack. → *[The SSL plugin seam](03-ssl-plugin-seam.md)*

4. **Batteries included, dependencies excluded.** MD5, MD4, SHA-1, HMAC, Base64,
   quoted-printable, DES/3DES — all **hand-rolled** in `synacode`/`synacrypt`, so
   authentication and encoding work with zero external libraries. → *[Rolling its
   own crypto](04-own-crypto.md)*

On top of those four seams sit the protocol clients — SMTP, POP3, IMAP, HTTP,
FTP, NNTP, LDAP, SNMP, SNTP, DNS, ping, telnet — each a thin, readable class that
speaks its protocol over a `TBlockSocket`. That is the whole shape of the
library: **thin, orthogonal layers, each doing one thing well.** Once you see the
seams, the rest of this cookbook is just usage.

> **Why celebrate the architecture at all?** Because it teaches transferable
> design: push platform differences down into a seam, express optional features
> (TLS) as pluggable metaclasses instead of flags, keep the I/O model simple
> (blocking + threads) and let the OS scheduler do the hard part. These lessons
> outlive Object Pascal.
