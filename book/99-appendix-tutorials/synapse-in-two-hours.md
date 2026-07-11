# Appendix — Synapse in Two Hours

Welcome. This is the on-ramp. In one sitting you will write a TCP client, fetch a
web page in a single line, run a threaded server, and switch the whole thing to
TLS by adding one word to a `uses` clause. Everything here is real code against
the real Ararat Synapse API — no pseudocode, no hand-waving. If you know a little
Object Pascal and can compile with FPC or Delphi, you have everything you need.

Read the [architecture chapter](../01-architecture/00-index.md) first if you want
the *why*; this chapter is the *how*. The one idea to carry in with you: Synapse
is **blocking with timeouts**. Every call either finishes its job or returns when
your timeout elapses — it never hangs forever, and it reports status through
`LastError` rather than throwing. That single decision is what keeps every
example below short and linear. See [The blocking model &
threads](../01-architecture/01-blocking-and-threads.md) for the full story.

---

## 1. Hello, socket — a minimal TCP client

The workhorse class is `TTCPBlockSocket`, declared in `blcksock.pas`. It gives
you TCP behind five methods you will use constantly:

- `Connect(IP, Port: string)` — open the connection (both arguments are strings;
  `Port` can be a number like `'13'` or a service name).
- `SendString(Data: AnsiString)` — write bytes.
- `RecvString(Timeout: Integer): AnsiString` — read one CRLF-terminated line,
  returning it *without* the line ending.
- `LastError: Integer` — `0` means success; anything else is the socket error
  code, with `LastErrorDesc` giving a human-readable string.
- `CloseSocket` — release the connection (the destructor calls it for you too).

Let's talk to a **daytime** service (TCP port 13), one of the oldest and simplest
text protocols on the internet: connect, and the server sends back the current
date and time as a line of text, then closes. No request needed.

```pascal
program HelloSocket;

{$mode objfpc}{$H+}

uses
  blcksock;

var
  Sock: TTCPBlockSocket;
  Line: string;
begin
  Sock := TTCPBlockSocket.Create;
  try
    // Connect blocks until the connection is up or ConnectionTimeout elapses.
    Sock.Connect('time.nist.gov', '13');
    if Sock.LastError <> 0 then
    begin
      WriteLn('Connect failed: ', Sock.LastErrorDesc);
      Exit;
    end;

    // Read lines until the server closes and the read times out.
    repeat
      Line := Sock.RecvString(5000);   // wait up to 5 seconds for a line
      if Sock.LastError = 0 then
        WriteLn(Line);
    until Sock.LastError <> 0;

  finally
    Sock.Free;                         // destructor closes the socket
  end;
end.
```

Notice the **discipline**: after *every* operation we check `LastError` before
trusting the result. That is the Synapse rhythm. `Connect` doesn't raise on
failure — it sets `LastError` and returns, so you decide what to do. `RecvString`
returns an empty string on timeout *and* sets `LastError` to `WSAETIMEDOUT`, which
is exactly how we know the server has finished and it's time to stop reading.

That is a complete, correct network client. Twenty lines. This is what "blocking
with timeouts" buys you: code that reads top-to-bottom like a description of the
conversation.

### Sending a request

The daytime server talks first. Most protocols want you to speak first. The
pattern is identical — `SendString`, then `RecvString`:

```pascal
Sock.Connect('example.com', '80');
if Sock.LastError = 0 then
begin
  Sock.SendString('GET / HTTP/1.0' + CRLF + CRLF);   // CRLF is declared in blcksock
  Line := Sock.RecvString(5000);
  WriteLn(Line);                                       // -> HTTP/1.1 200 OK
end;
```

`CRLF` is a constant Synapse exports from `blcksock` (`CR + LF`), so you never
have to remember `#13#10`. You *could* speak the whole of HTTP this way, line by
line. You shouldn't — because Synapse already did it for you. That's section 2.

---

## 2. One line of HTTP — the convenience layer

`httpsend.pas` sits on top of `TTCPBlockSocket` and speaks HTTP so you don't have
to. For the common case there is a free function, `HttpGetText`, that does
connect, request, read the response, and disconnect — all of it:

```pascal
program OneLineHTTP;

{$mode objfpc}{$H+}

uses
  Classes, httpsend;

var
  Page: TStringList;
begin
  Page := TStringList.Create;
  try
    if HttpGetText('http://example.com/', Page) then
      WriteLn(Page.Text)
    else
      WriteLn('Request failed');
  finally
    Page.Free;
  end;
end.
```

`HttpGetText(const URL: string; const Response: TStrings): Boolean` returns
`True` on a successful fetch and fills your `TStrings` with the response body.
One call. Compare that to hand-rolling the request, parsing status lines, and
handling headers — this is the payoff for the protocol classes.

### When you need the details — THTTPSend

