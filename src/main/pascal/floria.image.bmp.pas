unit Floria.Image.BMP;

// Floria.Image.BMP
// ================
// Pure Object Pascal BMP image decoder and encoder.
// Zero external dependencies; no FCL-Image required.
//
// Supports:
// - Reading 24-bit BGR, 32-bit BGRA, and 8-bit indexed BMP.
// - Top-down and bottom-up row orientations.
// - Writing 32-bit BGRA and 24-bit BGR BMP images.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  Floria.Image.Core;

type
  // Standard BMP headers
  TBitmapFileHeader = packed record
    bfType      : Word;      // 'BM' ($4D42)
    bfSize      : Cardinal;  // Total file size
    bfReserved1 : Word;      // 0
    bfReserved2 : Word;      // 0
    bfOffBits   : Cardinal;  // Offset from beginning to pixel bits
  end;

  TBitmapInfoHeader = packed record
    biSize          : Cardinal; // 40
    biWidth         : Integer;
    biHeight        : Integer;  // Positive = bottom-up, negative = top-down
    biPlanes        : Word;     // 1
    biBitCount      : Word;     // 1, 4, 8, 16, 24, 32
    biCompression   : Cardinal; // 0 = BI_RGB
    biSizeImage     : Cardinal;
    biXPelsPerMeter : Integer;
    biYPelsPerMeter : Integer;
    biClrUsed       : Cardinal;
    biClrImportant  : Cardinal;
  end;

  TRgbQuad = packed record
    b : Byte;
    g : Byte;
    r : Byte;
    reserved : Byte;
  end;

  // BMP Reader Codec
  TFloriaBMPReader = class(TFloriaImageReader)
  public
    class function CanRead(AStream: TStream): Boolean; override;
    class function Format(): TFloriaImageFormat; override;
    procedure ReadImage(AStream: TStream; AImage: TFloriaImage); override;
  end;

  // BMP Writer Codec
  TFloriaBMPWriter = class(TFloriaImageWriter)
  public
    class function Format(): TFloriaImageFormat; override;
    procedure WriteImage(AStream: TStream; AImage: TFloriaImage); override;
  end;

implementation

// ============================================================================
// TFloriaBMPReader
// ============================================================================

class function TFloriaBMPReader.CanRead(AStream: TStream): Boolean;
var
  Magic: Word;
  OldPos: Int64;
begin
  Result := False;
  if not Assigned(AStream) or (AStream.Size - AStream.Position < 2) then Exit;

  OldPos := AStream.Position;
  try
    Magic := 0;
    if AStream.Read(Magic, 2) = 2 then
      Result := (Magic = $4D42); // 'BM'
  finally
    AStream.Position := OldPos;
  end;
end;

class function TFloriaBMPReader.Format(): TFloriaImageFormat;
begin
  Result := fifBMP;
end;

procedure TFloriaBMPReader.ReadImage(AStream: TStream; AImage: TFloriaImage);
var
  FileHdr: TBitmapFileHeader;
  InfoHdr: TBitmapInfoHeader;
  StartPos: Int64;
  W, H: Integer;
  IsTopDown: Boolean;
  Row, X: Integer;
  DstRow: PBgraPixel;
  RowBytes, PadBytes: Integer;
  Buf24: array of Byte;
  Palette: array[0..255] of TRgbQuad;
  NumColors: Integer;
  PalIdx: Byte;
  RowBuf: array of Byte;
  P32: PBgraPixel;
