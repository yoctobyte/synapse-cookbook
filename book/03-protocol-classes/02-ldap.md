# TLDAPSend — LDAP directory queries

LDAP is a different animal from the mail protocols. Where POP3 and SMTP trade
lines of ASCII text, LDAP speaks **ASN.1 BER**, a binary encoding, over the wire.
Synapse hides all of that: `TLDAPSend` (in `ldapsend`) builds and decodes the BER
packets internally — leaning on the `asn1util` unit — and hands you plain Pascal
objects. You bind, you search, you read result objects. The binary protocol never
surfaces.

## The class at a glance

Connection and credentials come from the `TSynaClient` base
(`TargetHost`, `TargetPort`, `UserName`, `Password`). `TLDAPSend` adds the
directory operations and, crucially, a structured result model:

```pascal
TLDAPSend = class(TSynaClient)
  function Login: Boolean;            // connect (+ optional StartTLS) -- does NOT bind
  function Bind: Boolean;             // simple bind (plaintext password!)
  function BindSasl: Boolean;         // SASL DIGEST-MD5 bind (password never sent)
  function Logout: Boolean;
  function Search(obj: AnsiString; TypesOnly: Boolean; Filter: AnsiString;
    const Attributes: TStrings): Boolean;
  function Compare(obj, AttributeValue: AnsiString): Boolean;
  function Add(obj: AnsiString; const Value: TLDAPAttributeList): Boolean;
  function Modify(obj: AnsiString; Op: TLDAPModifyOp;
    const Value: TLDAPAttribute): Boolean;
  function ModifyDN(obj, newRDN, newSuperior: AnsiString;
    DeleteoldRDN: Boolean): Boolean;
  function Delete(obj: AnsiString): Boolean;
  function Extended(const Name, Value: AnsiString): Boolean;
  function StartTLS: Boolean;

  property Version: integer;          // default 3
  property ResultCode: Integer;       // 0 = Success (LDAP result code)
  property ResultString: AnsiString;  // human-readable description
  property SearchScope: TLDAPSearchScope;   // SS_BaseObject|SS_SingleLevel|SS_WholeSubtree
  property SearchSizeLimit: integer;
  property SearchTimeLimit: integer;
  property SearchResult: TLDAPResultList;   // <-- results land here
  property Referals: TStringList;
  property AutoTLS: Boolean;
  property FullSSL: Boolean;
  property Sock: TTCPBlockSocket;
end;
```

Note the LDAP convention on `ResultCode`: **0 means Success** here (it is the
LDAP protocol result code — 0 Success, 49 Invalid credentials, 32 No such object,
and so on), the opposite of POP3's `1 = OK`. `ResultString` gives you the
human-readable form for logging.

## Login, then bind — they are two steps

This is the one place `TLDAPSend` differs from the other clients in a way that
trips people up. Its `Login` **only opens the connection** (and runs `StartTLS`
if `AutoTLS` is set) — it does *not* authenticate:

```pascal
function TLDAPSend.Login: Boolean;
begin
  Result := False;
  if not Connect then Exit;
  Result := True;
  if FAutoTLS then
    Result := StartTLS;
end;
```

Authentication is a separate `Bind` (or `BindSasl`). So the sequence is always
`Login` → `Bind`/`BindSasl` → your operations → `Logout`. An empty `UserName`
and `Password` at `Bind` time is a valid **anonymous bind** — common for public,
read-only directory lookups.

- **`Bind`** sends a *simple bind*: the password travels in a BER octet-string,
  in the clear. Fine over TLS, unsafe otherwise.
- **`BindSasl`** does a **SASL DIGEST-MD5** exchange (built with `synacode`'s
  HMAC/MD5, no external library) so the password is never transmitted. Prefer it
  when you cannot use TLS — though DIGEST-MD5 is itself dated, so the real answer
  for a hostile network is TLS underneath.

## TLS

The usual seam applies — add an `ssl_*` plugin and choose implicit or explicit:

```pascal
uses ldapsend, ssl_openssl;
```

- **LDAPS (implicit)** — set `FullSSL := True`, `TargetPort := '636'`.
- **STARTTLS (explicit)** — set `AutoTLS := True` so `Login` upgrades the plain
  :389 connection before you bind, or call `StartTLS` yourself.

