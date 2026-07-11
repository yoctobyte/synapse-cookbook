# Synapse Protocol Classes

Above the socket layer sits the part of Synapse most people actually reach for:
the protocol clients. SMTP, POP3, IMAP, HTTP, FTP, NNTP, LDAP, SNMP, SNTP, DNS,
ping, telnet — each is a small, readable class that speaks one protocol over a
`TTCPBlockSocket`. There is no framework here, no plugin registry, no visual
component to drop on a form. There is a class, you set a few properties, you call
a few methods in order, and you read the result. That is the whole story, and it
is the same story for every protocol in the list.

## One shape, repeated

Almost every client descends from a single tiny base class, `TSynaClient`
(defined in `blcksock`). It contributes nothing protocol-specific — just the
connection knobs every client needs:

```pascal
TSynaClient = class(TObject)
published
  property TargetHost: string;   // server IP or name  (default 'localhost')
  property TargetPort: string;   // server port        (client sets its default)
  property IPInterface: string;  // outgoing local address
  property Timeout: integer;     // socket timeout, ms
  property UserName: string;      // auth, if the protocol needs it
  property Password: string;
  property OAuth2Token: string;
end;
```

A concrete client — `TPOP3Send`, `TSMTPSend`, `TLDAPSend`, and the rest — then
owns a `TTCPBlockSocket` (exposed as the `Sock` property) and adds the verbs of
its protocol. The constructor picks the standard port for you, so you usually
only need to set `TargetHost`, maybe `UserName`/`Password`, and go. The socket
is created and freed with the client; you never manage it directly, though `Sock`
is right there when you want to attach an `OnStatus` hook or tune a timeout.

## The request/response rhythm

The clients are *blocking* by design (see
[The blocking model](../01-architecture/01-blocking-and-threads.md)). That makes
their internals a linear script rather than a state machine, and it makes the
public API read the same way. The pattern, across protocols, is:

1. **`Login`** — connect the socket, do the protocol greeting/handshake, and (if
   you supplied credentials) authenticate. Returns `Boolean`.
2. **Issue verbs** — `Stat`, `Retr`, `MailFrom`, `Search`, `HTTPMethod`… each
   sends a command, blocks for the reply, and returns `True`/`False`.
3. **Read the result** — most clients expose `ResultCode` / `ResultString` for
   the last reply, plus a protocol-appropriate payload holder (`FullResult`,
   `Document`, `SearchResult`, …).
4. **`Logout`** — send the protocol's goodbye and close the socket.

Because each verb blocks until its reply lands, you never poll and you never
register a callback. Concurrency, when you want it, is "run the client on another
thread" — nothing in the class needs to change.

## TLS drops in from the side

None of these clients contain any TLS code. Encryption is supplied by the
[SSL plugin seam](../01-architecture/03-ssl-plugin-seam.md): you add one
`ssl_*` unit to your `uses` clause and the global `SSLImplementation`
metaclass is swapped for a real backend.

```pascal
uses
  smtpsend, ssl_openssl;   // that one extra unit is the entire TLS wiring
```

With a plugin present, two idioms cover almost everything:

- **Implicit TLS (tunnel from the first byte).** Set `FullSSL := True` before
  `Login`. The socket does its TLS handshake immediately on connect — this is the
  "SSL on a dedicated port" style (POP3S :995, SMTPS :465, IMAPS :993, HTTPS
  :443, LDAPS :636).
- **Explicit TLS (STARTTLS-style upgrade).** Set `AutoTLS := True` and `Login`
  will, if the server advertises the capability, upgrade the *live* plaintext
  connection to TLS mid-session (POP3 `STLS`, SMTP/LDAP `STARTTLS`). Each client
  that supports it also exposes a public `StartTLS` method if you want to drive
  the upgrade yourself.

`HTTPS` is even quieter: `THTTPSend` upgrades automatically when the URL scheme
is `https://`, so a plugin in `uses` is all it takes.

## The clients

All of these live in `/home/rene/pastella-archive/synapse-upstream/` (one unit
per protocol). Ports are the defaults each client's constructor sets.

| Protocol | Unit | Class | Default port | Notes |
|----------|------|-------|:------------:|-------|
| SMTP / ESMTP | `smtpsend` | `TSMTPSend` | 25 | STARTTLS, CRAM-MD5/PLAIN/LOGIN auth · [chapter](03-tsmtpsend.md) |
| POP3 | `pop3send` | `TPOP3Send` | 110 | APOP, STLS, XOAUTH2 · [chapter](01-tpop3send.md) |
| IMAP4 | `imapsend` | `TIMAPSend` | 143 | full mailbox client |
| HTTP / HTTPS | `httpsend` | `THTTPSend` | 80 | convenience `HttpGetText` etc. · [chapter](04-thttpsend.md) |
| FTP | `ftpsend` | `TFTPSend` | 21 | active/passive data connections |
| NNTP | `nntpsend` | `TNNTPSend` | 119 | Usenet news |
| LDAP v2/v3 | `ldapsend` | `TLDAPSend` | 389 | bind/search, SASL DIGEST-MD5 · [chapter](02-ldap.md) |
| SNMP | `snmpsend` | `TSNMPSend` | 161 | plus traps on 162 |
| SNTP | `sntpsend` | `TSNTPSend` | 123 | network time |
| DNS | `dnssend` | `TDNSSend` | 53 | resolver client |
| Ping | `pingsend` | `TPINGSend` | — | ICMP echo (raw socket) |
| Telnet | `tlntsend` | `TTelnetSend` | 23 | terminal session |
| Syslog | `slogsend` | `TSyslogSend` | 514 | RFC-3164 logging (UDP) |
| ClamAV | `clamsend` | `TClamSend` | 3310 | virus-scan daemon client |

The chapters that follow work through five of these in detail — POP3, LDAP,
SMTP, and HTTP — but once you have read one, the others hold no surprises. Learn
the rhythm once; it repeats all the way down the table.
</content>
</invoke>