`HttpGetText` is a convenience wrapper around the real workhorse, `THTTPSend`.
Reach for the class when you need headers, status codes, or anything other than a
plain GET. The pattern is: create it, call `HTTPMethod(Method, URL)`, then read
the results off its properties:

- `Document: TMemoryStream` — the response body.
- `Headers: TStringList` — request headers going out, response headers coming
  back.
- `ResultCode: Integer` / `ResultString: string` — the HTTP status.
- `MimeType: string` — content type for the body you send.

```pascal
program HttpGetClass;

{$mode objfpc}{$H+}

uses
  Classes, httpsend;

var
  HTTP: THTTPSend;
  Body: TStringList;
begin
  HTTP := THTTPSend.Create;
  Body := TStringList.Create;
  try
    if HTTP.HTTPMethod('GET', 'http://example.com/') then
    begin
      WriteLn('Status: ', HTTP.ResultCode, ' ', HTTP.ResultString);
      Body.LoadFromStream(HTTP.Document);   // Document is a TMemoryStream
      WriteLn(Body.Text);
    end
    else
      WriteLn('Failed: ', HTTP.Sock.LastErrorDesc);
  finally
    Body.Free;
    HTTP.Free;
  end;
end.
```

Note `HTTP.Sock` — `THTTPSend` exposes the underlying `TTCPBlockSocket` it drives,
so the same `LastError`/`LastErrorDesc` discipline is right there when a request
fails at the socket level.

### Posting data

For a POST you load the request body into `Document`, set `MimeType`, and call
`HTTPMethod('POST', URL)`:

```pascal
program HttpPost;

{$mode objfpc}{$H+}

uses
  Classes, httpsend;

var
  HTTP: THTTPSend;
  Payload: string;
begin
  HTTP := THTTPSend.Create;
  try
    Payload := '{"name":"synapse","stars":9001}';
    HTTP.Document.Write(Pointer(Payload)^, Length(Payload));   // fill the request body
    HTTP.MimeType := 'application/json';

    if HTTP.HTTPMethod('POST', 'http://example.com/api') then
      WriteLn('Server said: ', HTTP.ResultCode, ' ', HTTP.ResultString)
    else
      WriteLn('POST failed: ', HTTP.Sock.LastErrorDesc);
  finally
    HTTP.Free;
  end;
end.
```

`Document` is a `TMemoryStream`, so anything you can write to a stream — a string,
a file, binary — becomes your request body. If you just want to submit a URL-encoded
form, `httpsend` also exports the one-liner `HttpPostURL(const URL, URLData: string;
const Data: TStream): Boolean`.

That's HTTP. The protocol classes (SMTP in `smtpsend.pas`, POP3, IMAP, FTP, and
the rest) all follow the same shape: a thin class over a block socket, a handful
of methods, status reported the Synapse way.

---

## 3. Your first server — a threaded echo/line server

A client is one conversation. A **server** is many at once, and here is where the
blocking model earns its keep. The recipe:

1. `Bind(IP, Port)` — claim the address.
2. `Listen` — start accepting.
3. `Accept` — block until a client arrives; it returns a raw `TSocket` handle.
4. **Hand that handle to its own thread** and go straight back to `Accept`.

That fourth step is the whole trick. The listener's only job is to accept and
delegate. Each accepted connection gets a `TThread` running plain, sequential
protocol code — no shared state machine, no re-entrancy puzzles. One connection,
one thread, one readable `Execute`.

### The per-connection handler thread

```pascal
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
  FSock.Socket := ClientSocket;   // adopt the handle Accept handed us
  FreeOnTerminate := True;        // clean itself up when done
  inherited Create(False);        // start running immediately
end;

procedure TEchoThread.Execute;
var
  Line: string;
begin
  try
    FSock.SendString('Welcome. Type something; QUIT to leave.' + CRLF);
    repeat
      Line := FSock.RecvString(60000);     // up to 60 s of idle before we drop them
      if FSock.LastError <> 0 then
        Break;                             // timeout or disconnect
      if Line = 'QUIT' then
        Break;
      FSock.SendString('you said: ' + Line + CRLF);
    until Terminated;
  finally
    FSock.Free;   // closes the connection
  end;
end;
```

Straight-line code. It reads exactly like the protocol it speaks, because a
blocking socket lets it. Assigning to the `Socket` property is how you wrap the
raw handle that `Accept` returns in a full `TTCPBlockSocket`.

### The listener loop

