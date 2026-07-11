# TTCPBlockSocket — TCP

`TTCPBlockSocket` is the workhorse of the family: a blocking TCP socket that
speaks stream protocols top-to-bottom, upgrades to TLS through the
[SSL plugin seam](../01-architecture/03-ssl-plugin-seam.md), and can route
itself through a SOCKS or HTTP proxy without your protocol code noticing. It
descends `TSocksBlockSocket`, so it inherits everything in
[the base class](01-tblocksocket.md) plus the proxy plumbing.

Declared features, from the source:

> IPv4, IPv6, SSL/TLS or SSH (depending on used plugin), SOCKS5 proxy (outgoing
> and limited incoming), SOCKS4/4a proxy (outgoing and limited incoming), TCP
> through HTTP proxy tunnel.

## The client pattern

Connect, check `LastError`, talk, close. That is the whole shape:

```pascal
uses blcksock, synautil;

procedure HttpHead(const Host: string);
var
  sock: TTCPBlockSocket;
  line: AnsiString;
begin
  sock := TTCPBlockSocket.Create;
  try
    sock.ConnectionTimeout := 5000;
    sock.Connect(Host, '80');
    if sock.LastError <> 0 then
    begin
      Writeln('connect: ', sock.LastErrorDesc);
      Exit;
    end;

    sock.SendString('HEAD / HTTP/1.0' + CRLF +
                    'Host: ' + Host + CRLF + CRLF);

    repeat
      line := sock.RecvString(10000);
      if sock.LastError = 0 then
        Writeln('S: ', line);
    until (sock.LastError <> 0) or (line = '');
  finally
    sock.CloseSocket;
    sock.Free;
  end;
end;
```

`Connect(IP, Port)` creates the OS socket if needed and blocks until the
connection is up or `ConnectionTimeout` expires. Ports may be numeric (`'80'`)
or symbolic (`'http'`). Set `Family` to `SF_IP4` or `SF_IP6` if you want to pin
the address family; the default `SF_Any` picks based on how the host resolves.

## The listen / accept pattern

A TCP server binds, listens, then accepts. `Accept` returns a raw OS socket
handle (`TSocket`) for the new connection — you wrap it in a fresh
`TTCPBlockSocket` by assigning its `Socket` property:

```pascal
procedure RunServer;
var
  listener, client: TTCPBlockSocket;
begin
  listener := TTCPBlockSocket.Create;
  try
    listener.CreateSocket;
    listener.SetLinger(True, 10000);
    listener.Bind('0.0.0.0', '8080');     // cAnyHost, any interface
    listener.Listen;
    if listener.LastError <> 0 then
    begin
      Writeln('bind/listen: ', listener.LastErrorDesc);
      Exit;
    end;

    while True do
    begin
      if listener.CanRead(1000) then       // 1 s poll so we can check for shutdown
      begin
        client := TTCPBlockSocket.Create;
        client.Socket := listener.Accept;  // adopt the accepted handle
        HandleClient(client);              // in real code: hand to a thread (below)
      end;
    end;
  finally
    listener.CloseSocket;
    listener.Free;
  end;
end;
```

`CanRead` on the listener is how you tell an incoming connection is waiting
without blocking `Accept` forever — the same readiness poll from the base class.

## The threaded server

The idiomatic Synapse server gives every connection its own thread of
straight-line protocol code. This is exactly the model described in
[The Blocking Model & Threads](../01-architecture/01-blocking-and-threads.md):
the listener accepts, then hands each connection to a handler thread.

```pascal
uses blcksock, synautil, Classes;

type
  TClientThread = class(TThread)
  private
    FSock: TTCPBlockSocket;
  public
    constructor Create(AHandle: TSocket);
    procedure Execute; override;
  end;

constructor TClientThread.Create(AHandle: TSocket);
begin
  FSock := TTCPBlockSocket.Create;
  FSock.Socket := AHandle;         // adopt the handle Accept returned
  FreeOnTerminate := True;
  inherited Create(False);
end;

procedure TClientThread.Execute;
var
  line: AnsiString;
begin
  try
    line := FSock.RecvString(30000);
    while (FSock.LastError = 0) and (line <> '') do
    begin
      FSock.SendString('echo: ' + line + CRLF);
      line := FSock.RecvString(30000);
    end;
  finally
    FSock.CloseSocket;
    FSock.Free;
  end;
end;
```

The listener loop becomes: `TClientThread.Create(listener.Accept)` for each
connection. One socket, one thread, one readable `Execute` — no shared state
machine. **Never share a single `TTCPBlockSocket` across threads**; give each
connection its own.

## SSL/TLS upgrade

`TTCPBlockSocket` never encrypts by itself. TLS is a plugin attached at link
time — include an `ssl_*` unit and the socket gains it transparently. The full
story is in [The SSL Plugin Seam](../01-architecture/03-ssl-plugin-seam.md); the
socket-side methods are:

```pascal
constructor CreateWithSSL(SSLPlugin: TSSLClass);  // pick a plugin per-socket
procedure SSLDoConnect;                            // upgrade a live client socket to TLS
function  SSLAcceptConnection: Boolean;            // server side: start TLS on an accepted socket
procedure SSLDoShutdown;                           // downgrade back to plain TCP
property  SSL: TCustomSSL read FSSL;               // the plugin instance (config: certs, keys, versions)
```

**Implicit TLS** (HTTPS-style — encrypted from the first byte): include
`ssl_openssl`, then call `SSLDoConnect` right after `Connect`:

```pascal
uses blcksock, ssl_openssl;   // <-- this line chooses OpenSSL

sock.Connect('example.org', '443');
sock.SSLDoConnect;
if sock.LastError <> 0 then
  Writeln('TLS handshake failed: ', sock.LastErrorDesc);
```

**Opportunistic TLS** (STARTTLS-style — start plaintext, negotiate, then
upgrade the *same* live connection):

```pascal
sock.Connect('mail.example.org', '25');   // plaintext SMTP
sock.SendString('STARTTLS' + CRLF);
sock.RecvString(10000);                    // '220 ready to start TLS'
sock.SSLDoConnect;                         // upgrade in place
```

Server side, configure certificates on the `SSL` object before you accept, then
turn the accepted socket into a TLS session:

```pascal
client.Socket := listener.Accept;
client.SSL.CertificateFile := 'server.crt';
client.SSL.PrivateKeyFile  := 'server.key';
if not client.SSLAcceptConnection then
  Writeln('TLS accept failed: ', client.LastErrorDesc);
```

## Other TCP-specific methods

- **`GetRemoteSinIP` / `GetRemoteSinPort` / `GetLocalSinIP` / `GetLocalSinPort`**
  — who you are talking to and from, once connected.
- **`SetLinger(Enable, Linger)`** (from the base) — control how long `close`
  waits to flush unsent data; stream-socket only.
- **`OnAfterConnect`** — an event fired right after a successful TCP connect,
  useful for logging or per-connection setup.
- **`WaitingData` / `RecvPacket`** are overridden to account for buffered TLS
  data, so they stay correct once you are inside a TLS session.

## Honest caveats

- `SendString` adds **no** terminator — you append `CRLF` for line protocols
  (see the base class chapter). This is not TCP-specific but it bites here most.
- Synapse is optimised for **synchronous** use. `NonBlockMode` exists but "not
  all functions work properly in it" — the source's own warning. Prefer
  blocking + threads.
- In SOCKS mode a server can accept only **one** connection, and `Accept`
  reuses the listening socket rather than making a new one — a limitation of
  SOCKS BIND, not of Synapse. For real servers, proxy the clients, not the
  listener.
