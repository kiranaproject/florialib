unit Floria.Image.PNG;

// Floria.Image.PNG
// ================
// Pure Object Pascal PNG image decoder and encoder.
// Uses Floria.Compression.Zlib and Floria.Compression.CRC for RFC 1950/1951
// streaming compression. Zero external dependencies.
//
// Supports:
// - Reading RGBA (32-bit), RGB (24-bit), Grayscale+Alpha, Grayscale, and Indexed PNG.
// - All 5 standard PNG scanline reconstruction filters (None, Sub, Up, Average, Paeth).
// - Writing standard 32-bit RGBA PNG images with LZ77 Deflate compression.

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils,
  Floria.Image.Core,
  Floria.Compression.CRC,
  Floria.Compression.Deflate,
  Floria.Compression.Zlib;

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
// Paeth Predictor & Scanline Unfiltering
// ============================================================================

function PaethPredictor(const A, B, C: Integer): Byte; inline;
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
        // Skip unknown chunk data
        AStream.Seek(ChunkLen, soFromCurrent);
      end;

      // Skip Chunk CRC
      AStream.ReadBuffer(ChunkCRC, 4);
    end;

    if (W <= 0) or (H <= 0) or (IDATStream.Size = 0) then
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
    Uncompressed := ZlibDecompress(IDATStream.Memory, IDATStream.Size, H * (RowBytes + 1));

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
          0: // None
            CurrentRow[X] := Uncompressed[SrcIdx];
          1: // Sub
            CurrentRow[X] := Byte(Uncompressed[SrcIdx] + A);
          2: // Up
            CurrentRow[X] := Byte(Uncompressed[SrcIdx] + B);
          3: // Average
            CurrentRow[X] := Byte(Uncompressed[SrcIdx] + ((A + B) div 2));
          4: // Paeth
            CurrentRow[X] := Byte(Uncompressed[SrcIdx] + PaethPredictor(A, B, C));
        else
          CurrentRow[X] := Uncompressed[SrcIdx];
        end;
        Inc(SrcIdx);
      end;

      // Convert unfiltered scanline to 32-bit BGRA
      DstPixel := PBgraPixel(AImage.Scanline[Row]);
      for X := 0 to W - 1 do
      begin
        case ColorType of
          0: // Grayscale
            begin
              DstPixel^.B := CurrentRow[X];
              DstPixel^.G := CurrentRow[X];
              DstPixel^.R := CurrentRow[X];
              DstPixel^.A := 255;
            end;
          2: // RGB
            begin
              DstPixel^.R := CurrentRow[X * 3 + 0];
              DstPixel^.G := CurrentRow[X * 3 + 1];
              DstPixel^.B := CurrentRow[X * 3 + 2];
              DstPixel^.A := 255;
            end;
          3: // Indexed Palette
            begin
              PalIdx := CurrentRow[X];
              if HasPalette and (PalIdx < Length(Palette)) then
              begin
                DstPixel^.R := Palette[PalIdx].R;
                DstPixel^.G := Palette[PalIdx].G;
                DstPixel^.B := Palette[PalIdx].B;
                DstPixel^.A := Palette[PalIdx].A;
              end
              else
              begin
                DstPixel^.R := PalIdx;
                DstPixel^.G := PalIdx;
                DstPixel^.B := PalIdx;
                DstPixel^.A := 255;
              end;
            end;
          4: // Gray + Alpha
            begin
              DstPixel^.B := CurrentRow[X * 2 + 0];
              DstPixel^.G := CurrentRow[X * 2 + 0];
              DstPixel^.R := CurrentRow[X * 2 + 0];
              DstPixel^.A := CurrentRow[X * 2 + 1];
            end;
          6: // RGBA
            begin
              DstPixel^.R := CurrentRow[X * 4 + 0];
              DstPixel^.G := CurrentRow[X * 4 + 1];
              DstPixel^.B := CurrentRow[X * 4 + 2];
              DstPixel^.A := CurrentRow[X * 4 + 3];
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

  CRCVal := UpdateCRC32(0, @TypeBytes[0], 4);
  if ALength > 0 then
  begin
    AStream.WriteBuffer(AData^, ALength);
    CRCVal := UpdateCRC32(CRCVal, AData, ALength);
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
  IDATData: TBytes;
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
        if AImage.IsPremultiplied and (SrcPixel^.A > 0) and (SrcPixel^.A < 255) then
        begin
          PixelRGBA[0] := (SrcPixel^.R * 255) div SrcPixel^.A;
          if PixelRGBA[0] > 255 then PixelRGBA[0] := 255;
          PixelRGBA[1] := (SrcPixel^.G * 255) div SrcPixel^.A;
          if PixelRGBA[1] > 255 then PixelRGBA[1] := 255;
          PixelRGBA[2] := (SrcPixel^.B * 255) div SrcPixel^.A;
          if PixelRGBA[2] > 255 then PixelRGBA[2] := 255;
        end
        else
        begin
          PixelRGBA[0] := SrcPixel^.R;
          PixelRGBA[1] := SrcPixel^.G;
          PixelRGBA[2] := SrcPixel^.B;
        end;
        PixelRGBA[3] := SrcPixel^.A;
        RawScanlines.WriteBuffer(PixelRGBA[0], 4);
        Inc(SrcPixel);
      end;
    end;

    // 4. Compress IDAT with Zlib LZ77 Deflate
    IDATData := ZlibCompress(RawScanlines.Memory, RawScanlines.Size, fclDefault);
    if Length(IDATData) > 0 then
      WriteChunk(AStream, 'IDAT', @IDATData[0], Length(IDATData))
    else
      WriteChunk(AStream, 'IDAT', nil, 0);

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
