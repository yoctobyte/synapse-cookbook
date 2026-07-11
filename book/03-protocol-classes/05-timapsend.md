# TIMAPSend — the mailbox client

`TIMAPSend` (in `imapsend`) is the one client in this chapter that does more than
push a message through a pipe: it drives a *stateful* mailbox on the server. IMAP
keeps your mail on the server and lets you browse folders, fetch individual
messages or just their headers, search, and set flags — all without downloading
the whole mailbox. `TIMAPSend` is Synapse's IMAP4rev1 implementation (RFC-2060,
RFC-2595), and like every client here it is a thin `TSynaClient` descendant over
a `TTCPBlockSocket`: set a few properties, call the verbs in order, read the
result.

## The class at a glance

Connection and credentials come from `TSynaClient` (`TargetHost`, `TargetPort`,
`UserName`, `Password`, `OAuth2Token`). `TIMAPSend` adds the IMAP verbs and the
selected-folder state:

```pascal
TIMAPSend = class(TSynaClient)
  function Login: Boolean;            // connect, greeting, STARTTLS, LOGIN
  function Logout: Boolean;           // LOGOUT + close
  function NoOp: Boolean;             // NOOP (keep-alive)
  function Capability: Boolean;       // CAPABILITY -> fills IMAPcap

  // folders
  function List(FromFolder: string; const FolderList: TStrings): Boolean;
  function ListSubscribed(FromFolder: string; const FolderList: TStrings): Boolean;
  function ListSearch(FromFolder, Search: string; const FolderList: TStrings): Boolean;
  function CreateFolder(FolderName: string): Boolean;
  function DeleteFolder(FolderName: string): Boolean;
  function RenameFolder(FolderName, NewFolderName: string): Boolean;
  function SubscribeFolder(FolderName: string): Boolean;
  function UnsubscribeFolder(FolderName: string): Boolean;
  function SelectFolder(FolderName: string): Boolean;    // SELECT (read/write)
  function SelectROFolder(FolderName: string): Boolean;  // EXAMINE (read-only)
  function CloseFolder: Boolean;
  function StatusFolder(FolderName, Value: string): integer;
  function ExpungeFolder: Boolean;
  function CheckFolder: Boolean;

  // messages
  function FetchMess(MessID: integer; const Mess: TStrings): Boolean;     // whole message
  function FetchHeader(MessID: integer; const Headers: TStrings): Boolean;// headers only
  function MessageSize(MessID: integer): integer;
  function AppendMess(ToFolder: string; const Mess: TStrings): Boolean;
  function DeleteMess(MessID: integer): Boolean;         // mark \Deleted
  function CopyMess(MessID: integer; ToFolder: string): Boolean;
  function SearchMess(Criteria: string; const FoundMess: TStrings): Boolean;
  function GetUID(MessID: integer; var UID: Integer): Boolean;

  // flags
  function GetFlagsMess(MessID: integer; var Flags: string): Boolean;
  function SetFlagsMess(MessID: integer; Flags: string): Boolean;   // replace
  function AddFlagsMess(MessID: integer; Flags: string): Boolean;   // +FLAGS
  function DelFlagsMess(MessID: integer; Flags: string): Boolean;   // -FLAGS

  function StartTLS: Boolean;
  function FindCap(const Value: string): string;

  property ResultString: string;        // status line of the last operation
  property FullResult: TStringList;      // every reply line of the last operation
  property IMAPcap: TStringList;         // server capabilities
  property AuthDone: Boolean;
  property UID: Boolean;                 // interpret MessID as UID, not sequence no.
  property SelectedFolder: string;
  property SelectedCount: integer;       // messages in the selected folder
  property SelectedRecent: integer;
  property SelectedUIDvalidity: integer;
  property AutoTLS: Boolean;
  property FullSSL: Boolean;
  property Sock: TTCPBlockSocket;
end;
```

Note what is *not* here. Unlike SMTP or HTTP there is no numeric `ResultCode` —
IMAP replies are tagged text (`OK`, `NO`, `BAD`), and the source models that
directly: the internal `IMAPcommand` returns the uppercase status word and every
public verb boils it down to `= 'OK'`. So a method returning `True` means the
server tagged the command `OK`; when it returns `False`, `ResultString` holds the
raw tagged line the server sent, which is your diagnostic.

