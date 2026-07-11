# Recipes — Email

Sending with `smtpsend`, composing MIME with `mimemess`, reading with
`pop3send`. Depth in [SMTP — TSMTPSend](../03-protocol-classes/03-tsmtpsend.md),
[POP3 — TPOP3Send](../03-protocol-classes/01-tpop3send.md), and
[MIME messages](../04-mime-messages/00-index.md).

## Send a plain-text mail

**Problem:** fire off one text email without touching the SMTP object.

```pascal
program SendMail;

{$mode objfpc}{$H+}

uses
  Classes, smtpsend;

var
  Msg: TStringList;
begin
  Msg := TStringList.Create;
  try
    Msg.Add('Hello from Synapse.');
    Msg.Add('This is the body.');

    // SendTo(MailFrom, MailTo, Subject, SMTPHost, MailData): Boolean
    if SendTo('me@example.com', 'you@example.com',
              'Test message', 'mail.example.com', Msg) then
      WriteLn('Sent')
    else
      WriteLn('Send failed');
  finally
    Msg.Free;
  end;
end.
```

`SendTo` builds the headers, connects, and delivers in one call. **Gotcha:** it
takes **no** username/password — it's for open/relay-by-IP servers. For
authenticated SMTP use `SendToEx(..., Username, Password)`, or the `TSMTPSend`
object (`FullSSL := True` for SMTPS on port 465, or `ssl_openssl` in `uses` +
STARTTLS for 587).

## Send a mail with an attachment

**Problem:** build a multipart message with a text body and a file attachment,
then hand it to `TSMTPSend`.

```pascal
program SendAttachment;

{$mode objfpc}{$H+}

uses
  Classes, mimemess, mimepart, smtpsend;

var
  Mime: TMimeMess;
  Body: TStringList;
  SMTP: TSMTPSend;
begin
  Mime := TMimeMess.Create;
  Body := TStringList.Create;
  try
    Body.Add('Report attached.');

    Mime.Header.From := 'me@example.com';
    Mime.Header.ToList.Add('you@example.com');
    Mime.Header.Subject := 'Monthly report';

    Mime.AddPartText(Body, nil);                    // the text body
    Mime.AddPartBinaryFromFile('report.pdf', nil);  // the attachment
    Mime.EncodeMessage;                             // -> Mime.Lines

    SMTP := TSMTPSend.Create;
    try
      SMTP.TargetHost := 'mail.example.com';
      SMTP.Username := 'me@example.com';
      SMTP.Password := 'secret';
      if SMTP.Login and
         SMTP.MailFrom('me@example.com', Length(Mime.Lines.Text)) and
         SMTP.MailTo('you@example.com') and
         SMTP.MailData(Mime.Lines) then
        WriteLn('Sent')
      else
        WriteLn('SMTP error: ', SMTP.ResultString);
      SMTP.Logout;
    finally
      SMTP.Free;
    end;
  finally
    Body.Free;
    Mime.Free;
  end;
end.
```

**Gotcha:** you must call `Mime.EncodeMessage` **before** reading `Mime.Lines` —
that's the step that renders the parts into the encoded message. The recipient
list on the envelope (`MailTo`) is separate from the `To:` header
(`Header.ToList`); set both. For an authenticated/TLS server, add `ssl_openssl`
to `uses` and set `SMTP.FullSSL := True` (or STARTTLS) as the SMTP chapter shows.

## Fetch and list an inbox

**Problem:** log into POP3, report how many messages are waiting, and show the
first line of each.

```pascal
program ListInbox;

{$mode objfpc}{$H+}

uses
  Classes, pop3send;

var
  POP3: TPOP3Send;
  i: Integer;
begin
  POP3 := TPOP3Send.Create;
  try
    POP3.TargetHost := 'mail.example.com';
    POP3.Username := 'me@example.com';
    POP3.Password := 'secret';

    if not POP3.Login then
    begin
      WriteLn('Login failed: ', POP3.ResultString);
      Exit;
    end;

    POP3.Stat;                                     // fills StatCount / StatSize
    WriteLn(POP3.StatCount, ' messages, ', POP3.StatSize, ' bytes');

    for i := 1 to POP3.StatCount do
      if POP3.Retr(i) then                         // full message -> FullResult
        WriteLn(i, ': ', POP3.FullResult[0]);

    POP3.Logout;
  finally
    POP3.Free;
  end;
end.
```

`Stat` populates `StatCount` and `StatSize`; messages are numbered `1..StatCount`
and their text lands in the `FullResult` string list after `Retr`. **Gotcha:**
`Retr` downloads the *whole* message — for just the headers use
`Top(Index, 0)`, which is far cheaper on a big mailbox. For POP3S add
`ssl_openssl` to `uses` and set `POP3.FullSSL := True` (port 995).
