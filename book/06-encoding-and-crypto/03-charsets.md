# Charsets

`synachar` is Synapse's charset layer: it knows a large set of encodings, can
guess which one a byte string is, and can convert between any two of them. This
is what keeps an accented `Subject:` line or a Latin-1 HTTP body from turning into
mojibake. The mail units (`mimemess`, `mimeinln`, `mimepart`) call into it for
you; you touch it directly when you are decoding non-ASCII text the higher layers
handed you raw.

## Charsets are a `TMimeChar` enum, not numeric IDs

The set of supported charsets is the enumerated type `TMimeChar` (`synachar.pas`,
line 101). Each member *is* the charset identifier — there is no separate `idNN`
constant table; you name charsets by these enum values:

```pascal
type
  TMimeChar = (ISO_8859_1, ISO_8859_2, ISO_8859_3, ISO_8859_4, ISO_8859_5,
    ISO_8859_6, ISO_8859_7, ISO_8859_8, ISO_8859_9, ISO_8859_10, ISO_8859_13,
    ISO_8859_14, ISO_8859_15, CP1250, CP1251, CP1252, CP1253, CP1254, CP1255,
    CP1256, CP1257, CP1258, KOI8_R, CP895, CP852, UCS_2, UCS_4, UTF_8, UTF_7,
    UTF_7mod, UCS_2LE, UCS_4LE,
    // the following are supported through iconv only:
    UTF_16, UTF_16LE, UTF_32, UTF_32LE, C99, JAVA, ISO_8859_16, KOI8_U, ...);
```

(The list continues with the Mac charsets, the CJK encodings — `EUC_JP`,
`SHIFT_JIS`, `GB2312`, `BIG5`, `EUC_KR` — and more. See the full declaration in
`synachar.pas`.)

Two important companion sets in the same unit:

- `IconvOnlyChars` — charsets that only work when `iconv` is present (via
  `synaicnv`; non-Windows). On a build without iconv these are unavailable.
- `NoIconvChars` — `[CP895, UTF_7mod]`, the two Synapse handles with its own
  internal routines regardless of iconv.

## Name ↔ enum: `GetCPFromID` / `GetIDFromCP`

Wire formats carry charset *names* (`"utf-8"`, `"iso-8859-1"`, `"windows-1252"`),
so you convert between the string label and the enum:

```pascal
function GetCPFromID(Value: AnsiString): TMimeChar;   // "iso-8859-2" -> ISO_8859_2
function GetIDFromCP(Value: TMimeChar): AnsiString;    // ISO_8859_2  -> "ISO-8859-2"
```

(`synachar.pas`, interface lines 213, 216.) `GetCPFromID` is generous: it
uppercases the input and matches against a large alias table (so `"LATIN1"`,
`"CP819"`, `"ISO8859-1"` all resolve to `ISO_8859_1`), with special-cased names
for `CP895`/Kamenicky and modified UTF-7. Feed it the charset token straight out
of a MIME `Content-Type` or HTTP `charset=` parameter.

```pascal
uses
  synachar;

var
  cs: TMimeChar;
begin
  cs := GetCPFromID('windows-1252');   // -> CP1252
  WriteLn(GetIDFromCP(cs));            // canonical name back
end;
```

## Converting: `CharsetConversion`

The core conversion is:

```pascal
function CharsetConversion(const Value: AnsiString;
  CharFrom: TMimeChar; CharTo: TMimeChar): AnsiString;
```

(`synachar.pas`, interface line 191.) Give it the bytes, the charset they are
*in*, and the charset you want them *in*:

```pascal
uses
  synachar;

var
  latin1, utf8: AnsiString;
begin
  latin1 := 'Caf'#$E9;                              // 'Café' in ISO-8859-1
  utf8 := CharsetConversion(latin1, ISO_8859_1, UTF_8);
  // utf8 now holds the UTF-8 bytes 'Caf' + C3 A9
end;
```

If you have a charset *name* rather than an enum, resolve it first:

```pascal
from := GetCPFromID(headerCharsetName);
utf8 := CharsetConversion(rawBody, from, UTF_8);
```

### The richer variants

```pascal
function CharsetConversionEx(const Value: AnsiString; CharFrom: TMimeChar;
  CharTo: TMimeChar; const TransformTable: array of Word): AnsiString;

function CharsetConversionTrans(Value: AnsiString; CharFrom: TMimeChar;
  CharTo: TMimeChar; const TransformTable: array of Word;
  Translit: Boolean): AnsiString;
```

(interface lines 196, 202.) `CharsetConversionEx` applies an extra character
replacement table during conversion — pass `Replace_None` for no substitution, or
`Replace_Czech` (both declared in `synachar`) to strip Czech diacritics.
`CharsetConversionTrans` adds a `Translit` flag: when `False`, unconvertible
characters are *not* transliterated to approximations. Plain `CharsetConversion`
is `CharsetConversionEx` with `Replace_None` and transliteration on.

## Detection helpers

```pascal
function NeedCharsetConversion(const Value: AnsiString): Boolean;
function GetCurCP: TMimeChar;
function GetCurOEMCP: TMimeChar;
function IdealCharsetCoding(const Value: AnsiString; CharFrom: TMimeChar;
  CharTo: TMimeSetChar): TMimeChar;
```

(interface lines 219, 206, 210, 223.)

- `NeedCharsetConversion` returns `True` only when the string has non-7-bit-ASCII
  bytes — a cheap gate so you skip conversion for pure-ASCII text.
- `GetCurCP` / `GetCurOEMCP` report the operating system's current charset (and
  the OEM/DOS-box charset on Windows), useful as a `CharFrom` when reading
  platform-local text.
- `IdealCharsetCoding` picks, from a candidate `TMimeSetChar`, the target charset
  that encodes `Value` with the fewest unconvertible characters — this is how the
  mail encoder chooses the smallest adequate charset for an outgoing header.

```pascal
uses
  synachar;

begin
  if NeedCharsetConversion(body) then
    body := CharsetConversion(body, GetCPFromID(declaredCharset), UTF_8);
  // pure-ASCII bodies pass through untouched
end;
```

## iconv: the reach beyond the built-in tables

Many of the `TMimeChar` members (everything in `IconvOnlyChars` — the CJK
encodings, UTF-16/32, the Mac charsets) are handled by delegating to the system
`iconv` through `synaicnv`. On a platform without iconv, or with the global
`DisableIconv` flag set, those charsets are unavailable and conversions involving
them will fail; the built-in ISO-8859-*, CP125x, KOI8, UTF-7/8, and UCS
conversions always work. If you support arbitrary inbound charsets, test on your
target platform with iconv actually present.

## No security dimension — just correctness

Charset conversion is neither encryption nor sanitization: it changes byte
*representation*, not meaning, and provides no safety guarantees. The failure mode
is silent corruption — pass the wrong `CharFrom`, or run the bytes through
conversion twice, and you get mojibake or lost characters. Always convert from the
charset the data actually declares (from the MIME/HTTP header via `GetCPFromID`),
convert once, and prefer `UTF_8` as your internal target. For where this fits the
overall design, see [Rolling Its Own Crypto & Encoding](../01-architecture/04-own-crypto.md).
