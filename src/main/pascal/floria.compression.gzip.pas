unit Floria.Compression.Gzip;

// Floria.Compression.Gzip
// ========================
// RFC 1952 Gzip stream compression and decompression container.
// Pure Object Pascal, zero external dependencies.
//
// Enables transparent loading of compressed SVGZ (.svgz) vector files,
// assets, and web payloads.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  Floria.Compression.CRC,
  Floria.Compression.Deflate;

function IsGzip(const AData: Pointer; const ASize: Integer): Boolean;
function IsGzipStream(AStream: TStream): Boolean;

function GzipDecompress(const AData: Pointer; const ASize: Integer): TBytes;
function GzipCompress(const AData: Pointer; const ASize: Integer; const Level: TFloriaCompressionLevel = fclDefault): TBytes;

procedure GzipDecompressStream(AInStream, AOutStream: TStream);
procedure GzipCompressStream(AInStream, AOutStream: TStream; const Level: TFloriaCompressionLevel = fclDefault);

implementation

const
  GZIP_MAGIC_1 = $1F;
  GZIP_MAGIC_2 = $8B;
  GZIP_CM_DEFLATE = 8;

  // Header flags
  FLAG_FTEXT    = $01;
  FLAG_FHCRC    = $02;
  FLAG_FEXTRA   = $04;
  FLAG_FNAME    = $08;
  FLAG_FCOMMENT = $10;

function IsGzip(const AData: Pointer; const ASize: Integer): Boolean;
var
  P: PByte;
begin
  if (AData = nil) or (ASize < 10) then Exit(False);
  P := PByte(AData);
  Result := (P[0] = GZIP_MAGIC_1) and (P[1] = GZIP_MAGIC_2) and (P[2] = GZIP_CM_DEFLATE);
end;

function IsGzipStream(AStream: TStream): Boolean;
var
  Sig: array[0..2] of Byte;
  OldPos: Int64;
begin
  Result := False;
  if AStream = nil then Exit;
  OldPos := AStream.Position;
  try
    if AStream.Read(Sig[0], 3) = 3 then
      Result := (Sig[0] = GZIP_MAGIC_1) and (Sig[1] = GZIP_MAGIC_2) and (Sig[2] = GZIP_CM_DEFLATE);
  finally
    AStream.Position := OldPos;
  end;
end;

function GzipDecompress(const AData: Pointer; const ASize: Integer): TBytes;
var
  P: PByte;
  Offset, HeaderEnd: Integer;
  FLG: Byte;
  XLen: Word;
  ExpectedCRC, ActualCRC: Cardinal;
  ExpectedSize, ActualSize: Cardinal;
  PayloadSize: Integer;
begin
  if not IsGzip(AData, ASize) then
    raise Exception.Create('Invalid Gzip header or unsupported compression format');

  if ASize < 18 then // 10 bytes header + at least 8 bytes trailer
    raise Exception.Create('Corrupted Gzip file: buffer too short');

  P := PByte(AData);
  FLG := P[3];
  Offset := 10; // Base header is 10 bytes

  // Skip FEXTRA
  if (FLG and FLAG_FEXTRA) <> 0 then
  begin
    if Offset + 2 > ASize then raise Exception.Create('Malformed Gzip FEXTRA field');
    XLen := P[Offset] or (P[Offset + 1] shl 8);
    Inc(Offset, 2 + XLen);
  end;

  // Skip FNAME (null-terminated string)
  if (FLG and FLAG_FNAME) <> 0 then
  begin
    while (Offset < ASize) and (P[Offset] <> 0) do Inc(Offset);
    Inc(Offset); // Skip terminating zero
  end;

  // Skip FCOMMENT (null-terminated string)
  if (FLG and FLAG_FCOMMENT) <> 0 then
  begin
    while (Offset < ASize) and (P[Offset] <> 0) do Inc(Offset);
    Inc(Offset); // Skip terminating zero
  end;

  // Skip FHCRC (2-byte CRC16)
  if (FLG and FLAG_FHCRC) <> 0 then
    Inc(Offset, 2);

  if Offset + 8 > ASize then
    raise Exception.Create('Corrupted Gzip stream: payload truncated');

  HeaderEnd := Offset;
  PayloadSize := (ASize - 8) - HeaderEnd;

  // Decompress raw Deflate payload
  Result := Inflate(P + HeaderEnd, PayloadSize);

  // Read little-endian CRC32 and ISIZE from 8-byte trailer
  ExpectedCRC := Cardinal(P[ASize - 8]) or
                (Cardinal(P[ASize - 7]) shl 8) or
                (Cardinal(P[ASize - 6]) shl 16) or
                (Cardinal(P[ASize - 5]) shl 24);

  ExpectedSize := Cardinal(P[ASize - 4]) or
                 (Cardinal(P[ASize - 3]) shl 8) or
                 (Cardinal(P[ASize - 2]) shl 16) or
                 (Cardinal(P[ASize - 1]) shl 24);

  ActualSize := Cardinal(Length(Result));
  if (ActualSize and $FFFFFFFF) <> ExpectedSize then
    raise Exception.Create(Format('Gzip uncompressed size mismatch (expected %d, got %d)', [ExpectedSize, ActualSize]));

  if ActualSize > 0 then
    ActualCRC := CRC32(@Result[0], ActualSize)
  else
    ActualCRC := 0;

  if ActualCRC <> ExpectedCRC then
    raise Exception.Create(Format('Gzip CRC32 checksum mismatch (expected $%08X, got $%08X)', [ExpectedCRC, ActualCRC]));
