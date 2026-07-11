# The Utility Units

Under every Synapse protocol class sits a thin layer of plain functions — no
objects, no state, just helpers that the protocol code (and you) call directly.
They are the parts of Synapse you end up reaching for even when you never open a
socket: split a header line, format an RFC-822 date, validate an IP address,
encode an ASN.1 packet, ask the OS which DNS server it uses.

This chapter covers the four units that make up that layer:

| Unit           | What it is for                                                        |
|----------------|-----------------------------------------------------------------------|
| `synautil.pas` | The general toolbox: string splitting, date/time, hex/binary, headers |
| `asn1util.pas` | BER/DER encode & decode — the bytes under LDAP and SNMP               |
| `synaip.pas`   | IP-address parsing and formatting (IPv4 and IPv6)                     |
| `synamisc.pas` | Host/system info: DNS servers, local IPs, proxy settings, Wake-on-LAN |

## How they fit together

None of these units depend on a socket. `synautil` depends on nothing but the
RTL; `synaip` uses `synautil`; `asn1util` is self-contained; `synamisc` reaches
into the OS. That independence is the point — the protocol classes are built
*on top* of these functions, so anything a protocol can do to a string or an
address, you can do too, in isolation, without instantiating anything.

- **`synautil` is the workhorse.** Almost every other unit in Synapse uses it.
  When you parse a MIME header, decode a `Date:` field, or `Fetch` tokens off a
  server response, you are calling `synautil`. It is the one to learn first.
- **`asn1util` is a translation layer.** ASN.1 BER is how LDAP and SNMP put
  structured data on the wire. The unit is small — a handful of `ASNEnc*` /
  `ASNItem` functions — because BER itself is a small, recursive grammar. You
  rarely call it directly (the LDAP and SNMP classes do), but understanding it
  demystifies both protocols.
- **`synaip` is pure conversion.** No I/O — it turns `'192.168.0.1'` into an
  integer and back, validates addresses, expands short-form IPv6. It never
  resolves a name (that is DNS, and lives elsewhere); `IsIP` explicitly rejects
  symbolic names.
- **`synamisc` asks the operating system questions.** Its answers (the system's
  DNS servers, every local IP, the configured proxy) come from Windows registry
  / IP Helper calls or from `/etc/resolv.conf`-style probing on POSIX, so the
  same function name returns platform-specific truth.

## A note on strings

Everything here works with `AnsiString` — byte strings, not UTF-16. Synapse
treats the wire as bytes and these helpers do too: `StrToHex`, `ASNObject`,
`IPToID`, and the `Fetch` family all move raw octets. That is deliberate and it
is why the same code compiles on FPC and every Delphi from 7 up.

The rest of the chapter: [the `synautil` toolbox](01-synautil.md),
[ASN.1 with `asn1util`](02-asn1util.md), and
[IP and host helpers](03-ip-and-host.md).
