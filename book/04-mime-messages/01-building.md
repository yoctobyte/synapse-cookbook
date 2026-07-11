# Building a Message

The goal: a mail with a plain-text body **and** a file attachment, ready to hand
to `TSMTPSend`. That is a two-leaf tree under a `multipart/mixed` root, and
`TMimeMess` builds it in a handful of calls.

## The shape you are building

```
multipart/mixed              <- AddPartMultipart('mixed', nil)  -> root
├── text/plain               <- AddPartText(Body, root)
└── application/pdf           <- AddPartBinaryFromFile('report.pdf', root)
```

The rule from the source: to add **more than one** subpart you must have a
multipart parent, and the first argument to every `AddPart…` helper is that
parent. Pass `nil` for the root; pass the multipart part for each leaf.

## Worked example

```pascal
program BuildMail;

uses
  SysUtils, Classes,
  mimemess, mimepart,
  smtpsend, ssl_openssl;   // ssl_openssl enables STARTTLS / SMTPS

var
  Mime: TMimeMess;
  Body: TStringList;
  Root: TMimePart;
  Smtp: TSMTPSend;
begin
  Mime := TMimeMess.Create;
  Body := TStringList.Create;
  try
    // --- Headers -----------------------------------------------------------
    // From / ReplyTo / Subject are single strings; ToList / CCList take one
    // address per line. Subject is inline-encoded automatically, so non-ASCII
    // is fine.
    Mime.Header.From := 'alice@example.com';
    Mime.Header.ToList.Add('bob@example.org');
    Mime.Header.CCList.Add('carol@example.org');
    Mime.Header.Subject := 'Quarterly report (Æblegrød included)';
    // Date, Message-ID, MIME-Version and X-mailer are filled in for you on
    // encode if you leave them unset.

    // --- Body tree ---------------------------------------------------------
    // A message with an attachment needs a multipart/mixed container as root.
    Root := Mime.AddPartMultipart('mixed', nil);

    // The text body: text/plain, inline, quoted-printable, ideal charset.
    Body.Add('Hi Bob,');
    Body.Add('');
    Body.Add('The quarterly report is attached as a PDF.');
    Body.Add('');
    Body.Add('-- Alice');
    Mime.AddPartText(Body, Root);

    // The attachment: MIME type derived from the extension, base64, marked as
    // an attachment with this file name.
    Mime.AddPartBinaryFromFile('report.pdf', Root);

    // --- Serialise ---------------------------------------------------------
    // EncodeMessage merges Header into the root part and composes the whole
    // tree into Mime.Lines.
    Mime.EncodeMessage;

    // Mime.Lines is now a complete RFC-822 message. Send it.
    Smtp := TSMTPSend.Create;
    try
      Smtp.TargetHost := 'smtp.example.com';
      Smtp.TargetPort := '587';
      Smtp.UserName   := 'alice@example.com';
      Smtp.Password   := 's3cret';
      Smtp.AutoTLS    := True;             // STARTTLS before AUTH

      if not Smtp.Login then
        raise Exception.Create('SMTP login failed: ' + Smtp.ResultString);

      if Smtp.MailFrom('alice@example.com', Length(Mime.Lines.Text)) and
         Smtp.MailTo('bob@example.org') and
         Smtp.MailTo('carol@example.org') and
         Smtp.MailData(Mime.Lines) then      // <-- the seam: Lines -> MailData
        Writeln('Sent: ', Smtp.ResultString)
      else
        Writeln('Send failed: ', Smtp.ResultString);

      Smtp.Logout;
    finally
      Smtp.Free;
    end;
  finally
    Body.Free;
    Mime.Free;
  end;
end.
```

## What the calls actually did

- **`AddPartMultipart('mixed', nil)`** created the root part, set it to
  `multipart/mixed`, gave it a fresh `Boundary` (via `GenerateBoundary`), and
  encoded its header. Its return value is the parent you pass to the leaves.
- **`AddPartText(Body, Root)`** saved `Body` into the new part's
  `DecodedLines`, set `text/plain`, `inline`, quoted-printable, chose an ideal
  charset for the text, then called `EncodePart` + `EncodePartHeader`. The part
  comes back fully encoded.
- **`AddPartBinaryFromFile('report.pdf', Root)`** loaded the file into a memory
  stream, derived the MIME type from the extension (`application/PDF` from the
  built-in table; unknown extensions fall back to
  `application/octet-string`), set `Disposition := 'attachment'` and
  `FileName`, base64-encoded it, and built the header.
- **`EncodeMessage`** lifted the root part's `Content-*` headers up next to the
  `From/To/Subject/…` headers, composed every part into the wire form, and
  copied the result into `Mime.Lines`.

## Variations

**HTML with an inline image.** Swap the text leaf for an HTML leaf and add the
image as an inline (not attachment) part carrying a `Content-ID`:

```pascal
Root := Mime.AddPartMultipart('related', nil);        // 'related' ties HTML + cid
Html := TStringList.Create;
Html.Add('<p>See the chart: <img src="cid:chart1"></p>');
Mime.AddPartHTML(Html, Root);
Mime.AddPartHTMLBinaryFromFile('chart.png', 'chart1', Root);  // Cid = 'chart1'
```

`AddPartHTMLBinary…` sets `Disposition := 'inline'` and `ContentID := Cid`; the
HTML references it as `cid:chart1`. Use `multipart/related` (not `mixed`) so
mail clients know the image belongs to the HTML body.

**Content from files.** `AddPartTextFromFile` and `AddPartHTMLFromFile` are the
same as their in-memory versions but `LoadFromFile` the content for you.

**Precise charset / encoding control.** `AddPartText` picks the charset and
forces quoted-printable. When you need to override either — a fixed charset, a
`Raw` (no charset conversion) part, or base64 text — use `AddPartTextEx`:

```pascal
Mime.AddPartTextEx(Body, Root, UTF_8, {Raw=}False, ME_BASE64);
```

## Caveats

- **Build the tree before `EncodeMessage`.** `EncodeMessage` composes whatever
  is in `MessagePart` at call time; add all parts first, then encode once. Call
  it again only after changing the tree.
- **Envelope vs. header addresses are separate.** `MailFrom`/`MailTo` are the
  SMTP envelope; `Header.From`/`Header.ToList` are what the reader sees. They
  are usually the same, but `Bcc` works precisely by adding a `MailTo` with no
  matching header line — so do not expect a `Header.CCList` entry to reach a
  recipient unless you also `MailTo` them.
- **A single-part message needs no multipart.** If you only have a text body,
  skip `AddPartMultipart` and call `AddPartText(Body, nil)` to make the text
  the root directly. The multipart wrapper is only needed once you have two or
  more leaves.
