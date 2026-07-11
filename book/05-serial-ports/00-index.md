# TBlockSerial — the sockets model, applied to RS-232

Here is the quietly lovely thing about Synapse: when its authors needed a serial
port library, they did not invent a new vocabulary. They took the *exact* mental
model of `TBlockSocket` — blocking calls, millisecond timeouts, a `LastError`
you check after each step, `RecvString`/`RecvTerminated` for line protocols — and
pointed it at a UART instead of a TCP stream. The unit's own header says so:

> This class provides numerous methods with same name and functionality as
> methods of the Ararat Synapse TCP/IP library.

If you have read the [`TBlockSocket`](../02-socket-classes/01-tblocksocket.md)
chapter, you already know most of `TBlockSerial`. This chapter is about the parts
that are genuinely different — opening a port instead of connecting to a host,
configuring baud/bits/parity, and driving the modem control lines — and about how
little else changes.

The unit is `synaser`. The one class you use is `TBlockSerial`.

## The lifecycle

A serial port has the same explicit life as a socket, with `Connect` opening a
device and `CloseSocket` closing it:

```
Create ──▶ Connect(device) ──▶ Config(...) ──▶ Send/Recv … ──▶ CloseSocket ──▶ Free
```

- **`constructor Create`** — makes the object. It does *not* open a port yet.
- **`procedure Connect(comport: string)`** — opens the named device. The
  parameters are whatever the OS had configured for that port; call `Config`
  afterwards if you need specific settings.
- **`procedure CloseSocket`** — closes the handle. The destructor calls it, so
  `Free` is enough, but closing explicitly is good manners (and releases any lock
  file — see privileges below).

Note the name: it really is `CloseSocket`, not `ClosePort`. That is the design
consistency showing through — the method names were kept identical to the socket
library on purpose.

```pascal
uses synaser;

var ser: TBlockSerial;
begin
  ser := TBlockSerial.Create;
  try
    ser.Connect('/dev/ttyUSB0');
    if ser.LastError <> 0 then
    begin
      Writeln('open: ', ser.LastErrorDesc);
      Exit;
    end;
    ser.Config(9600, 8, 'N', SB1, False, False);   // 9600 8N1, no flow control
    { ...talk to the device... }
  finally
    ser.CloseSocket;
    ser.Free;
  end;
end;
```

## Naming the device — 'COM1' vs '/dev/ttyS0'

`Connect` takes a device *name*, and Synapse is bi-dialect about it. From the
source documentation on `Connect`:

> Comport can be used in Windows style (COM2), or in Linux style (/dev/ttyS1).
> When you use windows style in Linux, then it will be converted to Linux name.
> And vice versa!

So `Connect('COM2')` on Linux is translated to `/dev/ttyS1` (the conversion is
zero-based on the Unix side: `COM1` → `/dev/ttyS0`, `COM2` → `/dev/ttyS1`), and a
`/dev/ttyS1` on Windows maps back to a `COM` number. The translation lives in the
`GetComNr` helper and only recognises the `COM`*n* and `/dev/ttyS`*n* forms.

That last point matters in practice: **anything that is not a `COMn` or
`/dev/ttySn` name is passed through unchanged.** USB-serial adapters
(`/dev/ttyUSB0`), ACM/CDC modems (`/dev/ttyACM0`), and ARM on-chip UARTs
(`/dev/ttyAMA0`) are *not* rewritten — you give the literal path and it is opened
as-is. In modern life that is most of what you connect to, so the usual advice is
simply: **on Unix, name the real device path; on Windows, use `COMn`.** The
`Device` property tells you the actual OS name that ended up being opened.

To discover what is present, the unit exports a free function:

```pascal
function GetSerialPortNames: string;   // comma-separated list of port names
```

On Unix it globs `/dev/ttyS*`, `/dev/ttyUSB*`, `/dev/ttyAM*` and `/dev/ttyACM*`;
on Windows it reads them from the registry's `SERIALCOMM` map. Handy for
populating a "choose a port" dropdown.

