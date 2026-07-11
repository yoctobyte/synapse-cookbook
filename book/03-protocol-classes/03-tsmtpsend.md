# TSMTPSend — sending mail

`TSMTPSend` (in `smtpsend`) is the send half of the mail story. It speaks SMTP
and ESMTP, handles the `EHLO`/`HELO` negotiation, authenticates with the best
mechanism the server offers, and — with an SSL plugin in `uses` — upgrades the
session to TLS. As with every Synapse client it is a thin `TSynaClient`
descendant over a `TTCPBlockSocket`; you set a few properties and call the verbs
in the order the protocol expects.

## The class at a glance

Credentials and connection come from `TSynaClient`
(`TargetHost`, `TargetPort`, `UserName`, `Password`). `TSMTPSend` adds the SMTP
verbs and ESMTP state:

```pascal
TSMTPSend = class(TSynaClient)
  function Login: Boolean;            // connect, EHLO/HELO, STARTTLS, AUTH
  function Logout: Boolean;           // QUIT + close
  function MailFrom(const Value: string; Size: Integer): Boolean;   // MAIL FROM
  function MailTo(const Value: string): Boolean;                    // RCPT TO
  function MailData(const Value: TStrings): Boolean;                // DATA + body
  function Reset: Boolean;            // RSET
  function NoOp: Boolean;
  function Verify(const Value: string): Boolean;   // VRFY
  function Etrn(const Value: string): Boolean;
  function StartTLS: Boolean;         // STARTTLS upgrade
  function FindCap(const Value: string): string;   // query an ESMTP capability

  property ResultCode: Integer;       // the numeric SMTP reply code (250, 550…)
  property ResultString: string;      // the last reply line
  property FullResult: TStringList;   // the full (maybe multiline) reply
  property ESMTPcap: TStringList;     // capabilities from EHLO
  property ESMTP: Boolean;            // True if the server spoke ESMTP
  property AuthDone: Boolean;         // True if AUTH succeeded
  property ESMTPSize: Boolean;
  property MaxSize: Integer;          // server's max message size, if advertised
  property SystemName: string;        // name we send in HELO/EHLO
  property AutoTLS: Boolean;
  property FullSSL: Boolean;
  property Sock: TTCPBlockSocket;
end;
```

Unlike POP3's `1/0`, SMTP's `ResultCode` is the real three-digit reply code, so
you can reason about it directly (`250` OK, `354` "send your data", `550`
rejected, …). Synapse also parses RFC-3463 enhanced status codes into
`EnhCode1/2/3`, with `EnhCodeString` giving a human sentence for the last one.

## What `Login` does for you

`Login` is a lot of protocol folded into one call. Reading the source, it:

1. Connects (doing an immediate TLS handshake first if `FullSSL` is set).
2. Sends **`EHLO`**; if the server rejects ESMTP it falls back to plain `HELO`.
3. Parses the advertised capabilities into `ESMTPcap`.
4. If `AutoTLS` is set and the server advertises `STARTTLS`, upgrades the live
   connection to TLS and re-runs `EHLO`.
5. If you supplied a `UserName`/`Password`, authenticates — **preferring
   CRAM-MD5**, then `PLAIN`, then `LOGIN`, based on what the server's `AUTH`
   capability lists. All three digests/encodings come from `synacode`
   (HMAC-MD5, Base64) — no external crypto library. `AuthDone` tells you whether
   auth actually happened.

The name announced in `HELO`/`EHLO` defaults to the socket's local name; override
it via `SystemName` if you need a specific identity.

## STARTTLS via the plugin

TLS is the usual [SSL plugin seam](../01-architecture/03-ssl-plugin-seam.md) —
one unit in `uses`, then choose implicit or explicit:

```pascal
uses smtpsend, ssl_openssl;
```

- **Submission with STARTTLS (explicit).** Set `AutoTLS := True`, use the
  submission port `TargetPort := '587'` (or plain `25`). `Login` upgrades the
  connection before it authenticates, so your credentials go out encrypted.
- **SMTPS (implicit).** Set `FullSSL := True`, `TargetPort := '465'`. The TLS
  handshake happens the instant the socket connects.

> **Honest caveat.** `AUTH LOGIN` and `AUTH PLAIN` hand the server your password
> (Base64 is encoding, not encryption). Only send credentials over a TLS-upgraded
> session — which is exactly why `Login` performs STARTTLS *before* AUTH when
> `AutoTLS` is on.

## The send rhythm

An SMTP transaction is a fixed sequence of verbs, and `TSMTPSend` maps one method
to each:

```
Login  ->  MailFrom(sender)  ->  MailTo(rcpt)  [->  MailTo(rcpt2) …]  ->  MailData(lines)  ->  Logout
```