## What `Login` does for you

Reading the source, `Login` folds the whole session opening into one call:

1. Connects (doing an immediate TLS handshake first if `FullSSL` is set).
2. Reads the server greeting. `* PREAUTH` means the connection is already
   authenticated (and sets `AuthDone`); `* OK` means proceed to login; anything
   else fails.
3. Runs `CAPABILITY` and requires the server to advertise `IMAP4rev1` — Synapse
   will not talk to a server that does not claim the base protocol.
4. If `AutoTLS` is set and the server advertises `STARTTLS`, upgrades the live
   connection to TLS and re-reads the capabilities.
5. Authenticates. With an `OAuth2Token` set it sends `AUTHENTICATE XOAUTH2`;
   otherwise it sends a plain `LOGIN "user" "pass"` (user and password escaped
   for the quoting rules — see below). `AuthDone` reports whether auth succeeded.

## FullSSL vs. STARTTLS

TLS is the usual [SSL plugin seam](../01-architecture/03-ssl-plugin-seam.md) —
one unit in `uses`, then pick implicit or explicit, exactly as described in the
[chapter intro](00-index.md):

```pascal
uses imapsend, ssl_openssl;
```

- **IMAPS (implicit).** Set `FullSSL := True`, `TargetPort := '993'`. The TLS
  handshake happens the instant the socket connects.
- **STARTTLS (explicit).** Set `AutoTLS := True`, keep the plain port `143`.
  `Login` upgrades the connection *before* it sends `LOGIN`, so your credentials
  travel encrypted. You can also drive the upgrade yourself with the public
  `StartTLS` method (it checks `FindCap('STARTTLS')` first and returns `False` if
  the server never advertised it).

> **Honest caveat.** `LOGIN` sends your username and password in the clear (IMAP
> does no hashing of its own here). Only ever log in over a TLS session — which is
> exactly why `Login` performs STARTTLS *before* `LOGIN` when `AutoTLS` is on.

## Sequence numbers vs. UIDs

Every message verb takes a `MessID: integer`, and the `UID` property decides how
the server reads it. With `UID := False` (the default), `MessID` is the message's
*sequence number* within the selected folder — `1` is the first message,
`SelectedCount` is the last. Sequence numbers are stable only for the current
selection: expunging a message renumbers everything after it. With `UID := True`,
Synapse prefixes each command with `UID` and `MessID` is the message's permanent
unique identifier — stable across sessions, paired with `SelectedUIDvalidity` to
detect a folder that was deleted and recreated. Reach for UIDs the moment you
need an identifier that survives past the current `SELECT`.

## Selecting a folder is a mode switch

IMAP is stateful: most message verbs only work once a folder is *selected*.

- **`SelectFolder`** issues `SELECT` and enters read/write state — flags and
  deletions take effect. After it returns, `SelectedCount`, `SelectedRecent`, and
  `SelectedUIDvalidity` describe the folder, and `SelectedFolder` names it.
- **`SelectROFolder`** issues `EXAMINE` — the same, but read-only, so you can
  browse without marking anything `\Seen`.
- **`CloseFolder`** leaves selected state (and silently expunges `\Deleted`
  messages, per the protocol).

`List` fills a `TStrings` with folder *names* (it filters out `\Noselect`
containers and un-escapes quoted names for you); pass an empty `FromFolder` to
list everything. `ListSubscribed` does the same over `LSUB`, and `ListSearch`
takes a wildcard pattern.

## Deleting is two steps

`DeleteMess` does **not** remove a message — it sets the `\Deleted` flag
(`STORE … +FLAGS.SILENT (\Deleted)`). The message physically goes away only when
you call `ExpungeFolder` (or `CloseFolder`, which expunges on its way out). That
two-step is IMAP's design, not a Synapse quirk: it lets a client "undelete" by
clearing the flag before the expunge. The flag verbs are the general form —
`AddFlagsMess`/`DelFlagsMess` add or remove flags (`\Seen`, `\Flagged`,
`\Answered`, …), `SetFlagsMess` replaces the whole set, and `GetFlagsMess` reads
it back.

