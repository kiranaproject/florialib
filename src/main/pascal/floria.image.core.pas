unit Floria.Image.Core;

// Floria.Image.Core
// =================
// Core raster image model, pixel definitions, and extensible codec registry.
// Pure Object Pascal, zero dependencies on FCL-Image (FPImage).
//
// Pixel buffer is natively 32-bit BGRA (little-endian: B, G, R, A) for zero-copy
// compatibility with XCB Render, Cairo, and AggPas pixfmt_bgra32.

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils,
  agg_basics,
  agg_rendering_buffer,
  agg_pixfmt,
  agg_pixfmt_rgba;

type
  // 32-bit BGRA pixel (native AggPas / Cairo / XCB visual format in little-endian)
  TBgraPixel = packed record
    B : Byte;
    G : Byte;
    R : Byte;
    A : Byte;
    class function Create(const AR, AG, AB: Byte; const AA: Byte = 255): TBgraPixel; static;
  end;
  PBgraPixel = ^TBgraPixel;

  // 32-bit RGBA pixel
  TRgbaPixel = packed record
    R : Byte;
    G : Byte;
    B : Byte;
    A : Byte;
    class function Create(const AR, AG, AB: Byte; const AA: Byte = 255): TRgbaPixel; static;
  end;
  PRgbaPixel = ^TRgbaPixel;

  // Pixel format enumeration
  TFloriaPixelFormat = (
    fpfBGRA32,
    fpfRGBA32,
    fpfBGR24,
    fpfRGB24,
    fpfGray8
  );

  // Image file format enumeration
  TFloriaImageFormat = (
    fifUnknown,
    fifBMP,
    fifPNG,
    fifJPEG
  );

  // Forward declaration
  TFloriaImage = class;

  // Base image reader codec class
  TFloriaImageReader = class
  public
    class function CanRead(AStream: TStream): Boolean; virtual; abstract;
    class function Format(): TFloriaImageFormat; virtual;
    procedure ReadImage(AStream: TStream; AImage: TFloriaImage); virtual; abstract;
  end;
  TFloriaImageReaderClass = class of TFloriaImageReader;

  // Base image writer codec class
  TFloriaImageWriter = class
  public
    class function Format(): TFloriaImageFormat; virtual;
    procedure WriteImage(AStream: TStream; AImage: TFloriaImage); virtual; abstract;
  end;
  TFloriaImageWriterClass = class of TFloriaImageWriter;

  // TFloriaImage
  // 2D raster image buffer with integrated AggPas rendering surface
  TFloriaImage = class
  private
    FWidth       : Integer;
    FHeight      : Integer;
    FStride      : Integer;
    FPixelBuffer : Pointer;
    FPixelFormat : TFloriaPixelFormat;
    FRenderingBuf: rendering_buffer;
    FPixFormat   : pixel_formats;

    function GetPixel(const X, Y: Integer): TBgraPixel;
    procedure SetPixel(const X, Y: Integer; const AValue: TBgraPixel);
    function GetScanline(const Y: Integer): Pointer;
  public
    constructor Create();
    constructor Create(const AWidth, AHeight: Integer; const AFormat: TFloriaPixelFormat = fpfBGRA32);
    constructor CreateFromFile(const AFileName: string);
    constructor CreateFromStream(AStream: TStream);
    constructor CreateFromMemory(const AData: Pointer; const ASize: Integer);
    constructor CreateFromRGBA(const AData: Pointer; const AWidth, AHeight: Integer);
    constructor CreateFromBGRA(const AData: Pointer; const AWidth, AHeight: Integer);
    destructor Destroy(); override;

    procedure Allocate(const AWidth, AHeight: Integer; const AFormat: TFloriaPixelFormat = fpfBGRA32);
    procedure Clear(const R, G, B: Byte; const A: Byte = 255);
    function Clone(): TFloriaImage;
    function CreateScaled(const NewW, NewH: Integer; const ABilinear: Boolean = True): TFloriaImage;
    procedure CopyFrom(ASource: TFloriaImage; const SrcX, SrcY, DstX, DstY, W, H: Integer);

    function PixFormatPtr(): pixel_formats_ptr;
    function RenderingBufPtr(): rendering_buffer_ptr;

    procedure LoadFromFile(const AFileName: string);
    procedure LoadFromStream(AStream: TStream);
    procedure LoadFromMemory(const AData: Pointer; const ASize: Integer);
    procedure SaveToFile(const AFileName: string; const AFormat: TFloriaImageFormat = fifUnknown);
    procedure SaveToStream(AStream: TStream; const AFormat: TFloriaImageFormat);

    property Width       : Integer            read FWidth;
    property Height      : Integer            read FHeight;
    property Stride      : Integer            read FStride;
    property PixelBuffer : Pointer            read FPixelBuffer;
    property Data        : Pointer            read FPixelBuffer;
    property PixelFormat : TFloriaPixelFormat read FPixelFormat;
    property Pixels[const X, Y: Integer]: TBgraPixel read GetPixel write SetPixel;
    property Scanline[const Y: Integer]: Pointer     read GetScanline;
  end;

