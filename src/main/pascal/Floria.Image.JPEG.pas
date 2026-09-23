unit Floria.Image.JPEG;

// Floria.Image.JPEG
// =================
// Pure Object Pascal baseline JPEG decoder.
// Zero external dependencies; no libjpeg or FCL-Image required.
//
// Supports:
// - Baseline DCT JPEG decoding (SOF0).
// - Chroma subsampling: 4:4:4, 4:2:2 (H2V1), and 4:2:0 (H2V2).
// - Grayscale (1-component) and YCbCr (3-component) color spaces.
// - Fixed-point 8x8 Inverse Discrete Cosine Transform (IDCT).
// - Automatic byte-stuffing ($FF00) stripping in entropy stream.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  Floria.Image.Core;

type
  // JPEG Reader Codec
  TFloriaJPEGReader = class(TFloriaImageReader)
  public
    class function CanRead(AStream: TStream): Boolean; override;
    class function Format(): TFloriaImageFormat; override;
    procedure ReadImage(AStream: TStream; AImage: TFloriaImage); override;
  end;

implementation

const
  ZIGZAG: array[0..63] of Byte = (
     0,  1,  8, 16,  9,  2,  3, 10,
    17, 24, 32, 25, 18, 11,  4,  5,
    12, 19, 26, 33, 40, 48, 41, 34,
    27, 20, 13,  6,  7, 14, 21, 28,
    35, 42, 49, 56, 57, 50, 43, 36,
    29, 22, 15, 23, 30, 37, 44, 51,
    58, 59, 52, 45, 38, 31, 39, 46,
    53, 60, 61, 54, 47, 55, 62, 63
  );

type
  TQuantTable = array[0..63] of Word;

  TJpegHuffmanTable = record
    Counts  : array[1..16] of Byte;
    Symbols : array[0..255] of Byte;
    Offsets : array[1..17] of Integer;
  end;

  TJpegComponent = record
    Id       : Byte;
    HFactor  : Byte;
    VFactor  : Byte;
    QuantId  : Byte;
    DcTableId: Byte;
    AcTableId: Byte;
    DcPred   : Integer;
  end;

  TJpegBitStream = record
    Data     : PByte;
    Size     : Integer;
    BytePos  : Integer;
    BitBuf   : Cardinal;
    BitsInBuf: Integer;
  end;

procedure InitJpegBitStream(var BS: TJpegBitStream; const AData: Pointer; const ASize: Integer);
begin
  BS.Data := PByte(AData);
  BS.Size := ASize;
  BS.BytePos := 0;
  BS.BitBuf := 0;
  BS.BitsInBuf := 0;
end;

function ReadJpegBit(var BS: TJpegBitStream): Integer;
var
  B: Byte;
begin
  if BS.BitsInBuf = 0 then
  begin
    if BS.BytePos < BS.Size then
    begin
      B := BS.Data[BS.BytePos];
      Inc(BS.BytePos);
      if B = $FF then
      begin
        if (BS.BytePos < BS.Size) and (BS.Data[BS.BytePos] = $00) then
          Inc(BS.BytePos); // Skip stuffed zero byte
      end;
      BS.BitBuf := B;
      BS.BitsInBuf := 8;
    end
    else
    begin
      BS.BitBuf := 0;
      BS.BitsInBuf := 8;
    end;
  end;

  Result := (BS.BitBuf shr 7) and 1;
  BS.BitBuf := (BS.BitBuf shl 1) and $FF;
  Dec(BS.BitsInBuf);
end;

function ReadJpegBits(var BS: TJpegBitStream; const ACount: Integer): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to ACount - 1 do
    Result := (Result shl 1) or ReadJpegBit(BS);
end;

function DecodeJpegHuffmanSymbol(var BS: TJpegBitStream; const Table: TJpegHuffmanTable): Integer;
var
  Code: Integer;
  Len: Integer;
  Count: Integer;
begin
  Code := 0;
  for Len := 1 to 16 do
  begin
    Code := (Code shl 1) or ReadJpegBit(BS);
    Count := Table.Counts[Len];
    if Code < Count then
    begin
      Result := Table.Symbols[Table.Offsets[Len] + Code];
      Exit;
    end;
    Code := Code - Count;
  end;
  Result := 0;
