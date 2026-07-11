# TPOP3Send

POP3 is the simplest of the mail protocols — a numbered mailbox you connect to,
count, download, and delete from — and `TPOP3Send` (in `pop3send`) is a faithful,
compact mirror of it. If you have read the [protocol-class
overview](00-index.md), everything here will feel familiar: a `TSynaClient`
descendant wrapping a `TTCPBlockSocket`, a `Login`, a handful of verbs, a
`Logout`.

## The class at a glance

The credentials and connection properties come from the base `TSynaClient`
(`TargetHost`, `TargetPort`, `UserName`, `Password`, `Timeout`). `TPOP3Send`
adds the POP3 verbs and a few result holders:

```pascal
TPOP3Send = class(TSynaClient)
  function Login: Boolean;
  function Logout: Boolean;
  function Stat: Boolean;              // -> StatCount, StatSize
  function List(Value: Integer): Boolean;   // 0 = all messages
  function Retr(Value: Integer): Boolean;   // download message N
  function RetrStream(Value: Integer; Stream: TStream): Boolean;
  function Dele(Value: Integer): Boolean;   // mark message N deleted
  function Top(Value, Maxlines: Integer): Boolean;
  function Uidl(Value: Integer): Boolean;   // unique-id listing
  function Reset: Boolean;            // RSET
  function NoOp: Boolean;
  function Capability: Boolean;       // CAPA
  function StartTLS: Boolean;         // STLS upgrade
  function CustomCommand(const Command: string; MultiLine: Boolean): Boolean;

  property ResultCode: Integer;       // 1 = OK, 0 = error
  property ResultString: string;      // the server's +OK / -ERR line
  property FullResult: TStringList;   // multiline payload (message, listing…)
  property StatCount: Integer;        // messages in mailbox, after Stat
  property StatSize: Integer;         // total bytes, after Stat
  property ListSize: Integer;         // size of one message, after List(N)
  property TimeStamp: string;         // APOP challenge, if the server sent one
  property AuthType: TPOP3AuthType;   // POP3AuthAll | POP3AuthLogin | POP3AuthAPOP
  property AutoTLS: Boolean;
  property FullSSL: Boolean;
  property Sock: TTCPBlockSocket;
end;
```

A couple of things worth noting from the source. `ResultCode` is *not* an HTTP-
style code — POP3 only ever answers `+OK` or `-ERR`, so `ResultCode` is simply
`1` for success and `0` for failure, and the raw reply line is in `ResultString`.
Every multiline reply (a retrieved message, a `LIST` of the whole mailbox) lands
in `FullResult`, a `TStringList`, with POP3's byte-stuffed leading dots already
un-stuffed for you.

## Authentication: where the hand-rolled crypto earns its keep

`Login` does the whole handshake for you, and its auth logic is a nice
illustration of why Synapse [rolls its own
crypto](../01-architecture/04-own-crypto.md). The default `AuthType` is
`POP3AuthAll`, which means *autodetect*:

- If the server's greeting carries an **APOP timestamp** (a `<...>` token, stored
  in the `TimeStamp` property), `Login` tries **APOP**: it hashes
  `MD5(TimeStamp + Password)` and sends the digest, so the password never crosses
  the wire. That `MD5` is the one in `synacode` — no external library.
- Otherwise it falls back to plain **USER/PASS**.
- If you set `OAuth2Token` on the client, `Login` uses **XOAUTH2** instead.

You can force one path by setting `AuthType` to `POP3AuthLogin` (USER/PASS only)
or `POP3AuthAPOP` (APOP only).

> **Honest caveat.** USER/PASS sends your password in the clear, and APOP —
> though it hides the password — relies on MD5 and is long deprecated. Neither is
> safe on an untrusted network *by itself*. For real security, put the session
> inside TLS (below); then even USER/PASS is protected by the transport.

## TLS: implicit tunnel or STLS upgrade

As with every Synapse client, TLS is a `uses` clause away — add an `ssl_*`
plugin and pick one of two styles:

```pascal
uses pop3send, ssl_openssl;
```

- **POP3S (implicit).** Set `FullSSL := True` and point `TargetPort` at `995`.
  The socket does its TLS handshake the moment it connects.
- **STLS (explicit upgrade).** Set `AutoTLS := True`. During `Login`, if the
  server's `CAPA` advertises `STLS`, the live plaintext connection is upgraded to
  TLS before authentication — Synapse re-runs `Capability` afterwards so the post-
  TLS capability set is the one you see.

## Worked example: fetch and print the first message

```pascal
program PopFetch;

uses
  SysUtils, Classes,
  pop3send, ssl_openssl;   // ssl_openssl supplies TLS for STLS / POP3S

var
  Pop: TPOP3Send;
  i: Integer;
begin
  Pop := TPOP3Send.Create;
  try
    Pop.TargetHost := 'mail.example.com';
    Pop.UserName   := 'alice';
    Pop.Password   := 's3cret';
    Pop.AutoTLS    := True;          // upgrade with STLS if offered

    if not Pop.Login then
    begin
      Writeln('Login failed: ', Pop.ResultString);
      Halt(1);
    end;

    // How many messages, and how many bytes total?
    if Pop.Stat then
      Writeln(Format('Mailbox: %d messages, %d bytes',
        [Pop.StatCount, Pop.StatSize]));

    if Pop.StatCount > 0 then
    begin
      // Retrieve message #1 in full; it lands in FullResult, line by line.
      if Pop.Retr(1) then
      begin
        Writeln('--- message 1 ---');
        for i := 0 to Pop.FullResult.Count - 1 do
          Writeln(Pop.FullResult[i]);
      end
      else
        Writeln('RETR failed: ', Pop.ResultString);

      // To delete it instead (marked now, removed at QUIT):
      // Pop.Dele(1);
    end;

    Pop.Logout;                      // sends QUIT and closes the socket
  finally
    Pop.Free;
  end;
end.
```

The retrieved message in `FullResult` is the raw RFC-822 text — headers, a blank
line, then the body, exactly as the server stored it. To turn that into decoded
subject/from/body fields (and to walk MIME attachments), feed it to a
`TMimeMess` and call `DecodeMessage`; the mail-message chapter covers that.

## Peeking without downloading

Two verbs let you inspect a mailbox cheaply:

- **`Top(N, Lines)`** downloads message `N`'s headers plus the first `Lines`
  lines of its body into `FullResult` — ideal for a message-list preview without
  pulling megabytes.
- **`Uidl(N)`** returns a stable *unique id* for a message (or, with `0`, for the
  whole mailbox in `FullResult`). Because POP3 message numbers are only stable
  within a single session, UIDLs are how a "leave mail on server, download only
  what's new" client remembers what it has already seen.

## Deletion is deferred

`Dele(N)` does not delete immediately — it *marks* the message, and the server
only actually removes marked messages when the session ends cleanly with
`Logout` (QUIT). Call `Reset` to clear all delete marks in the current session,
and remember that dropping the connection without `Logout` abandons the
deletions.

## Streaming large messages

For a big message you do not want the whole thing buffered in a `TStringList`.
`RetrStream(N, AStream)` writes message `N` straight into any `TStream` (a file,
a memory stream) as it arrives, bypassing `FullResult` entirely — the right tool
for large attachments.
