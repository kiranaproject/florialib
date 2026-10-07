unit Floria.Compression.CRC;

// Floria.Compression.CRC
// ======================
// High-performance CRC32 and Adler32 checksum implementations.
// Pure Object Pascal, zero dependencies.
//
// - CRC32: Standard IEEE 802.3 / ISO 3309 / PNG / Gzip polynomial ($EDB88320).
// - Adler32: RFC 1950 Zlib checksum (modulo 65521).

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

// CRC32 calculation
function CRC32(const ABuffer: Pointer; const ALength: Cardinal; const AInitCRC: Cardinal = 0): Cardinal;
function UpdateCRC32(const ACurrentCRC: Cardinal; const ABuffer: Pointer; const ALength: Cardinal): Cardinal;
function CRC32Stream(AStream: TStream; const ACount: Int64 = -1): Cardinal;

// Adler32 calculation
function Adler32(const ABuffer: Pointer; const ALength: Cardinal; const AInitAdler: Cardinal = 1): Cardinal;
function UpdateAdler32(const ACurrentAdler: Cardinal; const ABuffer: Pointer; const ALength: Cardinal): Cardinal;
function Adler32Stream(AStream: TStream; const ACount: Int64 = -1): Cardinal;

implementation

const
  ADLER_BASE = 65521;
  // Maximum number of bytes that can be accumulated before 32-bit overflow
  ADLER_NMAX = 5552;

var
  GCRCTable: array[0..255] of Cardinal;
  GCRCTableReady: Boolean = False;

procedure InitCRCTable();
var
  C: Cardinal;
  N, K: Integer;
begin
  if GCRCTableReady then Exit;
  for N := 0 to 255 do
  begin
    C := Cardinal(N);
    for K := 0 to 7 do
    begin
      if (C and 1) <> 0 then
        C := $EDB88320 xor (C shr 1)
      else
        C := C shr 1;
    end;
    GCRCTable[N] := C;
  end;
  GCRCTableReady := True;
end;

function UpdateCRC32(const ACurrentCRC: Cardinal; const ABuffer: Pointer; const ALength: Cardinal): Cardinal;
var
  P: PByte;
  I: Cardinal;
begin
  if not GCRCTableReady then InitCRCTable();
  if (ABuffer = nil) or (ALength = 0) then Exit(ACurrentCRC);

  Result := ACurrentCRC xor $FFFFFFFF;
  P := PByte(ABuffer);
  for I := 0 to ALength - 1 do
  begin
    Result := GCRCTable[(Result xor P^) and $FF] xor (Result shr 8);
    Inc(P);
  end;
  Result := Result xor $FFFFFFFF;
end;

function CRC32(const ABuffer: Pointer; const ALength: Cardinal; const AInitCRC: Cardinal = 0): Cardinal;
begin
  Result := UpdateCRC32(AInitCRC, ABuffer, ALength);
end;

function CRC32Stream(AStream: TStream; const ACount: Int64 = -1): Cardinal;
var
  Buffer: array[0..65535] of Byte;
  ToRead, ReadBytes: Integer;
  Remaining: Int64;
begin
  Result := 0;
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
    Result := UpdateCRC32(Result, @Buffer[0], ReadBytes);
    Dec(Remaining, ReadBytes);
  end;
end;

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

initialization
  InitCRCTable();

end.
