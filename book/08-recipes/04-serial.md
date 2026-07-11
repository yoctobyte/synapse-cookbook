# Recipes — Serial

`TBlockSerial` (in `synaser`) is the same blocking-with-timeouts model as the
block sockets, aimed at a serial port instead of a network peer. Full API and
platform notes in [the serial-ports chapter](../05-serial-ports/).

## Open a port and do a request/response

**Problem:** open a serial port, send a command, and read the device's reply.

```pascal
program SerialQuery;

{$mode objfpc}{$H+}

uses
  synaser;

var
  Ser: TBlockSerial;
  Reply: string;
begin
  Ser := TBlockSerial.Create;
  try
    // COM3 on Windows, /dev/ttyUSB0 on Linux — names are auto-translated.
    Ser.Connect('/dev/ttyUSB0');
    if Ser.LastError <> 0 then
    begin
      WriteLn('Open failed: ', Ser.LastErrorDesc);
      Exit;
    end;

    // baud, data bits, parity, stop bits, software flow, hardware flow.
    Ser.Config(9600, 8, 'N', SB1, False, False);

    Ser.SendString('STATUS?' + CRLF);
    Reply := Ser.RecvString(2000);       // one CRLF-terminated line, 2 s timeout
    if Ser.LastError = 0 then
      WriteLn('Device said: ', Reply)
    else
      WriteLn('No reply: ', Ser.LastErrorDesc);
  finally
    Ser.Free;   // destructor closes the port
  end;
end.
```

`Connect` opens the port (check `LastError`), `Config(baud, bits, parity, stop,
softflow, hardflow)` sets the line parameters, and `SendString`/`RecvString`
mirror the socket API exactly — `RecvString(Timeout)` returns one CRLF-terminated
line without the terminator. **Gotcha:** many devices are slow to wake, so allow a
generous receive timeout and, for a fixed terminator other than CRLF, use
`RecvTerminated(Timeout, Terminator)`; for raw byte counts use
`RecvPacket`/`RecvBufferEx`. For a modem, `ATCommand('AT')` sends a command and
returns the response in one call.
