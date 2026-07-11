# Cross-Platform: the `synsock` Seam

Synapse runs on Windows, Linux, other Unixes, and Windows CE, across Delphi,
Kylix, and Free Pascal — and the socket classes are written **once**. The trick
is a single thin unit that absorbs every platform difference: `synsock`.

## The idea

Operating systems disagree about sockets: Windows has Winsock (`ws2_32.dll`, an
explicit `WSAStartup`/`WSACleanup` lifecycle, `SOCKET` handles), Unix has BSD
sockets in libc (file descriptors, `errno`), Windows CE has its own quirks. If
those differences leak upward, every socket class needs `{$IFDEF}` clutter.

`synsock` is the **seam** that stops the leak. It exposes one internal socket API
— the calls `blcksock` needs — and implements it per platform behind conditional
compilation:

```pascal
unit synsock;
{$IFDEF WINCE}
  ...windows CE backend...
{$ELSE}
  {$I sslinux.inc}   // unix/linux backend, pulled in by include
{$ENDIF}
```

Above `synsock`, `blcksock.pas` is platform-agnostic. It calls the seam's
functions and never names a specific OS. Port to a new platform → implement the
seam once, and every socket class and protocol client comes along for free.

## Why a seam beats scattered `IFDEF`s

- **One place to be right.** Platform bugs live in `synsock`, not smeared across
  50 units.
- **The layer above stays readable.** `TTCPBlockSocket` reads like sockets, not
  like a compatibility matrix.
- **New platforms are additive.** You extend the seam; you don't touch the
  library on top of it.

This is the same principle as a Hardware Abstraction Layer, or a driver
interface: *define the narrow contract the upper layers need, then satisfy it per
target.* Synapse applied it to the OS socket API long before "platform abstraction
layer" was a buzzword — and it is why one Pascal codebase quietly serves every
target at once.

## Companion seams

`synsock` handles sockets; two sibling units finish the portability story:

- **`synafpc`** — smooths *compiler* differences (Delphi vs Kylix vs Free
  Pascal): types, RTL calls, and dialect quirks, so the same source compiles on
  each.
- **`synachar` / `synaicnv`** — charset conversion, so text protocols behave the
  same regardless of the host's locale.

Together: `synsock` abstracts the OS, `synafpc` abstracts the compiler,
`synachar` abstracts the locale. Three narrow seams, and the rest of Synapse is
written once for all of them.
