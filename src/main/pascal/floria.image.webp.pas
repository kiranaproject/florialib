unit Floria.Image.WebP;

// Floria.Image.WebP
// =================
// WebP image codec reader and writer for Floria.Image subsystem.
// Dynamically binds to libwebp (libwebp.so.7 / libwebp.so) at runtime via dynlibs.
// Decodes directly into native 32-bit BGRA (fpfBGRA32) pixel buffers.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, ctypes, dynlibs,
  Floria.Image.Core;

type
  // Dynamic function pointer types for libwebp
  TWebPGetInfo = function(const data: PByte; data_size: csize_t; width: pcint; height: pcint): cint; cdecl;
  TWebPDecodeBGRAInto = function(const data: PByte; data_size: csize_t; output_buffer: PByte; output_buffer_size: csize_t; output_stride: cint): PByte; cdecl;
  TWebPEncodeBGRA = function(const rgba: PByte; width: cint; height: cint; stride: cint; quality_factor: cfloat; output: PPByte): csize_t; cdecl;
  TWebPEncodeLosslessBGRA = function(const rgba: PByte; width: cint; height: cint; stride: cint; output: PPByte): csize_t; cdecl;
  TWebPFree = procedure(p: Pointer); cdecl;
  TWebPGetDecoderVersion = function(): cint; cdecl;

  // WebP dynamic loader and codec engine
  TWebPEngine = class
  private
    FLibHandle: TLibHandle;
    FAvailable: Boolean;
    FVersion: Integer;
    FGetInfo: TWebPGetInfo;
    FDecodeBGRAInto: TWebPDecodeBGRAInto;
    FEncodeBGRA: TWebPEncodeBGRA;
    FEncodeLosslessBGRA: TWebPEncodeLosslessBGRA;
    FFreeFunc: TWebPFree;
    FGetDecoderVersion: TWebPGetDecoderVersion;

    procedure LoadSymbols();
  public
    constructor Create();
    destructor Destroy(); override;

    function Decode(const AData: Pointer; const ASize: Integer; AImage: TFloriaImage): Boolean;
    function Encode(AImage: TFloriaImage; AStream: TStream; const ALossless: Boolean = True; const AQuality: Single = 85.0): Boolean;

    property Available: Boolean read FAvailable;
    property Version: Integer read FVersion;
  end;

  // WebP Reader Codec
  TFloriaWebPReader = class(TFloriaImageReader)
  public
    class function CanRead(AStream: TStream): Boolean; override;
    class function Format(): TFloriaImageFormat; override;
    procedure ReadImage(AStream: TStream; AImage: TFloriaImage); override;
  end;

  // WebP Writer Codec
  TFloriaWebPWriter = class(TFloriaImageWriter)
  public
    class function Format(): TFloriaImageFormat; override;
    procedure WriteImage(AStream: TStream; AImage: TFloriaImage); override;
  end;

function GetWebPEngine(): TWebPEngine;
function IsWebPAvailable(): Boolean;
function GetWebPVersion(): Integer;

implementation

var
  GWebPEngine: TWebPEngine = nil;

function GetWebPEngine(): TWebPEngine;
begin
  if GWebPEngine = nil then
    GWebPEngine := TWebPEngine.Create();
  Result := GWebPEngine;
end;

function IsWebPAvailable(): Boolean;
begin
  Result := GetWebPEngine().Available;
end;

function GetWebPVersion(): Integer;
begin
  Result := GetWebPEngine().Version;
end;

// ============================================================================
// TWebPEngine
// ============================================================================

constructor TWebPEngine.Create();
const
  LIB_CANDIDATES: array[0..7] of string = (
    'libwebp.so.7',
    'libwebp.so',
    'libwebp.so.6',
    'libwebp.so.5',
    'libwebp.7.dylib',
    'libwebp.dylib',
    'libwebp-7.dll',
    'libwebp.dll'
  );
var
  I: Integer;
begin
  inherited Create();
  FLibHandle := NilHandle;
  FAvailable := False;
  FVersion   := 0;

  for I := Low(LIB_CANDIDATES) to High(LIB_CANDIDATES) do
  begin
    FLibHandle := SafeLoadLibrary(LIB_CANDIDATES[I]);
    if FLibHandle <> NilHandle then
      Break;
  end;

  if FLibHandle <> NilHandle then
    LoadSymbols();
end;

destructor TWebPEngine.Destroy();
begin
  if FLibHandle <> NilHandle then
  begin
    UnloadLibrary(FLibHandle);
    FLibHandle := NilHandle;
  end;
  inherited Destroy();
end;

procedure TWebPEngine.LoadSymbols();
begin
  Pointer(FGetInfo)            := GetProcedureAddress(FLibHandle, 'WebPGetInfo');
  Pointer(FDecodeBGRAInto)     := GetProcedureAddress(FLibHandle, 'WebPDecodeBGRAInto');
  Pointer(FEncodeBGRA)         := GetProcedureAddress(FLibHandle, 'WebPEncodeBGRA');
  Pointer(FEncodeLosslessBGRA) := GetProcedureAddress(FLibHandle, 'WebPEncodeLosslessBGRA');
  Pointer(FFreeFunc)           := GetProcedureAddress(FLibHandle, 'WebPFree');
  Pointer(FGetDecoderVersion)  := GetProcedureAddress(FLibHandle, 'WebPGetDecoderVersion');

  if Assigned(FGetInfo) and Assigned(FDecodeBGRAInto) then
  begin
    FAvailable := True;
    if Assigned(FGetDecoderVersion) then
      FVersion := FGetDecoderVersion()
    else
      FVersion := 0;
  end;
