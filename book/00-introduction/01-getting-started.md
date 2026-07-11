# Getting Started

New to Synapse — or to network programming in general? Start here. In a few
minutes you will have a program that talks to the internet. No prior networking
knowledge assumed.

## A 60-second mental model

Networking is simpler than it sounds:

- A **host** is a computer on a network, named by an address like `example.com`
  or `93.184.216.34`. Turning a name into an address is **DNS**.
- A **port** is a numbered door on that host. Web servers listen on port 80
  (443 for HTTPS), mail on 25, and so on.
- A **socket** is your end of a connection to `host:port`. You open it, send
  bytes, receive bytes, close it. That's it.

A **client** opens connections (your browser); a **server** waits for them (the
web server). Synapse does both. Everything else in this book is detail on top of
those four words: host, port, socket, bytes.

## What you need

1. **A Pascal compiler.** [Free Pascal](https://www.freepascal.org/) (FPC) with
   or without the [Lazarus](https://www.lazarus-ide.org/) IDE, or Delphi. All are
   supported.
2. **Ararat Synapse** itself — it is a set of source units, nothing to compile or
   install as a library. Get it from
   [github.com/geby/synapse](https://github.com/geby/synapse) (or the
   [homepage](https://synapse.ararat.cz/)) and unzip it somewhere, e.g.
   `~/synapse`.

That's the whole setup. Synapse has **no external dependencies** for the basics
(see [Rolling its own crypto](../01-architecture/04-own-crypto.md)); you only add
an SSL unit later if you want TLS.

## Hello, network — fetch a web page

The friendliest possible start. This downloads a page and prints it:

```pascal
program hello_net;
uses httpsend;              // Synapse's HTTP client
var
  page: string;
begin
  if HttpGetText('http://example.com/', page) then
    WriteLn(page)
  else
    WriteLn('request failed');
end.
```

`HttpGetText` is a one-line convenience: give it a URL and a string, it fills the
string with the response body and returns `True`/`False`. You just made an HTTP
request. (For HTTPS, add one unit — see below.)

## Hello, socket — the raw version

To *see* the socket underneath, connect to a host and read what it says. Here we
open a plain TCP connection and read the greeting a server sends:

```pascal
program hello_socket;
uses blcksock;             // Synapse's socket classes
var
  sock: TTCPBlockSocket;
begin
  sock := TTCPBlockSocket.Create;
  try
    sock.Connect('example.com', '80');        // host, port (as strings)
    if sock.LastError <> 0 then
    begin
      WriteLn('connect failed: ', sock.LastErrorDesc);
      Exit;
    end;
    sock.SendString('GET / HTTP/1.0' + CRLF + CRLF);   // ask for the page
    WriteLn(sock.RecvString(3000));           // read one line, wait up to 3 s
  finally
    sock.Free;
  end;
end.
```

Two habits to notice, because they run through all of Synapse:

- **Ports are strings** (`'80'`), not integers — Synapse also accepts service
  names.
- **Check `LastError` after operations.** Synapse *reports* problems rather than
  raising exceptions, which keeps your code a straight line. `LastError = 0`
  means success; `LastErrorDesc` is the human-readable reason. This is the whole
  error model — no try/except gymnastics required.

## Compiling it

**With FPC on the command line** — point it at the Synapse source with `-Fu`:

```sh
fpc -Fu~/synapse hello_net.pas
./hello_net
```

**With Lazarus** — Project → Project Options → Compiler Options → Paths, and add
`~/synapse` to *Other unit files (-Fu)*. Then Run.

That's it — the same `-Fu path` idea, once per project.

## Going encrypted (one line)

Want HTTPS instead of HTTP? Add a single SSL unit to `uses` and use an `https://`
URL — nothing else changes:

```pascal
uses httpsend, ssl_openssl;        // that extra unit is the entire TLS wiring
...
HttpGetText('https://example.com/', page);
```

That one line is Synapse's [SSL plugin seam](../01-architecture/03-ssl-plugin-seam.md)
at work — TLS is a plugin you switch on by including it.

## Where to go next

- **[Synapse in Two Hours](../99-appendix-tutorials/synapse-in-two-hours.md)** —
  the fuller tutorial: HTTP GET/POST, a threaded echo *server*, TLS.
- **[The Architecture of Synapse](../01-architecture/00-index.md)** — *why* it is
  shaped this way; short and worth it.
- **[Recipes](../08-recipes/00-index.md)** — copy-paste solutions to common tasks
  (send mail, download a file, resolve a name, ping a host, talk to a serial
  port).

You now know the whole shape: open a socket to `host:port`, send and receive
bytes, check `LastError`, close. Everything else is a protocol class doing that
for you.
