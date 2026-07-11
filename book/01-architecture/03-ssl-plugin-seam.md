# The SSL Plugin Seam

This is Synapse's most elegant idea, and worth studying even if you never write
Pascal: **TLS is not a feature of the socket — it is a plugin selected at link
time and attached to a live connection.**

## The problem it solves

A naive socket library bakes SSL in: `#ifdef` around OpenSSL, a `UseSSL: Boolean`
flag, and the library now *depends* on one TLS implementation forever. Change
your mind (OpenSSL → SChannel → a hardware library) and you rewrite the socket.

Synapse refuses that. The block socket knows *nothing* about any specific TLS
library. It only knows an abstract contract.

## How it works

In `blcksock.pas`:

```pascal
type
  TCustomSSL = class;                 // abstract TLS contract
  TSSLClass = class of TCustomSSL;    // a metaclass (class reference)

var
  SSLImplementation: TSSLClass = TSSLNone;   // global default: "no TLS"
```

Three moving parts:

1. **`TCustomSSL`** — an abstract base class defining what a TLS provider must do
   (`Connect`, `Accept`, `Shutdown`, read/write, certificate handling…).
2. **`TSSLNone`** — a null-object implementation. With no TLS unit included, this
   is what you get: a socket that simply passes bytes through, unencrypted.
3. **`SSLImplementation`** — a single global **metaclass variable**. Every socket
   creates its TLS object from it:

   ```pascal
   FSSL := SSLImplementation.Create(self);   // in the socket constructor
   ```

The trick: each concrete provider unit **sets that global in its own
initialization**. `ssl_openssl.pas`, `ssl_schannel.pas`, `ssl_cryptlib.pas`,
`ssl_streamsec.pas`, `ssl_libssh2.pas`, and more each do, in effect:

```pascal
initialization
  SSLImplementation := TSSLOpenSSL;   // (or TSSLSChannel, TSSLCryptLib, …)
```

So **you choose your TLS backend simply by which unit appears in `uses`.** No
flag, no factory call, no configuration:

```pascal
uses blcksock, ssl_openssl;   // <-- this line is the entire choice
```

Include `ssl_openssl` and every socket transparently gains OpenSSL. Swap it for
`ssl_schannel` and the *same socket code* now uses Windows' native TLS. Include
nothing and you get `TSSLNone` — plaintext, zero TLS dependency. The socket
classes never change.

## TLS "midway" — upgrading a live socket

Because TLS is a layer attached to an already-open `TBlockSocket`, you can start
a connection in plaintext and **upgrade it to TLS mid-stream** — exactly what
protocols like SMTP `STARTTLS`, IMAP, FTP-over-TLS, and LDAP need:

```pascal
sock.Connect(host, '25');        // plaintext
// ... negotiate STARTTLS in the protocol ...
sock.SSLDoConnect;               // upgrade this live socket to TLS
```

`SSLDoConnect` hands the existing connection to the plugin, which performs the
handshake over it. The protocol clients (`smtpsend`, `imapsend`, …) use exactly
this to implement opportunistic encryption.

## Why it is beautiful

- **Zero coupling.** The socket depends on an *interface* (`TCustomSSL`), never a
  library. OpenSSL is not a dependency of Synapse — it is a dependency of *your
  choice to include `ssl_openssl`*.
- **Link-time polymorphism, no cost.** The selection is a metaclass assignment at
  unit initialization — no runtime factory, no config parsing.
- **Extensible by outsiders.** Anyone can add a new TLS provider by writing one
  unit that descends `TCustomSSL` and sets `SSLImplementation`. The core never
  learns their name. (The ~20 `ssl_*` units in the tree are exactly this,
  accreted over 20 years.)
- **Graceful default.** No TLS unit → `TSSLNone` → it still compiles and runs,
  just unencrypted. Nothing to stub.

This is the null-object pattern and link-time strategy selection, done in a few
lines of Object Pascal, years before those names were common vocabulary.
