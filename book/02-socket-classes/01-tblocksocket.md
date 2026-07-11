# TBlockSocket — the base class

`TBlockSocket` is the root of the whole family. You almost never instantiate it
directly — you create a `TTCPBlockSocket` or `TUDPBlockSocket` — but *every*
method and property you use lives here or is overridden from here. This chapter
is the reference you come back to.

## The lifecycle

A Synapse socket has a simple, explicit life:

```
Create ──▶ Connect / Bind+Listen ──▶ Send/Recv … ──▶ CloseSocket ──▶ Free
```

- **`constructor Create`** — makes the object and loads the socket library, but
  does *not* create an OS socket yet. There is also
  `CreateAlternate(Stub: string)` for loading a non-default socket provider.
- **`Connect(IP, Port: string)`** / **`Bind(const IP, Port: string)`** — the OS
  socket is created lazily on first use. Both take strings, numeric or symbolic:
  `'192.168.0.1'` or `'cosi.nekde.cz'`, `'80'` or `'http'`.
- **`CloseSocket`** — closes the OS handle. It is `virtual` (TCP overrides it to
  shut down TLS first). The destructor calls it for you, so `Free` is enough,
  but closing explicitly when you are done is good manners.
- **`AbortSocket`** — the hard version: abandon any work and destroy the handle.

```pascal
var sock: TTCPBlockSocket;
begin
  sock := TTCPBlockSocket.Create;
  try
    sock.Connect('example.org', '80');
    if sock.LastError = 0 then
      { ...talk... };
  finally
    sock.CloseSocket;
    sock.Free;
  end;
end;
```

## The `LastError` model

Synapse **reports** rather than throws. After any operation:

```pascal
property LastError: Integer read FLastError;      // 0 = success
property LastErrorDesc: string read FLastErrorDesc;
```

`LastError` is a standard socket error code (e.g. `WSAETIMEDOUT` on a timeout).
`LastErrorDesc` is a human string for it, and the class function
`GetErrorDesc(ErrorCode)` / method `GetErrorDescEx` turn any code into text.
`ResetLastError` clears both back to the non-error state.

If you *prefer* exceptions, set `RaiseExcept := True` and Synapse raises
`ESynapseError` whenever a call fails. The default is `False` — the linear,
check-after-each-step style that keeps protocol code readable.

## Sending — low level and high level

**Low level**, raw bytes in your buffer:

```pascal
function SendBuffer(const Buffer: TMemory; Length: Integer): Integer; virtual;
procedure SendByte(Data: Byte); virtual;
```

`TMemory` is Synapse's pointer-to-bytes type; you pass the address of your data
and a length. `SendBuffer` returns the number of bytes actually sent.

**High level**, framing done for you:

```pascal
procedure SendString(Data: AnsiString); virtual;   // sends bytes as-is — NO terminator added
procedure SendInteger(Data: Integer); virtual;      // four bytes
procedure SendBlock(const Data: AnsiString); virtual;   // 4-byte length prefix, then data
procedure SendStreamRaw(const Stream: TStream); virtual;
procedure SendStream(const Stream: TStream); virtual;   // length-framed, pairs with RecvStream
```

Note the honest caveat baked into `SendString`: **it adds no line terminator.**
If your protocol is line-based, you append `CRLF` yourself:

```pascal
sock.SendString('USER alice' + CRLF);
```

## Receiving — low level and high level

**Low level** (you must know how much is coming, or check `WaitingData` first,
or you risk a deadlock):

```pascal
function RecvBuffer(Buffer: TMemory; Length: Integer): Integer; virtual;
function RecvByte(Timeout: Integer): Byte; virtual;
```

**High level**, all take a millisecond `Timeout` and set `LastError` to
`WSAETIMEDOUT` if it lapses:

```pascal
function RecvBufferEx(Buffer: TMemory; Len, Timeout: Integer): Integer; virtual;
function RecvBufferStr(Len, Timeout: Integer): AnsiString; virtual;
function RecvString(Timeout: Integer): AnsiString; virtual;   // reads up to a CRLF, strips it
function RecvTerminated(Timeout: Integer; const Terminator: AnsiString): AnsiString; virtual;
function RecvPacket(Timeout: Integer): AnsiString; virtual;   // whatever is waiting, dynamic size
function RecvInteger(Timeout: Integer): Integer; virtual;
function RecvBlock(Timeout: Integer): AnsiString; virtual;    // reads a SendBlock frame
procedure RecvStream(const Stream: TStream; Timeout: Integer); virtual;
```

