# THTTPSend — talking HTTP

`THTTPSend` (in `httpsend`) is probably the most-used class in Synapse, and it
comes at two levels. For the common cases there are one-line module functions —
`HttpGetText`, `HttpPostURL`, and friends — that create the object, do the
transfer, and free it. When you need control over headers, methods, cookies, or
the raw response, you drop to the object itself. Both sit on the same
`TSynaClient`-over-`TTCPBlockSocket` foundation as the rest of the protocol
clients, and both get HTTPS for free from the [SSL plugin
seam](../01-architecture/03-ssl-plugin-seam.md).

## The class at a glance

`THTTPSend` diverges a little from the mail clients: there is no `Login`/`Logout`
pair, because HTTP is request-response. Instead the engine is a single method,
`HTTPMethod`, and everything around it is properties you set before and read
after:

```pascal
THTTPSend = class(TSynaClient)
  function HTTPMethod(const Method, URL: string): Boolean;

  property Headers: TStringList;      // request headers in / response headers out
  property Cookies: TStringList;      // parsed Set-Cookie, reused on next request
  property Document: TMemoryStream;   // request body in / response body out
  property MimeType: string;          // Content-Type for the request body
  property Protocol: string;          // '1.0' (default) or '1.1'
  property KeepAlive: Boolean;
  property UserAgent: string;
  property ResultCode: Integer;       // HTTP status code: 200, 404, 500…
  property ResultString: string;      // the status reason phrase
  property DownloadSize: int64;
  property UploadSize: int64;
  property Sock: TTCPBlockSocket;
  property ProxyHost, ProxyPort, ProxyUser, ProxyPass: string;
end;
```

The one object you touch most is **`Document`**, a `TMemoryStream`. It is
bidirectional: you fill it with the request body before a POST/PUT, and after any
call it holds the response body. `ResultCode` is the real HTTP status code, so
you branch on it directly.

## HTTPS is automatic

Here Synapse is at its quietest. `HTTPMethod` calls `ParseURL` on the URL, and if
the scheme is `https`, it does the TLS handshake for you — no property to set:

```pascal
if UpperCase(Prot) = 'HTTPS' then
  ...            // connect with SSL
```

So all HTTPS needs is an SSL plugin in `uses` and an `https://` URL:

```pascal
uses httpsend, ssl_openssl;
...
HttpGetText('https://example.com/', Response);   // just works
```

No plugin, and an `https://` URL will fail at the handshake — the seam is present
but empty. That is the whole "HTTPS wiring."

## The convenience functions

For everyday work you rarely need the object. `httpsend` exposes these
module-level helpers (each spins up a `THTTPSend`, runs one transfer, frees it):

```pascal
function HttpGetText(const URL: string; const Response: TStrings): Boolean;
function HttpGetBinary(const URL: string; const Response: TStream): Boolean;
function HttpPostBinary(const URL: string; const Data: TStream): Boolean;
function HttpPostURL(const URL, URLData: string; const Data: TStream): Boolean;
function HttpPostFile(const URL, FieldName, FileName: string;
  const Data: TStream; const ResultData: TStrings): Boolean;
```

- **`HttpGetText`** — GET a URL, load the body into a `TStrings`. Perfect for an
  API that returns text/JSON.
- **`HttpGetBinary`** — GET into any `TStream` (a file, a memory stream) for
  images, downloads, binaries.
- **`HttpPostURL`** — POST form data. It sets `Content-Type:
  application/x-www-form-urlencoded`, sends `URLData` as the body, and returns
  the response in `Data`.
- **`HttpPostBinary`** — POST a raw octet-stream body.
- **`HttpPostFile`** — POST a `multipart/form-data` file upload, boundary and all.

### Worked example: a quick GET

```pascal
program HttpGet;

uses
  SysUtils, Classes,
  httpsend, ssl_openssl;   // ssl_openssl -> https:// works

var
  Response: TStringList;
begin
  Response := TStringList.Create;
  try
    if HttpGetText('https://example.com/', Response) then
      Writeln(Response.Text)
    else
      Writeln('Request failed');
  finally
    Response.Free;
  end;
end.
```