// Global codec registration and detection routines
procedure RegisterImageReader(const AReaderClass: TFloriaImageReaderClass);
procedure RegisterImageWriter(const AFormat: TFloriaImageFormat; const AWriterClass: TFloriaImageWriterClass);
function DetectImageFormat(AStream: TStream): TFloriaImageFormat;

implementation

type
  TReaderRegistry = array of TFloriaImageReaderClass;
  TWriterRegistry = array[TFloriaImageFormat] of TFloriaImageWriterClass;

var
  GReaders: TReaderRegistry;
  GWriters: TWriterRegistry;

procedure RegisterImageReader(const AReaderClass: TFloriaImageReaderClass);
var
  Len: Integer;
begin
  if AReaderClass = nil then Exit;
  Len := Length(GReaders);
  SetLength(GReaders, Len + 1);
  GReaders[Len] := AReaderClass;
end;

procedure RegisterImageWriter(const AFormat: TFloriaImageFormat; const AWriterClass: TFloriaImageWriterClass);
begin
  GWriters[AFormat] := AWriterClass;
end;

function DetectImageFormat(AStream: TStream): TFloriaImageFormat;
var
  I: Integer;
  OldPos: Int64;
begin
  Result := fifUnknown;
  if not Assigned(AStream) or (AStream.Size <= 0) then Exit;

  OldPos := AStream.Position;
  try
    for I := 0 to Length(GReaders) - 1 do
    begin
      AStream.Position := OldPos;
      if GReaders[I].CanRead(AStream) then
      begin
        Result := GReaders[I].Format();
        Exit;
      end;
    end;
  finally
    AStream.Position := OldPos;
  end;
end;

// ============================================================================
// TBgraPixel
// ============================================================================

class function TBgraPixel.Create(const AR, AG, AB: Byte; const AA: Byte = 255): TBgraPixel;
begin
  Result.B := AB;
  Result.G := AG;
  Result.R := AR;
  Result.A := AA;
end;

// ============================================================================
// TRgbaPixel
// ============================================================================

class function TRgbaPixel.Create(const AR, AG, AB: Byte; const AA: Byte = 255): TRgbaPixel;
begin
  Result.R := AR;
  Result.G := AG;
  Result.B := AB;
  Result.A := AA;
end;

// ============================================================================
// TFloriaImageReader / TFloriaImageWriter
// ============================================================================

class function TFloriaImageReader.Format(): TFloriaImageFormat;
begin
  Result := fifUnknown;
end;

class function TFloriaImageWriter.Format(): TFloriaImageFormat;
begin
  Result := fifUnknown;
end;

// ============================================================================
// TFloriaImage
// ============================================================================

constructor TFloriaImage.Create();
begin
  inherited Create();
  FWidth := 0;
  FHeight := 0;
  FStride := 0;
  FPixelBuffer := nil;
  FPixelFormat := fpfBGRA32;
end;

constructor TFloriaImage.Create(const AWidth, AHeight: Integer; const AFormat: TFloriaPixelFormat = fpfBGRA32);
begin
  inherited Create();
  Allocate(AWidth, AHeight, AFormat);
  Clear(0, 0, 0, 0);
end;

constructor TFloriaImage.CreateFromFile(const AFileName: string);
begin
  inherited Create();
  LoadFromFile(AFileName);
end;

constructor TFloriaImage.CreateFromStream(AStream: TStream);
begin
  inherited Create();
  LoadFromStream(AStream);
end;

constructor TFloriaImage.CreateFromMemory(const AData: Pointer; const ASize: Integer);
begin
  inherited Create();
  LoadFromMemory(AData, ASize);
end;

constructor TFloriaImage.CreateFromRGBA(const AData: Pointer; const AWidth, AHeight: Integer);
var
  src, dst: PByte;
  i, count: Integer;
