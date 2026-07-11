# The Socket Class Family

Synapse's socket layer is one file — `blcksock.pas` — and one idea: **a single
blocking base class, `TBlockSocket`, specialised by protocol.** Everything you
send or receive, in any protocol, over TCP, UDP, ICMP, or a raw socket, goes
through a descendant of that base. Learn the base once and every socket in the
tree behaves the same way.

## The hierarchy

The real tree, straight from `blcksock.pas`:

```
TBlockSocket                     (the blocking core: buffers, timeouts, LastError)
├── TSocksBlockSocket            (adds SOCKS4/4a/5 proxy plumbing — do not use directly)
│   ├── TTCPBlockSocket          (TCP: connect/listen/accept, SSL/TLS plugin, HTTP-tunnel)
│   └── TDgramBlockSocket        (datagram base: Send/Recv redirected to the *To/*From forms)
│       ├── TUDPBlockSocket      (UDP: unicast, broadcast, multicast)
│       └── TICMPBlockSocket     (raw ICMP — needs privilege)
├── TRAWBlockSocket              (raw IP socket — needs privilege)
├── TPGMMessageBlockSocket       (PGM reliable multicast, message mode)
└── TPGMStreamBlockSocket        (PGM reliable multicast, stream mode)
```

Two things are worth reading off that diagram:

- **SOCKS lives in the *middle* of the tree, not at the top.** `TBlockSocket`
  itself knows nothing about proxies. `TSocksBlockSocket` inserts the proxy
  machinery, and both the TCP and the datagram families inherit from it — so
  proxy support comes "for free" to the sockets that can use it, while
  `TRAWBlockSocket` (which cannot) simply skips that layer by descending
  straight from `TBlockSocket`.
- **`TDgramBlockSocket` is a helper, not a socket you instantiate.** It exists
  only to redirect the connection-style `SendBuffer`/`RecvBuffer` onto the
  connectionless `SendBufferTo`/`RecvBufferFrom`, so datagram code can use the
  same high-level helpers (`SendString`, `RecvPacket`) as stream code. You
  create `TUDPBlockSocket` or `TICMPBlockSocket`; you never create
  `TDgramBlockSocket` or `TSocksBlockSocket` directly — their own source
  comments say as much ("Do not use this class directly").

## What unifies them

Every socket in the family shares one contract, defined on `TBlockSocket`:

**A blocking API with timeouts.** Reads and writes block until they complete or
a millisecond timeout elapses; nothing hangs forever. See
[The Blocking Model & Threads](../01-architecture/01-blocking-and-threads.md)
for why that choice ages so well.

**The `LastError` model — report, don't throw.** After any operation you check
`LastError` (an integer socket error code) and `LastErrorDesc` (a human string).
Exceptions are opt-in: set `RaiseExcept := True` and Synapse raises
`ESynapseError` on failure; leave it `False` (the default) and your protocol
code stays linear.

```pascal
sock.Connect('example.org', '80');
if sock.LastError <> 0 then
  Writeln('connect failed: ', sock.LastErrorDesc);
```

**Two tiers of I/O on every socket.** Low-level `SendBuffer`/`RecvBuffer` move
raw bytes; high-level helpers built on an internal `LineBuffer`
(`SendString`, `RecvString`, `RecvPacket`, `RecvTerminated`, `SendInteger`,
`RecvBlock`, the stream methods…) do the framing for you. You can mix the two
tiers freely on the same socket because the high-level side always drains
`LineBuffer` first.

**Shared knobs.** Timeouts (`SetTimeout`, `ConnectionTimeout`), readiness polls
(`CanRead`, `CanWrite`), byte counters (`RecvCounter`, `SendCounter`), bandwidth
throttles (`MaxSendBandwidth`, `MaxRecvBandwidth`), a soft-abort `StopFlag`, and
IPv4/IPv6 selection via the `Family` property — all live on the base and work
identically for TCP, UDP, and the rest.

## Choosing one

| You want to…                                   | Use                 |
|------------------------------------------------|---------------------|
| Speak a stream protocol (HTTP, SMTP, a custom line protocol) | `TTCPBlockSocket` |
| Wrap that stream in TLS/SSL or SSH             | `TTCPBlockSocket` + an `ssl_*` plugin |
| Send/receive datagrams, broadcast, or multicast | `TUDPBlockSocket`  |
| Send ICMP (ping-style) packets                 | `TICMPBlockSocket`  |
| Craft raw IP packets yourself                  | `TRAWBlockSocket`   |
| Reach any of the above through a SOCKS proxy   | set `SocksIP` on the TCP/UDP socket you already have |

The rest of this chapter walks the four you will actually reach for:
[the base class](01-tblocksocket.md), [TCP](02-ttcpblocksocket.md),
[UDP](03-tudpblocksocket.md), and
[the SOCKS proxy layer](04-tsocksblocksocket.md) that quietly sits between them.