### A privilege caveat (Unix)

Opening a serial device on Linux/Unix normally requires membership in the
`dialout` group (or equivalent), because `/dev/ttyS*` and `/dev/ttyUSB*` are
owned `root:dialout`. If `Connect` comes back with `LastError` set to a
permission error, that is almost always the cause — add the user to `dialout`
rather than running as root. Synapse can also create a lock file under
`/var/lock` to cooperate with other programs using the port; this is governed by
the `LinuxLock` property (default `True`), and the `/var/lock` directory must be
writable for it. On Windows there is no such group; access is governed by whether
another process already holds the port open.

## Config — baud, bits, parity, stop bits, flow

One call sets every line parameter. You must be connected first:

```pascal
procedure Config(baud, bits: integer; parity: char; stop: integer;
  softflow, hardflow: boolean); virtual;
```

- **`baud`** — bits per second, an *actual number* (not an enum): `9600`,
  `19200`, `115200`, `460800`, up to `4000000` on capable hardware. Internally
  Synapse maps it to the nearest supported `Bxxx` termios rate on Unix.
- **`bits`** — data bits per character, typically `8` (or `7`, `6`, `5`).
- **`parity`** — a single character: **`'N'`** none, **`'O'`** odd, **`'E'`**
  even, **`'M'`** mark, **`'S'`** space. (Case-insensitive.)
- **`stop`** — stop bits, using the named constants **`SB1`** (1 stop bit, value
  0), **`SB1andHalf`** (1.5, value 1), or **`SB2`** (2, value 2).
- **`softflow`** — enable XON/XOFF software handshake.
- **`hardflow`** — enable RTS/CTS hardware handshake.

So the ubiquitous "9600 8N1, no flow control" is:

```pascal
ser.Config(9600, 8, 'N', SB1, False, False);
```

and "115200 8N1 with hardware handshake" is:

```pascal
ser.Config(115200, 8, 'N', SB1, False, True);
```

`Config` may be called again at any time to reconfigure a live port on the fly.
Under the hood it fills a `TDCB` (Windows' Device Control Block, *simulated* on
Unix so the same code path serves both) and pushes it with `SetCommState`; the
inverse `GetCommState` reads the current settings back. You rarely touch those
two directly.

## Sending — identical to the socket API

Every send method has the same name and shape as on `TBlockSocket`:

```pascal
function  SendBuffer(buffer: pointer; length: integer): integer; virtual;
procedure SendByte(data: byte); virtual;
procedure SendString(data: AnsiString); virtual;   // bytes as-is — NO terminator added
procedure SendInteger(Data: integer); virtual;      // four bytes
procedure SendBlock(const Data: AnsiString); virtual;   // 4-byte length prefix, then data
procedure SendStreamRaw(const Stream: TStream); virtual;
procedure SendStream(const Stream: TStream); virtual;
```

The same honest caveat applies as with the socket: **`SendString` appends no
terminator.** The source is explicit — "No terminator is appended by this method.
If you need to send a string with CR/LF terminator, you must append the CR/LF
characters." Because it adds nothing, it doubles as your binary-send path.

```pascal
ser.SendString('AT' + CRLF);         // you supply the CRLF
ser.SendByte($02);                   // a single control byte
```

`CR`, `LF`, and `CRLF` are declared right in `synaser`, so you do not need to
pull them from elsewhere.

## Receiving — the same three you already reach for

```pascal
function RecvBuffer(buffer: pointer; length: integer): integer; virtual;
function RecvBufferEx(buffer: pointer; length, timeout: integer): integer; virtual;
function RecvBufferStr(Length, Timeout: Integer): AnsiString; virtual;
function RecvPacket(Timeout: Integer): AnsiString; virtual;
function RecvByte(timeout: integer): byte; virtual;
function RecvTerminated(Timeout: Integer; const Terminator: AnsiString): AnsiString; virtual;
function RecvString(Timeout: Integer): AnsiString; virtual;
function RecvInteger(Timeout: Integer): Integer; virtual;
function RecvBlock(Timeout: Integer): AnsiString; virtual;
```

