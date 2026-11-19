unit Floria.Image.WebP;

// Floria.Image.WebP
// =================
// Pure Object Pascal WebP image reader and writer codec.
// Zero external dependencies; no C libraries, DLLs, or shared objects required.
//
// Supports:
// - Reading WebP images: lossy VP8, lossless VP8L, extended VP8X with alpha plane.
// - Writing lossless and lossy WebP images.
// - Native decoding directly into 32-bit BGRA (fpfBGRA32) pixel buffers.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  Floria.Image.Core,
  Floria.Image.WebP.Dec,
  Floria.Image.WebP.Enc;

type
  // WebP Reader Codec (Pure Object Pascal)
  TFloriaWebPReader = class(TFloriaImageReader)
  public
    class function CanRead(AStream: TStream): Boolean; override;
    class function Format(): TFloriaImageFormat; override;
    procedure ReadImage(AStream: TStream; AImage: TFloriaImage); override;
  end;

  // WebP Writer Codec (Pure Object Pascal)
  TFloriaWebPWriter = class(TFloriaImageWriter)
  private
    FQuality: Single;
    FLossy: Boolean;
  public
    constructor Create(); override;
    class function Format(): TFloriaImageFormat; override;
    procedure WriteImage(AStream: TStream; AImage: TFloriaImage); override;

    property Quality: Single read FQuality write FQuality;
    property Lossy: Boolean read FLossy write FLossy;
  end;

function IsWebPAvailable(): Boolean;

implementation

function IsWebPAvailable(): Boolean;
begin
  Result := True; // Pure Pascal implementation is always available
end;

// ============================================================================
// TFloriaWebPReader
// ============================================================================

class function TFloriaWebPReader.CanRead(AStream: TStream): Boolean;
var
  Hdr: array[0..11] of AnsiChar;
  OldPos: Int64;
begin
  Result := False;
  if not Assigned(AStream) or (AStream.Size - AStream.Position < 12) then Exit;

  OldPos := AStream.Position;
  try
    FillChar(Hdr, SizeOf(Hdr), 0);
    if AStream.Read(Hdr, 12) = 12 then
    begin
      Result := (Hdr[0] = 'R') and (Hdr[1] = 'I') and (Hdr[2] = 'F') and (Hdr[3] = 'F') and
                (Hdr[8] = 'W') and (Hdr[9] = 'E') and (Hdr[10] = 'B') and (Hdr[11] = 'P');
    end;
  finally
    AStream.Position := OldPos;
  end;
end;

class function TFloriaWebPReader.Format(): TFloriaImageFormat;
begin
  Result := fifWebP;
end;

procedure TFloriaWebPReader.ReadImage(AStream: TStream; AImage: TFloriaImage);
var
  DataSize: Int64;
  Buffer: PByte;
  MemStream: TCustomMemoryStream;
  Offset: Int64;
  W, H: Integer;
  Pixels: PByte;
  NeedsFreeBuffer: Boolean;
begin
  if not Assigned(AStream) or (AStream.Size <= 0) then
  begin
    AImage.Allocate(0, 0);
    Exit;
  end;

  Buffer := nil;
  NeedsFreeBuffer := False;

  if AStream is TCustomMemoryStream then
  begin
    MemStream := TCustomMemoryStream(AStream);
    Offset := MemStream.Position;
    DataSize := MemStream.Size - Offset;
    if DataSize < 12 then
    begin
      AImage.Allocate(0, 0);
      Exit;
    end;
    Buffer := PByte(MemStream.Memory) + Offset;
    MemStream.Position := MemStream.Size;
  end
  else
  begin
    DataSize := AStream.Size - AStream.Position;
    if DataSize < 12 then
    begin
      AImage.Allocate(0, 0);
      Exit;
    end;
    GetMem(Buffer, DataSize);
    NeedsFreeBuffer := True;
    AStream.ReadBuffer(Buffer^, DataSize);
  end;

  try
    W := 0;
    H := 0;
    Pixels := Floria.Image.WebP.Dec.WebPDecodeBGRA(Buffer, DataSize, W, H);
    if (Pixels = nil) or (W <= 0) or (H <= 0) then
      raise Exception.Create('Failed to decode WebP image stream');

    try
      AImage.Allocate(W, H, fpfBGRA32);
      if AImage.PixelBuffer <> nil then
        Move(Pixels^, AImage.PixelBuffer^, W * H * 4);
      AImage.IsPremultiplied := False;
    finally
      Floria.Image.WebP.Dec.WebPFree(Pixels);
    end;
  finally
    if NeedsFreeBuffer and (Buffer <> nil) then
      FreeMem(Buffer);
  end;
end;

// ============================================================================
// TFloriaWebPWriter
// ============================================================================

constructor TFloriaWebPWriter.Create();
begin
  inherited Create();
  FQuality := 85.0;
  FLossy := False;
end;

class function TFloriaWebPWriter.Format(): TFloriaImageFormat;
begin
  Result := fifWebP;
end;

procedure TFloriaWebPWriter.WriteImage(AStream: TStream; AImage: TFloriaImage);
var
  OutData: PByte;
  OutSize: Integer;
  Ok: Boolean;
  SrcImg: TFloriaImage;
  NeedsFreeSrc: Boolean;
begin
  if not Assigned(AStream) or not Assigned(AImage) then Exit;
  if (AImage.Width <= 0) or (AImage.Height <= 0) or (AImage.PixelBuffer = nil) then Exit;

  NeedsFreeSrc := False;
  SrcImg := AImage;
  if AImage.IsPremultiplied then
  begin
    SrcImg := AImage.Clone();
    SrcImg.DemultiplyAlpha();
    NeedsFreeSrc := True;
  end;

  try
    OutData := nil;
    OutSize := 0;

    if not FLossy then
      Ok := Floria.Image.WebP.Enc.WebPEncodeLosslessBGRA(
        PByte(SrcImg.PixelBuffer),
        SrcImg.Width,
        SrcImg.Height,
        SrcImg.Stride,
        OutData,
        OutSize
      )
    else
    begin
      if FQuality <= 0.0 then
        FQuality := 85.0;
      Ok := Floria.Image.WebP.Enc.WebPEncodeBGRA(
        PByte(SrcImg.PixelBuffer),
        SrcImg.Width,
        SrcImg.Height,
        SrcImg.Stride,
        FQuality,
        OutData,
        OutSize
      );
    end;

    if not Ok or (OutSize <= 0) or (OutData = nil) then
      raise Exception.Create('Failed to encode WebP image');

    try
      AStream.WriteBuffer(OutData^, OutSize);
    finally
      FreeMem(OutData);
    end;
  finally
    if NeedsFreeSrc then
      SrcImg.Free();
  end;
end;

initialization
  RegisterImageReader(TFloriaWebPReader);
  RegisterImageWriter(fifWebP, TFloriaWebPWriter);

end.