The three you will reach for most:

- **`RecvString`** — a CRLF-terminated line, returned *without* the CRLF. The
  bread and butter of text protocols (SMTP, POP3, HTTP status lines). Under the
  hood it calls `RecvTerminated(Timeout, CRLF)`.
- **`RecvPacket`** — "give me whatever is there right now." Ideal when you do
  not know the length ahead of time — reading a chunk of a TCP stream, or a
  whole UDP datagram.
- **`RecvBufferEx`** — "give me exactly `Len` bytes, waiting up to `Timeout`."
  For binary framing where the length is known.

The high-level functions share an internal `LineBuffer` (exposed as a property),
which is why you can mix them: a `RecvString` that over-reads leaves the surplus
in `LineBuffer` for the next call.

`ConvertLineEnd := True` relaxes `RecvString` to accept lone CR or lone LF as a
line end too, not only CRLF — handy against sloppy peers.

## Readiness and waiting

You do not usually need these — the `Recv*` timeouts already call them
internally — but they are the ingredients of a hand-rolled select loop:

```pascal
function CanRead(Timeout: Integer): Boolean; virtual;   // data waiting, or (TCP) an incoming connection
function CanReadEx(Timeout: Integer): Boolean; virtual; // also true if LineBuffer has data
function CanWrite(Timeout: Integer): Boolean; virtual;  // send buffer has room
function WaitingData: Integer; virtual;                 // bytes ready to read (or datagram length)
```

`Timeout = 0` means "test and return immediately"; `-1` means "wait, possibly
forever." `GroupCanRead` polls a whole `TSocketList` at once — a real
`select()` over many sockets, if you want one without leaving the blocking API.

## Timeouts and other knobs

```pascal
property ConnectionTimeout: Integer;      // connect timeout in ms (0 = system default)
procedure SetTimeout(Timeout: Integer);    // send + recv timeout (if the provider supports it)
procedure SetSendTimeout(Timeout: Integer);
procedure SetRecvTimeout(Timeout: Integer);
property MaxLineLength: Integer;           // cap on RecvString/RecvTerminated — anti-DoS
property StopFlag: Boolean;                // set True to soft-abort a long operation
property RecvCounter: int64;               // bytes received this connection
property SendCounter: int64;               // bytes sent this connection
property Family: TSocketFamily;            // SF_Any (default), SF_IP4, SF_IP6
```

`MaxLineLength` deserves a mention: it bounds how much `RecvString` /
`RecvTerminated` will buffer before erroring, so a hostile peer that never sends
a terminator cannot make you allocate memory until you fall over. Default `0`
means unlimited — set it on any server that reads lines from untrusted input.

## A worked example — a tiny POP3-style dialogue

Line protocols map almost one-to-one onto `RecvString`/`SendString`:

```pascal
uses blcksock, synautil;

procedure FetchGreeting;
var
  sock: TTCPBlockSocket;
  line: AnsiString;
begin
  sock := TTCPBlockSocket.Create;
  try
    sock.ConnectionTimeout := 5000;
    sock.Connect('mail.example.org', '110');
    if sock.LastError <> 0 then
    begin
      Writeln('connect: ', sock.LastErrorDesc);
      Exit;
    end;

    line := sock.RecvString(15000);        // server greeting, e.g. '+OK POP3 ready'
    Writeln('S: ', line);

    sock.SendString('USER alice' + CRLF);  // remember: we add CRLF ourselves
    Writeln('S: ', sock.RecvString(15000));

    sock.SendString('QUIT' + CRLF);
    Writeln('S: ', sock.RecvString(15000));

    Writeln(sock.RecvCounter, ' bytes received');
  finally
    sock.CloseSocket;
    sock.Free;
  end;
end;
```

Every line of that is base-class API — `TTCPBlockSocket` only adds the transport
underneath. That is the point of `TBlockSocket`: the vocabulary is fixed once,
and the protocol descendants and your own code both speak it unchanged.
