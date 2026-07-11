# The rest of the protocol clients

The chapters so far worked through the clients most programs reach for. Synapse
ships several more, and every one of them follows the same shape you have already
learned: a `TSynaClient` descendant, a socket exposed as `Sock`, a default port
set by the constructor, and a small set of verbs. This chapter is a guided tour
of six of them — NNTP, SNMP, SNTP, ping, telnet, and syslog — with enough of each
to place it and a minimal example. When you need the details, the unit source is
short and readable in every case.

Everything below is verified against the units in
the Synapse source (one unit per protocol).

---

## NNTP — Usenet news (`nntpsend`, `TNNTPSend`, port 119)

**What it's for.** Reading and posting Usenet articles: selecting a newsgroup,
downloading articles by number or message-id, listing groups, and posting.

**Key calls.** `Login` / `Logout` bracket the session (the same connect-and-greet
rhythm as the mail clients; `Login` also runs `AUTHINFO USER`/`PASS` if you set
`UserName`/`Password`, and will `STARTTLS` when `AutoTLS` is set and the server
advertises it). Then `SelectGroup(name)` switches group, `GetArticle(id)` /
`GetBody(id)` / `GetHead(id)` download into the `Data` string list, and
`PostArticle` posts the article you have placed in `Data`. Results come back as
`ResultCode` / `ResultString`, with multi-line payloads in `Data`.

```pascal
uses nntpsend;

var
  Nntp: TNNTPSend;
  i: Integer;
begin
  Nntp := TNNTPSend.Create;
  try
    Nntp.TargetHost := 'news.example.com';
    if Nntp.Login then
    begin
      if Nntp.SelectGroup('comp.lang.pascal.misc') then
        Writeln('group selected: ', Nntp.ResultString);

      if Nntp.GetArticle('1') then          // article #1 -> Data
        for i := 0 to Nntp.Data.Count - 1 do
          Writeln(Nntp.Data[i]);

      Nntp.Logout;
    end;
  finally
    Nntp.Free;
  end;
end.
```

TLS is available exactly as elsewhere: add an `ssl_*` unit and set `FullSSL`
(implicit) or `AutoTLS` (STARTTLS upgrade). `StartTLS` is public if you want to
drive the upgrade yourself.

---

## SNMP — device monitoring (`snmpsend`, `TSNMPSend`, port 161)

**What it's for.** Reading and writing values (MIB objects, addressed by OID) on
network devices — switches, printers, UPSes — using a *community string* as the
access credential.

**Key calls.** The class `TSNMPSend` owns a `Query` and a `Reply` record
(`TSNMPRec`, each carrying a `Community`, a `PDUType`, and a list of MIB
entries), and `SendRequest` performs one round trip. But for the common case you
never touch the class directly — the unit exports three convenience functions
that build the record, send, and read the answer for you:

```pascal
function SNMPGet(const OID, Community, SNMPHost: AnsiString;
  var Value: AnsiString): Boolean;
function SNMPGetNext(var OID: AnsiString; const Community, SNMPHost: AnsiString;
  var Value: AnsiString): Boolean;
function SNMPSet(const OID, Community, SNMPHost, Value: AnsiString;
  ValueType: Integer): Boolean;
```

Reading a single value is one line:

```pascal
uses snmpsend, asn1util;   // asn1util for the ASN1_* value-type constants

var
  V: AnsiString;
begin
  // sysDescr.0 with the read community 'public'
  if SNMPGet('1.3.6.1.2.1.1.1.0', 'public', '192.168.1.1', V) then
    Writeln('sysDescr = ', V);

  // Writing needs the value's ASN.1 type, e.g. ASN1_OCTSTR for a string,
  // ASN1_INT for an integer:
  // SNMPSet('1.3.6.1.2.1.1.5.0', 'private', '192.168.1.1', 'newname', ASN1_OCTSTR);
end.
```

> **Honest caveat.** These functions default to SNMP **v1/v2c**, whose community
> string is sent in clear text and is not real security. (`TSNMPRec` does carry
> v3 username/auth fields for the SNMPv3 path — the `Community` string is unused
> there — but that is well beyond a one-liner.) The `ValueType` argument to
> `SNMPSet` is one of the `ASN1_*` constants from `asn1util`
> (`ASN1_INT = $02`, `ASN1_OCTSTR = $04`, `ASN1_OBJID = $06`, …).

The unit also offers `SNMPGetTable` / `SNMPGetTableElement` for walking MIB
tables, and `SendTrap` / `RecvTrap` for the trap side (port 162).

---

## SNTP — network time (`sntpsend`, `TSNTPSend`, port 123)

**What it's for.** Asking an NTP server for the current time. It is a single
UDP exchange, so like DNS there is no login — you create, call, read.

**Key call.** `GetSNTP` sends the request and, on success, fills `NTPTime` (a
`TDateTime`, in UTC) and the raw `NTPReply` record. `GetNTP` does the fuller
four-timestamp exchange that also yields `NTPOffset` and `NTPDelay`;
`GetBroadcastNTP` listens for a broadcast time packet. If you set
`SyncTime := True`, a successful call will also set the local clock (subject to
`MaxSyncDiff`) — which of course needs the privilege to do so.

