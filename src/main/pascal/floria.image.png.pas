unit Floria.Image.PNG;

// Floria.Image.PNG
// ================
// Pure Object Pascal PNG image decoder and encoder.
// Includes a self-contained RFC 1950/1951 Zlib / Deflate decompressor
// and uncompressed-block Deflate encoder. Zero external dependencies.
//
// Supports:
// - Reading RGBA (32-bit), RGB (24-bit), Grayscale+Alpha, Grayscale, and Indexed PNG.
// - All 5 standard PNG scanline reconstruction filters (None, Sub, Up, Average, Paeth).
// - Writing standard 32-bit RGBA PNG images with CRC32 and Adler32 checksums.

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils,
  Floria.Image.Core;

type
  // PNG Reader Codec
  TFloriaPNGReader = class(TFloriaImageReader)
  public
    class function CanRead(AStream: TStream): Boolean; override;
    class function Format(): TFloriaImageFormat; override;
    procedure ReadImage(AStream: TStream; AImage: TFloriaImage); override;
  end;

  // PNG Writer Codec
  TFloriaPNGWriter = class(TFloriaImageWriter)
  public
    class function Format(): TFloriaImageFormat; override;
    procedure WriteImage(AStream: TStream; AImage: TFloriaImage); override;
  end;

implementation

const
  PNG_SIGNATURE: array[0..7] of Byte = ($89, $50, $4E, $47, $0D, $0A, $1A, $0A);

// ============================================================================
// CRC32 & Adler32 Checksum Engine
// ============================================================================

var
  CRCTable: array[0..255] of Cardinal;
  CRCTableReady: Boolean = False;

procedure InitCRCTable();
var
  C: Cardinal;
  N, K: Integer;
begin
  if CRCTableReady then Exit;
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
    CRCTable[N] := C;
  end;
  CRCTableReady := True;
end;

function UpdateCRC(const ACurrentCRC: Cardinal; const ABuffer: Pointer; const ALength: Cardinal): Cardinal;
var
  P: PByte;
  I: Cardinal;
begin
  InitCRCTable();
  Result := ACurrentCRC xor $FFFFFFFF;
  P := PByte(ABuffer);
  for I := 0 to ALength - 1 do
  begin
    Result := CRCTable[(Result xor P^) and $FF] xor (Result shr 8);
    Inc(P);
  end;
  Result := Result xor $FFFFFFFF;
end;

function ComputeAdler32(const ABuffer: Pointer; const ALength: Cardinal): Cardinal;
const
  BASE = 65521;
var
  S1, S2: Cardinal;
  P: PByte;
  I: Cardinal;
begin
  S1 := 1;
  S2 := 0;
  P := PByte(ABuffer);
  for I := 0 to ALength - 1 do
  begin
    S1 := (S1 + P^) mod BASE;
    S2 := (S2 + S1) mod BASE;
    Inc(P);
  end;
  Result := (S2 shl 16) or S1;
end;

// ============================================================================
// Bit Reader for Deflate Decompression
// ============================================================================

type
  TBitReader = record
    Data     : PByte;
    Size     : Integer;
    BitPos   : Integer;
    BitBuf   : Cardinal;
    BitsInBuf: Integer;
    function ReadBits(const ACount: Integer): Integer;
    function ReadBit(): Integer;
    procedure AlignToByte();
  end;

procedure InitBitReader(var BR: TBitReader; const AData: Pointer; const ASize: Integer);
begin
  BR.Data := PByte(AData);
  BR.Size := ASize;
  BR.BitPos := 0;
  BR.BitBuf := 0;
  BR.BitsInBuf := 0;
end;

function TBitReader.ReadBit(): Integer;
begin
  Result := ReadBits(1);
end;

function TBitReader.ReadBits(const ACount: Integer): Integer;
var
  ByteIdx: Integer;
begin
  while BitsInBuf < ACount do
  begin
    ByteIdx := BitPos div 8;
    if ByteIdx < Size then
    begin
      BitBuf := BitBuf or (Cardinal(Data[ByteIdx]) shl BitsInBuf);
      Inc(BitsInBuf, 8);
      Inc(BitPos, 8);
    end
    else
      Break;
  end;

  Result := BitBuf and ((1 shl ACount) - 1);
  BitBuf := BitBuf shr ACount;
  Dec(BitsInBuf, ACount);
end;

procedure TBitReader.AlignToByte();
begin
  BitBuf := 0;
  BitsInBuf := 0;
  BitPos := ((BitPos + 7) div 8) * 8;
