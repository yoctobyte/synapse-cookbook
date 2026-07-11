# MIME & Mail Messages

`TSMTPSend` gets a message to the server, but it does not care what the message
*is* — `MailData` takes a `TStrings` holding a complete RFC-822 message and
sends it verbatim. Producing that `TStrings` correctly — headers with non-ASCII
subjects, a text body, an HTML alternative, file attachments, inline images —
is a separate job, and it belongs to a separate pair of units:

- **`mimepart`** — `TMimePart`, one node of a MIME tree. Knows how to encode and
  decode a single part (its headers, its transfer encoding, its body) and holds
  a list of child parts.
- **`mimemess`** — `TMimeMess`, the whole message: a `TMessHeader` (the mail
  headers) plus a root `TMimePart` (the body tree), with convenience methods
  that build the common part shapes for you.
- **`mimeinln`** — the inline (RFC-2047) header encoding, so a `Subject:` or a
  display name can carry accented characters. `TMessHeader` calls into it for
  you; you rarely call it directly.

Together they are the "what the message is" half of the story; `TSMTPSend`
([TSMTPSend — sending mail](../03-protocol-classes/03-tsmtpsend.md)) is the
"getting it there" half. The seam between them is one property:
`TMimeMess.Lines`, a `TStringList`, is exactly the `TStrings` that
`TSMTPSend.MailData` expects.

## A message is a tree of parts

The core idea in `mimepart` is that a MIME message is a **tree**. Each
`TMimePart` is a node; a node is either a leaf (text, HTML, a binary
attachment) or a `multipart` container whose children are more parts. A simple
"body plus attachment" message is a three-node tree:

```
multipart/mixed              <- root container
├── text/plain               <- the body
└── application/pdf           <- the attachment
```

`TMimePart` (in `mimepart`) carries the properties of one node. The ones you
touch most:

```pascal
TMimePart = class(TObject)
published
  property Primary: string;         // 'text', 'multipart', 'message', 'application'…
  property Secondary: string;       // 'plain', 'mixed', 'html', 'pdf'…
  property PrimaryCode: TMimePrimary;   // MP_TEXT, MP_MULTIPART, MP_MESSAGE, MP_BINARY
  property EncodingCode: TMimeEncoding; // ME_7BIT, ME_8BIT, ME_QUOTED_PRINTABLE, ME_BASE64, ME_UU, ME_XX
  property CharsetCode: TMimeChar;  // charset for text parts
  property Disposition: string;     // 'inline' or 'attachment'
  property ContentID: string;       // the cid: for inline images
  property FileName: string;        // attachment file name
  property Boundary: string;        // multipart delimiter (multipart parts only)

  property Lines: TStringList;      // the raw, encoded part (headers + body)
  property Headers: TStringList;    // this part's header lines
  property PartBody: TStringList;   // the still-encoded body
  property DecodedLines: TMemoryStream; // the decoded body bytes
end;
```

Two `TStrings`/stream properties are the crux of encode-vs-decode: **`Lines`**
is the wire form (encoded), and **`DecodedLines`** is the raw bytes. Encoding
goes `DecodedLines -> Lines`; decoding goes `Lines -> DecodedLines`. You put
content into `DecodedLines` and call `EncodePart`; you read decoded content out
of `DecodedLines` after calling `DecodePart`.

The four primary types are a closed set:

```pascal
TMimePrimary  = (MP_TEXT, MP_MULTIPART, MP_MESSAGE, MP_BINARY);
TMimeEncoding = (ME_7BIT, ME_8BIT, ME_QUOTED_PRINTABLE, ME_BASE64, ME_UU, ME_XX);
```

An unrecognised primary type decodes to `MP_BINARY`; an unrecognised transfer
encoding decodes to `ME_7BIT`.

## The message: TMimeMess

You rarely build the tree by hand. `TMimeMess` (in `mimemess`) owns the root
part and a header object, and hands you `AddPart…` helpers that create a child
node, set its type, load its content, and encode it in one call:

```pascal
TMimeMess = class(TObject)
  function AddPart(const PartParent: TMimePart): TMimePart;
  function AddPartMultipart(const MultipartType: String; const PartParent: TMimePart): TMimePart;
  function AddPartText(const Value: TStrings; const PartParent: TMimePart): TMimePart;
  function AddPartTextEx(const Value: TStrings; const PartParent: TMimePart;
    PartCharset: TMimeChar; Raw: Boolean; PartEncoding: TMimeEncoding): TMimePart;
  function AddPartHTML(const Value: TStrings; const PartParent: TMimePart): TMimePart;
  function AddPartTextFromFile(const FileName: String; const PartParent: TMimePart): TMimePart;
  function AddPartHTMLFromFile(const FileName: String; const PartParent: TMimePart): TMimePart;
  function AddPartBinary(const Stream: TStream; const FileName: string; const PartParent: TMimePart): TMimePart;
  function AddPartBinaryFromFile(const FileName: string; const PartParent: TMimePart): TMimePart;
  function AddPartHTMLBinary(const Stream: TStream; const FileName, Cid: string; const PartParent: TMimePart): TMimePart;
  function AddPartHTMLBinaryFromFile(const FileName, Cid: string; const PartParent: TMimePart): TMimePart;
  function AddPartMess(const Value: TStrings; const PartParent: TMimePart): TMimePart;
  function AddPartMessFromFile(const FileName: string; const PartParent: TMimePart): TMimePart;

  procedure EncodeMessage; virtual;   // build MessagePart + Header into Lines
  procedure DecodeMessage; virtual;   // parse Lines into Header + MessagePart
published
  property MessagePart: TMimePart;    // the root of the part tree
  property Lines: TStringList;        // the raw RFC-822 message
  property Header: TMessHeader;       // From/To/Subject/…
end;
```

