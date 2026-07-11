# Transfer Encodings

Base64, quoted-printable, and URL encoding all live in `synacode`, and all share
the `AnsiString` → `AnsiString` shape. These are the encodings the mail and HTTP
clients lean on constantly, and they are the ones you are most likely to call by
hand when decoding a blob yourself.

## Base64

```pascal
function EncodeBase64(const Value: AnsiString): AnsiString;
function DecodeBase64(const Value: AnsiString): AnsiString;
```

(`synacode.pas`, interface lines 179–182.) Straightforward and byte-safe — encode
any bytes, decode back to the exact same bytes:

```pascal
uses
  synacode;

var
  enc, dec: AnsiString;
begin
  enc := EncodeBase64('Aladdin:open sesame');
  // enc = 'QWxhZGRpbjpvcGVuIHNlc2FtZQ=='
  dec := DecodeBase64(enc);
  // dec = 'Aladdin:open sesame'
end;
```

Internally `EncodeBase64` is `Encode3to4(Value, TableBase64)` and `DecodeBase64`
is `Decode4to3Ex(Value, ReTableBase64)` — the standard RFC alphabet
`A–Z a–z 0–9 + /` with `=` padding. `DecodeBase64` is tolerant of characters
outside the alphabet (line breaks in wrapped Base64 are skipped), so you can feed
it MIME-wrapped input directly.

There is also a URL-safe-ish variant pair, `EncodeBase64mod` / `DecodeBase64mod`,
which uses `+` and `,` instead of `+` and `/` (the "modified" IMAP-style
alphabet). Use it only when a spec calls for it.

This is the workhorse of SASL and MIME: `TSMTPSend` sends
`EncodeBase64(FUsername)` for AUTH LOGIN, and `TMimePart` Base64-encodes binary
attachment bodies.

## Quoted-printable

```pascal
function EncodeQuotedPrintable(const Value: AnsiString): AnsiString;
function DecodeQuotedPrintable(const Value: AnsiString): AnsiString;
function EncodeSafeQuotedPrintable(const Value: AnsiString): AnsiString;
```

(`synacode.pas`, interface lines 137, 149, 153.) Quoted-printable leaves ASCII
text mostly readable and escapes only the bytes that need it, as `=XX` triplets:

```pascal
uses
  synacode;

var
  s: AnsiString;
begin
  s := EncodeQuotedPrintable('Caf'#$E9' — 5'#$80);
  // non-ASCII bytes become =E9, =80, etc.; '=' itself becomes =3D
  WriteLn(s);
  WriteLn(DecodeQuotedPrintable(s));   // round-trips back to the bytes
end;
```

The two encoders differ in **which characters they escape**:

- `EncodeQuotedPrintable` escapes `=` plus all non-ASCII bytes
  (`#0..#31, #127..#255`). This is the normal body encoding.
- `EncodeSafeQuotedPrintable` escapes a wider `SpecialChar` set as well
  (`( ) [ ] < > : ; , @ / ? \ " _` and `=`), producing text safe to drop into
  places where those punctuation characters are structural — e.g. RFC-2047
  encoded-words in mail headers.

`DecodeQuotedPrintable` is just `DecodeTriplet(Value, '=')` — it reverses either
encoder. `TMimePart` calls these for text parts declared `quoted-printable`.

## URL encoding

```pascal
function EncodeURL(const Value: AnsiString): AnsiString;
function EncodeURLElement(const Value: AnsiString): AnsiString;
function DecodeURL(const Value: AnsiString): AnsiString;
```

(`synacode.pas`, interface lines 162, 158, 140. Exact names confirmed — note
`EncodeURLElement`, not `EncodeURIComponent` or similar.) Same triplet mechanism,
`%XX` delimiter. The two encoders differ, and the difference matters:

- **`EncodeURL`** escapes only `URLSpecialChar` — control bytes, high bytes, and
  the characters that are unsafe *anywhere* in a URL (`< > " % { } | \ ^ [ ] `
  backtick, space, `#$7F..#$FF`). It **leaves the URL structure alone**: `/`,
  `?`, `:`, `@`, `&`, `=`, `+`, `;`, `#` all pass through. Use it to clean up a
  whole URL without breaking it.
- **`EncodeURLElement`** escapes `URLSpecialChar` **plus** `URLFullSpecialChar`
  (`; / ? : @ = & # +`) — i.e. the reserved delimiters too. Use it to encode a
  single component (a query-string value, a path segment) that must not be
  interpreted as structure.

```pascal
uses
  synacode;

begin
  WriteLn(EncodeURL('http://h/a b?x=1'));
  // EncodeURL keeps ':/?=' → http://h/a%20b?x=1

  WriteLn(EncodeURLElement('a b?x=1'));
  // EncodeURLElement escapes the reserved chars too → a%20b%3Fx%3D1
end;
```

`httpsend.pas` documents that the value put into a request field "must be encoded
by the `EncodeURLElement` function," and it runs `DecodeURL` over the userinfo it
parses out of a `user:pass@host` URL. `DecodeURL` reverses both encoders (it just
undoes every `%XX`).

## No security caveat here — but a correctness one

These are encodings, not ciphers: they provide **zero** confidentiality or
integrity. Base64 is not encryption. The only pitfall is **round-tripping**: pick
the right encoder for the context (`EncodeURL` for a whole URL vs
`EncodeURLElement` for one component; plain vs safe quoted-printable), or you will
either over-escape and corrupt structure, or under-escape and break the message.
For where these sit in the larger design, see
[Rolling Its Own Crypto & Encoding](../01-architecture/04-own-crypto.md).
