# TFTPSend — file transfer over two connections

`TFTPSend` (in `ftpsend`) is the classic FTP client, and it is the one client in
this chapter with a twist the others do not have: FTP uses *two* sockets. The
**control** connection carries commands and replies; a separate **data**
connection carries each file or listing. `TFTPSend` manages both — it owns two
`TTCPBlockSocket`s (`Sock` for control, `DSock` for data) — but the two-channel
dance is mostly hidden behind ordinary-looking verbs. As always it descends from
`TSynaClient`, so you set a few properties and call methods in order.

## The class at a glance

Connection and credentials come from `TSynaClient`. Uniquely, the constructor
pre-fills anonymous credentials (`UserName := 'anonymous'`,
`Password := 'anonymous@<localname>'`), so a public server needs nothing but a
host. `TFTPSend` adds the FTP verbs plus the data-channel machinery:

```pascal
TFTPSend = class(TSynaClient)
  function Login: Boolean;            // connect, greeting, AUTH TLS, logon sequence
  function Logout: Boolean;           // QUIT + close
  function FTPCommand(const Value: string): integer;   // raw command -> reply code

  // transfers
  function RetrieveFile(const FileName: string; Restore: Boolean): Boolean;  // RETR
  function StoreFile(const FileName: string; Restore: Boolean): Boolean;     // STOR
  function StoreUniqueFile: Boolean;                                         // STOU
  function AppendFile(const FileName: string): Boolean;                      // APPE
  function List(Directory: string; NameList: Boolean): Boolean;             // LIST/NLST/MLSD

  // filesystem
  function RenameFile(const OldName, NewName: string): Boolean;
  function DeleteFile(const FileName: string): Boolean;
  function FileSize(const FileName: string): int64;                          // SIZE
  function ChangeWorkingDir(const Directory: string): Boolean;               // CWD
  function ChangeToParentDir: Boolean;                                       // CDUP
  function ChangeToRootDir: Boolean;
  function DeleteDir(const Directory: string): Boolean;                      // RMD
  function CreateDir(const Directory: string): Boolean;                      // MKD
  function GetCurrentDir: String;                                            // PWD
  function NoOp: Boolean;

  // low-level data channel (only for custom commands)
  function DataRead(const DestStream: TStream): Boolean;
  function DataWrite(const SourceStream: TStream): Boolean;
  procedure Abort;
  procedure TelnetAbort;

  property ResultCode: Integer;       // numeric reply code of the last command
  property ResultString: string;      // its main reply line
  property FullResult: TStringList;    // every line of the reply
  property Sock: TTCPBlockSocket;      // control connection
  property DSock: TTCPBlockSocket;     // data connection
  property DataStream: TMemoryStream;  // in-memory transfer buffer (default sink/source)
  property DirectFile: Boolean;        // transfer straight to/from a disk file instead
  property DirectFileName: string;
  property FtpList: TFTPList;          // parsed directory listing after List(...)
  property PassiveMode: Boolean;       // default True
  property BinaryMode: Boolean;        // default True (TYPE I); False = ASCII
  property CanResume: Boolean;         // set by Login if the server supports REST
  property AutoTLS: Boolean;           // explicit FTPS (AUTH TLS)
  property FullSSL: Boolean;           // implicit FTPS (TLS from connect)
  property IsTLS: Boolean;             // control channel is encrypted
  property IsDataTLS: Boolean;         // data channel is encrypted
  property TLSonData: Boolean;         // default True: encrypt data too
  property ForceDefaultPort: Boolean;
  property ForceOldPort: Boolean;      // disable EPSV/EPRT (breaks IPv6)
  property UseMLSDList: Boolean;
  // plus firewall/proxy: FWHost, FWPort, FWUsername, FWPassword, FWMode, Account
end;
```

FTP reply codes are the real three-digit numbers, so `ResultCode` reads directly
(`200` OK, `226` transfer complete, `550` no such file). Internally almost every
verb is `(FTPCommand(...) div 100) = 2` — "did the server answer in the 2xx
family?" — which is why you can reason about `ResultCode` the same way the class
does.

## What `Login` does for you

Reading the source, `Login`:

1. Connects the control socket (immediate TLS handshake if `FullSSL` is set).
2. Reads the greeting, waiting past any `1xx` preliminary lines for the real
   reply; a non-`2xx` greeting fails.
3. If `AutoTLS` is set, sends `AUTH TLS` and upgrades the control connection.
4. Runs the **logon sequence** — `USER` / `PASS` / `ACCT` — driven by `FWMode`.
   With no firewall (`FWHost` empty) it is the plain three-step login; the other
   modes thread the login through a firewall/proxy, and `FWMode := -1` runs a
   `CustomLogon` sequence you supply.