end;

// ============================================================================
// Pure Pascal Huffman Decoder & Inflate Decompressor
// ============================================================================

const
  MAX_BITS = 16;
  MAX_CODE = 288;

type
  THuffmanTree = record
    Counts  : array[0..MAX_BITS] of Integer;
    Symbols : array[0..MAX_CODE] of Integer;
    Offsets : array[0..MAX_BITS] of Integer;
  end;

procedure BuildHuffman(var Tree: THuffmanTree; const BitLengths: array of Integer; const Count: Integer);
var
  I, Len: Integer;
  CodeCount: array[0..MAX_BITS] of Integer;
begin
  FillChar(Tree, SizeOf(Tree), 0);
  FillChar(CodeCount, SizeOf(CodeCount), 0);

  for I := 0 to Count - 1 do
  begin
    Len := BitLengths[I];
    if (Len > 0) and (Len <= MAX_BITS) then
      Inc(CodeCount[Len]);
  end;

  Tree.Offsets[1] := 0;
  for I := 1 to MAX_BITS - 1 do
    Tree.Offsets[I + 1] := Tree.Offsets[I] + CodeCount[I];

  for I := 0 to Count - 1 do
  begin
    Len := BitLengths[I];
    if (Len > 0) and (Len <= MAX_BITS) then
    begin
      Tree.Symbols[Tree.Offsets[Len]] := I;
      Inc(Tree.Offsets[Len]);
    end;
  end;

  // Rebuild offsets for decoding
  Tree.Offsets[0] := 0;
  for I := 1 to MAX_BITS do
  begin
    Tree.Counts[I] := CodeCount[I];
    Tree.Offsets[I] := Tree.Offsets[I - 1] + CodeCount[I - 1];
  end;
end;

function DecodeHuffman(var BR: TBitReader; const Tree: THuffmanTree): Integer;
var
  Code: Integer;
  Len: Integer;
  Count: Integer;
begin
  Code := 0;
  for Len := 1 to MAX_BITS do
  begin
    Code := (Code shl 1) or BR.ReadBits(1);
    Count := Tree.Counts[Len];
    if Code < Count then
    begin
      Result := Tree.Symbols[Tree.Offsets[Len] + Code];
      Exit;
    end;
    Code := Code - Count;
  end;
  Result := -1; // Decode error
end;

const
  LENS_ORDER: array[0..18] of Integer = (16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15);
  LENGTH_BASE: array[0..28] of Integer = (3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258);
  LENGTH_EXTRA: array[0..28] of Integer = (0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0);
  DIST_BASE: array[0..29] of Integer = (1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577);
  DIST_EXTRA: array[0..29] of Integer = (0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13);

function InflateZlib(const ACompressedData: Pointer; const ACompressedSize: Integer; const AExpectedSize: Integer): TBytes;
var
  BR: TBitReader;
  CMF, FLG: Byte;
  IsFinal: Integer;
  BType: Integer;
  Len, NLen, I: Integer;
  HLit, HDist, HCLen: Integer;
  CodeLengths: array[0..18] of Integer;
  TreeCL: THuffmanTree;
  TreeLit, TreeDist: THuffmanTree;
  AllLengths: array of Integer;
  Sym, RepCount, PrevVal: Integer;
  FixedLitLengths: array[0..287] of Integer;
  FixedDistLengths: array[0..31] of Integer;
  MatchLen, MatchDist: Integer;
  OutPos: Integer;
  CopySrc: Integer;
  PComp: PByte;
