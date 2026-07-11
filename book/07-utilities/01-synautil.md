# The `synautil` Toolbox

`synautil.pas` is the single most-used non-socket unit in Synapse. It is a flat
collection of functions — no classes — that the protocol code leans on for
string surgery, date formatting, and byte packing. This page walks the ones you
will actually reach for. Every signature below is copied from the unit's
interface section.

Add it to your `uses` and call directly:

```pascal
uses synautil;
```

## Splitting strings

The two most-called functions in the whole unit split a string on a delimiter:

```pascal
{:Returns a portion of the "Value" string located to the left of the "Delimiter"
 string. If a delimiter is not found, results is original string.}
function SeparateLeft(const Value, Delimiter: string): string;

{:Returns the portion of the "Value" string located to the right of the
 "Delimiter" string. If a delimiter is not found, results is original string.}
function SeparateRight(const Value, Delimiter: string): string;
```

Both search for the *first* occurrence of `Delimiter`. If it is absent,
`SeparateLeft` returns the whole string and `SeparateRight` also returns the
whole string — so pair them carefully.

```pascal
host := SeparateLeft('example.org:443', ':');   // 'example.org'
port := SeparateRight('example.org:443', ':');  // '443'

// No delimiter present:
SeparateLeft('plainhost', ':');                 // 'plainhost'
SeparateRight('plainhost', ':');                // 'plainhost'
```

### `GetBetween` — respects nesting

```pascal
{:Get string between PairBegin and PairEnd. This function respect nesting.}
function GetBetween(const PairBegin, PairEnd, Value: string): string;
```

Unlike a naive left/right split, `GetBetween` matches balanced pairs:

```pascal
GetBetween('(', ')', 'Hi! (hello(yes!))');   // 'hello(yes!)'
```

## The `Fetch` family — consume tokens left to right

`Fetch` is destructive: it removes the returned token *and* the delimiter from
`Value` (a `var` parameter), so you can loop until the string is empty.

```pascal
{:Fetch string from left of Value string.}
function Fetch(var Value: string; const Delimiter: string): string;

{:Like fetch, but working with binary strings, not with text.}
function FetchBin(var Value: string; const Delimiter: string): string;

{:Fetch string from left of Value string. This function ignore delimiters inside
 quotations.}
function FetchEx(var Value: string; const Delimiter, Quotation: string): string;
```

`Fetch` trims surrounding spaces from the token; `FetchBin` does not (it is for
binary data where every byte matters); `FetchEx` skips delimiters that fall
inside a quoted run.

```pascal
var
  s, tok: string;
begin
  s := 'alice, bob, carol';
  while s <> '' do
  begin
    tok := Fetch(s, ',');     // 'alice', then 'bob', then 'carol'
    Writeln(tok);
  end;
end;
```

## Trimming — spaces only

Standard `Trim` also strips control characters. Synapse's variants remove
*only* spaces, which matters when a protocol field may legitimately end in a
tab or a control byte:

```pascal
{:Like TrimLeft, but remove only spaces, not control characters!}
function TrimSPLeft(const S: string): string;
{:Like TrimRight, but remove only spaces, not control characters!}
function TrimSPRight(const S: string): string;
{:Like Trim, but remove only spaces, not control characters!}
function TrimSP(const S: string): string;
```

## Dates and times

Synapse speaks the date formats the protocols require. The two you will use
most are the RFC-822 formatter (for mail and HTTP headers) and the general
decoder.

```pascal
{:Returns current time in format defined in RFC-822. ... (Example
 'Fri, 15 Oct 1999 21:14:56 +0200')}
function Rfc822DateTime(t: TDateTime): string;

{:Same as Rfc822DateTime, but GMT timezone is used.}
function Rfc822DateTimeGMT(t: TDateTime): string;

{:Returns date and time in format defined in RFC-3339 "yyyy-mm-ddThh:nn:ss.zzz"}
function Rfc3339DateTime(t: TDateTime): string;
```

Formatting a header value:

```pascal
Writeln('Date: ', Rfc822DateTime(Now));
// Date: Sat, 11 Jul 2026 14:03:22 +0200
```

Going the other way, `DecodeRfcDateTime` is the forgiving parser — it accepts
RFC-822/1123, RFC-850, and C `asctime()` shapes, and applies the timezone
correction so the result is always a comparable `TDateTime`:

```pascal
{:Decode various string representations of date and time to TDateTime type.
 This function do all timezone corrections too!}
function DecodeRfcDateTime(Value: string): TDateTime;
```

```pascal
dt := DecodeRfcDateTime('Sun, 06 Nov 1994 08:49:37 GMT');
dt := DecodeRfcDateTime('Sunday, 06-Nov-94 08:49:37 GMT');
dt := DecodeRfcDateTime('Sun Nov  6 08:49:37 1994');   // all three parse
```

Supporting pieces you can call on their own:

```pascal
{:Return your timezone bias from UTC time in minutes.}
function TimeZoneBias: integer;
{:Return your timezone bias ... in string representation like "+0200".}
function TimeZone: string;
{:Decode three-letter month name to month number (0 if no match).}
function GetMonthNumber(Value: String): integer;
{:Decode time from string with ':' separator ("hh:mm" or "hh:mm:ss").}
function GetTimeFromStr(Value: string): TDateTime;
{:Decode TimeZone string (CEST, GMT, +0200, ...) to offset.}
function DecodeTimeZone(Value: string; var Zone: integer): Boolean;
```

## Header lists

