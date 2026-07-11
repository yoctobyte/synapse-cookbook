# Encoding & Crypto

Synapse carries its own digests, MACs, ciphers, transfer encodings, and charset
tables — no external dependency for any of them. The architecture chapter
[Rolling Its Own Crypto & Encoding](../01-architecture/04-own-crypto.md) explains
*why* that choice was made and where it stops (TLS is delegated to a plugin, not
reimplemented). This section is the practical companion: **which function to
call, what it returns, and the honest caveats.**

## The three units

- **`synacode`** — digests (`MD5`, `MD4`, `SHA1`), keyed MACs (`HMAC_MD5`,
  `HMAC_SHA1`), and the MIME transfer encodings: Base64, quoted-printable, URL
  triplet encoding, UU/XX/yEnc, and CRC-16/CRC-32. Everything here operates on
  `AnsiString` and returns `AnsiString` (raw bytes, not text — see below).
- **`synacrypt`** — symmetric block ciphers (DES, 3DES, AES) as a small class
  hierarchy rooted at `TSynaBlockCipher`, with ECB/CBC/CFB/OFB/CTR modes.
- **`synachar`** — charset detection and conversion between `TMimeChar` values
  (ISO-8859-*, the CP125x Windows codepages, UTF-8/16/32, and dozens more),
  optionally backed by `iconv` on non-Windows platforms via `synaicnv`.

## You usually don't call these directly

The protocol clients call them for you. A few real examples from the upstream
source:

- `TPOP3Send.AuthAPOP` computes `StrToHex(MD5(FTimeStamp + FPassWord))` for you
  (`pop3send.pas`).
- `TSMTPSend` does CRAM-MD5 as `EncodeBase64(HMAC_MD5(challenge, FPassword))`
  and AUTH LOGIN as `EncodeBase64(FUsername)` (`smtpsend.pas`).
- `TMimePart` encodes and decodes bodies with `EncodeBase64` /
  `EncodeQuotedPrintable` based on the part's declared transfer encoding
  (`mimepart.pas`).
- `THTTPSend` runs `DecodeURL` over the credentials in a `user:pass@host` URL
  (`httpsend.pas`).
- `mimemess` / `mimeinln` reach into `synachar` to encode non-ASCII mail headers
  correctly.

So reach into these units directly when you are **speaking a protocol Synapse
doesn't wrap**, decoding a blob by hand, or converting a charset the higher
layers didn't handle for you. The rest of the time, let the client do it.

## The recipes

- [Hashing & HMAC](01-hashing-and-hmac.md) — `MD5`/`SHA1`/`HMAC_MD5`/`HMAC_SHA1`,
  why the output is raw bytes, and how to hex it.
- [Transfer encodings](02-transfer-encodings.md) — Base64, quoted-printable, URL
  encoding, and the exact character sets each one escapes.
- [Charsets](03-charsets.md) — `TMimeChar`, `GetCPFromID`, `CharsetConversion`,
  and how non-ASCII mail/HTTP text survives a round trip.

## One caveat up front

`MD5`, `MD4`, `SHA-1`, and single-DES live here because the *protocols* still
specify them — APOP, CRAM-MD5, legacy SASL, and older cipher suites. They are
**not** security primitives for new designs. Use them to speak the protocol that
demands them; reach for the [SSL plugin seam](../01-architecture/03-ssl-plugin-seam.md)
when you need real transport strength. This caveat is repeated on each recipe
because it matters at each call site.