begin
  SetLength(Result, AExpectedSize);
  OutPos := 0;

  PComp := PByte(ACompressedData);
  if ACompressedSize < 6 then Exit;

  // Zlib header check
  CMF := PComp[0];
  FLG := PComp[1];
  if ((Integer(CMF) * 256 + FLG) mod 31) <> 0 then
    raise Exception.Create('Invalid Zlib header checksum');

  // Skip 2 header bytes
  InitBitReader(BR, PComp + 2, ACompressedSize - 2);

  repeat
    IsFinal := BR.ReadBits(1);
    BType := BR.ReadBits(2);

    case BType of
      0:
      begin
        // Stored / uncompressed block
        BR.AlignToByte();
        Len := BR.ReadBits(16);
        NLen := BR.ReadBits(16);
        if (Len and $FFFF) <> ((not NLen) and $FFFF) then
          raise Exception.Create('Deflate uncompressed block length mismatch');

        for I := 0 to Len - 1 do
        begin
          if OutPos >= Length(Result) then SetLength(Result, OutPos + 4096);
          Result[OutPos] := Byte(BR.ReadBits(8));
          Inc(OutPos);
        end;
      end;

      1, 2:
      begin
        // Huffman block
        if BType = 1 then
        begin
          // Fixed Huffman
          for I := 0 to 143 do FixedLitLengths[I] := 8;
          for I := 144 to 255 do FixedLitLengths[I] := 9;
          for I := 256 to 279 do FixedLitLengths[I] := 7;
          for I := 280 to 287 do FixedLitLengths[I] := 8;
          for I := 0 to 31 do FixedDistLengths[I] := 5;

          BuildHuffman(TreeLit, FixedLitLengths, 288);
          BuildHuffman(TreeDist, FixedDistLengths, 32);
        end
        else
        begin
          // Dynamic Huffman
          HLit := BR.ReadBits(5) + 257;
          HDist := BR.ReadBits(5) + 1;
          HCLen := BR.ReadBits(4) + 4;

          FillChar(CodeLengths, SizeOf(CodeLengths), 0);
          for I := 0 to HCLen - 1 do
            CodeLengths[LENS_ORDER[I]] := BR.ReadBits(3);

          BuildHuffman(TreeCL, CodeLengths, 19);

          SetLength(AllLengths, HLit + HDist);
          I := 0;
          while I < HLit + HDist do
          begin
            Sym := DecodeHuffman(BR, TreeCL);
            if Sym < 16 then
            begin
              AllLengths[I] := Sym;
              Inc(I);
            end
            else if Sym = 16 then
            begin
              RepCount := BR.ReadBits(2) + 3;
              if I = 0 then PrevVal := 0 else PrevVal := AllLengths[I - 1];
              while (RepCount > 0) and (I < HLit + HDist) do
              begin
                AllLengths[I] := PrevVal;
                Inc(I);
                Dec(RepCount);
              end;
            end
            else if Sym = 17 then
            begin
              RepCount := BR.ReadBits(3) + 3;
              while (RepCount > 0) and (I < HLit + HDist) do
              begin
                AllLengths[I] := 0;
                Inc(I);
                Dec(RepCount);
              end;
            end
            else if Sym = 18 then
            begin
              RepCount := BR.ReadBits(7) + 11;
              while (RepCount > 0) and (I < HLit + HDist) do
              begin
                AllLengths[I] := 0;
                Inc(I);
                Dec(RepCount);
              end;
            end;
          end;

          BuildHuffman(TreeLit, Slice(AllLengths, HLit), HLit);
          BuildHuffman(TreeDist, Copy(AllLengths, HLit, HDist), HDist);
        end;

        // Decode symbols
        while True do
        begin
          Sym := DecodeHuffman(BR, TreeLit);
          if Sym < 256 then
          begin
            if OutPos >= Length(Result) then SetLength(Result, OutPos + 4096);
            Result[OutPos] := Byte(Sym);
            Inc(OutPos);
          end
          else if Sym = 256 then
            Break // End of block
          else
          begin
            // Match length
            Dec(Sym, 257);
            MatchLen := LENGTH_BASE[Sym] + BR.ReadBits(LENGTH_EXTRA[Sym]);

            // Match distance
            Sym := DecodeHuffman(BR, TreeDist);
            MatchDist := DIST_BASE[Sym] + BR.ReadBits(DIST_EXTRA[Sym]);

            while OutPos + MatchLen > Length(Result) do
              SetLength(Result, Length(Result) * 2 + MatchLen);

            CopySrc := OutPos - MatchDist;
            for I := 0 to MatchLen - 1 do
            begin
              Result[OutPos] := Result[CopySrc + I];
              Inc(OutPos);
            end;
          end;
        end;
      end;
    else
      raise Exception.Create('Reserved Deflate block type');
    end;
  until IsFinal <> 0;

  SetLength(Result, OutPos);
end;

// ============================================================================
// Paeth Predictor & Scanline Unfiltering
// ============================================================================

function PaethPredictor(const A, B, C: Integer): Byte;
var
  P, PA, PB, PC: Integer;
begin
  P := A + B - C;
  PA := Abs(P - A);
  PB := Abs(P - B);
  PC := Abs(P - C);
  if (PA <= PB) and (PA <= PC) then
    Result := Byte(A)
  else if PB <= PC then
    Result := Byte(B)
  else
    Result := Byte(C);