end;

function GzipCompress(const AData: Pointer; const ASize: Integer; const Level: TFloriaCompressionLevel = fclDefault): TBytes;
var
  Deflated: TBytes;
  DeflatedLen: Integer;
  CRC: Cardinal;
  XFL: Byte;
  POut: PByte;
begin
  // 1. Deflate raw payload
  Deflated := Deflate(AData, ASize, Level);
  DeflatedLen := Length(Deflated);

  // 2. Compute CRC32
  if (AData <> nil) and (ASize > 0) then
    CRC := CRC32(AData, ASize)
  else
    CRC := 0;

  case Level of
    fclMax:  XFL := 2; // Maximum compression
    fclFast: XFL := 4; // Fastest
  else
    XFL := 0;
  end;

  // 3. Allocate: 10 bytes header + deflated payload + 8 bytes trailer
  SetLength(Result, 10 + DeflatedLen + 8);
  POut := @Result[0];

  // Header (10 bytes)
  POut[0] := GZIP_MAGIC_1;
  POut[1] := GZIP_MAGIC_2;
  POut[2] := GZIP_CM_DEFLATE;
  POut[3] := 0; // FLG
  POut[4] := 0; POut[5] := 0; POut[6] := 0; POut[7] := 0; // MTIME
  POut[8] := XFL;
  POut[9] := 3; // OS: Unix

  // Payload
  if DeflatedLen > 0 then
    Move(Deflated[0], POut[10], DeflatedLen);

  // Trailer (8 bytes): CRC32 (little endian) + ISIZE (little endian)
  POut[10 + DeflatedLen + 0] := Byte(CRC and $FF);
  POut[10 + DeflatedLen + 1] := Byte((CRC shr 8) and $FF);
  POut[10 + DeflatedLen + 2] := Byte((CRC shr 16) and $FF);
  POut[10 + DeflatedLen + 3] := Byte((CRC shr 24) and $FF);

  POut[10 + DeflatedLen + 4] := Byte(ASize and $FF);
  POut[10 + DeflatedLen + 5] := Byte((ASize shr 8) and $FF);
  POut[10 + DeflatedLen + 6] := Byte((ASize shr 16) and $FF);
  POut[10 + DeflatedLen + 7] := Byte((ASize shr 24) and $FF);
end;

procedure GzipDecompressStream(AInStream, AOutStream: TStream);
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

  OutBuf := GzipDecompress(@InBuf[0], InSize);
  if Length(OutBuf) > 0 then
    AOutStream.WriteBuffer(OutBuf[0], Length(OutBuf));
end;

procedure GzipCompressStream(AInStream, AOutStream: TStream; const Level: TFloriaCompressionLevel = fclDefault);
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

  OutBuf := GzipCompress(@InBuf[0], InSize, Level);
  if Length(OutBuf) > 0 then
    AOutStream.WriteBuffer(OutBuf[0], Length(OutBuf));
end;

end.