end;

function TWebPEngine.Decode(const AData: Pointer; const ASize: Integer; AImage: TFloriaImage): Boolean;
var
  W, H: cint;
  Res: PByte;
  RequiredSize: csize_t;
begin
  Result := False;
  if not FAvailable or (AData = nil) or (ASize <= 0) or (AImage = nil) then Exit;

  W := 0;
  H := 0;
  if FGetInfo(PByte(AData), csize_t(ASize), @W, @H) = 0 then Exit;
  if (W <= 0) or (H <= 0) then Exit;

  AImage.Allocate(W, H, fpfBGRA32);
  if AImage.PixelBuffer = nil then Exit;

  RequiredSize := csize_t(AImage.Stride) * csize_t(H);
  Res := FDecodeBGRAInto(PByte(AData), csize_t(ASize), PByte(AImage.PixelBuffer), RequiredSize, AImage.Stride);
  if Res = nil then
  begin
    AImage.Allocate(0, 0);
    Exit;
  end;

  AImage.IsPremultiplied := False;
  Result := True;
end;

function TWebPEngine.Encode(AImage: TFloriaImage; AStream: TStream; const ALossless: Boolean = True; const AQuality: Single = 85.0): Boolean;
var
  Encoded: PByte;
  EncSize: csize_t;
  NeedsFreeSrc: Boolean;
  SrcImg: TFloriaImage;
begin
  Result := False;
  if not FAvailable or (AImage = nil) or (AStream = nil) or (AImage.PixelBuffer = nil) then Exit;
  if (AImage.Width <= 0) or (AImage.Height <= 0) then Exit;

  NeedsFreeSrc := False;
  SrcImg := AImage;
  if AImage.IsPremultiplied then
  begin
    SrcImg := AImage.Clone();
    SrcImg.DemultiplyAlpha();
    NeedsFreeSrc := True;
  end;

  try
    Encoded := nil;
    EncSize := 0;
    if ALossless then
    begin
      if Assigned(FEncodeLosslessBGRA) then
        EncSize := FEncodeLosslessBGRA(PByte(SrcImg.PixelBuffer), SrcImg.Width, SrcImg.Height, SrcImg.Stride, @Encoded);
    end
    else
    begin
      if Assigned(FEncodeBGRA) then
        EncSize := FEncodeBGRA(PByte(SrcImg.PixelBuffer), SrcImg.Width, SrcImg.Height, SrcImg.Stride, AQuality, @Encoded);
    end;

    if (EncSize > 0) and (Encoded <> nil) then
    begin
      try
        AStream.WriteBuffer(Encoded^, EncSize);
        Result := True;
      finally
        if Assigned(FFreeFunc) then
          FFreeFunc(Encoded);
      end;
    end;
  finally
    if NeedsFreeSrc then
      SrcImg.Free();
  end;
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
  Engine: TWebPEngine;
  DataSize: Int64;
  Buffer: Pointer;
  MemStream: TCustomMemoryStream;
  Offset: Int64;
begin
  if not Assigned(AStream) or (AStream.Size <= 0) then
  begin
    AImage.Allocate(0, 0);
    Exit;
  end;

  Engine := GetWebPEngine();
  if not Engine.Available then
    raise Exception.Create('WebP dynamic library (libwebp) is not available');

  if AStream is TCustomMemoryStream then
  begin
    MemStream := TCustomMemoryStream(AStream);
    Offset := MemStream.Position;
    DataSize := MemStream.Size - Offset;
    if DataSize <= 0 then
    begin
      AImage.Allocate(0, 0);
      Exit;
    end;
    if not Engine.Decode(PByte(MemStream.Memory) + Offset, DataSize, AImage) then
      raise Exception.Create('Failed to decode WebP image stream');
    AStream.Position := MemStream.Size;
    Exit;
  end;

  DataSize := AStream.Size - AStream.Position;
  if DataSize <= 0 then
  begin
    AImage.Allocate(0, 0);
    Exit;
  end;

  GetMem(Buffer, DataSize);
  try
    AStream.ReadBuffer(Buffer^, DataSize);
    if not Engine.Decode(Buffer, DataSize, AImage) then
      raise Exception.Create('Failed to decode WebP image stream');
  finally
    FreeMem(Buffer);
  end;
end;

// ============================================================================
// TFloriaWebPWriter
// ============================================================================

class function TFloriaWebPWriter.Format(): TFloriaImageFormat;
begin
  Result := fifWebP;
end;

procedure TFloriaWebPWriter.WriteImage(AStream: TStream; AImage: TFloriaImage);
var
  Engine: TWebPEngine;
begin
  if not Assigned(AStream) or not Assigned(AImage) then Exit;

  Engine := GetWebPEngine();
  if not Engine.Available then
    raise Exception.Create('WebP dynamic library (libwebp) is not available');

  if not Engine.Encode(AImage, AStream, True) then
    raise Exception.Create('Failed to encode WebP image');
end;

initialization
  RegisterImageReader(TFloriaWebPReader);
  RegisterImageWriter(fifWebP, TFloriaWebPWriter);

finalization
  if GWebPEngine <> nil then
  begin
    GWebPEngine.Free();
    GWebPEngine := nil;
  end;

end.
