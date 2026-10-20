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
// - Fixed-point 8x8 Inverse Discrete Cosine Transform (IDCT) via IJG integer standard.
// - ITU-T T.81 compliant canonical Huffman decoding (MinCode/MaxCode/ValPtr).
// - 8-bit and 16-bit Quantization tables.
// - Restart markers (DRI / RST0..RST7).
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

  FIX_0_298631336 = 2446;
  FIX_0_390180644 = 3196;
  FIX_0_541196100 = 4433;
  FIX_0_765366865 = 6270;
  FIX_0_899976223 = 7373;
  FIX_1_175875602 = 9633;
  FIX_1_501321110 = 12299;
  FIX_1_847759065 = 15137;
  FIX_1_961570560 = 16069;
  FIX_2_053119869 = 16819;
  FIX_2_562915447 = 20995;
  FIX_3_072711026 = 25172;

type
  TQuantTable = array[0..63] of Word;

  TJpegHuffmanTable = record
    Counts  : array[1..16] of Byte;
    Symbols : array[0..255] of Byte;
    MinCode : array[1..16] of Integer;
    MaxCode : array[1..16] of Integer;
    ValPtr  : array[1..16] of Integer;
    IsValid : Boolean;
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
    Marker   : Byte;
  end;

procedure InitJpegBitStream(var BS: TJpegBitStream; const AData: Pointer; const ASize: Integer);
begin
  BS.Data := PByte(AData);
  BS.Size := ASize;
  BS.BytePos := 0;
  BS.BitBuf := 0;
  BS.BitsInBuf := 0;
  BS.Marker := 0;
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
        while (BS.BytePos < BS.Size) and (BS.Data[BS.BytePos] = $FF) do
          Inc(BS.BytePos);
        if BS.BytePos < BS.Size then
        begin
          if BS.Data[BS.BytePos] = $00 then
            Inc(BS.BytePos)
          else if (BS.Data[BS.BytePos] >= $D0) and (BS.Data[BS.BytePos] <= $D7) then
          begin
            BS.Marker := BS.Data[BS.BytePos];
            Inc(BS.BytePos);
          end;
        end;
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

procedure BuildHuffmanTable(var Table: TJpegHuffmanTable);
var
  I, J, Code: Integer;
begin
  J := 0;
  Code := 0;
  for I := 1 to 16 do
  begin
    if Table.Counts[I] = 0 then
      Table.MaxCode[I] := -1
    else
    begin
      Table.ValPtr[I] := J;
      Table.MinCode[I] := Code;
      Code := Code + Table.Counts[I] - 1;
      Table.MaxCode[I] := Code;
      Inc(Code);
      Inc(J, Table.Counts[I]);
    end;
    Code := Code shl 1;
  end;
  Table.IsValid := True;
end;

function DecodeJpegHuffmanSymbol(var BS: TJpegBitStream; const Table: TJpegHuffmanTable): Integer;
var
  Code: Integer;
  Len: Integer;
  J: Integer;
begin
  if not Table.IsValid then Exit(0);
  Code := ReadJpegBit(BS);
  Len := 1;
  while (Len <= 16) and (Code > Table.MaxCode[Len]) do
  begin
    Inc(Len);
    Code := (Code shl 1) or ReadJpegBit(BS);
  end;
  if Len <= 16 then
  begin
    J := Table.ValPtr[Len] + Code - Table.MinCode[Len];
    if (J >= 0) and (J <= 255) then
      Exit(Table.Symbols[J]);
  end;
  Result := 0;
end;

function ExtendJpegSign(const Val, Bits: Integer): Integer;
begin
  if Bits <= 0 then Exit(0);
  if Val < (1 shl (Bits - 1)) then
    Result := Val + (-1 shl Bits) + 1
  else
    Result := Val;
end;

// ============================================================================
// Fast 8x8 Inverse Discrete Cosine Transform (IDCT) — IJG Integer Algorithm
// ============================================================================

procedure InverseDCT8x8(var Block: array of Integer);
var
  I, J: Integer;
  Val: Integer;
  Z1, Z2, Z3, Z4, Z5: Integer;
  Tmp0, Tmp1, Tmp2, Tmp3: Integer;
  Tmp10, Tmp11, Tmp12, Tmp13: Integer;
  Ws: array[0..63] of Integer;
  RowStart: Integer;
  AllZero: Boolean;
