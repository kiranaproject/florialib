unit Floria.Compression.CRC;

// Floria.Compression.CRC
// ======================
// Compatibility unit forwarding to Floria.Hash.CRC and Floria.Hash.Adler.
//
// New code should use Floria.Hash.CRC and Floria.Hash.Adler directly.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  Floria.Hash.CRC,
  Floria.Hash.Adler;

// CRC32
function CRC32(const ABuffer: Pointer; const ALength: Cardinal; const AInitCRC: Cardinal = 0): Cardinal; inline;
function UpdateCRC32(const ACurrentCRC: Cardinal; const ABuffer: Pointer; const ALength: Cardinal): Cardinal; inline;
function CRC32Stream(AStream: TStream; const ACount: Int64 = -1): Cardinal; inline;

// Adler32
function Adler32(const ABuffer: Pointer; const ALength: Cardinal; const AInitAdler: Cardinal = 1): Cardinal; inline;
function UpdateAdler32(const ACurrentAdler: Cardinal; const ABuffer: Pointer; const ALength: Cardinal): Cardinal; inline;
function Adler32Stream(AStream: TStream; const ACount: Int64 = -1): Cardinal; inline;

implementation

function CRC32(const ABuffer: Pointer; const ALength: Cardinal; const AInitCRC: Cardinal = 0): Cardinal;
begin
  Result := Floria.Hash.CRC.CRC32(ABuffer, ALength, AInitCRC);
end;

function UpdateCRC32(const ACurrentCRC: Cardinal; const ABuffer: Pointer; const ALength: Cardinal): Cardinal;
begin
  Result := Floria.Hash.CRC.UpdateCRC32(ACurrentCRC, ABuffer, ALength);
end;

function CRC32Stream(AStream: TStream; const ACount: Int64 = -1): Cardinal;
begin
  Result := Floria.Hash.CRC.CRC32Stream(AStream, ACount);
end;

function Adler32(const ABuffer: Pointer; const ALength: Cardinal; const AInitAdler: Cardinal = 1): Cardinal;
begin
  Result := Floria.Hash.Adler.Adler32(ABuffer, ALength, AInitAdler);
end;

function UpdateAdler32(const ACurrentAdler: Cardinal; const ABuffer: Pointer; const ALength: Cardinal): Cardinal;
begin
  Result := Floria.Hash.Adler.UpdateAdler32(ACurrentAdler, ABuffer, ALength);
end;

function Adler32Stream(AStream: TStream; const ACount: Int64 = -1): Cardinal;
begin
  Result := Floria.Hash.Adler.Adler32Stream(AStream, ACount);
end;

end.