end;

function ExtendJpegSign(const Val, Bits: Integer): Integer;
begin
  if Val < (1 shl (Bits - 1)) then
    Result := Val + (-1 shl Bits) + 1
  else
    Result := Val;
end;

// ============================================================================
// Fast 8x8 Inverse Discrete Cosine Transform (IDCT)
// ============================================================================

procedure InverseDCT8x8(var Block: array of Integer);
var
  I: Integer;
  X0, X1, X2, X3, X4, X5, X6, X7, X8: Integer;
  Row: array[0..63] of Integer;
  P: Integer;
begin
  // Horizontal IDCT
  for I := 0 to 7 do
  begin
    P := I * 8;
    if (Block[P+1] = 0) and (Block[P+2] = 0) and (Block[P+3] = 0) and
       (Block[P+4] = 0) and (Block[P+5] = 0) and (Block[P+6] = 0) and (Block[P+7] = 0) then
    begin
      X0 := Block[P] shl 3;
      Row[P+0] := X0; Row[P+1] := X0; Row[P+2] := X0; Row[P+3] := X0;
      Row[P+4] := X0; Row[P+5] := X0; Row[P+6] := X0; Row[P+7] := X0;
      Continue;
    end;

    X0 := (Block[P+0] shl 11) + 128;
    X1 := Block[P+4] shl 11;
    X2 := Block[P+6];
    X3 := Block[P+2];
    X4 := Block[P+1];
    X5 := Block[P+7];
    X6 := Block[P+5];
    X7 := Block[P+3];

    X8 := X7 + X5;
    X7 := X7 - X5;
    X5 := X4 + X6;
    X4 := X4 - X6;

    X6 := (X8 + X5) * 4433;
    X5 := X6 + X5 * 6270;
    X8 := X6 - X8 * 15137;

    X6 := X4 * 9633 + X7 * 2446;
    X4 := X4 * 2446 - X7 * 9633;

    X7 := X0 + X1;
    X0 := X0 - X1;
    X1 := (X3 + X2) * 4433;
    X2 := X1 - X2 * 15137;
    X3 := X1 + X3 * 6270;

    X1 := X7 + X3;
    X7 := X7 - X3;
    X3 := X0 + X2;
    X0 := X0 - X2;

    Row[P+0] := (X1 + X5) shr 8;
    Row[P+7] := (X1 - X5) shr 8;
    Row[P+1] := (X3 + X4) shr 8;
    Row[P+6] := (X3 - X4) shr 8;
    Row[P+2] := (X0 + X6) shr 8;
    Row[P+5] := (X0 - X6) shr 8;
    Row[P+3] := (X7 + X8) shr 8;
    Row[P+4] := (X7 - X8) shr 8;
  end;

  // Vertical IDCT
  for I := 0 to 7 do
  begin
    X0 := (Row[I] shl 8) + 8192;
    X1 := Row[I+32] shl 8;
    X2 := Row[I+48];
    X3 := Row[I+16];
    X4 := Row[I+8];
    X5 := Row[I+56];
    X6 := Row[I+40];
    X7 := Row[I+24];

    X8 := X7 + X5;
    X7 := X7 - X5;
    X5 := X4 + X6;
    X4 := X4 - X6;

    X6 := (X8 + X5) * 4433;
    X5 := X6 + X5 * 6270;
    X8 := X6 - X8 * 15137;

    X6 := X4 * 9633 + X7 * 2446;
    X4 := X4 * 2446 - X7 * 9633;

    X7 := X0 + X1;
    X0 := X0 - X1;
    X1 := (X3 + X2) * 4433;
    X2 := X1 - X2 * 15137;
    X3 := X1 + X3 * 6270;

    X1 := X7 + X3;
    X7 := X7 - X3;
    X3 := X0 + X2;
    X0 := X0 - X2;

    Block[I+0]  := (X1 + X5) shr 14;
    Block[I+56] := (X1 - X5) shr 14;
    Block[I+8]  := (X3 + X4) shr 14;
    Block[I+48] := (X3 - X4) shr 14;
    Block[I+16] := (X0 + X6) shr 14;
    Block[I+40] := (X0 - X6) shr 14;
    Block[I+24] := (X7 + X8) shr 14;
    Block[I+32] := (X7 - X8) shr 14;
  end;