begin
  // Pass 1: process rows
  for I := 0 to 7 do
  begin
    RowStart := I * 8;
    AllZero := True;
    for J := 1 to 7 do
    begin
      if Block[RowStart + J] <> 0 then
      begin
        AllZero := False;
        Break;
      end;
    end;

    if AllZero then
    begin
      Val := Block[RowStart] shl 2;
      for J := 0 to 7 do
        Ws[RowStart + J] := Val;
      Continue;
    end;

    // Even part
    Z2 := Block[RowStart + 2];
    Z3 := Block[RowStart + 6];
    Z1 := (Z2 + Z3) * FIX_0_541196100;
    Tmp2 := Z1 + Z3 * (-FIX_1_847759065);
    Tmp3 := Z1 + Z2 * FIX_0_765366865;

    Tmp0 := (Block[RowStart + 0] + Block[RowStart + 4]) shl 13;
    Tmp1 := (Block[RowStart + 0] - Block[RowStart + 4]) shl 13;

    Tmp10 := Tmp0 + Tmp3;
    Tmp13 := Tmp0 - Tmp3;
    Tmp11 := Tmp1 + Tmp2;
    Tmp12 := Tmp1 - Tmp2;

    // Odd part
    Tmp0 := Block[RowStart + 7];
    Tmp1 := Block[RowStart + 5];
    Tmp2 := Block[RowStart + 3];
    Tmp3 := Block[RowStart + 1];

    Z1 := Tmp0 + Tmp3;
    Z2 := Tmp1 + Tmp2;
    Z3 := Tmp0 + Tmp2;
    Z4 := Tmp1 + Tmp3;
    Z5 := (Z3 + Z4) * FIX_1_175875602;

    Tmp0 := Tmp0 * FIX_0_298631336;
    Tmp1 := Tmp1 * FIX_2_053119869;
    Tmp2 := Tmp2 * FIX_3_072711026;
    Tmp3 := Tmp3 * FIX_1_501321110;
    Z1 := Z1 * (-FIX_0_899976223);
    Z2 := Z2 * (-FIX_2_562915447);
    Z3 := Z3 * (-FIX_1_961570560);
    Z4 := Z4 * (-FIX_0_390180644);

    Z3 := Z3 + Z5;
    Z4 := Z4 + Z5;

    Tmp0 := Tmp0 + Z1 + Z3;
    Tmp1 := Tmp1 + Z2 + Z4;
    Tmp2 := Tmp2 + Z2 + Z3;
    Tmp3 := Tmp3 + Z1 + Z4;

    Ws[RowStart + 0] := SarLongint(Tmp10 + Tmp3 + 1024, 11);
    Ws[RowStart + 7] := SarLongint(Tmp10 - Tmp3 + 1024, 11);
    Ws[RowStart + 1] := SarLongint(Tmp11 + Tmp2 + 1024, 11);
    Ws[RowStart + 6] := SarLongint(Tmp11 - Tmp2 + 1024, 11);
    Ws[RowStart + 2] := SarLongint(Tmp12 + Tmp1 + 1024, 11);
    Ws[RowStart + 5] := SarLongint(Tmp12 - Tmp1 + 1024, 11);
    Ws[RowStart + 3] := SarLongint(Tmp13 + Tmp0 + 1024, 11);
    Ws[RowStart + 4] := SarLongint(Tmp13 - Tmp0 + 1024, 11);
  end;

  // Pass 2: process columns
  for I := 0 to 7 do
  begin
    AllZero := True;
    for J := 1 to 7 do
    begin
      if Ws[J * 8 + I] <> 0 then
      begin
        AllZero := False;
        Break;
      end;
    end;

    if AllZero then
    begin
      Val := SarLongint(Ws[I] + 16, 5);
      for J := 0 to 7 do
        Block[J * 8 + I] := Val;
      Continue;
    end;

    Z2 := Ws[2 * 8 + I];
    Z3 := Ws[6 * 8 + I];
    Z1 := (Z2 + Z3) * FIX_0_541196100;
    Tmp2 := Z1 + Z3 * (-FIX_1_847759065);
    Tmp3 := Z1 + Z2 * FIX_0_765366865;

    Tmp0 := (Ws[0 * 8 + I] + Ws[4 * 8 + I]) shl 13;
    Tmp1 := (Ws[0 * 8 + I] - Ws[4 * 8 + I]) shl 13;

    Tmp10 := Tmp0 + Tmp3;
    Tmp13 := Tmp0 - Tmp3;
    Tmp11 := Tmp1 + Tmp2;
    Tmp12 := Tmp1 - Tmp2;

    Tmp0 := Ws[7 * 8 + I];
    Tmp1 := Ws[5 * 8 + I];
    Tmp2 := Ws[3 * 8 + I];
    Tmp3 := Ws[1 * 8 + I];

    Z1 := Tmp0 + Tmp3;
    Z2 := Tmp1 + Tmp2;
    Z3 := Tmp0 + Tmp2;
    Z4 := Tmp1 + Tmp3;
    Z5 := (Z3 + Z4) * FIX_1_175875602;

    Tmp0 := Tmp0 * FIX_0_298631336;
    Tmp1 := Tmp1 * FIX_2_053119869;
    Tmp2 := Tmp2 * FIX_3_072711026;
    Tmp3 := Tmp3 * FIX_1_501321110;
    Z1 := Z1 * (-FIX_0_899976223);
    Z2 := Z2 * (-FIX_2_562915447);
    Z3 := Z3 * (-FIX_1_961570560);
    Z4 := Z4 * (-FIX_0_390180644);

    Z3 := Z3 + Z5;
    Z4 := Z4 + Z5;

    Tmp0 := Tmp0 + Z1 + Z3;
    Tmp1 := Tmp1 + Z2 + Z4;
    Tmp2 := Tmp2 + Z2 + Z3;
    Tmp3 := Tmp3 + Z1 + Z4;

    Block[0 * 8 + I] := SarLongint(Tmp10 + Tmp3 + 131072, 18);
    Block[7 * 8 + I] := SarLongint(Tmp10 - Tmp3 + 131072, 18);
    Block[1 * 8 + I] := SarLongint(Tmp11 + Tmp2 + 131072, 18);
    Block[6 * 8 + I] := SarLongint(Tmp11 - Tmp2 + 131072, 18);
    Block[2 * 8 + I] := SarLongint(Tmp12 + Tmp1 + 131072, 18);
    Block[5 * 8 + I] := SarLongint(Tmp12 - Tmp1 + 131072, 18);
    Block[3 * 8 + I] := SarLongint(Tmp13 + Tmp0 + 131072, 18);
    Block[4 * 8 + I] := SarLongint(Tmp13 - Tmp0 + 131072, 18);
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
  TableId, TableClass, TablePrec: Byte;
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
  Blocks: array[0..3, 0..15, 0..63] of Integer;
  RawBlock: array[0..63] of Integer;
  Sym, Bits, CoeffIdx: Integer;
  R, G, B: Integer;
  YVal, CbVal, CrVal: Integer;
  PixX, PixY: Integer;
  SubX, SubY: Integer;
  BlockX, BlockY: Integer;
  DstPixel: PBgraPixel;
  TempByte: Byte;
  TempWord, hWord, wWord: Word;
  RestartInterval, McuCount: Integer;
