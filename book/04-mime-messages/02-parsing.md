# Parsing a Message

Receiving is the mirror of building. You have the raw RFC-822 bytes (from
`TPOP3Send`, `TIMAPSend`, an `.eml` file — anywhere), and you want the parsed
headers, the readable text, and the attachments written to disk. `TMimeMess`
decodes the message; walking the `TMimePart` tree pulls out the pieces.

## The two-step decode

`TMimeMess.DecodeMessage` does two things, from the source:

1. `Header.DecodeHeaders(Lines)` — parses the mail headers into `From`,
   `ToList`, `Subject`, `Date`, … (and everything else into `CustomHeaders`).
2. `MessagePart.DecomposeParts` — parses the body into the part tree.

Crucially, `DecomposeParts` **does not decode the part bodies** — it only splits
the tree and reads each part's headers. Decoding a body (base64 →
bytes, quoted-printable → text, charset conversion) is a separate `DecodePart`
call per part, deliberately, so you don't pay to decode a 10 MB attachment you
are going to skip. So the rhythm is: `DecodeMessage` once, then `DecodePart` on
each leaf you actually want.

## Walking the tree

Two ways to visit every node:

- **Manual recursion** with `GetSubPartCount` / `GetSubPart(i)` — full control,
  easy to read.
- **The `WalkPart` hook** — assign an `OnWalkPart` handler and Synapse calls it
  for the part and every descendant (it propagates the hook down the tree for
  you).

This example uses manual recursion.

## Worked example

```pascal
program ParseMail;

uses
  SysUtils, Classes,
  mimemess, mimepart;

// Recursively visit every part; decode text into Text, save attachments.
procedure HandlePart(Part: TMimePart; const Text: TStrings);
var
  i: Integer;
begin
  case Part.PrimaryCode of
    MP_MULTIPART:
      // A container — recurse into its children, nothing to decode here.
      for i := 0 to Part.GetSubPartCount - 1 do
        HandlePart(Part.GetSubPart(i), Text);

    MP_MESSAGE:
      // An embedded message/rfc822 — it too has subparts; recurse.
      for i := 0 to Part.GetSubPartCount - 1 do
        HandlePart(Part.GetSubPart(i), Text);

    MP_TEXT:
      begin
        Part.DecodePart;   // Lines -> DecodedLines (+ charset conversion)
        // Only fold plain text into the body; skip 'html' if you prefer.
        if LowerCase(Part.Secondary) = 'plain' then
        begin
          Part.DecodedLines.Position := 0;
          Text.LoadFromStream(Part.DecodedLines);
        end;
      end;

    MP_BINARY:
      begin
        // An attachment (or inline image). Decode and write it out.
        Part.DecodePart;
        if Part.FileName <> '' then
        begin
          Part.DecodedLines.Position := 0;
          Part.DecodedLines.SaveToFile('inbox_' + ExtractFileName(Part.FileName));
          Writeln('Saved attachment: ', Part.FileName,
                  ' (', Part.DecodedLines.Size, ' bytes)');
        end;
      end;
  end;
end;

var
  Mime: TMimeMess;
  Text: TStringList;
begin
  Mime := TMimeMess.Create;
  Text := TStringList.Create;
  try
    // Load the raw message into Lines. (Here from a file; in practice this is
    // whatever POP3/IMAP handed you.)
    Mime.Lines.LoadFromFile('received.eml');

    // Step 1: parse headers + split the part tree (bodies NOT yet decoded).
    Mime.DecodeMessage;

    Writeln('From:    ', Mime.Header.From);
    Writeln('Subject: ', Mime.Header.Subject);
    Writeln('Date:    ', DateTimeToStr(Mime.Header.Date));
    Writeln('To:      ', Mime.Header.ToList.CommaText);

    // Step 2: walk the tree, decoding parts on demand.
    HandlePart(Mime.MessagePart, Text);

    Writeln('--- body ---');
    Writeln(Text.Text);
  finally
    Text.Free;
    Mime.Free;
  end;
end.
```

## Reading the results

- **Headers** are on `Mime.Header` as typed fields the moment `DecodeMessage`
  returns — `From`, `Subject`, `ToList`, `Date`, and so on. Anything the parser
  did not special-case (e.g. `Received:`, `X-Spam-Score:`) is in
  `CustomHeaders`; fetch it with `Header.FindHeader('X-Spam-Score')` or, for a
  header that repeats, `Header.FindHeaderList('Received', List)`.
- **The body** is the `MessagePart` tree. For a simple message the root *is* the
  text part (`PrimaryCode = MP_TEXT`, `GetSubPartCount = 0`); for a multipart
  message the root is `MP_MULTIPART` and the leaves are its children. The
  recursion above handles both without a special case.
- **Distinguishing body from attachment** is by `Disposition` and `FileName`:
  an attachment has `Disposition = 'attachment'` and a non-empty `FileName`; an
  inline image has `Disposition = 'inline'` and a `ContentID`. The example keys
  off `FileName` being set, which catches both cases where there is a file to
  write.

## Using the WalkPart hook instead

If you prefer a flat callback to explicit recursion, assign `OnWalkPart` on the
root and call `WalkPart` — Synapse invokes your handler for the root and every
descendant:

```pascal
type
  TCollector = class
    procedure OnPart(const Sender: TMimePart);
  end;

procedure TCollector.OnPart(const Sender: TMimePart);
begin
  if (Sender.PrimaryCode = MP_BINARY) and (Sender.FileName <> '') then
  begin
    Sender.DecodePart;
    Sender.DecodedLines.Position := 0;
    Sender.DecodedLines.SaveToFile(ExtractFileName(Sender.FileName));
  end;
end;

// ...
Coll := TCollector.Create;
Mime.MessagePart.OnWalkPart := Coll.OnPart;
Mime.MessagePart.WalkPart;    // fires OnPart for the root and all subparts
```

`WalkPart` only calls your hook if `OnWalkPart` is assigned, and it copies the
hook onto each child before descending — so one assignment on the root covers
the whole tree.

## Caveats

- **`DecomposeParts` splits, `DecodePart` decodes.** Reading `DecodedLines`
  without first calling `DecodePart` on that part gives you nothing useful — the
  decoded stream is only populated by `DecodePart`. Always decode the leaf
  before you read its `DecodedLines`.
- **Reset the stream position.** `DecodedLines` is a `TMemoryStream`; set
  `Position := 0` before `LoadFromStream`/reading, or `SaveToFile` (which seeks
  itself) as shown.
- **Malformed real-world mail.** Broken senders (the source singles out some
  Outlook versions) omit charset labels; `DefaultCharset` on the part governs
  how such text is decoded — adjust it before `DecodePart` if you see mojibake.
- **Depth limiting.** `MaxSubLevel` on a part caps how deep `DecomposeParts`
  will recurse (default `-1` = unlimited). Set it to guard against pathological
  deeply-nested messages.
- **Binary receive path.** If the raw message came from `THTTPSend` (headers and
  an 8-bit body stream held separately, no transfer encoding applied), use
  `DecodeMessageBinary(AHeader, AData)` instead of `DecodeMessage` — it is the
  8-bit-native equivalent.
