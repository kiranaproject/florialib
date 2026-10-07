unit Floria.Hash.FNV;

// Floria.Hash.FNV
// ===============
// Fowler-Noll-Vo FNV-1a non-cryptographic hash functions (32-bit and 64-bit).
// Ideal for fast string interning, CSS property hashing, and dictionary keys.
//
// Pure Object Pascal, zero dependencies.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  FNV1A_32_INIT: Cardinal = $811C9DC5;
  FNV1A_32_PRIME: Cardinal = $01000193;

  FNV1A_64_INIT: QWord = $CBF29CE484222325;
  FNV1A_64_PRIME: QWord = $00000100000001B3;

// 32-bit FNV-1a
function FNV1a_32(const ABuffer: Pointer; const ALength: Cardinal; const AInitHash: Cardinal = $811C9DC5): Cardinal;
function FNV1a_32Str(const S: AnsiString): Cardinal; inline;
function FNV1a_32Stream(AStream: TStream; const ACount: Int64 = -1): Cardinal;

// 64-bit FNV-1a
function FNV1a_64(const ABuffer: Pointer; const ALength: Cardinal; const AInitHash: QWord = $CBF29CE484222325): QWord;
function FNV1a_64Str(const S: AnsiString): QWord; inline;
function FNV1a_64Stream(AStream: TStream; const ACount: Int64 = -1): QWord;

implementation

function FNV1a_32(const ABuffer: Pointer; const ALength: Cardinal; const AInitHash: Cardinal = $811C9DC5): Cardinal;
var
  P: PByte;
  I: Cardinal;
begin
  Result := AInitHash;
  if (ABuffer = nil) or (ALength = 0) then Exit;

  P := PByte(ABuffer);
  for I := 0 to ALength - 1 do
  begin
    Result := (Result xor P^) * FNV1A_32_PRIME;
    Inc(P);
  end;
end;

function FNV1a_32Str(const S: AnsiString): Cardinal;
begin
  if Length(S) = 0 then
    Result := FNV1A_32_INIT
  else
    Result := FNV1a_32(PAnsiChar(S), Length(S));
end;

function FNV1a_32Stream(AStream: TStream; const ACount: Int64 = -1): Cardinal;
var
  Buffer: array[0..65535] of Byte;
  ToRead, ReadBytes: Integer;
  Remaining: Int64;
begin
  Result := FNV1A_32_INIT;
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
    Result := FNV1a_32(@Buffer[0], ReadBytes, Result);
    Dec(Remaining, ReadBytes);
  end;
end;

function FNV1a_64(const ABuffer: Pointer; const ALength: Cardinal; const AInitHash: QWord = $CBF29CE484222325): QWord;
var
  P: PByte;
  I: Cardinal;
begin
  Result := AInitHash;
  if (ABuffer = nil) or (ALength = 0) then Exit;

  P := PByte(ABuffer);
  for I := 0 to ALength - 1 do
  begin
    Result := (Result xor P^) * FNV1A_64_PRIME;
    Inc(P);
  end;
end;

function FNV1a_64Str(const S: AnsiString): QWord;
begin
  if Length(S) = 0 then
    Result := FNV1A_64_INIT
  else
    Result := FNV1a_64(PAnsiChar(S), Length(S));
end;

function FNV1a_64Stream(AStream: TStream; const ACount: Int64 = -1): QWord;
var
  Buffer: array[0..65535] of Byte;
  ToRead, ReadBytes: Integer;
  Remaining: Int64;
begin
  Result := FNV1A_64_INIT;
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
    Result := FNV1a_64(@Buffer[0], ReadBytes, Result);
    Dec(Remaining, ReadBytes);
  end;
end;

end.