begin
  inherited Create();
  Allocate(AWidth, AHeight, fpfBGRA32);
  if (FPixelBuffer = nil) or (AData = nil) then Exit;

  src := PByte(AData);
  dst := PByte(FPixelBuffer);
  count := AWidth * AHeight;
  for i := 0 to count - 1 do
  begin
    dst[0] := src[2]; // B <- B(2)
    dst[1] := src[1]; // G <- G(1)
    dst[2] := src[0]; // R <- R(0)
    dst[3] := src[3]; // A <- A(3)
    Inc(src, 4);
    Inc(dst, 4);
  end;
end;

constructor TFloriaImage.CreateFromBGRA(const AData: Pointer; const AWidth, AHeight: Integer);
begin
  inherited Create();
  Allocate(AWidth, AHeight, fpfBGRA32);
  if (FPixelBuffer = nil) or (AData = nil) then Exit;
  Move(AData^, FPixelBuffer^, FHeight * FStride);
end;

destructor TFloriaImage.Destroy();
begin
  if Assigned(FPixelBuffer) then
  begin
    FreeMem(FPixelBuffer);
    FPixelBuffer := nil;
  end;
  FRenderingBuf.Construct();
  inherited Destroy();
end;

procedure TFloriaImage.Allocate(const AWidth, AHeight: Integer; const AFormat: TFloriaPixelFormat = fpfBGRA32);
var
  TotalBytes: Integer;
begin
  if Assigned(FPixelBuffer) then
  begin
    FreeMem(FPixelBuffer);
    FPixelBuffer := nil;
  end;

  FWidth := AWidth;
  FHeight := AHeight;
  if FWidth < 0 then FWidth := 0;
  if FHeight < 0 then FHeight := 0;
  FPixelFormat := AFormat;

  case FPixelFormat of
    fpfBGRA32, fpfRGBA32:
      FStride := FWidth * 4;
    fpfBGR24, fpfRGB24:
      FStride := ((FWidth * 3 + 3) div 4) * 4; // 4-byte aligned
    fpfGray8:
      FStride := ((FWidth + 3) div 4) * 4;
  end;

  if (FWidth > 0) and (FHeight > 0) then
  begin
    TotalBytes := FHeight * FStride;
    GetMem(FPixelBuffer, TotalBytes);
    FillChar(FPixelBuffer^, TotalBytes, 0);
    FRenderingBuf.Construct();
    FRenderingBuf.attach(int8u_ptr(FPixelBuffer), FWidth, FHeight, FStride);
    pixfmt_bgra32(FPixFormat, @FRenderingBuf);
  end
  else
  begin
    FStride := 0;
    FPixelBuffer := nil;
    FRenderingBuf.Construct();
  end;
end;

function TFloriaImage.PixFormatPtr(): pixel_formats_ptr;
begin
  Result := @FPixFormat;
end;

function TFloriaImage.RenderingBufPtr(): rendering_buffer_ptr;
begin
  Result := @FRenderingBuf;
end;

procedure TFloriaImage.Clear(const R, G, B: Byte; const A: Byte = 255);
var
  P: PBgraPixel;
  TotalPixels, I: Integer;
  Val: TBgraPixel;
begin
  if (FPixelBuffer = nil) or (FWidth <= 0) or (FHeight <= 0) then Exit;

  if FPixelFormat = fpfBGRA32 then
  begin
    Val := TBgraPixel.Create(R, G, B, A);
    P := PBgraPixel(FPixelBuffer);
    TotalPixels := FWidth * FHeight;
    for I := 0 to TotalPixels - 1 do
    begin
      P^ := Val;
      Inc(P);
    end;
  end
  else
    FillChar(FPixelBuffer^, FHeight * FStride, 0);
end;

function TFloriaImage.GetPixel(const X, Y: Integer): TBgraPixel;
var
  Row: PByte;
  P: PBgraPixel;
begin
  if (FPixelBuffer = nil) or (X < 0) or (X >= FWidth) or (Y < 0) or (Y >= FHeight) then
  begin
    Result.B := 0; Result.G := 0; Result.R := 0; Result.A := 0;
    Exit;
  end;

  Row := PByte(FPixelBuffer) + Y * FStride;
  P := PBgraPixel(Row + X * 4);
  Result := P^;
end;

procedure TFloriaImage.SetPixel(const X, Y: Integer; const AValue: TBgraPixel);
var
  Row: PByte;
  P: PBgraPixel;
