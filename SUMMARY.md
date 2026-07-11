# The Synapse Cookbook — Contents

Navigate the book. Reading order follows the numeric prefixes; each chapter is
self-contained enough to jump into.

## Introduction
- [Introduction](book/00-introduction/00-index.md)
- [Getting Started — hello, network](book/00-introduction/01-getting-started.md)

## 1 · The Architecture of Synapse *(the heart)*
- [Overview — four seams](book/01-architecture/00-index.md)
- [The blocking model & threads](book/01-architecture/01-blocking-and-threads.md)
- [Cross-platform: the synsock seam](book/01-architecture/02-cross-platform-synsock.md)
- [The SSL plugin seam](book/01-architecture/03-ssl-plugin-seam.md)
- [Rolling its own crypto & encoding](book/01-architecture/04-own-crypto.md)

## 2 · Socket Classes
- [The socket class family](book/02-socket-classes/00-index.md)
- [TBlockSocket — the base](book/02-socket-classes/01-tblocksocket.md)
- [TTCPBlockSocket](book/02-socket-classes/02-ttcpblocksocket.md)
- [TUDPBlockSocket](book/02-socket-classes/03-tudpblocksocket.md)
- [TSocksBlockSocket & proxies](book/02-socket-classes/04-tsocksblocksocket.md)

## 3 · Protocol Classes
- [The protocol-client pattern](book/03-protocol-classes/00-index.md)
- [POP3 — TPOP3Send](book/03-protocol-classes/01-tpop3send.md)
- [LDAP — TLDAPSend](book/03-protocol-classes/02-ldap.md)
- [SMTP — TSMTPSend](book/03-protocol-classes/03-tsmtpsend.md)
- [HTTP — THTTPSend](book/03-protocol-classes/04-thttpsend.md)
- [IMAP — TIMAPSend](book/03-protocol-classes/05-timapsend.md)
- [FTP — TFTPSend](book/03-protocol-classes/06-tftpsend.md)
- [DNS — TDNSSend](book/03-protocol-classes/07-dns.md)
- [Other protocols (NNTP, SNMP, SNTP, ping, telnet, syslog)](book/03-protocol-classes/08-other-protocols.md)

## 4 · MIME & Mail Messages
- [The MIME message model](book/04-mime-messages/00-index.md)
- [Building a message](book/04-mime-messages/01-building.md)
- [Parsing a message](book/04-mime-messages/02-parsing.md)

## 5 · Serial Ports
- [TBlockSerial — the block model over RS-232](book/05-serial-ports/00-index.md)

## 6 · Encoding & Crypto
- [Overview](book/06-encoding-and-crypto/00-index.md)
- [Hashing & HMAC](book/06-encoding-and-crypto/01-hashing-and-hmac.md)
- [Transfer encodings (Base64, quoted-printable, URL)](book/06-encoding-and-crypto/02-transfer-encodings.md)
- [Charsets](book/06-encoding-and-crypto/03-charsets.md)

## 7 · Utilities
- [Overview](book/07-utilities/00-index.md)
- [synautil — the toolbox](book/07-utilities/01-synautil.md)
- [asn1util — BER/DER](book/07-utilities/02-asn1util.md)
- [IP & host helpers](book/07-utilities/03-ip-and-host.md)

## 8 · Recipes *(task-oriented)*
- [How to use this section](book/08-recipes/00-index.md)
- [Web](book/08-recipes/01-web.md)
- [Email](book/08-recipes/02-email.md)
- [Network tools](book/08-recipes/03-network-tools.md)
- [Serial](book/08-recipes/04-serial.md)

## 9 · Visual Synapse
- [Components & servers built on Synapse](book/09-visual-synapse/index.md)

## Appendix
- [Synapse in Two Hours — the tutorial](book/99-appendix-tutorials/synapse-in-two-hours.md)

---

See also: [`NOTES.md`](NOTES.md) (provenance & authenticity) · the recovered
original under [`releases/`](releases/).
