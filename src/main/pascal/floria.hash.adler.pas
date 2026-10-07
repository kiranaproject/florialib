unit Floria.Hash.Adler;

// Floria.Hash.Adler
// =================
// Fast Adler32 checksum implementation according to RFC 1950.
// Pure Object Pascal, zero dependencies.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

function Adler32(const ABuffer: Pointer; const ALength: Cardinal; const AInitAdler: Cardinal = 1): Cardinal;
function UpdateAdler32(const ACurrentAdler: Cardinal; const ABuffer: Pointer; const ALength: Cardinal): Cardinal;
function Adler32Stream(AStream: TStream; const ACount: Int64 = -1): Cardinal;
function Adler32Str(const S: AnsiString): Cardinal; inline;

implementation

const
  ADLER_BASE = 65521;
  // Maximum number of bytes that can be accumulated before 32-bit overflow
  ADLER_NMAX = 5552;

function UpdateAdler32(const ACurrentAdler: Cardinal; const ABuffer: Pointer; const ALength: Cardinal): Cardinal;
var
  S1, S2: Cardinal;
  P: PByte;
  Remaining, Chunk, I: Cardinal;
begin
  if (ABuffer = nil) or (ALength = 0) then Exit(ACurrentAdler);

  S1 := ACurrentAdler and $FFFF;
  S2 := (ACurrentAdler shr 16) and $FFFF;
  P := PByte(ABuffer);
  Remaining := ALength;

  while Remaining > 0 do
  begin
    Chunk := Remaining;
    if Chunk > ADLER_NMAX then Chunk := ADLER_NMAX;

    for I := 0 to Chunk - 1 do
    begin
      Inc(S1, P^);
      Inc(S2, S1);
      Inc(P);
    end;

    S1 := S1 mod ADLER_BASE;
    S2 := S2 mod ADLER_BASE;
    Dec(Remaining, Chunk);
  end;

  Result := (S2 shl 16) or S1;
end;

function Adler32(const ABuffer: Pointer; const ALength: Cardinal; const AInitAdler: Cardinal = 1): Cardinal;
begin
  Result := UpdateAdler32(AInitAdler, ABuffer, ALength);
end;

function Adler32Str(const S: AnsiString): Cardinal;
begin
  if Length(S) = 0 then
    Result := 1
  else
    Result := Adler32(PAnsiChar(S), Length(S));
end;

function Adler32Stream(AStream: TStream; const ACount: Int64 = -1): Cardinal;
var
  Buffer: array[0..65535] of Byte;
  ToRead, ReadBytes: Integer;
  Remaining: Int64;
begin
  Result := 1;
  if AStream = nil then Exit;

  if ACount < 0 then
    Remaining := AStream.Size - AStream.Position
  else
    Remaining := ACount;

  while Remaining > 0 do
  begin
    ToRead := SizeOf(Buffer);
    if Remaining < ToRead then
      ToRead := Integer(Remaining);
    ReadBytes := AStream.Read(Buffer[0], ToRead);
    if ReadBytes <= 0 then Break;
    Result := UpdateAdler32(Result, @Buffer[0], ReadBytes);
    Dec(Remaining, ReadBytes);
  end;
end;

end.