begin
  if (FPixelBuffer = nil) or (X < 0) or (X >= FWidth) or (Y < 0) or (Y >= FHeight) then Exit;

  Row := PByte(FPixelBuffer) + Y * FStride;
  P := PBgraPixel(Row + X * 4);
  P^ := AValue;
end;

function TFloriaImage.GetScanline(const Y: Integer): Pointer;
begin
  if (FPixelBuffer = nil) or (Y < 0) or (Y >= FHeight) then
    Result := nil
  else
    Result := PByte(FPixelBuffer) + Y * FStride;
end;

function TFloriaImage.Clone(): TFloriaImage;
begin
  Result := TFloriaImage.Create(FWidth, FHeight, FPixelFormat);
  if (FPixelBuffer <> nil) and (Result.PixelBuffer <> nil) then
    Move(FPixelBuffer^, Result.PixelBuffer^, FHeight * FStride);
end;

function TFloriaImage.CreateScaled(const NewW, NewH: Integer; const ABilinear: Boolean = True): TFloriaImage;
var
  DstX, DstY: Integer;
  SrcX, SrcY: Integer;
  PCol: TBgraPixel;
  stepX_fp, stepY_fp: Int64;
  curSrcY_fp, curSrcX_fp: Int64;
  dx, dy, sx, sy: Integer;
  fx, fy, invFx, invFy: Integer;
  srcStride, dstStride: Integer;
  srcPixels, dstPixels, dstRow: PByte;
  p00, p10, p01, p11: PByte;
  b, g, r, a: Integer;
begin
  if (NewW <= 0) or (NewH <= 0) or (FWidth <= 0) or (FHeight <= 0) or (FPixelBuffer = nil) then
    Exit(TFloriaImage.Create(0, 0, FPixelFormat));

  Result := TFloriaImage.Create(NewW, NewH, FPixelFormat);
  if (Result.PixelBuffer = nil) then Exit;

  if ABilinear and (FPixelFormat = fpfBGRA32) and (NewW > 1) and (NewH > 1) and (FWidth > 1) and (FHeight > 1) then
  begin
    stepX_fp := (Int64(FWidth) shl 16) div NewW;
    stepY_fp := (Int64(FHeight) shl 16) div NewH;
    srcStride := FStride;
    dstStride := Result.Stride;
    srcPixels := PByte(FPixelBuffer);
    dstPixels := PByte(Result.PixelBuffer);

    for dy := 0 to NewH - 1 do
    begin
      curSrcY_fp := Int64(dy) * stepY_fp;
      sy := curSrcY_fp shr 16;
      fy := (curSrcY_fp shr 8) and $FF;
      invFy := 255 - fy;

      if sy < 0 then sy := 0;
      if sy >= FHeight - 1 then sy := FHeight - 2;
      if sy < 0 then sy := 0;

      dstRow := dstPixels + dy * dstStride;

      for dx := 0 to NewW - 1 do
      begin
        curSrcX_fp := Int64(dx) * stepX_fp;
        sx := curSrcX_fp shr 16;
        fx := (curSrcX_fp shr 8) and $FF;
        invFx := 255 - fx;

        if sx < 0 then sx := 0;
        if sx >= FWidth - 1 then sx := FWidth - 2;
        if sx < 0 then sx := 0;

        p00 := srcPixels + sy * srcStride + sx * 4;
        p10 := p00 + 4;
        p01 := p00 + srcStride;
        p11 := p01 + 4;

        b := (p00[0] * invFx * invFy + p10[0] * fx * invFy + p01[0] * invFx * fy + p11[0] * fx * fy) shr 16;
        g := (p00[1] * invFx * invFy + p10[1] * fx * invFy + p01[1] * invFx * fy + p11[1] * fx * fy) shr 16;
        r := (p00[2] * invFx * invFy + p10[2] * fx * invFy + p01[2] * invFx * fy + p11[2] * fx * fy) shr 16;
        a := (p00[3] * invFx * invFy + p10[3] * fx * invFy + p01[3] * invFx * fy + p11[3] * fx * fy) shr 16;

        dstRow[0] := b;
        dstRow[1] := g;
        dstRow[2] := r;
        dstRow[3] := a;
        Inc(dstRow, 4);
      end;
    end;
  end
  else
  begin
    // Nearest neighbor sampling fallback
    for DstY := 0 to NewH - 1 do
    begin
      SrcY := (DstY * FHeight) div NewH;
      if SrcY >= FHeight then SrcY := FHeight - 1;

      for DstX := 0 to NewW - 1 do
      begin
        SrcX := (DstX * FWidth) div NewW;
        if SrcX >= FWidth then SrcX := FWidth - 1;

        PCol := GetPixel(SrcX, SrcY);
        Result.SetPixel(DstX, DstY, PCol);
      end;
    end;
  end;
