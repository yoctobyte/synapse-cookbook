# TUDPBlockSocket — UDP

`TUDPBlockSocket` is the connectionless member of the family. There is no
connect handshake, no stream, no "connection closed" — just datagrams in and
datagrams out. It descends `TDgramBlockSocket` (which descends
`TSocksBlockSocket`), and that middle class does one clever thing for you: it
**redirects the ordinary `SendBuffer`/`RecvBuffer` onto the connectionless
`SendBufferTo`/`RecvBufferFrom`**, so all the high-level helpers from
[the base class](01-tblocksocket.md) — `SendString`, `RecvPacket`, and friends —
just work on datagrams.

Declared features, from the source:

> IPv4, IPv6, unicasts, broadcasts, multicasts, SOCKS5 proxy (only unicasts,
> outgoing and incoming).

## Do I need a thread? No.

Unlike TCP, UDP is fine on your main thread. Sending a datagram costs about as
much as handing the packet to the network adapter, and for receiving you can
poll with a `0` ms timeout and simply check whether anything arrived. Blocking
UDP in the main thread is perfectly workable.

## The two addressing styles

Synapse gives you two ways to name the far end:

1. **`Connect(IP, Port)`** — for UDP this does *not* handshake. It just fills in
   the remote address (`RemoteSin`), so subsequent `SendString` / `SendBuffer`
   go to that peer. Convenient when you talk to one fixed target.
2. **`SendBufferTo` + `RecvBufferFrom`** — explicit per-datagram addressing.
   `RecvBufferFrom` fills `RemoteSin` with the *sender's* address, so you can
   reply to whoever just wrote to you. This is the natural server style.

```pascal
function SendBufferTo(const Buffer: TMemory; Length: Integer): Integer; override;
function RecvBufferFrom(Buffer: TMemory; Length: Integer): Integer; override;
```

## Worked example — a client that sends and waits for a reply

The UDP echo service (port 7) is the classic demo: send a datagram, read the
one that comes back.

```pascal
uses blcksock;

procedure UdpEcho(const Host, Msg: string);
var
  sock: TUDPBlockSocket;
  reply: AnsiString;
begin
  sock := TUDPBlockSocket.Create;
  try
    sock.Connect(Host, '7');        // fixes RemoteSin; no handshake happens
    sock.SendString(Msg);           // redirected to SendBufferTo(RemoteSin)
    if sock.LastError <> 0 then
    begin
      Writeln('send: ', sock.LastErrorDesc);
      Exit;
    end;

    reply := sock.RecvPacket(2000); // whole datagram, up to 2 s
    if sock.LastError = 0 then
      Writeln('got back: ', reply)
    else
      Writeln('no reply: ', sock.LastErrorDesc);
  finally
    sock.CloseSocket;
    sock.Free;
  end;
end;
```

`RecvPacket` is the right receive call for UDP: one call returns exactly one
whole datagram (its size is dynamic, so you never guess a buffer length).

## Worked example — a UDP server

A server binds a port and loops, replying to each sender. Because
`RecvBufferFrom` (and therefore `RecvPacket`) records the sender in `RemoteSin`,
`SendString` back out goes straight to them.

```pascal
uses blcksock;

procedure RunUdpServer(const Port: string);
var
  sock: TUDPBlockSocket;
  data: AnsiString;
begin
  sock := TUDPBlockSocket.Create;
  try
    sock.Bind('0.0.0.0', Port);     // cAnyHost = all interfaces
    if sock.LastError <> 0 then
    begin
      Writeln('bind: ', sock.LastErrorDesc);
      Exit;
    end;

    while True do
    begin
      data := sock.RecvPacket(1000);         // 1 s poll
      if sock.LastError = 0 then
      begin
        Writeln('from ', sock.GetRemoteSinIP, ':', sock.GetRemoteSinPort,
                ' -> ', data);
        sock.SendString('ack: ' + data);     // replies to RemoteSin (the sender)
      end;
      // on WSAETIMEDOUT, loop again — lets you check a shutdown flag
    end;
  finally
    sock.CloseSocket;
    sock.Free;
  end;
end;
```

If you ever need to send to a peer you have not received from, set the target
explicitly with `SetRemoteSin(IP, Port)` (inherited) before `SendString`.

## Broadcast

UDP can hit every host on the local network. Enable it, then send to the
broadcast address (`cBroadcast = '255.255.255.255'`):

```pascal
sock := TUDPBlockSocket.Create;
try
  sock.EnableBroadcast(True);          // must be on before broadcasting
  sock.Connect('255.255.255.255', '9999');
  sock.SendString('DISCOVER');
  // ...then RecvPacket in a loop to collect replies from responders...
finally
  sock.CloseSocket;
  sock.Free;
end;
```

`EnableBroadcast` binds the socket if it is not already bound. Note from the
source: broadcast is **not** available in SOCKS5 mode, and **IPv6 has no
broadcast at all** — use multicast there instead.

## Multicast

For group communication (and the IPv6 replacement for broadcast):

```pascal
procedure AddMulticast(MCastIP: string);        // join a group
procedure DropMulticast(MCastIP: string);       // leave it
procedure EnableMulticastLoop(Value: Boolean);  // hear your own sends, or not
property  MulticastTTL: Integer;                 // router hops (1 = local network only)
```

```pascal
sock := TUDPBlockSocket.Create;
try
  sock.Bind('0.0.0.0', '5000');
  sock.AddMulticast('239.1.2.3');      // join the group
  sock.MulticastTTL := 1;              // stay on the local segment
  sock.SendString('hello group');      // reaches all joined members
finally
  sock.DropMulticast('239.1.2.3');
  sock.CloseSocket;
  sock.Free;
end;
```

`MulticastTTL` is a genuine footgun in disguise: leave it at `1` unless you mean
to cross routers, because raising it sprays your traffic outward — and many
routers drop multicast anyway, so a high TTL is often disappointment plus risk.

## Honest caveats

- **UDP is lossy and unordered by design.** Synapse does not add reliability.
  A `RecvPacket` timeout on a UDP socket usually means the datagram (or its
  reply) was simply dropped — retry logic is your job.
- A datagram larger than your buffer in the low-level `RecvBufferFrom` is
  **truncated**; `RecvPacket` avoids this by sizing dynamically.
- SOCKS support here is **unicast only** — no broadcast or multicast through a
  proxy.