5. On a TLS session, negotiates data-channel protection (`PBSZ 0`, then `PROT P`
   if `TLSonData`, else `PROT C`).
6. Sets binary type (`TYPE I`), stream mode, and *probes* for resume support with
   `REST` — setting `CanResume` accordingly.

## The data-connection model

Every transfer — a file or a directory listing — needs a fresh data connection,
and there are two ways to open one. This is the single most important thing to
understand about FTP, and `PassiveMode` (default **`True`**) picks between them:

- **Passive (`PassiveMode := True`).** The client asks the server "what port
  should I connect to?" (`PASV`, or `EPSV` for IPv6), the server answers with an
  address, and the *client* opens the data connection. Because the client makes
  both outbound connections, passive mode sails through client-side firewalls and
  NAT — which is why it is the default and almost always the right choice.
- **Active (`PassiveMode := False`).** The client opens a listening socket and
  tells the server where to connect back (`PORT`, or `EPRT` for IPv6); the
  *server* dials in. This needs the client to be reachable from the server, so it
  often trips over NAT. `ForceDefaultPort` pins the listen to port 20;
  `ForceOldPort` disables the `EPSV`/`EPRT` extensions (which also disables IPv6).

You rarely touch any of this. The high-level verbs (`RetrieveFile`, `StoreFile`,
`List`) open, use, and close the data connection internally via `DataSocket` /
`DataRead` / `DataWrite`. Those three lower-level methods are exposed only for the
rare case of implementing an unsupported command by hand.

## DataStream vs. DirectFile

Where do the bytes go? Two modes, chosen by `DirectFile`:

- **`DirectFile := False` (default).** All transfers run through `DataStream`, an
  in-memory `TMemoryStream`. After `RetrieveFile` it holds the downloaded bytes
  (rewound to position 0); before `StoreFile` you fill it with what to upload.
  Simple, and fine for anything that fits in RAM.
- **`DirectFile := True`.** Transfers stream straight to or from a disk file named
  by `DirectFileName` — a `TFileStream` under the hood — so a multi-gigabyte
  download never has to fit in memory. This is the mode the convenience functions
  use.

## FTPS: explicit and implicit

TLS is again the [SSL plugin seam](../01-architecture/03-ssl-plugin-seam.md) —
add a plugin, then choose:

```pascal
uses ftpsend, ssl_openssl;
```

- **Explicit FTPS (`AUTH TLS`).** Set `AutoTLS := True` on the standard port 21.
  `Login` upgrades the control connection after connecting, then negotiates
  data-channel encryption. This is the modern default for secure FTP.
- **Implicit FTPS.** Set `FullSSL := True` (historically port 990); TLS starts at
  connect time.
- **`TLSonData`** (default `True`) controls whether the *data* connection is
  encrypted too. `IsTLS` and `IsDataTLS` report what actually happened after
  `Login`.

> **Honest caveat.** Plain FTP sends your password — and every byte of every
> file — in the clear. Prefer `AutoTLS := True`, and check `IsTLS` (and
> `IsDataTLS` if the payload is sensitive) before trusting the session.

## Worked example: download a file

The rhythm is `Login → (navigate) → RetrieveFile → Logout`. Here streaming
straight to disk with `DirectFile`:

```pascal
program FtpDownload;

uses
  SysUtils, Classes,
  ftpsend, ssl_openssl;   // ssl_openssl enables AUTH TLS / FTPS

var
  Ftp: TFTPSend;
begin
  Ftp := TFTPSend.Create;
  try
    Ftp.TargetHost := 'ftp.example.com';
    // TargetPort defaults to 21; UserName/Password default to anonymous.
    Ftp.UserName := 'alice';
    Ftp.Password := 's3cret';
    Ftp.AutoTLS  := True;             // explicit FTPS

    if not Ftp.Login then
    begin
      Writeln('Login failed (', Ftp.ResultCode, '): ', Ftp.ResultString);
      Halt(1);
    end;

    Ftp.ChangeWorkingDir('/pub/reports');

    // Stream the download straight to a local file.
    Ftp.DirectFileName := 'report.pdf';
    Ftp.DirectFile     := True;

    if Ftp.RetrieveFile('report.pdf', False) then   // Restore=False: fresh download
      Writeln('Downloaded. Server said: ', Ftp.ResultString)
    else
      Writeln('Download failed (', Ftp.ResultCode, '): ', Ftp.ResultString);

    Ftp.Logout;
  finally
    Ftp.Free;
  end;
end.
```