end;

function ClampByte(const V: Integer): Byte; inline;
begin
  if V < 0 then Result := 0
  else if V > 255 then Result := 255
  else Result := Byte(V);
end;

// ============================================================================
// TFloriaJPEGReader
// ============================================================================

class function TFloriaJPEGReader.CanRead(AStream: TStream): Boolean;
var
  Magic: array[0..2] of Byte;
  OldPos: Int64;
begin
  Result := False;
  if not Assigned(AStream) or (AStream.Size - AStream.Position < 3) then Exit;

  OldPos := AStream.Position;
  try
    if AStream.Read(Magic, 3) = 3 then
      Result := (Magic[0] = $FF) and (Magic[1] = $D8) and (Magic[2] = $FF);
  finally
    AStream.Position := OldPos;
  end;
end;

class function TFloriaJPEGReader.Format(): TFloriaImageFormat;
begin
  Result := fifJPEG;
end;

procedure TFloriaJPEGReader.ReadImage(AStream: TStream; AImage: TFloriaImage);
var
  Marker: Word;
  Len: Word;
  W, H: Integer;
  NumComponents: Integer;
  Components: array[0..3] of TJpegComponent;
  QuantTables: array[0..3] of TQuantTable;
  DCHuffman: array[0..3] of TJpegHuffmanTable;
  ACHuffman: array[0..3] of TJpegHuffmanTable;
  TableId, TableClass: Byte;
  Counts: array[1..16] of Byte;
  TotalSyms, I, K: Integer;
  CompId: Byte;
  ScanData: TMemoryStream;
  BS: TJpegBitStream;
  MaxH, MaxV: Integer;
  McuW, McuH: Integer;
  McusX, McusY: Integer;
  McuX, McuY: Integer;
  CompIdx: Integer;
  BlockIdx: Integer;
  BlocksPerMCU: array[0..3] of Integer;
  Blocks: array[0..3, 0..3, 0..63] of Integer;
  RawBlock: array[0..63] of Integer;
  Sym, Bits, CoeffIdx: Integer;
  R, G, B: Integer;
  YVal, CbVal, CrVal: Integer;
  PixX, PixY: Integer;
  SubX, SubY: Integer;
  BlockX, BlockY: Integer;
  DstPixel: PBgraPixel;
  TempByte: Byte;