Every one that can wait takes a **millisecond `Timeout`** and sets `LastError` to
**`ErrTimeout`** if it lapses — exactly the blocking-with-timeouts contract from
the sockets chapter, and exactly what makes serial code safe to write in a
straight line. The three you will use most:

- **`RecvString(Timeout)`** — reads up to a CR/LF terminator and returns the line
  *without* it. This is the workhorse for line-oriented instruments and modems.
  It is `RecvTerminated(Timeout, CRLF)` under the hood, and it keeps its own
  internal buffer, so do not interleave it with raw `RecvBuffer` calls on the
  same port (the source warns this can lose data).
- **`RecvTerminated(Timeout, Terminator)`** — the same idea for devices that end
  each reply with something other than CR/LF: an ETX (`#3`), a `'>'` prompt, a
  `'#'`, whatever your protocol uses. Returns the payload without the terminator.
- **`RecvPacket(Timeout)`** — "give me whatever bytes are waiting right now."
  Ideal when the reply has no fixed framing and you just want to drain the port.

If a device uses lone-CR or lone-LF line ends rather than strict CR/LF, set
`ConvertLineEnd := True` and `RecvString` will accept any of them. `MaxLineLength`
caps how much `RecvString`/`RecvTerminated` will buffer before erroring (default
`0` = unlimited) — worth setting when a misbehaving device might never send a
terminator.

## Readiness and buffers

Also mirrored from the socket class — you seldom need these because the `Recv*`
timeouts already poll internally, but they are here:

```pascal
function  CanRead(Timeout: integer): boolean; virtual;    // data available to read
function  CanWrite(Timeout: integer): boolean; virtual;   // room to write
function  CanReadEx(Timeout: integer): boolean; virtual;  // also true if LineBuffer has data
function  WaitingData: integer; virtual;                  // bytes ready to read now
function  WaitingDataEx: integer; virtual;                // ... including LineBuffer
function  SendingData: integer; virtual;                  // bytes still queued to send
procedure Flush; virtual;                                 // wait until the output buffer drains
procedure Purge; virtual;                                 // discard both buffers immediately
```

`Timeout = 0` on the `Can*` calls means "test and return now"; `-1` means "wait,
possibly forever." **`Purge`** is the one to remember for serial work: after a
timeout or a protocol error, `Purge` throws away any half-received garbage in
both directions so your next exchange starts clean. **`Flush`** blocks until the
transmit buffer has been handed to the hardware.

## The `LastError` model — reports, not exceptions

Identical philosophy to the sockets. After any operation:

```pascal
property LastError: integer read FLastError;        // 0 = success
property LastErrorDesc: string read FLastErrorDesc; // human-readable
```

On success `LastError` is `0`. On failure it is either an OS error code or one of
synaser's own constants, which are worth recognising:

| Constant | Meaning |
| --- | --- |
| `ErrTimeout` (9997) | A read/write timed out |
| `ErrPortNotOpen` (9994) | Operation attempted with no open port |
| `ErrAccessDenied` (9990) | Could not open the device (permissions / in use) |
| `ErrAlreadyInUse` (9992) | Port is locked by another process |
| `ErrAlreadyOwned` (9991) | This process already owns the lock |
| `ErrWrongParameter` (9993) | Bad `Config` parameter |
| `ErrFrame` (9999) | Framing error on the line |
| `ErrOverrun` / `ErrRxOver` (10000/10001) | Receiver overrun |
| `ErrRxParity` (10002) | Parity error |

As with the sockets, if you prefer exceptions set `RaiseExcept := True` and a
failing call raises `ESynaSerError` (carrying `ErrorCode`); the default `False`
keeps the linear check-after-each-step style.