end;

// ============================================================================
// TFloriaPNGReader
// ============================================================================

class function TFloriaPNGReader.CanRead(AStream: TStream): Boolean;
var
  Sig: array[0..7] of Byte;
  OldPos: Int64;
begin
  Result := False;
  if not Assigned(AStream) or (AStream.Size - AStream.Position < 8) then Exit;

  OldPos := AStream.Position;
  try
    if AStream.Read(Sig, 8) = 8 then
      Result := CompareMem(@Sig[0], @PNG_SIGNATURE[0], 8);
  finally
    AStream.Position := OldPos;
  end;
end;

class function TFloriaPNGReader.Format(): TFloriaImageFormat;
begin
  Result := fifPNG;
end;

procedure TFloriaPNGReader.ReadImage(AStream: TStream; AImage: TFloriaImage);
var
  Sig: array[0..7] of Byte;
  ChunkLen: Cardinal;
  ChunkType: array[0..3] of AnsiChar;
  ChunkCRC: Cardinal;
  W, H: Integer;
  BitDepth, ColorType, CompMethod, FilterMethod, Interlace: Byte;
  IDATStream: TMemoryStream;
  Palette: array of TRgbaPixel;
  HasPalette: Boolean;
  Uncompressed: TBytes;
  Bpp: Integer;
  RowBytes: Integer;
  PriorRow, CurrentRow: array of Byte;
  FilterType: Byte;
  Row, X, SrcIdx: Integer;
  A, B, C: Byte;
  DstPixel: PBgraPixel;
  PalIdx: Byte;