```pascal
uses sntpsend;

var
  Sntp: TSNTPSend;
begin
  Sntp := TSNTPSend.Create;
  try
    Sntp.TargetHost := 'pool.ntp.org';
    if Sntp.GetSNTP then
      Writeln('server time (UTC): ', DateTimeToStr(Sntp.NTPTime))
    else
      Writeln('no reply');
  finally
    Sntp.Free;
  end;
end.
```

---

## Ping — ICMP echo (`pingsend`, `TPINGSend`, no TCP port)

**What it's for.** Testing reachability and round-trip time with an ICMP echo
("ping"). Because ICMP is not TCP or UDP, this client uses a raw socket rather
than a normal port.

**Key call.** `Ping(host)` sends one echo and returns `True` on a reply, filling
`PingTime` (ms), `ReplyFrom`, and `ReplyError`. For a throwaway check the unit
exports a convenience:

```pascal
function PingHost(const Host: string): Integer;   // ms, or -1 on failure/timeout
```

```pascal
uses pingsend;

var
  Ms: Integer;
begin
  Ms := PingHost('example.com');
  if Ms >= 0 then
    Writeln('round trip: ', Ms, ' ms')
  else
    Writeln('no reply');
end.
```

> **Honest caveat — needs privileges.** Raw ICMP sockets are privileged. On
> Linux this means running as root or granting the binary the `cap_net_raw`
> capability; on Windows it needs the analogous rights. Without them the raw
> socket cannot be created and the ping fails regardless of whether the host is
> up. (On Windows, `TPINGSend` can fall back to the IP Helper `IcmpSendEcho`
> path internally, but the privilege point still stands.) The unit also exports
> `TraceRouteHost` for a traceroute-style probe.

---

## Telnet — terminal sessions (`tlntsend`, `TTelnetSend`, port 23)

**What it's for.** Driving a line-oriented telnet server: connecting, waiting for
prompts, sending commands, and reading the response. `TTelnetSend` handles telnet
option negotiation (IAC sequences) transparently and accumulates everything it
sees in `SessionLog`.

**Key calls.** `Login` connects (it is just a connect — telnet has no protocol
login step; you authenticate by scripting the login prompt yourself). Then
`WaitFor(text)` blocks until `text` appears in the stream, `Send(text)` sends
input, and `RecvString` reads a CRLF-terminated line. `Logout` closes the socket.

```pascal
uses tlntsend;

var
  Tel: TTelnetSend;
begin
  Tel := TTelnetSend.Create;
  try
    Tel.TargetHost := '192.168.1.1';
    if Tel.Login then
    begin
      Tel.WaitFor('login:');
      Tel.Send('admin' + #13#10);
      Tel.WaitFor('Password:');
      Tel.Send('secret' + #13#10);
      Tel.WaitFor('$');            // shell prompt
      Tel.Send('uptime' + #13#10);
      Writeln(Tel.RecvString);
      Tel.Logout;
    end;
  finally
    Tel.Free;
  end;
end.
```

> **Caveat.** Telnet is plaintext — credentials and session both cross the wire
> unencrypted. `TTelnetSend` does expose an `SSHLogin` method that reuses the
> socket's SSL layer to negotiate an SSHv2 transport (via the libssh2 plugin), if
> you have that plugin in `uses`; plain `Login` gives you classic telnet.

---

## Syslog — remote logging (`slogsend`, `TSyslogSend`, port 514, UDP)

**What it's for.** Shipping a log line to a syslog collector as a single UDP
packet (RFC 3164, with RFC 5424 also supported by the message class).

**Key call.** `TSyslogSend` carries a `SysLogMessage` (a `TSyslogMessage` with
`Facility`, `Severity`, `Tag`/`AppName`, and `LogMessage`), and `DoIt` sends it.
For a one-shot line the unit exports a convenience wrapper:

```pascal
function ToSysLog(const SyslogServer: string; Facil: Byte;
  Sever: TSyslogSeverity; const Content: string): Boolean;
```

`TSyslogSeverity` is the RFC enum: `Emergency, Alert, Critical, Error, Warning,
Notice, Info, Debug`. Facility is the numeric code (e.g. 1 = user, 16 = local0).

```pascal
uses slogsend;

begin
  // facility 16 (local0), severity Info, one line to the collector
  ToSysLog('192.168.1.10', 16, Info, 'backup completed');
end.
```

Driving the class directly lets you set the `Tag`/`AppName` and other header
fields before calling `DoIt`:

```pascal
uses slogsend;

var
  Log: TSyslogSend;
begin
  Log := TSyslogSend.Create;
  try
    Log.TargetHost := '192.168.1.10';
    Log.SysLogMessage.Facility   := 16;
    Log.SysLogMessage.Severity   := Warning;
    Log.SysLogMessage.Tag        := 'myapp';
    Log.SysLogMessage.LogMessage := 'disk 85% full';
    Log.DoIt;
  finally
    Log.Free;
  end;
end.
```

> **Note.** Classic syslog over UDP/514 is fire-and-forget and unencrypted:
> `DoIt` returning `True` means the packet was sent, not that anything received
> it. That is inherent to the protocol, not a limitation of the client.

---

## Where to go next

Every client here rewards a glance at its unit source — they are small, and each
convenience function (`GetMailServers`, `SNMPGet`, `PingHost`, `ToSysLog`) is
itself a worked example of driving the underlying class. Once the request /
response rhythm from the [overview](00-index.md) is in your hands, none of these
hold surprises; they differ only in the verbs of their protocol.