## Modem control lines — RTS, DTR, and the status inputs

This is the part that has no socket equivalent, and Synapse exposes the RS-232
control lines as plain properties. The two *outputs* you drive are **write-only**:

```pascal
property RTS: Boolean write SetRTSF;   // Request To Send  (output)
property DTR: Boolean write SetDTRF;   // Data Terminal Ready (output)
```

and the *inputs* you read are read-only:

```pascal
property CTS: Boolean read GetCTS;         // Clear To Send
property DSR: Boolean read GetDSR;         // Data Set Ready
property Carrier: Boolean read GetCarrier; // DCD — carrier detect
property Ring: Boolean read GetRing;       // RI — ring indicator
```

By default, a successful `Connect` **raises DTR** (and RTS too, unless you asked
for hardware handshake). If you need the lines left exactly as found — because you
are bit-banging DTR/RTS yourself, e.g. to control a device's reset or power line —
set **`ManualSignals := True`** *before* connecting. Then `Connect` and `Config`
never touch RTS/DTR, and their values are entirely yours:

```pascal
ser.ManualSignals := True;
ser.Connect('/dev/ttyUSB0');
ser.DTR := False;   // hold the target in reset
Sleep(50);
ser.DTR := True;    // release
```

Related odds and ends: `EnableRTSToggle(True)` puts the driver in half-duplex
RTS-toggle mode for RS-485 transceivers; `SetBreak(Duration)` sends a line break
for `Duration` ms; `ModemStatus` returns the raw status word the input properties
decode. There is also a small AT-command helper layer (`ATCommand`, `ATConnect`,
`ATResult`) for talking to Hayes modems, which is where this library was born.

## A worked example — 9600 8N1, command and terminated reply

Putting it together: open a USB-serial device, configure it, send a command, and
read one CR/LF-terminated line back — the whole exchange in linear, timeout-safe
code that reads like the socket examples because it *is* the same shape.

```pascal
uses synaser;

function QueryInstrument(const Device, Cmd: string): string;
var
  ser: TBlockSerial;
begin
  Result := '';
  ser := TBlockSerial.Create;
  try
    // Open the port. Unix: a literal /dev path; Windows: 'COM3'.
    ser.Connect(Device);
    if ser.LastError <> 0 then
    begin
      Writeln('open ', Device, ': ', ser.LastErrorDesc);
      Exit;
    end;

    // 9600 baud, 8 data bits, no parity, 1 stop bit, no flow control.
    ser.Config(9600, 8, 'N', SB1, False, False);
    if ser.LastError <> 0 then
    begin
      Writeln('config: ', ser.LastErrorDesc);
      Exit;
    end;

    // Some instruments need a moment after the line settles.
    ser.Purge;                          // start from a clean slate

    // Send a command. We supply the terminator ourselves, as always.
    ser.SendString(Cmd + CRLF);

    // Read one CR/LF-terminated reply, waiting up to 2 seconds.
    Result := ser.RecvString(2000);
    if ser.LastError = ErrTimeout then
      Writeln('no reply within 2 s')
    else if ser.LastError <> 0 then
      Writeln('read: ', ser.LastErrorDesc);
  finally
    ser.CloseSocket;
    ser.Free;
  end;
end;

// usage:
//   Writeln(QueryInstrument('/dev/ttyUSB0', '*IDN?'));   // Unix
//   Writeln(QueryInstrument('COM3', '*IDN?'));           // Windows
```

If your device does not frame replies with CR/LF, swap the one line:

```pascal
Result := ser.RecvTerminated(2000, '>');   // read up to a '>' prompt
```

That is the entire story. The port-opening and line-configuration parts are new;
everything after `Config` — `SendString`, `RecvString`/`RecvTerminated`, the
`Timeout` argument, the `LastError` check, `Purge` — is the socket vocabulary you
already speak, now driving a UART. Synapse chose one I/O model and applied it
everywhere, and *that* consistency is the feature.