```pascal
program EchoServer;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX} cthreads, {$ENDIF}   // FPC needs this unit for threads on Unix
  Classes, blcksock, synsock;        // synsock exports TSocket

  { ... TEchoThread from above ... }

var
  Listener: TTCPBlockSocket;
  ClientHandle: TSocket;
begin
  Listener := TTCPBlockSocket.Create;
  try
    Listener.CreateSocket;
    Listener.SetLinger(True, 10000);
    Listener.Bind('0.0.0.0', '9000');       // all interfaces, port 9000
    if Listener.LastError <> 0 then
    begin
      WriteLn('Bind failed: ', Listener.LastErrorDesc);
      Exit;
    end;
    Listener.Listen;
    WriteLn('Listening on port 9000...');

    repeat
      // CanRead lets the accept loop stay responsive and interruptible.
      if Listener.CanRead(1000) then
      begin
        ClientHandle := Listener.Accept;
        if Listener.LastError = 0 then
          TEchoThread.Create(ClientHandle);   // fire and forget; thread owns it now
      end;
    until False;   // real code: break on a shutdown flag
  finally
    Listener.Free;
  end;
end.
```

`CanRead(1000)` polls the listening socket for a pending connection with a
one-second timeout, so the loop wakes up regularly instead of blocking forever in
`Accept` — that's your hook for a clean shutdown flag. When a client is waiting,
`Accept` returns instantly with its handle, we spin up a `TEchoThread`, and we're
back at the top of the loop ready for the next one. The listener never does any
real work; the threads do. That is how one small program serves hundreds of
simultaneous connections.

> **Two rules for servers.** Give every connection its *own* thread, and never
> share one `TBlockSocket` across threads. Stay inside those two lines and
> Synapse's concurrency story stays as simple as the code above.

Connect to it with `telnet localhost 9000`, or point the client from section 1 at
it. This is a real, working server.

---

## 4. Going encrypted — TLS by adding one word

Here is the most elegant trick in the library. You do **not** rewrite your client
to speak HTTPS. TLS in Synapse is a *plugin*, selected purely by which unit you
put in your `uses` clause. Add one:

```pascal
uses
  Classes, httpsend,
  ssl_openssl;      // <-- this line turns on TLS
```

Just placing `ssl_openssl` (or `ssl_openssl3` for OpenSSL 3.x) in `uses`
registers an SSL implementation globally. Now the very same `THTTPSend` code from
section 2 handles `https://` URLs — the block socket underneath negotiates TLS on
your behalf when the scheme calls for it:

```pascal
if HTTP.HTTPMethod('GET', 'https://example.com/') then   // now works, unchanged
  WriteLn('Secure status: ', HTTP.ResultCode);
```

Nothing else in your program changes. That's the payoff of TLS-as-a-swappable-plugin:
the socket classes were written once with a seam for encryption, and the `ssl_*`
unit you link decides what fills it.

### STARTTLS — upgrading a live connection

Some protocols (SMTP, IMAP, FTP) start in plaintext and upgrade the *existing*
connection to TLS mid-stream. Synapse supports this directly: once you're
connected, call `SSLDoConnect` on the block socket to perform the TLS handshake in
place.

```pascal
Sock.Connect('mail.example.com', '587');
Sock.SendString('STARTTLS' + CRLF);   // tell the server we want to go secure
Sock.RecvString(5000);                // read its go-ahead
Sock.SSLDoConnect;                     // upgrade this live socket to TLS
if Sock.SSL.LastError <> 0 then
  WriteLn('TLS handshake failed: ', Sock.SSL.LastErrorDesc);
```

`SSLDoConnect` (declared on `TTCPBlockSocket` in `blcksock.pas`) runs the
handshake over the connection you already have. From that point on your `SendString`
and `RecvString` calls are encrypted, with no other change to your code. TLS-level
status lives on the socket's `SSL` object (`Sock.SSL.LastError` /
`Sock.SSL.LastErrorDesc`).

For the full picture of how the plugin seam works — the global `SSLImplementation`
metaclass and why a `uses` line is all it takes — read [The SSL plugin
seam](../01-architecture/03-ssl-plugin-seam.md).

---

## 5. Where to next

Two hours in, you can open connections, fetch and post over HTTP, run a threaded
server, and encrypt any of it. That is the whole shape of Synapse — everything
else is more protocols in the same mold.

- **The socket classes** — `TBlockSocket` and its family (TCP, UDP, raw, even
  serial), timeouts, `CanRead`/`CanWrite`, the receive functions beyond
  `RecvString` (`RecvTerminated`, `RecvPacket`). Start with [The blocking model &
  threads](../01-architecture/01-blocking-and-threads.md), then the socket-classes
  section for the full API surface.
- **The protocol classes** — SMTP (`smtpsend.pas`; try the `SendTo` free function
  for a fire-and-forget email), POP3, IMAP, FTP, NNTP, LDAP, DNS and more. Each is
  a thin readable class over a block socket, and each follows the exact rhythm you
  learned here: create, call a method, check status the Synapse way.
- **The architecture chapters** — [start here](../01-architecture/00-index.md) for
  the four seams that make all of this so small: the blocking model, the `synsock`
  OS seam, the SSL plugin, and Synapse's own hand-rolled crypto.

The library rewards curiosity. Because every layer is thin and orthogonal, reading
the source of any one class is a short trip — and now you know the vocabulary to
follow it.
