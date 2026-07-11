# TDNSSend

DNS is the one protocol client in this chapter that does *not* speak a line-based
request/response conversation over TCP. It is a single binary packet out, a
single binary packet back, over UDP. `TDNSSend` (in `dnssend`) hides all of that
wire encoding behind one method — `DNSQuery` — and hands you back the answers as
plain strings, one resource record per line. There is no `Login`, no `Logout`,
no session: you create the object, point it at a resolver, and ask.

## The class at a glance

Like every client in this chapter, `TDNSSend` descends from `TSynaClient`, so the
connection knobs (`TargetHost`, `TargetPort`, `Timeout`, `IPInterface`) come from
the base. The constructor sets `TargetPort` to `53`. What `TDNSSend` adds is one
query method and a set of read-only result holders:

```pascal
TDNSSend = class(TSynaClient)
  constructor Create;
  destructor Destroy; override;

  {: Query TargetHost for QType records matching Name. Answers land in Reply,
     one record per line; multi-field records are comma-delimited. }
  function DNSQuery(Name: AnsiString; QType: Integer;
    const Reply: TStrings): Boolean;

  property Sock: TUDPBlockSocket;      // the UDP socket (for OnStatus, tuning)
  property TCPSock: TTCPBlockSocket;   // the TCP socket, used only when UseTCP
  property UseTCP: Boolean;            // send over TCP instead of UDP
  property RCode: Integer;             // DNS reply code: 0 ok, 3 name error, ...
  property Authoritative: Boolean;     // answer came from an authoritative server
  property Truncated: Boolean;         // reply was truncated (see "UDP vs TCP")
  property AnswerInfo: TStringList;    // detailed answer-section records
  property NameserverInfo: TStringList;// detailed authority-section records
  property AdditionalInfo: TStringList;// detailed additional-section records
end;
```

The `QType` argument is one of the `QTYPE_*` constants the unit exports. The ones
you will reach for:

| Constant | Value | Record | Asks for |
|----------|:-----:|--------|----------|
| `QTYPE_A` | 1 | A | IPv4 address of a host |
| `QTYPE_NS` | 2 | NS | authoritative name servers for a zone |
| `QTYPE_CNAME` | 5 | CNAME | canonical name (alias target) |
| `QTYPE_SOA` | 6 | SOA | zone start-of-authority |
| `QTYPE_PTR` | 12 | PTR | host name for an address (reverse lookup) |
| `QTYPE_MX` | 15 | MX | mail exchangers for a domain |
| `QTYPE_TXT` | 16 | TXT | free-form text (SPF, verification, …) |
| `QTYPE_AAAA` | 28 | AAAA | IPv6 address of a host |
| `QTYPE_SRV` | 33 | SRV | service location |
| `QTYPE_AXFR` | 252 | — | full zone transfer (**TCP only**) |
| `QTYPE_ALL` | 255 | * | any/all records |

The full list (`QTYPE_MD`, `QTYPE_HINFO`, `QTYPE_KX`, and the rest) is in the
`const` block at the top of `dnssend.pas`.

## How answers are shaped

`DNSQuery` returns `True` when it got a well-formed reply with `RCode = 0`, and
fills `Reply` with the answer records. The encoding is deliberately flat: **one
record per line**, and where a record has several fields they are joined with
commas. An `MX` record with preference `10` for `mail.example.com`, for example,
arrives as the single line:

```
10,mail.example.com
```

An `SRV` record comes back as `priority,weight,port,target`. A and AAAA records
are just the address as text; PTR and CNAME are just the name. Numbers and IP
addresses are always converted to their string form for you — you never decode
raw bytes.

The three `*Info` string lists give you the *detailed* view of the reply's three
sections (answer, authority, additional). Each line there is a comma-delimited
`name,type,ttl,data` tuple, so if you need the TTL or the record type number
alongside the value, read `AnswerInfo` instead of `Reply`.

## Reverse lookups are automatic