begin
  StartPos := AStream.Position;
  if AStream.Read(FileHdr, SizeOf(FileHdr)) <> SizeOf(FileHdr) then
    raise Exception.Create('Malformed BMP: premature end of file header');

  if FileHdr.bfType <> $4D42 then
    raise Exception.Create('Invalid BMP signature');

  if AStream.Read(InfoHdr, SizeOf(InfoHdr)) <> SizeOf(InfoHdr) then
    raise Exception.Create('Malformed BMP: premature end of info header');

  W := InfoHdr.biWidth;
  H := Abs(InfoHdr.biHeight);
  IsTopDown := (InfoHdr.biHeight < 0);

  if (W <= 0) or (H <= 0) then
  begin
    AImage.Allocate(0, 0);
    Exit;
  end;

  // Read palette if 8-bit
  if InfoHdr.biBitCount = 8 then
  begin
    NumColors := InfoHdr.biClrUsed;
    if NumColors = 0 then NumColors := 256;
    if NumColors > 256 then NumColors := 256;
    FillChar(Palette, SizeOf(Palette), 0);
    AStream.Read(Palette, NumColors * SizeOf(TRgbQuad));
  end;

  // Seek to pixel bits offset
  if FileHdr.bfOffBits > 0 then
    AStream.Position := StartPos + FileHdr.bfOffBits;

  AImage.Allocate(W, H, fpfBGRA32);

  case InfoHdr.biBitCount of
    32:
    begin
      // 32-bit BGRA: directly read row by row
      for Row := 0 to H - 1 do
      begin
        if IsTopDown then
          DstRow := PBgraPixel(AImage.Scanline[Row])
        else
          DstRow := PBgraPixel(AImage.Scanline[H - 1 - Row]);

        AStream.ReadBuffer(DstRow^, W * 4);
      end;
    end;

    24:
    begin
      // 24-bit BGR: padded to 4-byte boundary
      RowBytes := W * 3;
      PadBytes := ((RowBytes + 3) div 4) * 4 - RowBytes;
      SetLength(Buf24, RowBytes + PadBytes);

      for Row := 0 to H - 1 do
      begin
        if IsTopDown then
          DstRow := PBgraPixel(AImage.Scanline[Row])
        else
          DstRow := PBgraPixel(AImage.Scanline[H - 1 - Row]);

        AStream.ReadBuffer(Buf24[0], Length(Buf24));

        for X := 0 to W - 1 do
        begin
          DstRow^.B := Buf24[X * 3 + 0];
          DstRow^.G := Buf24[X * 3 + 1];
          DstRow^.R := Buf24[X * 3 + 2];
          DstRow^.A := 255;
          Inc(DstRow);
        end;
      end;
    end;

    8:
    begin
      // 8-bit indexed: padded to 4-byte boundary
      RowBytes := W;
      PadBytes := ((RowBytes + 3) div 4) * 4 - RowBytes;
      SetLength(RowBuf, RowBytes + PadBytes);

      for Row := 0 to H - 1 do
      begin
        if IsTopDown then
          DstRow := PBgraPixel(AImage.Scanline[Row])
        else
          DstRow := PBgraPixel(AImage.Scanline[H - 1 - Row]);

        AStream.ReadBuffer(RowBuf[0], Length(RowBuf));

        for X := 0 to W - 1 do
        begin
          PalIdx := RowBuf[X];
          DstRow^.B := Palette[PalIdx].b;
          DstRow^.G := Palette[PalIdx].g;
          DstRow^.R := Palette[PalIdx].r;
          DstRow^.A := 255;
          Inc(DstRow);
        end;
      end;
    end;
  else
    raise Exception.CreateFmt('Unsupported BMP bit depth: %d bits per pixel', [InfoHdr.biBitCount]);
  end;
end;

// ============================================================================
// TFloriaBMPWriter
// ============================================================================

class function TFloriaBMPWriter.Format(): TFloriaImageFormat;
begin
  Result := fifBMP;
end;

procedure TFloriaBMPWriter.WriteImage(AStream: TStream; AImage: TFloriaImage);
var
  FileHdr: TBitmapFileHeader;
  InfoHdr: TBitmapInfoHeader;
  W, H: Integer;
  Row: Integer;
  SrcRow: Pointer;
begin
  if (AImage = nil) or (AImage.Width <= 0) or (AImage.Height <= 0) then Exit;

  W := AImage.Width;
  H := AImage.Height;

  FillChar(FileHdr, SizeOf(FileHdr), 0);
  FileHdr.bfType := $4D42; // 'BM'
  FileHdr.bfOffBits := SizeOf(TBitmapFileHeader) + SizeOf(TBitmapInfoHeader); // 54
  FileHdr.bfSize := FileHdr.bfOffBits + Cardinal(W * H * 4);

  FillChar(InfoHdr, SizeOf(InfoHdr), 0);
  InfoHdr.biSize := SizeOf(TBitmapInfoHeader); // 40
  InfoHdr.biWidth := W;
  InfoHdr.biHeight := H; // Standard bottom-up
  InfoHdr.biPlanes := 1;
  InfoHdr.biBitCount := 32; // 32-bit BGRA
  InfoHdr.biCompression := 0; // BI_RGB
  InfoHdr.biSizeImage := W * H * 4;

  AStream.WriteBuffer(FileHdr, SizeOf(FileHdr));
  AStream.WriteBuffer(InfoHdr, SizeOf(InfoHdr));

  // Write pixels bottom-up
  for Row := H - 1 downto 0 do
  begin
    SrcRow := AImage.Scanline[Row];
    AStream.WriteBuffer(SrcRow^, W * 4);
  end;
end;

initialization
  RegisterImageReader(TFloriaBMPReader);
  RegisterImageWriter(fifBMP, TFloriaBMPWriter);

end.
