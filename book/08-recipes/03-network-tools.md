# Recipes — Network tools

DNS lookups, ICMP pings, and raw TCP. The socket layer under all of it is the
[socket classes](../02-socket-classes/00-index.md); the client/server walkthrough
is [Synapse in Two Hours](../99-appendix-tutorials/synapse-in-two-hours.md).

## Resolve a hostname

**Problem:** ask a DNS server for the A records of a name.

```pascal
program Resolve;

{$mode objfpc}{$H+}

uses
  Classes, dnssend;

var
  DNS: TDNSSend;
  Answers: TStringList;
  i: Integer;
begin
  DNS := TDNSSend.Create;
  Answers := TStringList.Create;
  try
    DNS.TargetHost := '8.8.8.8';                 // the DNS server to query

    // QTYPE_A = IPv4 address records (QTYPE_AAAA for IPv6, QTYPE_MX for mail).
    if DNS.DNSQuery('example.com', QTYPE_A, Answers) then
      for i := 0 to Answers.Count - 1 do
        WriteLn(Answers[i])
    else
      WriteLn('Query failed, RCode=', DNS.RCode);
  finally
    Answers.Free;
    DNS.Free;
  end;
end.
```

`DNSQuery(Name, QType, Reply)` sends over UDP and fills `Reply` with one value
per line. **Gotcha:** you must set `TargetHost` to an actual resolver — Synapse
does not read your system's `/etc/resolv.conf`. For mail servers specifically,
`GetMailServers(const DNSHost, Domain: AnsiString; const Servers: TStrings)`
queries MX and returns the hosts already sorted by preference.

## Ping a host

**Problem:** measure round-trip time to a host with ICMP.

```pascal
program Ping;

{$mode objfpc}{$H+}

uses
  pingsend;

var
  Ms: Integer;
begin
  Ms := PingHost('example.com');   // round-trip in ms, or -1 on failure
  if Ms >= 0 then
    WriteLn('Reply in ', Ms, ' ms')
  else
    WriteLn('No reply');
end.
```

`PingHost` wraps `TPINGSend`, returning the round-trip time in milliseconds or
`-1` if there's no reply. **Gotcha:** ICMP needs a raw socket, so on Unix this
must run as root (or with `CAP_NET_RAW`). Use the `TPINGSend` object directly when
you want to set `Timeout`/`TTL` or read `ReplyFrom` and `PingTime`.

## A minimal TCP client

**Problem:** connect, send a line, read the reply — the bare socket pattern.

```pascal
program TcpClient;

{$mode objfpc}{$H+}

uses
  blcksock;

var
  Sock: TTCPBlockSocket;
begin
  Sock := TTCPBlockSocket.Create;
  try
    Sock.Connect('example.com', '80');
    if Sock.LastError <> 0 then
    begin
      WriteLn('Connect failed: ', Sock.LastErrorDesc);
      Exit;
    end;
    Sock.SendString('GET / HTTP/1.0' + CRLF + CRLF);  // CRLF is exported by blcksock
    WriteLn(Sock.RecvString(5000));                    // first response line
  finally
    Sock.Free;   // destructor closes the socket
  end;
end.
```

Every call sets `LastError` (`0` = success) rather than raising — check it after
`Connect`. `RecvString(Timeout)` returns one CRLF-terminated line without the line
ending, and sets `LastError` to a timeout code when the peer goes quiet.

## A threaded echo server

**Problem:** accept many clients at once, one thread per connection.

```pascal
program EchoServer;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX} cthreads, {$ENDIF}
  Classes, blcksock, synsock;   // synsock exports TSocket

type
  TEchoThread = class(TThread)
  private
    FSock: TTCPBlockSocket;
  public
    constructor Create(ClientSocket: TSocket);
    procedure Execute; override;
  end;

constructor TEchoThread.Create(ClientSocket: TSocket);
begin
  FSock := TTCPBlockSocket.Create;
  FSock.Socket := ClientSocket;   // adopt the handle Accept returned
  FreeOnTerminate := True;
  inherited Create(False);        // start immediately
end;

procedure TEchoThread.Execute;
var
  Line: string;
begin
  try
    repeat
      Line := FSock.RecvString(60000);
      if FSock.LastError <> 0 then Break;
      FSock.SendString('you said: ' + Line + CRLF);
    until Terminated;
  finally
    FSock.Free;
  end;
end;

var
  Listener: TTCPBlockSocket;
  Client: TSocket;
begin
  Listener := TTCPBlockSocket.Create;
  try
    Listener.CreateSocket;
    Listener.SetLinger(True, 10000);
    Listener.Bind('0.0.0.0', '9000');
    if Listener.LastError <> 0 then
    begin
      WriteLn('Bind failed: ', Listener.LastErrorDesc);
      Exit;
    end;
    Listener.Listen;
    WriteLn('Listening on 9000...');
    repeat
      if Listener.CanRead(1000) then           // stay interruptible
      begin
        Client := Listener.Accept;
        if Listener.LastError = 0 then
          TEchoThread.Create(Client);          // fire and forget
      end;
    until False;
  finally
    Listener.Free;
  end;
end.
```

The listener only accepts and delegates; each connection runs plain sequential
code in its own thread. **Gotcha:** never share one `TBlockSocket` across threads
— give every connection its own, as above. The full walkthrough (including the
TLS one-liner) is in
[Synapse in Two Hours §3](../99-appendix-tutorials/synapse-in-two-hours.md).