begin
  W := 0; H := 0; NumComponents := 0;
  MaxH := 1; MaxV := 1;
  RestartInterval := 0;
  McuCount := 0;
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
        AStream.ReadBuffer(hWord, 2); H := BEtoN(hWord);
        AStream.ReadBuffer(wWord, 2); W := BEtoN(wWord);
        AStream.ReadBuffer(TempByte, 1); NumComponents := TempByte;

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
      // SOF2: Progressive DCT (unsupported)
      else if Marker = $FFC2 then
      begin
        raise Exception.Create('Progressive JPEG (SOF2) is not currently supported; please use Baseline JPEG');
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
          TablePrec := (TableId shr 4) and $0F;
          TableId := TableId and $0F;
          if TableId <= 3 then
          begin
            for K := 0 to 63 do
            begin
              if TablePrec = 0 then
              begin
                AStream.ReadBuffer(TempByte, 1);
                QuantTables[TableId][K] := TempByte;
                Dec(Len);
              end
              else
              begin
                AStream.ReadBuffer(TempWord, 2);
                QuantTables[TableId][K] := BEtoN(TempWord);
                Dec(Len, 2);
              end;
            end;
          end
          else
          begin
            if TablePrec = 0 then
            begin
              AStream.Seek(64, soFromCurrent);
              Dec(Len, 64);
            end
            else
            begin
              AStream.Seek(128, soFromCurrent);
              Dec(Len, 128);
            end;
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

          if TableId <= 3 then
          begin
            if TableClass = 0 then
            begin
              DCHuffman[TableId].Counts := Counts;
              for K := 0 to TotalSyms - 1 do
              begin
                AStream.ReadBuffer(DCHuffman[TableId].Symbols[K], 1); Dec(Len);
              end;
              BuildHuffmanTable(DCHuffman[TableId]);
            end
            else
            begin
              ACHuffman[TableId].Counts := Counts;
              for K := 0 to TotalSyms - 1 do
              begin
                AStream.ReadBuffer(ACHuffman[TableId].Symbols[K], 1); Dec(Len);
              end;
              BuildHuffmanTable(ACHuffman[TableId]);
            end;
          end
          else
          begin
            AStream.Seek(TotalSyms, soFromCurrent);
            Dec(Len, TotalSyms);
          end;
        end;
      end
      // DRI: Define Restart Interval
      else if Marker = $FFDD then
      begin
        AStream.ReadBuffer(Len, 2); Len := BEtoN(Len);
        AStream.ReadBuffer(TempWord, 2);
        RestartInterval := BEtoN(TempWord);
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
        // Handle restart interval
        if (RestartInterval > 0) and (McuCount > 0) and (McuCount mod RestartInterval = 0) then
        begin
          for I := 0 to NumComponents - 1 do
            Components[I].DcPred := 0;
          BS.BitsInBuf := 0;
        end;
        Inc(McuCount);

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

              R := ClampByte(YVal + SarLongint(359 * CrVal, 8));
              G := ClampByte(YVal - SarLongint(88 * CbVal + 183 * CrVal, 8));
              B := ClampByte(YVal + SarLongint(454 * CbVal, 8));
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