The `PartParent` argument is how you place a node in the tree. Pass `nil` and
the part becomes the **root** (`MessagePart` itself); pass an existing
multipart part and the new part is added as its child. So the pattern for a
multipart message is: create a `multipart/mixed` root with
`AddPartMultipart('mixed', nil)`, then add each leaf with that root as parent.

> **What each helper produces (read from the source).** `AddPartText` makes a
> `text/plain`, `inline`, quoted-printable part and picks an ideal charset for
> the content. `AddPartHTML` makes a `text/html`, `inline`, quoted-printable,
> UTF-8 part. `AddPartBinary`/`…FromFile` makes an `attachment`, base64 part
> and derives the MIME type from the file extension. `AddPartHTMLBinary` makes
> an `inline` base64 part with a `Content-ID` (`Cid`) — the referent for a
> `<img src="cid:…">` inside an HTML part. `AddPartMess` embeds a whole
> `message/rfc822`. Each helper calls `EncodePart` + `EncodePartHeader` before
> returning, so the part is fully encoded the moment you get it back.

## The headers: TMessHeader

`TMimeMess.Header` is a `TMessHeader` holding the parsed mail headers as typed
fields, not raw strings:

```pascal
TMessHeader = class(TObject)
published
  property From: string;
  property ToList: TStringList;       // one recipient per line
  property CCList: TStringList;       // one CC per line
  property Subject: string;
  property Organization: string;
  property ReplyTo: string;
  property MessageID: string;
  property Date: TDateTime;
  property XMailer: string;
  property Priority: TMessPriority;   // MP_unknown, MP_low, MP_normal, MP_high
  property CharsetCode: TMimeChar;    // charset for encoding the headers
  property CustomHeaders: TStringList; // everything not parsed into a field above
end;
```

Note the shape: `From`, `Subject`, `ReplyTo` are single strings, but `ToList`
and `CCList` are `TStringList`s — you `.Add` one address per line rather than
assigning a comma-joined string. On encode, `TMessHeader.EncodeHeaders` joins
them with `, ` and runs each through the inline encoder. It also fills in
sensible defaults you did not set: a `Date:` of `Now` if you left it `0`, a
`MIME-Version: 1.0`, and an `X-mailer:` identifying Synapse. Anything the parser
does not recognise on decode lands in `CustomHeaders`, readable with
`FindHeader` / `FindHeaderList`.

## Encodings: transfer encoding vs. inline header encoding

MIME has two distinct encoding problems, and Synapse keeps them in two places:

1. **Transfer encoding of part bodies** — making arbitrary bytes safe for a
   7-bit mail path. This is `EncodingCode` on a part: `ME_QUOTED_PRINTABLE` for
   mostly-ASCII text (the default for `AddPartText`/`AddPartHTML`), `ME_BASE64`
   for binary attachments (the default for `AddPartBinary`). The actual
   base64/quoted-printable routines live in `synacode` (see
   [Rolling its own crypto & encoding](../01-architecture/04-own-crypto.md)) and
   are driven by `TMimePart.EncodePart` / `DecodePart`.

2. **Inline encoding of header text** — a `Subject:` or a display name cannot
   carry raw 8-bit bytes, so RFC-2047 wraps them as `=?charset?B?…?=` /
   `=?charset?Q?…?=` words. That is `mimeinln`:

   ```pascal
   function InlineDecode(const Value: string; CP: TMimeChar): string;
   function InlineEncode(const Value: string; CP, MimeP: TMimeChar): string;
   function InlineCode(const Value: string): string;
   function InlineCodeEx(const Value: string; FromCP: TMimeChar): string;
   function InlineEmail(const Value: string): string;
   function InlineEmailEx(const Value: string; FromCP: TMimeChar): string;
   function NeedInline(const Value: AnsiString): boolean;
   ```

   `TMessHeader` calls `InlineCodeEx` (for `Subject`/`Organization`) and
   `InlineEmailEx` (for addresses, which must keep the `<addr>` un-encoded) on
   your behalf, so a `Subject := 'Æblegrød'` just works. You reach for these
   directly only when hand-building headers outside `TMessHeader`.

## Where to go next

- [Building a message](01-building.md) — assemble a multipart message with a
  text body and a file attachment, then feed `Lines` to `TSMTPSend.MailData`.
- [Parsing a message](02-parsing.md) — take a raw received message, decode it,
  walk the part tree, and pull out the text and the attachments.
