# Recipes — Web

HTTP tasks with `httpsend`. The module-level helpers (`HttpGetText`,
`HttpGetBinary`, `HttpPostURL`) cover the common cases in one line; drop to
`THTTPSend` when you need headers or the status code. Full API in
[THTTPSend — talking HTTP](../03-protocol-classes/04-thttpsend.md).

## Download a URL to a file

**Problem:** fetch a remote resource (image, archive, anything binary) and save
it to disk.

```pascal
program Download;

{$mode objfpc}{$H+}

uses
  Classes,
  httpsend, ssl_openssl;   // ssl_openssl -> https:// works

var
  FileStream: TFileStream;
begin
  FileStream := TFileStream.Create('synapse.zip', fmCreate);
  try
    if HttpGetBinary('https://example.com/synapse.zip', FileStream) then
      WriteLn('Saved ', FileStream.Size, ' bytes')
    else
      WriteLn('Download failed');
  finally
    FileStream.Free;
  end;
end.
```

`HttpGetBinary(const URL: string; const Response: TStream): Boolean` streams the
body straight into any `TStream`, so it never buffers the whole file in memory.
**Gotcha:** a `True` return only means a reply arrived — for a broken link the
server may hand you a `404` page as the body. If that matters, use the object and
check `ResultCode` (next recipes).

## POST form data

**Problem:** submit an HTML form (`application/x-www-form-urlencoded`).

```pascal
program PostForm;

{$mode objfpc}{$H+}

uses
  Classes,
  httpsend, synacode, synautil;   // synacode: EncodeURLElement; synautil: ReadStrFromStream

var
  Reply: TMemoryStream;
  FormData: string;
begin
  Reply := TMemoryStream.Create;
  try
    // key=value&key=value, with every value percent-escaped.
    FormData := 'user=' + EncodeURLElement('Alice') +
                '&city=' + EncodeURLElement('São Paulo');

    if HttpPostURL('http://httpbin.org/post', FormData, Reply) then
    begin
      Reply.Position := 0;
      WriteLn(ReadStrFromStream(Reply, Reply.Size));
    end
    else
      WriteLn('POST failed');
  finally
    Reply.Free;
  end;
end.
```

`HttpPostURL(const URL, URLData: string; const Data: TStream): Boolean` sets the
`Content-Type` to `application/x-www-form-urlencoded`, sends `URLData` as the
body, and returns the response in `Data`. **Gotcha:** always run each value
through `EncodeURLElement` (from `synacode`) — an unescaped `&` or space in a
field corrupts the form.

## Fetch JSON over HTTPS

**Problem:** call a JSON API with custom headers and read both the status code
and the body.

```pascal
program FetchJson;

{$mode objfpc}{$H+}

uses
  Classes,
  httpsend, ssl_openssl;

var
  Http: THTTPSend;
  Body: TStringList;
begin
  Http := THTTPSend.Create;
  Body := TStringList.Create;
  try
    Http.Headers.Add('Accept: application/json');
    Http.Headers.Add('Authorization: Bearer my-token');

    if Http.HTTPMethod('GET', 'https://api.example.com/status') then
    begin
      WriteLn('Status: ', Http.ResultCode, ' ', Http.ResultString);
      Http.Document.Position := 0;             // rewind before reading
      Body.LoadFromStream(Http.Document);      // Document is a TMemoryStream
      WriteLn(Body.Text);
    end
    else
      WriteLn('Transport failed: ', Http.Sock.LastErrorDesc);
  finally
    Body.Free;
    Http.Free;
  end;
end.
```

`HTTPMethod` returns `True` for *any* reply, including `404`/`500` — branch on
`Http.ResultCode` for the real outcome. **Gotcha:** `Document` is a
`TMemoryStream`, not text; set `Position := 0` before `LoadFromStream`, or you'll
read zero bytes. To POST JSON, write the body into `Document`, set
`Http.MimeType := 'application/json'`, and call `HTTPMethod('POST', URL)`.
