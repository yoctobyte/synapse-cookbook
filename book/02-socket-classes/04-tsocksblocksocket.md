# TSocksBlockSocket — the proxy layer

`TSocksBlockSocket` is the quiet middle of the hierarchy. You never instantiate
it — its own source comment says "Do not use this class directly" — but it sits
between [the base class](01-tblocksocket.md) and both `TTCPBlockSocket` and the
datagram sockets, and it carries the machinery that lets any of them reach the
network **through a SOCKS proxy**. The elegant part: it does this without adding
a single new call to your protocol code.

## The idea: proxying is configuration, not a code path

A naive design would give you a "connect through proxy" method distinct from a
"connect direct" one. Synapse refuses that. Instead, the proxy is a set of
**properties** on the socket. Set them and the ordinary `Connect` /
`Bind` / `Listen` you already call quietly route through the proxy; leave them
empty and the same code connects directly.

```pascal
property SocksIP: string;        // proxy address — EMPTY = SOCKS disabled; setting it ENABLES SOCKS
property SocksPort: string;      // proxy port, default '1080'
property SocksUsername: string;  // set if the proxy needs auth
property SocksPassword: string;
property SocksTimeout: integer;  // proxy-conversation timeout, default one minute
property SocksResolver: Boolean; // let the PROXY resolve hostnames (default True)
property SocksType: TSocksType;  // ST_Socks5 (default) or ST_Socks4
```

The trigger is `SocksIP`: assigning any non-empty value turns SOCKS mode on;
clearing it turns it off. There is no separate "enable" switch — the source is
explicit that "assigning any value to this property enables SOCKS mode."

## Using it — the whole change is three lines

Take the TCP client from [the TCP chapter](02-ttcpblocksocket.md) and route it
through a SOCKS5 proxy. The protocol code is untouched; only setup changes:

```pascal
uses blcksock;

var
  sock: TTCPBlockSocket;
begin
  sock := TTCPBlockSocket.Create;
  try
    sock.SocksIP   := '10.0.0.1';    // <-- these three lines are the entire
    sock.SocksPort := '1080';        //     difference from a direct connection
    sock.SocksType := ST_Socks5;

    sock.Connect('example.org', '80');   // now tunnelled through the proxy
    if sock.LastError <> 0 then
    begin
      Writeln('connect via proxy: ', sock.LastErrorDesc);
      Exit;
    end;
    sock.SendString('HEAD / HTTP/1.0' + CRLF + CRLF);
    Writeln(sock.RecvString(10000));
  finally
    sock.CloseSocket;
    sock.Free;
  end;
end;
```

`Connect` internally opens the connection to `SocksIP:SocksPort`, performs the
SOCKS handshake (authenticating with `SocksUsername`/`SocksPassword` if set),
asks the proxy to reach `example.org:80`, and only then returns. Your
`SendString`/`RecvString` see a normal live socket.

With auth:

```pascal
sock.SocksIP       := '10.0.0.1';
sock.SocksUsername := 'alice';
sock.SocksPassword := 's3cret';
```

## SOCKS4, SOCKS4a, SOCKS5 — and who resolves the name

`SocksType` picks the protocol, and it interacts with `SocksResolver`:

- **`ST_Socks5`** (default) — full SOCKS5, with username/password auth and
  remote name resolution.
- **`ST_Socks4`** with `SocksResolver = True` — uses **SOCKS4a**, the extension
  that lets the proxy resolve the hostname.
- **`ST_Socks4`** with `SocksResolver = False` — pure SOCKS4, which cannot carry
  a hostname, so the name is resolved **locally** first.

`SocksResolver` (default `True`) is the privacy-relevant knob: leave it on and
DNS lookups happen at the proxy, so the target hostname never leaks from your
machine. Turn it off and your host resolves the name before connecting.

## It works for UDP too

Because `TDgramBlockSocket` also descends `TSocksBlockSocket`,
`TUDPBlockSocket` inherits the same properties. Set `SocksIP` on a UDP socket
and unicast datagrams route through a SOCKS5 UDP association — with the honest
limitation, noted in [the UDP chapter](03-tudpblocksocket.md), that **only
unicast** works through a proxy: no broadcast, no multicast.

## Status and internals

A few members let you inspect what happened:

```pascal
property UsingSocks: Boolean read FUsingSocks;      // True once a proxy is actually in use
property SocksLastError: integer read FSocksLastError; // error code returned BY the proxy
```

The class also exposes `SocksOpen`, `SocksRequest`, and `SocksResponse`, but its
comments flag all three as "needed only in special cases (it is called
internally)" — you drive them by setting properties and calling `Connect`, not
by calling these directly.

## Not to be confused with the HTTP tunnel

`TTCPBlockSocket` has a *second*, independent way to traverse a proxy — an HTTP
`CONNECT` tunnel, configured with `HTTPTunnelIP` / `HTTPTunnelPort` /
`HTTPTunnelUser` / `HTTPTunnelPass`. That lives on `TTCPBlockSocket`, not here,
and the source is emphatic: **you cannot combine the two.** SOCKS mode
(`SocksIP` set) and HTTP-tunnel mode (`HTTPTunnelIP` set) are mutually
exclusive — pick one proxy mechanism per socket.

## Why it is nicely designed

- **Proxying is orthogonal.** It rides on the same `Connect`/`Bind`/`Listen`
  every socket already has, so *any* code built on `TTCPBlockSocket` or
  `TUDPBlockSocket` — including Synapse's own HTTP, SMTP, and FTP clients —
  gains proxy support for free, just by having the properties set.
- **Placed exactly once, inherited exactly where it belongs.** Putting SOCKS on
  a mid-tree class means TCP and UDP get it while `TRAWBlockSocket` (which
  cannot proxy) simply descends past it. The hierarchy encodes the capability.
- **Configuration over API surface.** No new verbs to learn; the proxy is data
  you set, not a control path you branch on. The same lesson the
  [SSL plugin seam](../01-architecture/03-ssl-plugin-seam.md) teaches, applied
  to proxies instead of TLS.
