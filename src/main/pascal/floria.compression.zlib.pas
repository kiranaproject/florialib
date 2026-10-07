unit Floria.Compression.Zlib;

// Floria.Compression.Zlib
// ========================
// RFC 1950 Zlib stream compression and decompression container.
// Pure Object Pascal, zero external dependencies.
//
// Wraps Deflate payload with CMF/FLG headers and Adler32 checksum.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  Floria.Compression.CRC,
  Floria.Compression.Deflate;

function ZlibDecompress(const AData: Pointer; const ASize: Integer; const AExpectedSize: Integer = 0): TBytes;
function ZlibCompress(const AData: Pointer; const ASize: Integer; const Level: TFloriaCompressionLevel = fclDefault): TBytes;

procedure ZlibDecompressStream(AInStream, AOutStream: TStream; const AExpectedSize: Integer = 0);
procedure ZlibCompressStream(AInStream, AOutStream: TStream; const Level: TFloriaCompressionLevel = fclDefault);

implementation

function ZlibDecompress(const AData: Pointer; const ASize: Integer; const AExpectedSize: Integer = 0): TBytes;
var
  P: PByte;
  CMF, FLG: Byte;
  ExpectedAdler, ActualAdler: Cardinal;
  PayloadSize: Integer;
begin
  if (AData = nil) or (ASize < 6) then
    raise Exception.Create('Invalid Zlib data: buffer too small for header and checksum');

  P := PByte(AData);
  CMF := P[0];
  FLG := P[1];

  // 1. Header integrity check: (CMF * 256 + FLG) mod 31 = 0
  if ((Integer(CMF) * 256 + Integer(FLG)) mod 31) <> 0 then
    raise Exception.Create('Invalid Zlib header checksum');

  // 2. Compression method must be Deflate (8)
  if (CMF and $0F) <> 8 then
    raise Exception.Create(Format('Unsupported Zlib compression method (%d)', [CMF and $0F]));

  // 3. Preset dictionary not supported
  if (FLG and $20) <> 0 then
    raise Exception.Create('Preset dictionary is not supported in Zlib streams');

  // 4. Decompress Deflate payload (excluding 2-byte header and 4-byte Adler32)
  PayloadSize := ASize - 6;
  Result := Inflate(P + 2, PayloadSize, AExpectedSize);

  // 5. Verify Adler32 checksum (stored in big-endian at the end of the stream)
  ExpectedAdler := (Cardinal(P[ASize - 4]) shl 24) or
                   (Cardinal(P[ASize - 3]) shl 16) or
                   (Cardinal(P[ASize - 2]) shl 8) or
                    Cardinal(P[ASize - 1]);

  if Length(Result) > 0 then
    ActualAdler := Adler32(@Result[0], Length(Result))
  else
    ActualAdler := 1;

  if ActualAdler <> ExpectedAdler then
    raise Exception.Create(Format('Zlib Adler32 checksum mismatch (expected $%08X, got $%08X)', [ExpectedAdler, ActualAdler]));
end;

function ZlibCompress(const AData: Pointer; const ASize: Integer; const Level: TFloriaCompressionLevel = fclDefault): TBytes;
var
  Deflated: TBytes;
  DeflatedLen: Integer;
  Adler: Cardinal;
  CMF, FLG: Byte;
  FLevel: Byte;
  CheckVal: Word;
begin
  // 1. Compress payload with Deflate
  Deflated := Deflate(AData, ASize, Level);
  DeflatedLen := Length(Deflated);

  // 2. Compute Adler32 checksum
  if (AData <> nil) and (ASize > 0) then
    Adler := Adler32(AData, ASize)
  else
    Adler := 1;

  // 3. Construct Zlib header
  // CMF: 8 (Deflate) + 7 (32K window) << 4 = $78
  CMF := $78;

  case Level of
    fclNone:    FLevel := 0; // Fastest
    fclFast:    FLevel := 1; // Fast
    fclDefault: FLevel := 2; // Default
    fclMax:     FLevel := 3; // Maximum
  else
    FLevel := 2;
  end;

  // Base FLG with FLEVEL in bits 6..7
  FLG := (FLevel shl 6);

  // Set FCHECK (bits 0..4) so (CMF * 256 + FLG) mod 31 = 0
  CheckVal := (Word(CMF) shl 8) or FLG;
  Inc(FLG, (31 - (CheckVal mod 31)) mod 31);

  // 4. Allocate final buffer: 2 bytes header + deflated payload + 4 bytes Adler32
  SetLength(Result, 2 + DeflatedLen + 4);
  Result[0] := CMF;
  Result[1] := FLG;

  if DeflatedLen > 0 then
    Move(Deflated[0], Result[2], DeflatedLen);

  // Adler32 Big-Endian trailer
  Result[2 + DeflatedLen + 0] := Byte((Adler shr 24) and $FF);
  Result[2 + DeflatedLen + 1] := Byte((Adler shr 16) and $FF);
  Result[2 + DeflatedLen + 2] := Byte((Adler shr 8) and $FF);
  Result[2 + DeflatedLen + 3] := Byte(Adler and $FF);
end;

procedure ZlibDecompressStream(AInStream, AOutStream: TStream; const AExpectedSize: Integer = 0);
var
  InBuf: TBytes;
  OutBuf: TBytes;
  InSize: Integer;
begin
  if (AInStream = nil) or (AOutStream = nil) then Exit;
  InSize := AInStream.Size - AInStream.Position;
  if InSize <= 0 then Exit;
  SetLength(InBuf, InSize);
  AInStream.ReadBuffer(InBuf[0], InSize);

  OutBuf := ZlibDecompress(@InBuf[0], InSize, AExpectedSize);
  if Length(OutBuf) > 0 then
    AOutStream.WriteBuffer(OutBuf[0], Length(OutBuf));
end;

procedure ZlibCompressStream(AInStream, AOutStream: TStream; const Level: TFloriaCompressionLevel = fclDefault);
var
  InBuf: TBytes;
  OutBuf: TBytes;
  InSize: Integer;
begin
  if (AInStream = nil) or (AOutStream = nil) then Exit;
  InSize := AInStream.Size - AInStream.Position;
  if InSize <= 0 then Exit;
  SetLength(InBuf, InSize);
  AInStream.ReadBuffer(InBuf[0], InSize);

  OutBuf := ZlibCompress(@InBuf[0], InSize, Level);
  if Length(OutBuf) > 0 then
    AOutStream.WriteBuffer(OutBuf[0], Length(OutBuf));
end;

end.