### Worked example: a form POST

```pascal
program HttpPost;

uses
  SysUtils, Classes,
  httpsend, synacode, synautil;   // synacode: EncodeURLElement; synautil: ReadStrFromStream

var
  Reply: TMemoryStream;
  FormData: string;
begin
  Reply := TMemoryStream.Create;
  try
    // application/x-www-form-urlencoded: key=value&key=value, values escaped.
    FormData := 'name=' + EncodeURLElement('Alice') +
                '&city=' + EncodeURLElement('São Paulo');

    if HttpPostURL('http://httpbin.org/post', FormData, Reply) then
    begin
      Reply.Position := 0;
      Writeln('Response:');
      Writeln(ReadStrFromStream(Reply, Reply.Size));   // synautil helper
    end
    else
      Writeln('POST failed');
  finally
    Reply.Free;
  end;
end.
```

## Object-level usage: full control

When you need custom headers, a specific method, a status code, or the response
headers, use `THTTPSend` directly. The pattern is: set `Headers`/`Document`/
`MimeType`, call `HTTPMethod(verb, url)`, then read `ResultCode`, `Headers`, and
`Document`.

```pascal
program HttpJsonApi;

uses
  SysUtils, Classes,
  httpsend, ssl_openssl;

var
  Http: THTTPSend;
  Body: string;
begin
  Http := THTTPSend.Create;
  try
    Http.Protocol := '1.1';
    Http.MimeType := 'application/json';          // Content-Type of our body
    Http.Headers.Add('Authorization: Bearer ' + 'my-token');
    Http.Headers.Add('Accept: application/json');

    // Put the request body into Document.
    WriteStrToStream(Http.Document, '{"name":"Alice"}');  // synautil helper

    if Http.HTTPMethod('POST', 'https://api.example.com/users') then
    begin
      Writeln('Status: ', Http.ResultCode, ' ', Http.ResultString);

      // Response body is in Document; rewind and read it out.
      Http.Document.Position := 0;
      SetLength(Body, Http.Document.Size);
      if Http.Document.Size > 0 then
        Http.Document.ReadBuffer(Body[1], Http.Document.Size);
      Writeln(Body);

      // Response headers are in Headers after the call.
      Writeln('--- response headers ---');
      Writeln(Http.Headers.Text);
    end
    else
      Writeln('Transport failed (no reply)');
  finally
    Http.Free;
  end;
end.
```

A few things the source makes clear, worth knowing:

- **`Headers` is reused in both directions.** You add request headers to it
  before the call; after the call it holds the *response* headers (the request
  ones having been sent and cleared). Read them straight back out of the same
  list.
- **`HTTPMethod` returns the transport result, not the HTTP result.** It returns
  `True` when a reply was received at all — even a `404` or `500`. Always inspect
  `ResultCode` to learn what the server actually said; a `True` return with
  `ResultCode = 404` is a perfectly normal "not found."
- **`Document` is a `TMemoryStream`, not text.** For a text/JSON response, read
  its bytes out (as above) or `LoadFromStream` it into a `TStringList`. Remember
  to set `Position := 0` before reading.
- **`MimeType`** becomes the request's `Content-Type`; **`Protocol`** selects
  HTTP/1.0 (default) or 1.1; **`KeepAlive`** (on by default) lets you reuse one
  `THTTPSend` across several requests to the same host, saving reconnects.
- **Cookies** set by the server are parsed into the `Cookies` list and sent back
  automatically on the next request from the same object — a small session for
  free.
- **Proxies** go through `ProxyHost`/`ProxyPort`/`ProxyUser`/`ProxyPass`; Basic
  auth to the target is handled if you embed `user:pass@` in the URL.

## When to use which

Reach for the **convenience function** whenever a single GET or POST with default
headers will do — it is a one-liner and manages the object's lifetime for you.
Reach for the **object** the moment you need custom headers, a non-GET/POST verb
(PUT, DELETE, PATCH — `HTTPMethod` takes any method string), the status code, the
response headers, cookie continuity, or keep-alive across calls. Both are the
same engine; the functions are just `THTTPSend` with the common case pre-wired.
