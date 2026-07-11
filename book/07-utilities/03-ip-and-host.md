# IP Addresses and Host Info

Two small units cover the address end of Synapse. `synaip.pas` is pure
conversion — strings to addresses and back, no I/O. `synamisc.pas` asks the
operating system what it knows: your DNS servers, your local IPs, your proxy.
Between them they answer "is this a valid address?", "what does it look like in
binary?", and "what is my machine configured to use?".

## `synaip` — parse and format addresses

```pascal
uses synaip;
```

This unit does no networking. It never resolves a name — `IsIP` explicitly
rejects symbolic hostnames — it only transforms address *text*.

### Validation

```pascal
{:Returns TRUE, if "Value" is a valid IPv4 address. Cannot be a symbolic Name!}
function IsIP(const Value: string): Boolean;
{:Returns TRUE, if "Value" is a valid IPv6 address. Cannot be a symbolic Name!}
function IsIP6(const Value: string): Boolean;
```

```pascal
IsIP('192.168.0.1');    // True
IsIP('example.org');    // False  — a name, not an address
IsIP6('::1');           // True
IsIP6('192.168.0.1');   // False  — that is IPv4
```

A common pattern is to decide whether you already have an address or still need
to resolve a name:

```pascal
if IsIP(target) or IsIP6(target) then
  // use it directly
else
  // hand it to DNS
```

### IPv4 conversion

```pascal
{:Convert IPv4 address from their string form to binary.}
function StrToIp(value: string): integer;
{:Convert IPv4 address from binary to string form.}
function IpToStr(value: integer): string;
```

```pascal
n := StrToIp('192.168.0.1');   // packed into an integer
s := IpToStr(n);               // '192.168.0.1'  (round-trip)
```

### IPv6 conversion

IPv6 addresses are 16 bytes, so they go through a byte-array type,
`TIp6Bytes = array [0..15] of Byte`:

```pascal
{:Convert IPv6 address from their string form to binary byte array.}
function StrToIp6(value: string): TIp6Bytes;
{:Convert IPv6 address from binary byte array to string form.}
function Ip6ToStr(value: TIp6Bytes): string;
{:Expand short form of IPv6 address to long form.}
function ExpandIP6(Value: AnsiString): AnsiString;
```

`ExpandIP6` turns the compressed `::` form into the full eight-group form —
useful when you need to compare two addresses textually:

```pascal
ExpandIP6('2001:db8::1');
// '2001:0DB8:0000:0000:0000:0000:0000:0001'
```

### Reverse form (for PTR / rDNS)

```pascal
{:Returns a string with the "Host" ip address converted to binary form.}
function IPToID(Host: string): Ansistring;
{:Convert IPv4 address to reverse form.}
function ReverseIP(Value: AnsiString): AnsiString;
{:Convert IPv6 address to reverse form.}
function ReverseIP6(Value: AnsiString): AnsiString;
```

`ReverseIP` produces the reversed-octet order that reverse-DNS lookups use:

```pascal
ReverseIP('192.168.0.1');   // '1.0.168.192'
```

`IPToID` returns the raw binary (byte-string) form of an address — the shape
DNS records and some protocol fields carry it in.

## `synamisc` — what the OS knows

```pascal
uses synamisc;
```

Where `synaip` is pure math, `synamisc` reaches into the operating system. The
same function name returns platform-specific truth: on Windows it reads the
registry and IP Helper API; on POSIX it probes the system's resolver
configuration.

### DNS servers

```pascal
{:Autodetect current DNS servers used by the system. If more than one DNS server
 is defined, then the result is comma-delimited.}
function GetDNS: string;
```

```pascal
Writeln('System DNS: ', GetDNS);
// e.g. '192.168.0.1,8.8.8.8'
```

This is the function to call when you want to do your *own* DNS query but need
to know which server to ask — Synapse's own resolver uses it for exactly that.

### Local IP addresses

```pascal
{:Return all known IP addresses on the local system. Addresses are
 comma-delimited.}
function GetLocalIPs: string;
{:Return all known IP addresses of the required type on the local system.}
function GetLocalIPsFamily(value: TSocketFamily): string;
```

`GetLocalIPs` returns every address the host has; `GetLocalIPsFamily` filters by
family (`TSocketFamily`, e.g. IPv4-only or IPv6-only):

```pascal
Writeln('This host: ', GetLocalIPs);
// e.g. '127.0.0.1,192.168.0.42,::1'
```

### Proxy settings

Proxy discovery is Windows-oriented (it reads Internet Explorer / WinHTTP
config) and returns a record:

```pascal
TProxySetting = record
  Host: string;
  Port: string;
  Bypass: string;
  ResultCode: integer;
  Autodetected: boolean;
end;

{:Read Internet Explorer 5.0+ proxy setting for given protocol. Windows only!}
function GetIEProxy(protocol: string): TProxySetting;

{$IFDEF MSWINDOWS}
{:Autodetect system proxy setting for a specified URL. Windows only!}
function GetProxyForURL(const AURL: WideString): TProxySetting;
{$ENDIF}
```

`GetProxyForURL` is compiled only on Windows (`{$IFDEF MSWINDOWS}`); on other
platforms it does not exist, so guard your calls with the same define.

### Wake-on-LAN

A genuinely miscellaneous member — send the magic packet that powers on a
sleeping machine:

```pascal
{:Turn on a network computer that supports Wake-on-LAN. You need the MAC
 address; you can also give a target IP (broadcast is used if omitted).}
procedure WakeOnLan(MAC, IP: string);
```

```pascal
WakeOnLan('00:11:22:33:44:55', '');   // broadcast on the local network
```

## What is *not* here

Neither unit resolves a hostname to an address — there is no `GetIPByName`.
Name resolution is DNS, and in Synapse that lives in the socket layer
(`synsock` / `blcksock`) and the DNS client (`dnssend.pas`), not in these
helpers. `synaip` validates and converts addresses you already have; `synamisc`
tells you which DNS server *would* answer such a query. The lookup itself is a
socket's job.

## Summary

| You want to…                              | Call                        | Unit     |
|-------------------------------------------|-----------------------------|----------|
| Check a string is a literal IPv4 / IPv6   | `IsIP` / `IsIP6`            | synaip   |
| Pack / unpack an IPv4 address             | `StrToIp` / `IpToStr`       | synaip   |
| Pack / unpack an IPv6 address             | `StrToIp6` / `Ip6ToStr`     | synaip   |
| Expand `::` shorthand                     | `ExpandIP6`                 | synaip   |
| Build a reverse-DNS name                  | `ReverseIP` / `ReverseIP6`  | synaip   |
| Find the system's DNS servers             | `GetDNS`                    | synamisc |
| List this host's own IPs                  | `GetLocalIPs`               | synamisc |
| Read the configured proxy (Windows)       | `GetIEProxy` / `GetProxyForURL` | synamisc |
| Power on a machine by MAC                 | `WakeOnLan`                 | synamisc |
