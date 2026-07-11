# Rolling Its Own Crypto & Encoding

Open a mail client library today and it pulls in a crypto dependency for the
message digests that authentication needs. Synapse pulls in **nothing** — the
hashes, HMACs, ciphers, and transfer encodings are all hand-written in Object
Pascal, in `synacode` and `synacrypt`. For the essentials, Synapse has *no
external dependency at all*.

## What's in the box

From `synacode.pas` — digests, MACs, and encodings, all from scratch:

```pascal
function MD5(const Value: AnsiString): AnsiString;
function MD4(const Value: AnsiString): AnsiString;
function SHA1(const Value: AnsiString): AnsiString;
function HMAC_MD5(Text, Key: AnsiString): AnsiString;
function HMAC_SHA1(Text, Key: AnsiString): AnsiString;
function MD5LongHash(const Value: AnsiString; Len: integer): AnsiString;
function SHA1LongHash(const Value: AnsiString; Len: integer): AnsiString;
```

plus Base64, quoted-printable, UU/XX, and the other MIME transfer encodings the
mail and HTTP clients need.

From `synacrypt.pas` — symmetric ciphers (DES, 3DES, and friends) implemented in
pure Pascal, for the protocols and SASL mechanisms that require them.

## Why roll your own here

In the era Synapse was built, you could not assume a crypto library was present
and portable across Windows, Linux, Kylix, and CE. The choices were: depend on
something that might not be there, or **implement the handful of algorithms you
actually need**, portably, once. Synapse chose the second — and it is exactly why
`pop3send`, `smtpsend`, `imapsend`, and the SASL/APOP/CRAM-MD5 authentication
paths *just work* with nothing else installed.

Note the deliberate scope: these are the digests and ciphers protocols require
for **authentication and encoding**, not a general-purpose crypto suite. For
transport encryption (TLS), Synapse does the opposite and delegates to a
best-in-class library through the [SSL plugin seam](03-ssl-plugin-seam.md) —
because reimplementing TLS would be reckless, while reimplementing MD5 is a
weekend and removes a dependency forever.

## The lesson (and the caveat)

- **The lesson:** know which wheels are worth reinventing. A 200-line MD5 that
  erases a fragile, non-portable dependency is a *good* trade. Synapse reinvents
  precisely the small, stable, spec-frozen algorithms — and delegates the large,
  evolving, security-critical one (TLS).
- **The caveat for today:** MD5, MD4, SHA-1, and single-DES are here because the
  *protocols* still specify them (APOP, CRAM-MD5, legacy auth), not because they
  are secure choices for new designs. Use them to speak the protocols that demand
  them; do not reach for them as your application's security primitives. Modern
  strength lives behind the TLS plugin.

Read `synacode.pas` end to end at least once — it is a compact, readable tour of
how these algorithms actually work, unobscured by macros or assembly. As teaching
material, it is worth as much as the cookbook chapters that use it.