Set `Restore := True` and, if the server advertised resume support (`CanResume`),
`RetrieveFile` picks up where an interrupted download left off — it seeks to the
end of the existing local file and sends `REST`. If you would rather keep the
bytes in memory, leave `DirectFile := False` and read them from `DataStream` after
the call (remember it is already rewound to position 0).

## Worked example: upload a file

`StoreFile` is the mirror image. In memory this time:

```pascal
program FtpUpload;

uses
  SysUtils, Classes,
  ftpsend, ssl_openssl;

var
  Ftp: TFTPSend;
begin
  Ftp := TFTPSend.Create;
  try
    Ftp.TargetHost := 'ftp.example.com';
    Ftp.UserName   := 'alice';
    Ftp.Password   := 's3cret';
    Ftp.AutoTLS    := True;

    if not Ftp.Login then
    begin
      Writeln('Login failed: ', Ftp.ResultString);
      Halt(1);
    end;

    // Fill DataStream with the payload (DirectFile stays False).
    Ftp.DataStream.LoadFromFile('local-notes.txt');

    if Ftp.StoreFile('notes.txt', False) then
      Writeln('Uploaded. Server said: ', Ftp.ResultString)
    else
      Writeln('Upload failed (', Ftp.ResultCode, '): ', Ftp.ResultString);

    Ftp.Logout;
  finally
    Ftp.Free;
  end;
end.
```

Related store verbs: `AppendFile` (`APPE`) appends to an existing remote file
instead of overwriting, and `StoreUniqueFile` (`STOU`) lets the server assign a
unique name. Set `BinaryMode := False` before a transfer to switch to ASCII mode
(`TYPE A`, which translates line endings) — leave it at the default `True` for
anything that is not plain text.

## Listing a directory

`List` fetches a directory over the data connection and, for a full listing, also
*parses* it:

```pascal
var
  i: Integer;
  rec: TFTPListRec;
begin
  if Ftp.List('/pub', False) then          // NameList=False -> full parsed listing
    for i := 0 to Ftp.FtpList.Count - 1 do
    begin
      rec := Ftp.FtpList.Items[i];
      if rec.Directory then
        Writeln(Format('%-30s  <dir>', [rec.FileName]))
      else
        Writeln(Format('%-30s %12d', [rec.FileName, rec.FileSize]));
    end;
end;
```

With `NameList := False`, `List` issues `LIST` (or `MLSD` if you set
`UseMLSDList := True`) and parses each line into `FtpList`, a `TFTPList` of
`TFTPListRec` — each record exposing `FileName`, `FileSize`, `Directory`,
`FileTime`, `Permission`, and the `OriginalLine`. Directory listing formats are a
notorious swamp (Unix, Windows, Novell, VMS…), and Synapse ships a table of masks
to cope; lines it cannot parse land in `FtpList.UnparsedLines`. With
`NameList := True` it issues `NLST` and you get bare names in `DataStream`, no
parsing. `MLSD` (RFC-3659) is the machine-readable modern format — prefer it when
the server supports it, since it sidesteps the parsing guesswork entirely.

## The convenience functions

For a one-shot transfer, `ftpsend` exposes three module-level helpers that create
a `TFTPSend`, run the whole `Login`/transfer/`Logout`, and free it:

```pascal
function FtpGetFile(const IP, Port, FileName, LocalFile, User, Pass: string): Boolean;
function FtpPutFile(const IP, Port, FileName, LocalFile, User, Pass: string): Boolean;
function FtpInterServerTransfer(
  const FromIP, FromPort, FromFile, FromUser, FromPass: string;
  const ToIP, ToPort, ToFile, ToUser, ToPass: string): Boolean;
```

`FtpGetFile` and `FtpPutFile` are the download/upload examples above in one line —
they use `DirectFile` internally, so they stream to/from `LocalFile` on disk. Pass
an empty `User` to log in anonymously. `FtpInterServerTransfer` wires two servers
together with a `PASV`/`PORT` pair so bytes flow server-to-server without passing
through your machine (the classic "FXP" transfer). Reach for the functions for the
common case; drop to the object the moment you need TLS toggles, resume, directory
navigation, or the parsed listing.

## A note on `ftptsend` — a different protocol

Do not confuse `ftpsend` with **`ftptsend`** (class `TTFTPSend`). Despite the
near-identical name, TFTP — *Trivial* File Transfer Protocol (RFC-1350) — is a
completely separate, minimal protocol that runs over **UDP**, with no login, no
directory listing, and no security. `TTFTPSend` is its client *and* server, with
`SendFile`/`RecvFile` and a `Data` buffer, and it is used mostly for bootstrapping
network devices, not general file transfer. If you mean ordinary FTP, you want
`ftpsend` / `TFTPSend` — this chapter.
