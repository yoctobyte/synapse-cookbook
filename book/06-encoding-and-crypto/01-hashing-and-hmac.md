# Hashing & HMAC

All the digest and MAC functions live in `synacode` and share one signature
shape: `AnsiString` in, `AnsiString` out.

```pascal
function MD5(const Value: AnsiString): AnsiString;
function MD4(const Value: AnsiString): AnsiString;
function SHA1(const Value: AnsiString): AnsiString;
function HMAC_MD5(Text, Key: AnsiString): AnsiString;
function HMAC_SHA1(Text, Key: AnsiString): AnsiString;
function MD5LongHash(const Value: AnsiString; Len: integer): AnsiString;
function SHA1LongHash(const Value: AnsiString; Len: integer): AnsiString;
```

(All verified in `synacode.pas` interface, lines 216–236.)

## The output is raw bytes, not text

This is the one thing to internalize. `MD5('abc')` does **not** return the
32-character hex string you see in most tools — it returns the **16 raw digest
bytes** packed into an `AnsiString`. `SHA1` returns 20 raw bytes, `HMAC_MD5` 16,
`HMAC_SHA1` 20. Printing that `AnsiString` gives you binary garbage.

That is deliberate: for most protocol work you want the raw bytes so you can
Base64-them or feed them onward. When you want the familiar hex, convert
explicitly with `StrToHex` from `synautil`:

```pascal
function StrToHex(const Value: Ansistring): string;   // synautil.pas
```

It walks the bytes as `IntToHex(Byte(...), 2)` and lowercases the result, so you
get the conventional lowercase hex digest.

```pascal
uses
  synacode, synautil;

var
  raw, hex: AnsiString;
begin
  raw := MD5('The quick brown fox jumps over the lazy dog');
  hex := StrToHex(raw);
  // hex = '9e107d9d372bb6826bd81d3542a419d6'
  WriteLn(hex);
end;
```

The same pattern gives you a hex SHA-1:

```pascal
WriteLn(StrToHex(SHA1('abc')));
// a9993e364706816aba3e25717850c26c9cd0d89d
```

## HMAC — keyed message authentication

`HMAC_MD5` and `HMAC_SHA1` take the message as `Text` and the secret as `Key`
(note: both are plain value parameters, in that order). They too return raw MAC
bytes.

```pascal
uses
  synacode, synautil;

var
  mac: AnsiString;
begin
  mac := HMAC_MD5('message-to-authenticate', 'shared-secret-key');
  WriteLn(StrToHex(mac));   // 32 hex chars
end;
```

## Real protocol usage — you often don't call these yourself

The mail clients already do the right thing. Two examples straight from upstream:

**APOP** (`pop3send.pas`, `TPOP3Send.AuthAPOP`) — the server's timestamp is
concatenated with the password, MD5'd, and hex-encoded:

```pascal
s := StrToHex(MD5(FTimeStamp + FPassWord));
Result := CustomCommand('APOP ' + FUserName + ' ' + s, False);
```

**CRAM-MD5** (`smtpsend.pas`) — the Base64 challenge is decoded, HMAC-MD5'd with
the password as key, and the raw MAC is re-encoded to Base64:

```pascal
s := DecodeBase64(s);              // server challenge
s := HMAC_MD5(s, FPassword);       // raw 16-byte MAC
FSock.SendString(EncodeBase64(FUsername + ' ' + StrToHex(s)) + CRLF);
```

Notice the two different tail conversions: APOP wants **hex**, CRAM-MD5's MAC is
carried as **hex inside a Base64 blob**. The raw-bytes return value is what lets
each protocol format it its own way — which is exactly why the functions don't
hex for you.

## Long-hash variants

`MD5LongHash` and `SHA1LongHash` take a `Len` and produce a digest stream of that
length by iterating the hash (a PRF-style key stretch used by a few protocols).
They are niche; reach for them only when a spec names them.

## The honest caveat

**MD5, MD4, and SHA-1 are here for protocol compatibility, not security.** APOP,
CRAM-MD5, and legacy SASL still specify them, so Synapse implements them to speak
those protocols. All three are broken for collision resistance (MD5 and SHA-1
demonstrably so), and HMAC-MD5 / HMAC-SHA1, while not collision-dependent, are
not what you would pick for a new authentication scheme.

Do **not** use these as your application's password hashing, integrity, or
signing primitives. For those, use a modern KDF/AEAD outside Synapse, and for
transport strength use the [SSL plugin seam](../01-architecture/03-ssl-plugin-seam.md).
Everything on this page exists to let old servers authenticate you, nothing more.
See the architecture chapter [Rolling Its Own Crypto & Encoding](../01-architecture/04-own-crypto.md)
for the reasoning behind that scope.
