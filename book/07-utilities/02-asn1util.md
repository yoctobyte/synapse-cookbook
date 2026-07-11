# ASN.1 BER with `asn1util`

LDAP and SNMP do not send text. They send **ASN.1 BER** — a compact, recursive,
type-length-value binary encoding. `asn1util.pas` is Synapse's implementation of
that encoding: a small set of functions that turn Pascal values into BER bytes
and back. The LDAP (`ldapsend.pas`) and SNMP (`snmpsend.pas`) classes are built
directly on it; you rarely call it yourself, but knowing it is what turns those
protocols from magic into plumbing.

```pascal
uses asn1util;
```

## The TLV idea

Every ASN.1 element is three parts laid end to end:

```
+--------+-----------+-------------------+
|  Type  |  Length   |      Contents     |
| 1 byte | 1+ bytes  |   Length bytes    |
+--------+-----------+-------------------+
```

- **Type** — one byte naming the kind of value (integer, string, sequence…).
- **Length** — how many content bytes follow. Short lengths (`< 128`) fit in one
  byte; longer ones use a multi-byte form flagged by the high bit.
- **Contents** — the value, whose interpretation depends on Type. For the
  *constructed* types (like `SEQUENCE`) the contents are themselves more TLV
  elements — that recursion is the whole grammar.

## The type constants

`asn1util` defines the BER type tags it understands:

```pascal
ASN1_BOOL      = $01;
ASN1_INT       = $02;
ASN1_OCTSTR    = $04;   // octet string
ASN1_NULL      = $05;
ASN1_OBJID     = $06;   // object identifier (an OID)
ASN1_ENUM      = $0a;
ASN1_SEQ       = $30;   // sequence (constructed)
ASN1_SETOF     = $31;   // set-of  (constructed)
ASN1_IPADDR    = $40;   // SNMP application types below
ASN1_COUNTER   = $41;
ASN1_GAUGE     = $42;
ASN1_TIMETICKS = $43;
ASN1_OPAQUE    = $44;
ASN1_COUNTER64 = $46;
```

The `$40`-range tags are SNMP's application-specific types; the rest are
universal ASN.1.

## Encoding

The workhorse is `ASNObject` — it wraps any content in its Type and Length,
producing a finished element:

```pascal
{:Encodes ASN.1 object to binary form.}
function ASNObject(const Data: AnsiString; ASNType: Integer): AnsiString;
```

Its whole body is the TLV definition made literal:

```pascal
Result := AnsiChar(ASNType) + ASNEncLen(Length(Data)) + Data;
```

You build the *content* with the typed encoders, then wrap it:

```pascal
{:Encodes a signed integer to ASN.1 binary}
function ASNEncInt(Value: Int64): AnsiString;
{:Encodes unsigned integer into ASN.1 binary}
function ASNEncUInt(Value: Integer): AnsiString;
{:Encodes the length of an ASN.1 element to binary.}
function ASNEncLen(Len: Integer): AnsiString;
{:Encodes an OID item to binary form.}
function ASNEncOIDItem(Value: Int64): AnsiString;
```

Encoding an integer element:

```pascal
var
  elem: AnsiString;
begin
  elem := ASNObject(ASNEncInt(42), ASN1_INT);
  // bytes: $02 $01 $2A  (type=INT, length=1, value=42)
  Writeln(StrToHex(elem));   // '02012a'  (StrToHex from synautil)
end;
```

Because `SEQUENCE` content is just concatenated elements, you nest by wrapping a
concatenation:

```pascal
var
  body, seq: AnsiString;
begin
  body := ASNObject(ASNEncInt(1),        ASN1_INT)
        + ASNObject('hello',             ASN1_OCTSTR);
  seq  := ASNObject(body, ASN1_SEQ);
  // seq is a SEQUENCE containing an INTEGER and an OCTET STRING
end;
```

## Decoding

Decoding walks the buffer with a **`var Start` cursor** — each call advances it
past the element it read, so you decode a sequence by calling repeatedly:

```pascal
{:Beginning with the "Start" position, decode the ASN.1 item of the next element
 in "Buffer". Type of item is stored in "ValueType."}
function ASNItem(var Start: Integer; const Buffer: AnsiString;
  var ValueType: Integer): AnsiString;

{:Decodes length of next element in "Buffer" from the "Start" position.}
function ASNDecLen(var Start: Integer; const Buffer: AnsiString): Integer;
{:Decodes an OID item of the next element from the "Start" position.}
function ASNDecOIDItem(var Start: Integer; const Buffer: AnsiString): Int64;
```

`ASNItem` returns the decoded value as a string and reports its BER type through
`ValueType`. `Start` is **1-based** (Pascal string indexing):

```pascal
var
  pos, vt: Integer;
  value: AnsiString;
begin
  pos := 1;
  value := ASNItem(pos, elem, vt);
  // for the '02012a' buffer above:
  //   vt    = ASN1_INT ($02)
  //   value = '42'   (integer types come back as their decimal string)
  //   pos   = 4      (advanced past the element)
end;
```

For a `SEQUENCE`, first decode the outer element (which for constructed types
returns the raw inner bytes), then loop `ASNItem` over those with a fresh cursor.

## OIDs and MIBs

SNMP object identifiers are dotted-number MIB strings like `1.3.6.1.2.1.1.1.0`.
`asn1util` converts between the string and its BER binary form:

```pascal
{:Encodes an MIB OID string to binary form.}
function MibToId(Mib: String): AnsiString;
{:Decodes MIB OID from binary form to string form.}
function IdToMib(const Id: AnsiString): String;
```

```pascal
var
  oid: AnsiString;
begin
  oid := MibToId('1.3.6.1.2.1.1.1.0');   // BER-encoded OID bytes
  Writeln(IdToMib(oid));                  // '1.3.6.1.2.1.1.1.0'  (round-trip)
end;
```

To place an OID on the wire, wrap it as an `ASN1_OBJID` element:

```pascal
oidElem := ASNObject(MibToId('1.3.6.1.2.1.1.1.0'), ASN1_OBJID);
```

## Debugging

When a decode goes wrong, dump the buffer in human-readable form:

```pascal
{:Convert ASN.1 BER encoded buffer to human readable form for debugging.}
function ASNdump(const Value: AnsiString): AnsiString;
```

`ASNdump` walks the TLV structure and prints each element's type and value —
the fastest way to see what an LDAP or SNMP packet actually contains.

## Summary

| You want to…                        | Call                          |
|-------------------------------------|-------------------------------|
| Wrap content as a typed element     | `ASNObject(data, ASN1_*)`     |
| Encode a signed / unsigned integer  | `ASNEncInt` / `ASNEncUInt`    |
| Encode an OID from a MIB string     | `MibToId`                     |
| Read the next element from a buffer | `ASNItem(Start, buf, vt)`     |
| Turn an OID back into dotted form   | `IdToMib`                     |
| Inspect a packet while debugging    | `ASNdump`                     |

You will most often *see* these functions inside `ldapsend.pas` and
`snmpsend.pas` rather than call them — but every LDAP filter and every SNMP
varbind on the wire is exactly this: `ASNObject` calls nested inside an
`ASN1_SEQ`, unwound on the far end by `ASNItem`.