begin
  W := 0; H := 0; NumComponents := 0;
  MaxH := 1; MaxV := 1;
  FillChar(QuantTables, SizeOf(QuantTables), 0);
  FillChar(DCHuffman, SizeOf(DCHuffman), 0);
  FillChar(ACHuffman, SizeOf(ACHuffman), 0);
  FillChar(Components, SizeOf(Components), 0);

  // Check SOI
  if AStream.Read(Marker, 2) <> 2 then Exit;
  if BEtoN(Marker) <> $FFD8 then
    raise Exception.Create('Invalid JPEG: missing SOI marker');

  ScanData := TMemoryStream.Create();
  try
    while AStream.Position < AStream.Size do
    begin
      if AStream.Read(Marker, 2) <> 2 then Break;
      Marker := BEtoN(Marker);

      if (Marker and $FF00) <> $FF00 then Break;

      // SOF0: Baseline DCT
      if Marker = $FFC0 then
      begin
        AStream.ReadBuffer(Len, 2); Len := BEtoN(Len);
        AStream.Seek(1, soFromCurrent); // Sample precision (8)
        AStream.ReadBuffer(H, 2); H := BEtoN(Cardinal(H));
        AStream.ReadBuffer(W, 2); W := BEtoN(Cardinal(W));
        AStream.ReadBuffer(NumComponents, 1);

        for I := 0 to NumComponents - 1 do
        begin
          AStream.ReadBuffer(Components[I].Id, 1);
          AStream.ReadBuffer(TempByte, 1);
          Components[I].HFactor := (TempByte shr 4) and $0F;
          Components[I].VFactor := TempByte and $0F;
          if Components[I].HFactor > MaxH then MaxH := Components[I].HFactor;
          if Components[I].VFactor > MaxV then MaxV := Components[I].VFactor;
          AStream.ReadBuffer(Components[I].QuantId, 1);
          Components[I].DcPred := 0;
        end;
      end
      // DQT: Define Quantization Tables
      else if Marker = $FFDB then
      begin
        AStream.ReadBuffer(Len, 2); Len := BEtoN(Len);
        Dec(Len, 2);
        while Len > 0 do
        begin
          AStream.ReadBuffer(TableId, 1);
          Dec(Len);
          TableId := TableId and $0F;
          for K := 0 to 63 do
          begin
            AStream.ReadBuffer(TempByte, 1);
            QuantTables[TableId][ZIGZAG[K]] := TempByte;
            Dec(Len);
          end;
        end;
      end
      // DHT: Define Huffman Tables
      else if Marker = $FFC4 then
      begin
        AStream.ReadBuffer(Len, 2); Len := BEtoN(Len);
        Dec(Len, 2);
        while Len > 0 do
        begin
          AStream.ReadBuffer(TempByte, 1); Dec(Len);
          TableClass := (TempByte shr 4) and $0F;
          TableId := TempByte and $0F;
          TotalSyms := 0;
          for K := 1 to 16 do
          begin
            AStream.ReadBuffer(Counts[K], 1); Dec(Len);
            Inc(TotalSyms, Counts[K]);
          end;

          if TableClass = 0 then
          begin
            DCHuffman[TableId].Counts := Counts;
            DCHuffman[TableId].Offsets[1] := 0;
            for K := 1 to 16 do
              DCHuffman[TableId].Offsets[K + 1] := DCHuffman[TableId].Offsets[K] + Counts[K];
            for K := 0 to TotalSyms - 1 do
            begin
              AStream.ReadBuffer(DCHuffman[TableId].Symbols[K], 1); Dec(Len);
            end;
          end
          else
          begin
            ACHuffman[TableId].Counts := Counts;
            ACHuffman[TableId].Offsets[1] := 0;
            for K := 1 to 16 do
              ACHuffman[TableId].Offsets[K + 1] := ACHuffman[TableId].Offsets[K] + Counts[K];
            for K := 0 to TotalSyms - 1 do
            begin
              AStream.ReadBuffer(ACHuffman[TableId].Symbols[K], 1); Dec(Len);
            end;
          end;
        end;
      end
      // SOS: Start of Scan
      else if Marker = $FFDA then
      begin
        AStream.ReadBuffer(Len, 2); Len := BEtoN(Len);
        AStream.ReadBuffer(TempByte, 1); // Component count in scan
        for I := 0 to TempByte - 1 do
        begin
          AStream.ReadBuffer(CompId, 1);
          AStream.ReadBuffer(TableId, 1);
          for K := 0 to NumComponents - 1 do
          begin
            if Components[K].Id = CompId then
            begin
              Components[K].DcTableId := (TableId shr 4) and $0F;
              Components[K].AcTableId := TableId and $0F;
            end;
          end;
        end;
        AStream.Seek(3, soFromCurrent); // Spectral selection & approximation

        // Copy remaining stream as entropy scan data until EOI ($FFD9)
        ScanData.CopyFrom(AStream, AStream.Size - AStream.Position);
        Break;
      end
      else if Marker = $FFD9 then // EOI
        Break
      else
      begin
        // Skip unhandled metadata markers
        if AStream.Read(Len, 2) = 2 then
        begin
          Len := BEtoN(Len);
          if Len >= 2 then AStream.Seek(Len - 2, soFromCurrent);
        end;
      end;
    end;

    if (W <= 0) or (H <= 0) or (NumComponents = 0) then
    begin
      AImage.Allocate(0, 0);
      Exit;
    end;

    AImage.Allocate(W, H, fpfBGRA32);

    McuW := MaxH * 8;
    McuH := MaxV * 8;
    McusX := (W + McuW - 1) div McuW;
    McusY := (H + McuH - 1) div McuH;

    for I := 0 to NumComponents - 1 do
      BlocksPerMCU[I] := Components[I].HFactor * Components[I].VFactor;

    InitJpegBitStream(BS, ScanData.Memory, ScanData.Size);

    // Decode MCUs
    for McuY := 0 to McusY - 1 do
    begin
      for McuX := 0 to McusX - 1 do
      begin
        for CompIdx := 0 to NumComponents - 1 do
        begin
          for BlockIdx := 0 to BlocksPerMCU[CompIdx] - 1 do
          begin
            FillChar(RawBlock, SizeOf(RawBlock), 0);

            // DC coefficient
            Sym := DecodeJpegHuffmanSymbol(BS, DCHuffman[Components[CompIdx].DcTableId]);
            if Sym > 0 then
            begin
              Bits := ReadJpegBits(BS, Sym);
              Inc(Components[CompIdx].DcPred, ExtendJpegSign(Bits, Sym));
            end;
            RawBlock[0] := Components[CompIdx].DcPred * QuantTables[Components[CompIdx].QuantId][0];

            // AC coefficients
            CoeffIdx := 1;
            while CoeffIdx < 64 do
            begin
              Sym := DecodeJpegHuffmanSymbol(BS, ACHuffman[Components[CompIdx].AcTableId]);
              if Sym = 0 then Break; // EOB (End of Block)
              if Sym = $F0 then
              begin
                Inc(CoeffIdx, 16); // ZRL (16 zeros)
                Continue;
              end;

              Inc(CoeffIdx, (Sym shr 4) and $0F); // Run of zeros
              Bits := ReadJpegBits(BS, Sym and $0F);
              if CoeffIdx < 64 then
              begin
                RawBlock[ZIGZAG[CoeffIdx]] := ExtendJpegSign(Bits, Sym and $0F) * QuantTables[Components[CompIdx].QuantId][CoeffIdx];
                Inc(CoeffIdx);
              end;
            end;

            InverseDCT8x8(RawBlock);
            for K := 0 to 63 do
              Blocks[CompIdx, BlockIdx, K] := RawBlock[K];
          end;
        end;

        // Render decoded MCU to image pixels
        for SubY := 0 to McuH - 1 do
        begin
          PixY := McuY * McuH + SubY;
          if PixY >= H then Continue;

          for SubX := 0 to McuW - 1 do
          begin
            PixX := McuX * McuW + SubX;
            if PixX >= W then Continue;

            if NumComponents = 1 then
            begin
              // Grayscale
              BlockIdx := (SubY div 8) * Components[0].HFactor + (SubX div 8);
              YVal := Blocks[0, BlockIdx, (SubY mod 8) * 8 + (SubX mod 8)] + 128;
              R := ClampByte(YVal);
              G := R; B := R;
            end
            else
            begin
              // YCbCr -> RGB
              // Luminance Y
              BlockX := SubX div 8;
              BlockY := SubY div 8;
              BlockIdx := BlockY * Components[0].HFactor + BlockX;
              YVal := Blocks[0, BlockIdx, (SubY mod 8) * 8 + (SubX mod 8)] + 128;

              // Chrominance Cb, Cr with subsampling
              BlockX := (SubX * Components[1].HFactor) div McuW;
              BlockY := (SubY * Components[1].VFactor) div McuH;
              BlockIdx := BlockY * Components[1].HFactor + BlockX;
              CbVal := Blocks[1, BlockIdx, (((SubY * Components[1].VFactor * 8) div McuH) mod 8) * 8 +
                                          (((SubX * Components[1].HFactor * 8) div McuW) mod 8)];

              CrVal := Blocks[2, BlockIdx, (((SubY * Components[2].VFactor * 8) div McuH) mod 8) * 8 +
                                          (((SubX * Components[2].HFactor * 8) div McuW) mod 8)];

              R := ClampByte(YVal + (359 * CrVal) shr 8);
              G := ClampByte(YVal - (88 * CbVal + 183 * CrVal) shr 8);
              B := ClampByte(YVal + (454 * CbVal) shr 8);
            end;

            DstPixel := PBgraPixel(PByte(AImage.Scanline[PixY]) + PixX * 4);
            DstPixel^.B := B;
            DstPixel^.G := G;
            DstPixel^.R := R;
            DstPixel^.A := 255;
          end;
        end;
      end;
    end;
  finally
    ScanData.Free();
  end;
end;

initialization
  RegisterImageReader(TFloriaJPEGReader);

end.