## Worked example: fetch a message from a folder

The core rhythm is `Login → SelectFolder → Fetch → Logout`:

```pascal
program ImapFetch;

uses
  SysUtils, Classes,
  imapsend, ssl_openssl;   // ssl_openssl enables IMAPS / STARTTLS

var
  Imap: TIMAPSend;
  Msg: TStringList;
begin
  Imap := TIMAPSend.Create;
  Msg  := TStringList.Create;
  try
    Imap.TargetHost := 'imap.example.com';
    Imap.TargetPort := '993';        // IMAPS
    Imap.FullSSL    := True;          // implicit TLS from the first byte
    Imap.UserName   := 'alice@example.com';
    Imap.Password   := 's3cret';

    if not Imap.Login then
    begin
      Writeln('Login failed: ', Imap.ResultString);
      Halt(1);
    end;

    // Enter the mailbox. After this, SelectedCount is the message count.
    if not Imap.SelectFolder('INBOX') then
    begin
      Writeln('Cannot select INBOX: ', Imap.ResultString);
      Imap.Logout;
      Halt(1);
    end;
    Writeln('INBOX holds ', Imap.SelectedCount, ' message(s).');

    if Imap.SelectedCount > 0 then
    begin
      // Fetch the newest message (highest sequence number) in full.
      if Imap.FetchMess(Imap.SelectedCount, Msg) then
      begin
        Writeln('--- message ', Imap.SelectedCount, ' ---');
        Writeln(Msg.Text);        // full RFC-822 message: headers + body
      end
      else
        Writeln('Fetch failed: ', Imap.ResultString);
    end;

    Imap.Logout;
  finally
    Msg.Free;
    Imap.Free;
  end;
end.
```

`FetchMess` retrieves the whole message (`FETCH n (RFC822)`) into the `TStrings`
as a complete RFC-822 message — headers, blank line, body. When you only need the
envelope (a message-list view, say), `FetchHeader` fetches just the headers
(`RFC822.HEADER`), and `MessageSize` returns the byte count without transferring
anything. To turn the fetched `Msg` into structured headers, alternatives, and
attachments, hand it to `TMimeMess.DecodeMessage` — the mail-message chapter
covers that; `TIMAPSend` owns *getting the bytes*, `TMimeMess` owns *what they
mean*.

## Searching

`SearchMess` sends IMAP's `SEARCH` and returns the matching message numbers (or
UIDs, if `UID` is set) as a `TStrings`. The criteria string is IMAP's own search
language — powerful, SQL-ish, but not SQL:

```pascal
var
  Hits: TStringList;
begin
  Hits := TStringList.Create;
  try
    Imap.SelectFolder('INBOX');
    // messages from a given sender that are still unseen
    if Imap.SearchMess('FROM "bob@example.org" UNSEEN', Hits) then
      Writeln(Hits.Count, ' match(es): ', Hits.CommaText);
  finally
    Hits.Free;
  end;
end;
```

Each entry in `Hits` is a message number you can pass straight to `FetchMess`,
`GetFlagsMess`, `CopyMess`, or `DeleteMess`.

## Escaping and the raw command

IMAP folder and mailbox names are quoted strings, and characters like `"` and `\`
must be escaped (RFC-2683). Synapse handles this for you inside every verb via
`EscapeSpecialCharacters`, and un-escapes returned names via
`UnescapeSpecialCharacters`; both are public if you build commands by hand. And
you can always drop to the raw protocol: `IMAPcommand(cmd)` sends any tagged
command and returns the status word, leaving the reply in `FullResult` — the
escape hatch for server-specific extensions Synapse does not wrap.

## When to use which verb

`SelectFolder`/`SelectROFolder` gate everything — call one first. Then
`FetchHeader` + `MessageSize` to *browse* cheaply, `FetchMess` to *read* in full,
`SearchMess` to *find*, the flag verbs to *mark*, and `DeleteMess` +
`ExpungeFolder` (or `CloseFolder`) to *remove*. `NoOp` keeps an idle connection
from timing out. It is the same blocking, one-verb-at-a-time rhythm as the rest of
the chapter — just with a folder's worth of state hanging off the client between
calls.