When you have a `TStringList` of raw `Name: value` header lines, these convert
in place to and from the `Name=value` form that `TStringList.Values` understands:

```pascal
{:Convert lines in stringlist from 'name: value' form to 'name=value' form.}
procedure HeadersToList(const Value: TStrings);
{:Convert lines in stringlist from 'name=value' form to 'name: value' form.}
procedure ListToHeaders(const Value: TStrings);
```

Related, for pulling a single parameter out of a header value:

```pascal
{:Returns parameter value from string in format:
 parameter1="value1"; parameter2=value2}
function GetParameter(const Value, Parameter: string): string;
```

```pascal
charset := GetParameter('text/html; charset="utf-8"', 'charset');  // 'utf-8'
```

## Email address extraction

```pascal
{:Returns only the e-mail portion of an address from the full address format.}
function GetEmailAddr(const Value: string): string;
{:Returns only the description part from a full address format.}
function GetEmailDesc(Value: string): string;
```

```pascal
GetEmailAddr('"someone" <nobody@somewhere.com>');  // 'nobody@somewhere.com'
GetEmailDesc('"someone" <nobody@somewhere.com>');  // 'someone'
```

## Hex, binary, and byte packing

```pascal
{:Returns hexadecimal digits for the bytes in "Value".}
function StrToHex(const Value: Ansistring): string;
{:Returns a string of binary "Digits" representing "Value".}
function IntToBin(Value: Integer; Digits: Byte): string;
{:Returns an integer equivalent of the binary string in "Value".}
function BinToInt(const Value: string): Integer;
```

The `Code*`/`Decode*` pair packs integers into big-endian byte strings — handy
for binary protocols:

```pascal
{:Return two characters representing the value in byte format. (High-endian)}
function CodeInt(Value: Word): Ansistring;
{:Decodes two characters at "Index" of "Value" to a Word.}
function DecodeInt(const Value: Ansistring; Index: Integer): Word;
{:Return four characters representing the value in byte format. (High-endian)}
function CodeLongInt(Value: LongInt): Ansistring;
{:Decodes four characters at "Index" of "Value" to a LongInt.}
function DecodeLongInt(const Value: Ansistring; Index: Integer): LongInt;
```

```pascal
StrToHex(CodeInt(258));      // '0102'  (two big-endian bytes)
DecodeInt(CodeInt(258), 1);  // 258     (Index is 1-based)
```

## Line-terminator and quoting helpers

```pascal
{:Return position of string terminator in string. Possible terminators are:
 CRLF, LFCR, CR, LF. The one found is returned in Terminator.}
function PosCRLF(const Value: AnsiString; var Terminator: AnsiString): integer;

{:Remove quotation from Value string. If not quoted, returns it unchanged.}
function UnquoteStr(const Value: string; Quote: Char): string;
{:Quote Value string. If Value contains Quote chars, they are doubled.}
function QuoteStr(const Value: string; Quote: Char): string;

{:Replaces all "Search" found within "Value" with "Replace".}
function ReplaceString(Value, Search, Replace: AnsiString): AnsiString;
{:Like POS, but from the right side of Value.}
function RPos(const Sub, Value: String): Integer;
{:Return count of Chr in Value string.}
function CountOfChar(const Value: string; Chr: char): integer;
```

> **Note on `CRLF`.** The `CR`, `LF`, and `CRLF` constants themselves are not
> declared in `synautil` — they live in `blcksock.pas` (`CRLF = CR + LF`).
> `synautil` gives you `PosCRLF` to *find* any of the four line terminators in a
> buffer, but for the literal constant you `uses blcksock`.

## URL parsing

```pascal
{:Parses a URL to its various components.}
function ParseURL(URL: string; var Prot, User, Pass, Host, Port, Path,
  Para: string): string;
```

```pascal
var Prot, User, Pass, Host, Port, Path, Para: string;
begin
  ParseURL('http://user:pw@example.org:8080/path?q=1',
    Prot, User, Pass, Host, Port, Path, Para);
  // Prot='http' User='user' Pass='pw' Host='example.org'
  // Port='8080' Path='/path' Para='q=1'
end;
```

## Streams and temp files

```pascal
{:Read a string of "len" bytes from a stream.}
function ReadStrFromStream(const Stream: TStream; len: integer): AnsiString;
{:Write a string to a stream.}
procedure WriteStrToStream(const Stream: TStream; Value: AnsiString);
{:Return a unique temp-file name in "Dir" with the given "prefix".}
function GetTempFile(const Dir, prefix: String): String;
```

## IP validation lives next door

`synautil` does *not* define `IsIP` / `IsIP6` — those are in
[`synaip`](03-ip-and-host.md), which `synautil` does not even use. If you want
to validate an address, reach for that unit.

## When to use what

| You want to…                                   | Call                      |
|------------------------------------------------|---------------------------|
| Split `host:port`                              | `SeparateLeft` / `SeparateRight` |
| Loop tokens off a list, consuming as you go    | `Fetch`                   |
| Pull text between balanced brackets            | `GetBetween`              |
| Format a header date                           | `Rfc822DateTime`          |
| Parse any RFC date string                      | `DecodeRfcDateTime`       |
| Read `charset=` out of a Content-Type          | `GetParameter`            |
| Turn `Name: value` lines into `Values[]`       | `HeadersToList`           |
| Pack an integer big-endian for a binary wire   | `CodeInt` / `CodeLongInt` |
| Hex-dump a byte string                         | `StrToHex`                |
| Break a URL into pieces                         | `ParseURL`                |