begin
  if AStream.Read(Sig, 8) <> 8 then
    raise Exception.Create('Premature end of PNG signature');

  if not CompareMem(@Sig[0], @PNG_SIGNATURE[0], 8) then
    raise Exception.Create('Invalid PNG signature');

  W := 0; H := 0;
  BitDepth := 8; ColorType := 6; CompMethod := 0; FilterMethod := 0; Interlace := 0;
  HasPalette := False;
  IDATStream := TMemoryStream.Create();

  try
    while AStream.Position < AStream.Size do
    begin
      if AStream.Read(ChunkLen, 4) <> 4 then Break;
      ChunkLen := BEtoN(ChunkLen);

      if AStream.Read(ChunkType, 4) <> 4 then Break;

      if ChunkType = 'IHDR' then
      begin
        AStream.ReadBuffer(W, 4); W := BEtoN(Cardinal(W));
        AStream.ReadBuffer(H, 4); H := BEtoN(Cardinal(H));
        AStream.ReadBuffer(BitDepth, 1);
        AStream.ReadBuffer(ColorType, 1);
        AStream.ReadBuffer(CompMethod, 1);
        AStream.ReadBuffer(FilterMethod, 1);
        AStream.ReadBuffer(Interlace, 1);
      end
      else if ChunkType = 'PLTE' then
      begin
        SetLength(Palette, ChunkLen div 3);
        HasPalette := True;
        for X := 0 to High(Palette) do
        begin
          AStream.ReadBuffer(Palette[X].R, 1);
          AStream.ReadBuffer(Palette[X].G, 1);
          AStream.ReadBuffer(Palette[X].B, 1);
          Palette[X].A := 255;
        end;
      end
      else if ChunkType = 'IDAT' then
      begin
        IDATStream.CopyFrom(AStream, ChunkLen);
      end
      else if ChunkType = 'IEND' then
      begin
        AStream.ReadBuffer(ChunkCRC, 4);
        Break;
      end
      else
      begin
        // Skip chunk data
        AStream.Seek(ChunkLen, soFromCurrent);
      end;

      AStream.ReadBuffer(ChunkCRC, 4);
    end;

    if (W <= 0) or (H <= 0) then
    begin
      AImage.Allocate(0, 0);
      Exit;
    end;

    // Bytes per pixel in raw scanlines
    case ColorType of
      0: Bpp := 1; // Gray
      2: Bpp := 3; // RGB
      3: Bpp := 1; // Palette
      4: Bpp := 2; // Gray + Alpha
      6: Bpp := 4; // RGBA
    else
      Bpp := 4;
    end;

    RowBytes := W * Bpp;
    Uncompressed := InflateZlib(IDATStream.Memory, IDATStream.Size, H * (RowBytes + 1));

    AImage.Allocate(W, H, fpfBGRA32);
    SetLength(PriorRow, RowBytes);
    SetLength(CurrentRow, RowBytes);
    FillChar(PriorRow[0], RowBytes, 0);

    SrcIdx := 0;
    for Row := 0 to H - 1 do
    begin
      if SrcIdx >= Length(Uncompressed) then Break;
      FilterType := Uncompressed[SrcIdx];
      Inc(SrcIdx);

      // Unfilter current row
      for X := 0 to RowBytes - 1 do
      begin
        if X >= Bpp then A := CurrentRow[X - Bpp] else A := 0;
        B := PriorRow[X];
        if X >= Bpp then C := PriorRow[X - Bpp] else C := 0;

        case FilterType of
          0: CurrentRow[X] := Uncompressed[SrcIdx]; // None
          1: CurrentRow[X] := Byte(Uncompressed[SrcIdx] + A); // Sub
          2: CurrentRow[X] := Byte(Uncompressed[SrcIdx] + B); // Up
          3: CurrentRow[X] := Byte(Uncompressed[SrcIdx] + ((A + B) div 2)); // Average
          4: CurrentRow[X] := Byte(Uncompressed[SrcIdx] + PaethPredictor(A, B, C)); // Paeth
        else
          CurrentRow[X] := Uncompressed[SrcIdx];
        end;
        Inc(SrcIdx);
      end;

      // Copy uncompressed pixels to image scanline as 32-bit BGRA
      DstPixel := PBgraPixel(AImage.Scanline[Row]);
      for X := 0 to W - 1 do
      begin
        case ColorType of
          6: // RGBA
          begin
            DstPixel^.R := CurrentRow[X * 4 + 0];
            DstPixel^.G := CurrentRow[X * 4 + 1];
            DstPixel^.B := CurrentRow[X * 4 + 2];
            DstPixel^.A := CurrentRow[X * 4 + 3];
          end;
          2: // RGB
          begin
            DstPixel^.R := CurrentRow[X * 3 + 0];
            DstPixel^.G := CurrentRow[X * 3 + 1];
            DstPixel^.B := CurrentRow[X * 3 + 2];
            DstPixel^.A := 255;
          end;
          3: // Palette
          begin
            PalIdx := CurrentRow[X];
            if HasPalette and (PalIdx <= High(Palette)) then
            begin
              DstPixel^.R := Palette[PalIdx].R;
              DstPixel^.G := Palette[PalIdx].G;
              DstPixel^.B := Palette[PalIdx].B;
            end
            else
            begin
              DstPixel^.R := PalIdx;
              DstPixel^.G := PalIdx;
              DstPixel^.B := PalIdx;
            end;
            DstPixel^.A := 255;
          end;
          0: // Grayscale
          begin
            DstPixel^.R := CurrentRow[X];
            DstPixel^.G := CurrentRow[X];
            DstPixel^.B := CurrentRow[X];
            DstPixel^.A := 255;
          end;
          4: // Grayscale + Alpha
          begin
            DstPixel^.R := CurrentRow[X * 2 + 0];
            DstPixel^.G := CurrentRow[X * 2 + 0];
            DstPixel^.B := CurrentRow[X * 2 + 0];
            DstPixel^.A := CurrentRow[X * 2 + 1];
          end;
        end;
        Inc(DstPixel);
      end;

      Move(CurrentRow[0], PriorRow[0], RowBytes);
    end;
  finally
    IDATStream.Free();
  end;
end;

// ============================================================================
// TFloriaPNGWriter
// ============================================================================

class function TFloriaPNGWriter.Format(): TFloriaImageFormat;
begin
  Result := fifPNG;
end;

procedure WriteChunk(AStream: TStream; const AType: AnsiString; const AData: Pointer; const ALength: Cardinal);
var
  LenBE, CRCVal: Cardinal;
  TypeBytes: array[0..3] of Byte;
begin
  LenBE := NtoBE(ALength);
  AStream.WriteBuffer(LenBE, 4);

  TypeBytes[0] := Ord(AType[1]);
  TypeBytes[1] := Ord(AType[2]);
  TypeBytes[2] := Ord(AType[3]);
  TypeBytes[3] := Ord(AType[4]);
  AStream.WriteBuffer(TypeBytes[0], 4);

  CRCVal := UpdateCRC(0, @TypeBytes[0], 4);

  if ALength > 0 then
  begin
    AStream.WriteBuffer(AData^, ALength);
    CRCVal := UpdateCRC(CRCVal, AData, ALength);
  end;

  CRCVal := NtoBE(CRCVal);
  AStream.WriteBuffer(CRCVal, 4);