## The result model

A `Search` fills `SearchResult`, a `TLDAPResultList`. The shape mirrors LDAP
itself:

- `SearchResult` — a list of `TLDAPResult` objects, one per directory entry
  found. Indexed with `[i]`, counted with `.Count`.
- Each `TLDAPResult` has an **`ObjectName`** (the entry's DN) and an
  **`Attributes`** list (`TLDAPAttributeList`).
- Each `TLDAPAttribute` is a `TStringList` descendant with an **`AttributeName`**
  and one line per value (attributes can be multi-valued). `Attributes.Get(name)`
  is a shortcut to the first value of a named attribute.

## Worked example: bind and search

Find every person whose surname is `Smith` under a base DN, and print their name
and email:

```pascal
program LdapSearch;

uses
  SysUtils, Classes,
  ldapsend, ssl_openssl;   // ssl_openssl enables StartTLS / LDAPS

var
  Ldap: TLDAPSend;
  Attrs: TStringList;
  i, j: Integer;
  Entry: TLDAPResult;
  Attr: TLDAPAttribute;
begin
  Ldap := TLDAPSend.Create;
  Attrs := TStringList.Create;
  try
    Ldap.TargetHost := 'ldap.example.com';
    Ldap.UserName   := 'cn=reader,dc=example,dc=com';
    Ldap.Password   := 'readonly';
    Ldap.AutoTLS    := True;             // upgrade to TLS before binding

    if not Ldap.Login then               // connect (+ StartTLS)
    begin
      Writeln('Connect failed');
      Halt(1);
    end;

    if not Ldap.Bind then                // authenticate; 0 = Success
    begin
      Writeln('Bind failed: ', Ldap.ResultString);
      Halt(1);
    end;

    // Only fetch the attributes we care about (empty list = all attributes).
    Attrs.Add('cn');
    Attrs.Add('mail');

    Ldap.SearchScope := SS_WholeSubtree;
    if Ldap.Search('dc=example,dc=com',  // base DN
                   False,                // TypesOnly = False -> return values
                   '(sn=Smith)',         // filter
                   Attrs) then
    begin
      Writeln(Ldap.SearchResult.Count, ' entries:');
      for i := 0 to Ldap.SearchResult.Count - 1 do
      begin
        Entry := Ldap.SearchResult[i];
        Writeln('DN: ', Entry.ObjectName);
        for j := 0 to Entry.Attributes.Count - 1 do
        begin
          Attr := Entry.Attributes[j];
          // Attr is a TStringList of values under Attr.AttributeName
          Writeln('  ', Attr.AttributeName, ' = ', Attr.Text);
        end;
      end;
    end
    else
      Writeln('Search failed: ', Ldap.ResultString);

    Ldap.Logout;
  finally
    Attrs.Free;
    Ldap.Free;
  end;
end.
```

The `Search` arguments map straight onto the LDAP operation: the **base DN** to
search under, `TypesOnly` (pass `False` to get attribute values, `True` for just
the attribute names), an **RFC-4515 filter string** (`(sn=Smith)`,
`(&(objectClass=person)(mail=*))`, …) which `TLDAPSend` translates to BER for
you, and the list of attributes to return (leave it empty to ask for all of
them). Scope is set separately via `SearchScope`, and you can cap a runaway query
with `SearchSizeLimit` / `SearchTimeLimit`.

## Writing to the directory

The same object drives the write side, each method a one-to-one LDAP operation:
`Add` (create an entry from a `TLDAPAttributeList`), `Modify` (add/delete/replace
an attribute's values via `TLDAPModifyOp` = `MO_Add`/`MO_Delete`/`MO_Replace`),
`ModifyDN` (rename or move an entry), and `Delete`. All obey the same
`ResultCode = 0` success convention, and all require a bind with sufficient
privilege first.

> **Honest caveat.** A simple `Bind` sends the password in cleartext BER; even
> `BindSasl`'s DIGEST-MD5 is a legacy mechanism. Treat TLS (LDAPS or STARTTLS) as
> mandatory for anything but an anonymous read against a public directory.
</content>
