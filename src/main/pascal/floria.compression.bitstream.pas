unit Floria.Compression.BitStream;

// Floria.Compression.BitStream
// =============================
// Low-level bitstream reading and writing primitives:
//   - TBitReaderLSB: LSB-first bit reader (RFC 1951 Deflate / Inflate).
//   - TBitReaderMSB: MSB-first bit reader (JPEG / ISO 10918-1).
//   - TBitWriterLSB: LSB-first bit writer (RFC 1951 Deflate compression).

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils;

type
  // Bit reader for LSB-first streams (Deflate / Gzip / Zlib)
  TBitReaderLSB = record
  private
    FData     : PByte;
    FSize     : Integer;
    FBytePos  : Integer;
    FBitBuf   : Cardinal;
    FBitsInBuf: Integer;
  public
    procedure Init(const AData: Pointer; const ASize: Integer);
    function ReadBits(const ACount: Integer): Integer;
    function ReadBit(): Integer; inline;
    procedure AlignToByte();
    function HasMore(): Boolean;
    property BitsInBuf: Integer read FBitsInBuf;
    property BytePosition: Integer read FBytePos;
  end;

  // Bit reader for MSB-first streams (JPEG, etc.)
  TBitReaderMSB = record
  private
    FData     : PByte;
    FSize     : Integer;
    FBytePos  : Integer;
    FBitBuf   : Cardinal;
    FBitsInBuf: Integer;
  public
    procedure Init(const AData: Pointer; const ASize: Integer);
    function ReadBits(const ACount: Integer): Integer;
    function ReadBit(): Integer; inline;
    procedure AlignToByte();
    function HasMore(): Boolean;
  end;

  // Bit writer for LSB-first streams (Deflate compression)
  TBitWriterLSB = record
  private
    FStream   : TMemoryStream;
    FOwnStream: Boolean;
    FBitBuf   : Cardinal;
    FBitsInBuf: Integer;
  public
    procedure Init();
    procedure InitWithStream(AStream: TMemoryStream);
    procedure Done();
    procedure WriteBits(const AValue: Cardinal; const ACount: Integer);
    procedure WriteBit(const ABit: Integer); inline;
    procedure AlignToByte();
    function ToBytes(): TBytes;
    property Stream: TMemoryStream read FStream;
  end;

// Utility: bit reversal for canonical Huffman code generation
function ReverseBits(const AValue: Cardinal; const ALength: Integer): Cardinal; inline;

implementation

function ReverseBits(const AValue: Cardinal; const ALength: Integer): Cardinal;
var
  Val: Cardinal;
  I: Integer;
begin
  Result := 0;
  Val := AValue;
  for I := 0 to ALength - 1 do
  begin
    Result := (Result shl 1) or (Val and 1);
    Val := Val shr 1;
  end;
end;

// ---------------------------------------------------------------------------
// TBitReaderLSB
// ---------------------------------------------------------------------------

procedure TBitReaderLSB.Init(const AData: Pointer; const ASize: Integer);
begin
  FData := PByte(AData);
  FSize := ASize;
  FBytePos := 0;
  FBitBuf := 0;
  FBitsInBuf := 0;
end;

function TBitReaderLSB.ReadBits(const ACount: Integer): Integer;
begin
  while FBitsInBuf < ACount do
  begin
    if FBytePos < FSize then
    begin
      FBitBuf := FBitBuf or (Cardinal(FData[FBytePos]) shl FBitsInBuf);
      Inc(FBitsInBuf, 8);
      Inc(FBytePos);
    end
    else
      Break;
  end;

  Result := FBitBuf and ((1 shl ACount) - 1);
  FBitBuf := FBitBuf shr ACount;
  Dec(FBitsInBuf, ACount);
  if FBitsInBuf < 0 then FBitsInBuf := 0;
end;

function TBitReaderLSB.ReadBit(): Integer;
begin
  Result := ReadBits(1);
end;

procedure TBitReaderLSB.AlignToByte();
begin
  FBitBuf := 0;
  FBitsInBuf := 0;
end;

function TBitReaderLSB.HasMore(): Boolean;
begin
  Result := (FBytePos < FSize) or (FBitsInBuf > 0);
end;

// ---------------------------------------------------------------------------
// TBitReaderMSB
// ---------------------------------------------------------------------------

procedure TBitReaderMSB.Init(const AData: Pointer; const ASize: Integer);
begin
  FData := PByte(AData);
  FSize := ASize;
  FBytePos := 0;
  FBitBuf := 0;
  FBitsInBuf := 0;
end;

function TBitReaderMSB.ReadBits(const ACount: Integer): Integer;
begin
  while FBitsInBuf < ACount do
  begin
    if FBytePos < FSize then
    begin
      FBitBuf := (FBitBuf shl 8) or Cardinal(FData[FBytePos]);
      Inc(FBitsInBuf, 8);
      Inc(FBytePos);
    end
    else
      Break;
  end;

  Result := (FBitBuf shr (FBitsInBuf - ACount)) and ((1 shl ACount) - 1);
  Dec(FBitsInBuf, ACount);
  if FBitsInBuf < 0 then FBitsInBuf := 0;
end;

function TBitReaderMSB.ReadBit(): Integer;
begin
  Result := ReadBits(1);
end;

procedure TBitReaderMSB.AlignToByte();
begin
  FBitBuf := 0;
  FBitsInBuf := 0;
end;

function TBitReaderMSB.HasMore(): Boolean;
begin
  Result := (FBytePos < FSize) or (FBitsInBuf > 0);
end;

// ---------------------------------------------------------------------------
// TBitWriterLSB
// ---------------------------------------------------------------------------

procedure TBitWriterLSB.Init();
begin
  FStream := TMemoryStream.Create();
  FOwnStream := True;
  FBitBuf := 0;
  FBitsInBuf := 0;
end;

procedure TBitWriterLSB.InitWithStream(AStream: TMemoryStream);
begin
  FStream := AStream;
  FOwnStream := False;
  FBitBuf := 0;
  FBitsInBuf := 0;
end;

procedure TBitWriterLSB.Done();
begin
  AlignToByte();
  if FOwnStream then
    FreeAndNil(FStream);
end;

procedure TBitWriterLSB.WriteBits(const AValue: Cardinal; const ACount: Integer);
var
  B: Byte;
begin
  FBitBuf := FBitBuf or ((AValue and ((1 shl ACount) - 1)) shl FBitsInBuf);
  Inc(FBitsInBuf, ACount);

  while FBitsInBuf >= 8 do
  begin
    B := Byte(FBitBuf and $FF);
    FStream.WriteBuffer(B, 1);
    FBitBuf := FBitBuf shr 8;
    Dec(FBitsInBuf, 8);
  end;
end;

procedure TBitWriterLSB.WriteBit(const ABit: Integer);
begin
  WriteBits(Cardinal(ABit and 1), 1);
end;

procedure TBitWriterLSB.AlignToByte();
var
  B: Byte;
begin
  if FBitsInBuf > 0 then
  begin
    B := Byte(FBitBuf and $FF);
    FStream.WriteBuffer(B, 1);
    FBitBuf := 0;
    FBitsInBuf := 0;
  end;
end;

function TBitWriterLSB.ToBytes(): TBytes;
begin
  AlignToByte();
  SetLength(Result, FStream.Size);
  if FStream.Size > 0 then
    Move(FStream.Memory^, Result[0], FStream.Size);
end;

end.