You do not build `.in-addr.arpa` names by hand. If the `Name` you pass to
`DNSQuery` is a literal IP address, `TDNSSend` detects that and rewrites it into
the correct reverse-DNS form for you — `1.2.3.4` becomes `4.3.2.1.in-addr.arpa`,
and an IPv6 literal becomes the matching `.ip6.arpa` name. So a PTR lookup is
just "pass the address with `QTYPE_PTR`"; the class does the inversion.

## UDP vs TCP — and the truncation caveat

By default `TDNSSend` sends the query as a **single UDP datagram** and reads a
**single UDP packet** back. That is the right transport for ordinary lookups and
what you almost always want.

Two things push you to TCP:

- **Zone transfers.** `QTYPE_AXFR` streams an entire zone and only works over
  TCP; `DNSQuery` has special multi-packet handling for it, but *only* when
  `UseTCP` is set.
- **Truncated replies.** A UDP answer that overflows is flagged by the server,
  and `TDNSSend` surfaces that in the read-only `Truncated` property.

> **Honest caveat — no automatic TCP fallback.** Unlike a full stub resolver,
> `TDNSSend` does **not** silently retry a truncated UDP answer over TCP. It
> exposes `Truncated` and leaves the decision to you: if you see it set, set
> `UseTCP := True` and call `DNSQuery` again to get the complete reply over the
> TCP socket. `UseTCP` simply switches which socket the query uses; there is no
> hybrid mode.

## Worked example: resolve a host (A record)

```pascal
program DnsA;

uses
  SysUtils, Classes,
  dnssend;

var
  Dns: TDNSSend;
  Reply: TStringList;
  i: Integer;
begin
  Dns := TDNSSend.Create;
  Reply := TStringList.Create;
  try
    Dns.TargetHost := '8.8.8.8';          // any resolver you trust

    if Dns.DNSQuery('www.example.com', QTYPE_A, Reply) then
      for i := 0 to Reply.Count - 1 do
        Writeln('A: ', Reply[i])          // each line is one IPv4 address
    else
      Writeln('query failed, RCode=', Dns.RCode);
  finally
    Reply.Free;
    Dns.Free;
  end;
end.
```

`TargetHost` here is the *resolver* you send the question to (a recursive server
such as your ISP's, `8.8.8.8`, `1.1.1.1`, …), not the host you are asking about.
That distinction is the whole mental model of the class: `TDNSSend` is a DNS
*client* that talks to a *server*; it does not itself walk the delegation tree.

## Worked example: look up mail exchangers (MX)

An MX query returns `preference,hostname` lines, and for real use you want them
tried lowest-preference first. You can sort them yourself, but the unit already
ships a convenience that does exactly that:

```pascal
{: Query DNSHost for the MX records of Domain, and return the mail-server
   host names in Servers, already sorted by preference (best first) and with
   the preference numbers stripped. }
function GetMailServers(const DNSHost, Domain: AnsiString;
  const Servers: TStrings): Boolean;
```

Using it:

```pascal
program MxLookup;

uses
  SysUtils, Classes,
  dnssend;

var
  Servers: TStringList;
  i: Integer;
begin
  Servers := TStringList.Create;
  try
    // DNSHost = resolver to ask; second arg = domain whose mail we want.
    if GetMailServers('8.8.8.8', 'example.com', Servers) then
      for i := 0 to Servers.Count - 1 do
        Writeln(i + 1, '. ', Servers[i])   // already in preference order
    else
      Writeln('no MX records found');
  finally
    Servers.Free;
  end;
end.
```

If you want the raw preference numbers, skip the helper and call
`DNSQuery(Domain, QTYPE_MX, Reply)` directly — each line is then `pref,host`, and
you sort them yourself. `GetMailServers` is just that call plus a
normalise-and-sort pass, and reading its (short) body in `dnssend.pas` is the
best possible tutorial on driving `DNSQuery` for a multi-field record.

## No TLS here

Note what is *absent* from this chapter: there is no `ssl_*` plugin, no
`FullSSL`, no `AutoTLS`. Classic DNS over UDP/53 is unencrypted, and `TDNSSend`
implements exactly that. DoT / DoH are different protocols and are not part of
this class. If you need the transport authenticated or private, that is a layer
above what `TDNSSend` provides.