`MailFrom` takes an optional size (pass the byte length of your message, or `0`);
if the server advertised the `SIZE` extension it will be sent along so an
over-limit message is rejected up front. `MailTo` is called once per recipient.
`MailData` takes a `TStrings` holding the **complete RFC-822 message** — headers,
a blank line, then the body — and handles SMTP's dot-stuffing for you.

## Worked example: send a plain message

```pascal
program SmtpSend;

uses
  SysUtils, Classes,
  smtpsend, ssl_openssl;   // ssl_openssl enables STARTTLS / SMTPS

var
  Smtp: TSMTPSend;
  Msg: TStringList;
begin
  Smtp := TSMTPSend.Create;
  Msg  := TStringList.Create;
  try
    // Build the full RFC-822 message: headers, blank line, body.
    Msg.Add('From: Alice <alice@example.com>');
    Msg.Add('To: Bob <bob@example.org>');
    Msg.Add('Subject: Hello from Synapse');
    Msg.Add('Date: ' + Rfc822DateTime(Now));   // Rfc822DateTime is in synautil
    Msg.Add('');                                // <-- header/body separator
    Msg.Add('This message was sent with TSMTPSend.');

    Smtp.TargetHost := 'smtp.example.com';
    Smtp.TargetPort := '587';        // submission port
    Smtp.UserName   := 'alice@example.com';
    Smtp.Password   := 's3cret';
    Smtp.AutoTLS    := True;          // STARTTLS before AUTH

    if not Smtp.Login then
    begin
      Writeln('Login failed: ', Smtp.ResultString);
      Halt(1);
    end;

    if Smtp.MailFrom('alice@example.com', Length(Msg.Text)) and
       Smtp.MailTo('bob@example.org') and
       Smtp.MailData(Msg) then
      Writeln('Sent. Server said: ', Smtp.ResultString)
    else
      Writeln('Send failed: ', Smtp.ResultString);

    Smtp.Logout;
  finally
    Msg.Free;
    Smtp.Free;
  end;
end.
```

The envelope addresses in `MailFrom`/`MailTo` are the SMTP-level sender and
recipients; the `From:`/`To:` *header* lines inside the message are separate
(what the reader sees). They are usually the same, but need not be — that split
is how mailing lists and `Bcc:` work.

## Composing the body with mimemess

Hand-assembling headers is fine for a one-line notification, but the moment you
want a subject with non-ASCII characters, an HTML alternative, or a file
attachment, reach for **`TMimeMess`** (in `mimemess`). It builds a correct MIME
message and serialises it to the `TStrings` that `MailData` wants:

```pascal
uses smtpsend, mimemess, mimepart, ssl_openssl;

var
  Mime: TMimeMess;
  Body: TStringList;
begin
  Mime := TMimeMess.Create;
  Body := TStringList.Create;
  try
    Mime.Header.From := 'alice@example.com';
    Mime.Header.ToList.Add('bob@example.org');
    Mime.Header.Subject := 'Report attached';

    Body.Add('Hi Bob, see the attached report.');
    Mime.AddPartText(Body, nil);                 // text/plain part
    Mime.AddPartBinaryFromFile('report.pdf', nil);  // attachment

    Mime.EncodeMessage;        // builds the full message into Mime.Lines

    // Mime.Lines is now the complete RFC-822 message -> hand it to MailData:
    // Smtp.MailData(Mime.Lines);
  finally
    Body.Free;
    Mime.Free;
  end;
end;
```

After `EncodeMessage`, `Mime.Lines` is exactly the `TStrings` `MailData` expects,
so the two compose cleanly: `TMimeMess` owns *what the message is*, `TSMTPSend`
owns *getting it to the server*. See the mail-message chapter for the full
`TMimeMess` treatment (parts, alternatives, inline images, charset handling).

## The shortcut functions

If you just want to fire one message off and do not need the object, `smtpsend`
exposes three module-level helpers that create a `TSMTPSend`, run the whole
`Login`/`MailFrom`/`MailTo`/`MailData`/`Logout` dance, and free it:

```pascal
function SendTo(const MailFrom, MailTo, Subject, SMTPHost: string;
  const MailData: TStrings): Boolean;
function SendToEx(const MailFrom, MailTo, Subject, SMTPHost: string;
  const MailData: TStrings; const Username, Password: string): Boolean;
function SendToRaw(const MailFrom, MailTo, SMTPHost: string;
  const MailData: TStrings; const Username, Password: string): Boolean;
```

`SendTo` builds the `From/To/Subject/Date` headers for you and needs only the
body; `SendToEx` adds authentication; `SendToRaw` takes an already-complete
message (headers and all — the natural partner for `TMimeMess.Lines`). Append a
`:port` to `SMTPHost` to override the port. They are the "send and forget" path;
drop to the object whenever you need TLS toggles, capability inspection, or per-
recipient control.
</content>
