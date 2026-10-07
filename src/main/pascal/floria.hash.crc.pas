unit Floria.Hash.CRC;

// Floria.Hash.CRC
// ===============
// Fast cyclic redundancy check algorithms:
//   - CRC32: Standard IEEE 802.3 / ISO 3309 / PNG / Gzip polynomial ($EDB88320).
//   - CRC16: Standard IBM / ANSI polynomial ($A001 reversed).
//   - CRC64: ECMA-182 polynomial ($C96C5795D7870F42 reversed).
//
// Pure Object Pascal, zero dependencies.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

// CRC32
function CRC32(const ABuffer: Pointer; const ALength: Cardinal; const AInitCRC: Cardinal = 0): Cardinal;
function UpdateCRC32(const ACurrentCRC: Cardinal; const ABuffer: Pointer; const ALength: Cardinal): Cardinal;
function CRC32Stream(AStream: TStream; const ACount: Int64 = -1): Cardinal;
function CRC32Str(const S: AnsiString): Cardinal; inline;

// CRC16
function CRC16(const ABuffer: Pointer; const ALength: Cardinal; const AInitCRC: Word = 0): Word;
function UpdateCRC16(const ACurrentCRC: Word; const ABuffer: Pointer; const ALength: Cardinal): Word;

// CRC64 (ECMA-182)
function CRC64(const ABuffer: Pointer; const ALength: Cardinal; const AInitCRC: QWord = 0): QWord;
function UpdateCRC64(const ACurrentCRC: QWord; const ABuffer: Pointer; const ALength: Cardinal): QWord;

implementation

var
  GCRC32Table: array[0..255] of Cardinal;
  GCRC32TableReady: Boolean = False;

  GCRC16Table: array[0..255] of Word;
  GCRC16TableReady: Boolean = False;

  GCRC64Table: array[0..255] of QWord;
  GCRC64TableReady: Boolean = False;

procedure InitCRC32Table();
var
  C: Cardinal;
  N, K: Integer;
begin
  if GCRC32TableReady then Exit;
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
    GCRC32Table[N] := C;
  end;
  GCRC32TableReady := True;
end;

procedure InitCRC16Table();
var
  C: Word;
  N, K: Integer;
begin
  if GCRC16TableReady then Exit;
  for N := 0 to 255 do
  begin
    C := Word(N);
    for K := 0 to 7 do
    begin
      if (C and 1) <> 0 then
        C := $A001 xor (C shr 1)
      else
        C := C shr 1;
    end;
    GCRC16Table[N] := C;
  end;
  GCRC16TableReady := True;
end;

procedure InitCRC64Table();
const
  POLY64_ECMA: QWord = $C96C5795D7870F42;
var
  C: QWord;
  N, K: Integer;
begin
  if GCRC64TableReady then Exit;
  for N := 0 to 255 do
  begin
    C := QWord(N);
    for K := 0 to 7 do
    begin
      if (C and 1) <> 0 then
        C := POLY64_ECMA xor (C shr 1)
      else
        C := C shr 1;
    end;
    GCRC64Table[N] := C;
  end;
  GCRC64TableReady := True;
end;

function UpdateCRC32(const ACurrentCRC: Cardinal; const ABuffer: Pointer; const ALength: Cardinal): Cardinal;
var
  P: PByte;
  I: Cardinal;
begin
  if not GCRC32TableReady then InitCRC32Table();
  if (ABuffer = nil) or (ALength = 0) then Exit(ACurrentCRC);

  Result := ACurrentCRC xor $FFFFFFFF;
  P := PByte(ABuffer);
  for I := 0 to ALength - 1 do
  begin
    Result := GCRC32Table[(Result xor P^) and $FF] xor (Result shr 8);
    Inc(P);
  end;
  Result := Result xor $FFFFFFFF;
end;

function CRC32(const ABuffer: Pointer; const ALength: Cardinal; const AInitCRC: Cardinal = 0): Cardinal;
begin
  Result := UpdateCRC32(AInitCRC, ABuffer, ALength);
end;

function CRC32Str(const S: AnsiString): Cardinal;
begin
  if Length(S) = 0 then
    Result := 0
  else
    Result := CRC32(PAnsiChar(S), Length(S));
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

function UpdateCRC16(const ACurrentCRC: Word; const ABuffer: Pointer; const ALength: Cardinal): Word;
var
  P: PByte;
  I: Cardinal;
begin
  if not GCRC16TableReady then InitCRC16Table();
  if (ABuffer = nil) or (ALength = 0) then Exit(ACurrentCRC);

  Result := ACurrentCRC;
  P := PByte(ABuffer);
  for I := 0 to ALength - 1 do
  begin
    Result := GCRC16Table[(Result xor P^) and $FF] xor (Result shr 8);
    Inc(P);
  end;
end;

function CRC16(const ABuffer: Pointer; const ALength: Cardinal; const AInitCRC: Word = 0): Word;
begin
  Result := UpdateCRC16(AInitCRC, ABuffer, ALength);
end;

function UpdateCRC64(const ACurrentCRC: QWord; const ABuffer: Pointer; const ALength: Cardinal): QWord;
var
  P: PByte;
  I: Cardinal;
begin
  if not GCRC64TableReady then InitCRC64Table();
  if (ABuffer = nil) or (ALength = 0) then Exit(ACurrentCRC);

  Result := ACurrentCRC xor $FFFFFFFFFFFFFFFF;
  P := PByte(ABuffer);
  for I := 0 to ALength - 1 do
  begin
    Result := GCRC64Table[(Result xor P^) and $FF] xor (Result shr 8);
    Inc(P);
  end;
  Result := Result xor $FFFFFFFFFFFFFFFF;
end;

function CRC64(const ABuffer: Pointer; const ALength: Cardinal; const AInitCRC: QWord = 0): QWord;
begin
  Result := UpdateCRC64(AInitCRC, ABuffer, ALength);
end;

initialization
  InitCRC32Table();
  InitCRC16Table();
  InitCRC64Table();

end.