end;

procedure TFloriaPNGWriter.WriteImage(AStream: TStream; AImage: TFloriaImage);
var
  W, H: Integer;
  IHDRData: array[0..12] of Byte;
  RawScanlines: TMemoryStream;
  FilterByte: Byte;
  Y, X: Integer;
  SrcPixel: PBgraPixel;
  PixelRGBA: array[0..3] of Byte;
  IDATStream: TMemoryStream;
  Adler: Cardinal;
  Remaining, ChunkBlockSize: Integer;
  BFinal: Byte;
  BlockLenWord, BlockNLenWord: Word;
  RawPtr: PByte;
  AdlerBE: Cardinal;
begin
  if (AImage = nil) or (AImage.Width <= 0) or (AImage.Height <= 0) then Exit;

  W := AImage.Width;
  H := AImage.Height;

  // 1. Write PNG Signature
  AStream.WriteBuffer(PNG_SIGNATURE[0], 8);

  // 2. Write IHDR Chunk
  PInteger(@IHDRData[0])^ := NtoBE(Cardinal(W));
  PInteger(@IHDRData[4])^ := NtoBE(Cardinal(H));
  IHDRData[8] := 8;  // 8-bit depth
  IHDRData[9] := 6;  // ColorType 6 (RGBA)
  IHDRData[10] := 0; // Compression (Deflate)
  IHDRData[11] := 0; // Filter method
  IHDRData[12] := 0; // Interlace (None)
  WriteChunk(AStream, 'IHDR', @IHDRData[0], 13);

  // 3. Prepare Raw Filtered Scanlines
  RawScanlines := TMemoryStream.Create();
  try
    FilterByte := 0; // Filter 0: None
    for Y := 0 to H - 1 do
    begin
      RawScanlines.WriteBuffer(FilterByte, 1);
      SrcPixel := PBgraPixel(AImage.Scanline[Y]);
      for X := 0 to W - 1 do
      begin
        PixelRGBA[0] := SrcPixel^.R;
        PixelRGBA[1] := SrcPixel^.G;
        PixelRGBA[2] := SrcPixel^.B;
        PixelRGBA[3] := SrcPixel^.A;
        RawScanlines.WriteBuffer(PixelRGBA[0], 4);
        Inc(SrcPixel);
      end;
    end;

    // 4. Wrap with Zlib Header & Uncompressed Deflate Blocks
    IDATStream := TMemoryStream.Create();
    try
      // Zlib header: CMF=$78 (Deflate, 32K window), FLG=$01 (No preset dict, check valid)
      FilterByte := $78; IDATStream.WriteBuffer(FilterByte, 1);
      FilterByte := $01; IDATStream.WriteBuffer(FilterByte, 1);

      Adler := ComputeAdler32(RawScanlines.Memory, RawScanlines.Size);

      Remaining := RawScanlines.Size;
      RawPtr := PByte(RawScanlines.Memory);

      while Remaining > 0 do
      begin
        ChunkBlockSize := Remaining;
        if ChunkBlockSize > 65535 then ChunkBlockSize := 65535;

        if Remaining = ChunkBlockSize then BFinal := 1 else BFinal := 0;
        IDATStream.WriteBuffer(BFinal, 1); // BTYPE 00: uncompressed stored block

        BlockLenWord := Word(ChunkBlockSize);
        BlockNLenWord := not BlockLenWord;
        IDATStream.WriteBuffer(BlockLenWord, 2);
        IDATStream.WriteBuffer(BlockNLenWord, 2);

        IDATStream.WriteBuffer(RawPtr^, ChunkBlockSize);
        Inc(RawPtr, ChunkBlockSize);
        Dec(Remaining, ChunkBlockSize);
      end;

      // Zlib Adler32 checksum (Big-Endian)
      AdlerBE := NtoBE(Adler);
      IDATStream.WriteBuffer(AdlerBE, 4);

      // Write IDAT Chunk
      WriteChunk(AStream, 'IDAT', IDATStream.Memory, IDATStream.Size);
    finally
      IDATStream.Free();
    end;
  finally
    RawScanlines.Free();
  end;

  // 5. Write IEND Chunk
  WriteChunk(AStream, 'IEND', nil, 0);
end;

initialization
  RegisterImageReader(TFloriaPNGReader);
  RegisterImageWriter(fifPNG, TFloriaPNGWriter);

end.