end;

procedure TFloriaImage.CopyFrom(ASource: TFloriaImage; const SrcX, SrcY, DstX, DstY, W, H: Integer);
var
  Row: Integer;
  ActualW, ActualH: Integer;
  SrcRow, DstRow: PByte;
begin
  if (ASource = nil) or (ASource.PixelBuffer = nil) or (FPixelBuffer = nil) then Exit;

  ActualW := W;
  ActualH := H;
  if DstX + ActualW > FWidth then ActualW := FWidth - DstX;
  if DstY + ActualH > FHeight then ActualH := FHeight - DstY;
  if SrcX + ActualW > ASource.Width then ActualW := ASource.Width - SrcX;
  if SrcY + ActualH > ASource.Height then ActualH := ASource.Height - SrcY;
  if (ActualW <= 0) or (ActualH <= 0) then Exit;

  for Row := 0 to ActualH - 1 do
  begin
    SrcRow := PByte(ASource.Scanline[SrcY + Row]) + SrcX * 4;
    DstRow := PByte(GetScanline(DstY + Row)) + DstX * 4;
    Move(SrcRow^, DstRow^, ActualW * 4);
  end;
end;

procedure TFloriaImage.LoadFromFile(const AFileName: string);
var
  FS: TFileStream;
begin
  if not FileExists(AFileName) then
    raise Exception.CreateFmt('Image file not found: %s', [AFileName]);

  FS := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    LoadFromStream(FS);
  finally
    FS.Free();
  end;
end;

procedure TFloriaImage.LoadFromStream(AStream: TStream);
var
  I: Integer;
  OldPos: Int64;
  Reader: TFloriaImageReader;
begin
  if not Assigned(AStream) or (AStream.Size <= 0) then
  begin
    Allocate(0, 0);
    Exit;
  end;

  OldPos := AStream.Position;
  for I := 0 to Length(GReaders) - 1 do
  begin
    AStream.Position := OldPos;
    if GReaders[I].CanRead(AStream) then
    begin
      AStream.Position := OldPos;
      Reader := GReaders[I].Create();
      try
        Reader.ReadImage(AStream, Self);
        Exit;
      finally
        Reader.Free();
      end;
    end;
  end;

  AStream.Position := OldPos;
  raise Exception.Create('Unsupported or unrecognized image format');
end;

procedure TFloriaImage.LoadFromMemory(const AData: Pointer; const ASize: Integer);
var
  MS: TMemoryStream;
begin
  if (AData = nil) or (ASize <= 0) then
  begin
    Allocate(0, 0);
    Exit;
  end;

  MS := TMemoryStream.Create();
  try
    MS.WriteBuffer(AData^, ASize);
    MS.Position := 0;
    LoadFromStream(MS);
  finally
    MS.Free();
  end;
end;

procedure TFloriaImage.SaveToFile(const AFileName: string; const AFormat: TFloriaImageFormat = fifUnknown);
var
  FS: TFileStream;
  Fmt: TFloriaImageFormat;
  Ext: string;
begin
  Fmt := AFormat;
  if Fmt = fifUnknown then
  begin
    Ext := LowerCase(ExtractFileExt(AFileName));
    if (Ext = '.bmp') then Fmt := fifBMP
    else if (Ext = '.png') then Fmt := fifPNG
    else if (Ext = '.jpg') or (Ext = '.jpeg') then Fmt := fifJPEG
    else Fmt := fifBMP;
  end;

  FS := TFileStream.Create(AFileName, fmCreate);
  try
    SaveToStream(FS, Fmt);
  finally
    FS.Free();
  end;
end;

procedure TFloriaImage.SaveToStream(AStream: TStream; const AFormat: TFloriaImageFormat);
var
  WriterClass: TFloriaImageWriterClass;
  Writer: TFloriaImageWriter;
begin
  WriterClass := GWriters[AFormat];
  if WriterClass = nil then
    raise Exception.CreateFmt('No image writer registered for format: %d', [Ord(AFormat)]);

  Writer := WriterClass.Create();
  try
    Writer.WriteImage(AStream, Self);
  finally
    Writer.Free();
  end;
end;

initialization
  SetLength(GReaders, 0);
  FillChar(GWriters, SizeOf(GWriters), 0);

finalization
  SetLength(GReaders, 0);

end.
