unit Floria.Text.Emoji;

// Floria.Text.Emoji
// =================
// Full-color OpenType emoji rendering engine for Floria Toolkit and Florialib.
// Loads CBDT/CBLC and PNG color bitmap strikes from Noto Color Emoji / system emoji
// fonts via FreeType, caches downscaled 32-bit BGRA images, and provides high-speed
// text measurement and alpha-blended rendering.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Process,
  agg_basics,
  agg_font_freetype_lib,
  Floria.Image.Core;

const
  FT_LOAD_COLOR          = 1 shl 20;
  FT_FACE_FLAG_COLOR     = 1 shl 23;
  FT_PIXEL_MODE_BGRA_VAL = 7;

{ FT_Select_Size binding }
function FT_Select_Size(face: FT_Face_ptr; strike_index: FT_Int): FT_Error; cdecl; external ft_lib name 'FT_Select_Size';

type
  { TEmojiCacheEntry }
  PEmojiCacheEntry = ^TEmojiCacheEntry;
  TEmojiCacheEntry = record
    CharCode: Cardinal;
    TargetHeight: Integer;
    Image: TFloriaImage;
  end;

  { TFloriaEmojiEngine — Singleton manager for native color emoji rendering }
  TFloriaEmojiEngine = class
  private
    FLibrary      : FT_Library_ptr;
    FFace         : FT_Face_ptr;
    FAvailable    : Boolean;
    FFontPath     : string;
    FStrikeWidth  : Integer;
    FStrikeHeight : Integer;
    FCache        : TFPList;
    procedure InitEngine();
    function FindEmojiFontFile(): string;
    function RenderGlyphToImage(ACharCode: Cardinal; ATargetHeight: Integer): TFloriaImage;
  public
    constructor Create();
    destructor Destroy; override;

    function IsAvailable: Boolean;
    function HasEmoji(ACharCode: Cardinal): Boolean;
    function GetEmojiImage(ACharCode: Cardinal; ATargetHeight: Integer): TFloriaImage;
    procedure ClearCache();

    property FontPath: string read FFontPath;
    property Available: Boolean read FAvailable;
  end;

function FloriaEmojiEngine(): TFloriaEmojiEngine;

implementation

var
  uEmojiEngine: TFloriaEmojiEngine = nil;

function FloriaEmojiEngine(): TFloriaEmojiEngine;
begin
  if uEmojiEngine = nil then
    uEmojiEngine := TFloriaEmojiEngine.Create();
  Result := uEmojiEngine;
end;

{ TFloriaEmojiEngine }

constructor TFloriaEmojiEngine.Create();
begin
  inherited Create();
  FLibrary := nil;
  FFace := nil;
  FAvailable := False;
  FStrikeWidth := 0;
  FStrikeHeight := 0;
  FCache := TFPList.Create();
  InitEngine();
end;

destructor TFloriaEmojiEngine.Destroy();
begin
  ClearCache();
  FCache.Free();
  if FFace <> nil then
  begin
    FT_Done_Face(FFace);
    FFace := nil;
  end;
  if FLibrary <> nil then
  begin
    FT_Done_FreeType(FLibrary);
    FLibrary := nil;
  end;
  inherited Destroy();
end;

procedure TFloriaEmojiEngine.ClearCache();
var
  i: Integer;
  entry: PEmojiCacheEntry;
begin
  if Assigned(FCache) then
  begin
    for i := 0 to FCache.Count - 1 do
    begin
      entry := PEmojiCacheEntry(FCache[i]);
      if Assigned(entry) then
      begin
        if Assigned(entry^.Image) then
          entry^.Image.Free();
        Dispose(entry);
      end;
    end;
    FCache.Clear();
  end;
end;

function TFloriaEmojiEngine.FindEmojiFontFile(): string;
var
  outPath: string;
const
  StandardEmojiPaths: array[0..3] of string = (
    '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf',
    '/usr/share/fonts/google-noto-color-emoji/NotoColorEmoji.ttf',
    '/usr/share/fonts/noto-color-emoji/NotoColorEmoji.ttf',
    '/usr/share/fonts/opentype/noto/NotoColorEmoji.otf'
  );
var
  i: Integer;
begin
  Result := '';

  // 1. Check known Linux filesystem paths
  for i := Low(StandardEmojiPaths) to High(StandardEmojiPaths) do
  begin
    if FileExists(StandardEmojiPaths[i]) then
      Exit(StandardEmojiPaths[i]);
  end;

  // 2. Query fontconfig for Noto Color Emoji
  if RunCommand('fc-match', ['-f', '%{file}', 'Noto Color Emoji'], outPath) then
  begin
    outPath := Trim(outPath);
    if (outPath <> '') and FileExists(outPath) and (Pos('Emoji', outPath) > 0) then
      Exit(outPath);
  end;

  // 3. Fallback fontconfig query for emoji category
  if RunCommand('fc-match', ['-f', '%{file}', ':family=emoji'], outPath) then
  begin
    outPath := Trim(outPath);
    if (outPath <> '') and FileExists(outPath) then
      Exit(outPath);
  end;
end;

procedure TFloriaEmojiEngine.InitEngine();
var
  err: FT_Error;
begin
  FFontPath := FindEmojiFontFile();
  if FFontPath = '' then Exit;

  err := FT_Init_FreeType(FLibrary);
  if err <> 0 then
  begin
    FLibrary := nil;
    Exit;
  end;

  err := FT_New_Face(FLibrary, PChar(FFontPath), 0, FFace);
  if err <> 0 then
  begin
    FFace := nil;
    Exit;
  end;

  // Select first available color strike size
  err := FT_Select_Size(FFace, 0);
  if err <> 0 then
  begin
    FT_Done_Face(FFace);
    FFace := nil;
    Exit;
  end;

  FAvailable := True;
end;

function TFloriaEmojiEngine.IsAvailable: Boolean;
begin
  Result := FAvailable and (FFace <> nil);
end;

function TFloriaEmojiEngine.HasEmoji(ACharCode: Cardinal): Boolean;
var
  glyphIdx: FT_UInt;
begin
  if not IsAvailable then Exit(False);

  // Fast check: standard ASCII, Latin, Cyrillic, Greek, etc. are not emojis
  if ACharCode < $2000 then Exit(False);

  // Check known emoji ranges
  case ACharCode of
    $203C, $2049, $2122, $2139,
    $2194..$2199, $21A9..$21AA,
    $231A..$231B, $2328, $23CF,
    $23E9..$23F3, $23F8..$23FA,
    $24C2, $25AA..$25AB, $25FB..$25FE,
    $2600..$27BF, // Misc Symbols and Dingbats
    $2934..$2935, $2B05..$2B07, $2B1B..$2B1C,
    $2B50, $2B55, $3030, $303D, $3297, $3299,
    $1F000..$1FAFF: // Supplementary Multilingual Plane Emojis and Pictographs
    begin
      glyphIdx := FT_Get_Char_Index(FFace, ACharCode);
      Result := (glyphIdx > 0);
    end;
  else
    Result := False;
  end;
end;

function TFloriaEmojiEngine.RenderGlyphToImage(ACharCode: Cardinal; ATargetHeight: Integer): TFloriaImage;
var
  glyphIdx: FT_UInt;
  err: FT_Error;
  slot: FT_GlyphSlot_ptr;
  srcW, srcH, srcPitch: Integer;
  srcBuf: PByte;
  dstW, dstH: Integer;
  dstImg: TFloriaImage;
  dstPixels: PByte;
  dstStride: Integer;
  dx, dy: Integer;
  dstPixel, pPixel: PBgraPixel;
  scaleX, scaleY: Double;
  x0, x1, y0, y1: Double;
  sx0, sx1, sy0, sy1: Integer;
  sx, sy: Integer;
  xWeight, yWeight, weight: Double;
  sumB, sumG, sumR, sumA, totalWeight, invWeight: Double;
  b, g, r, a: Integer;
  // Bilinear variables for upscaling fallback
  srcX_fp, srcY_fp: Int64;
  invFx, invFy, fx, fy: Integer;
  row0, row1: PByte;
  p00, p10, p01, p11: PBgraPixel;
  w00, w10, w01, w11: Integer;
begin
  Result := nil;
  if not IsAvailable then Exit;
  if ATargetHeight < 8 then ATargetHeight := 8;
  if ATargetHeight > 256 then ATargetHeight := 256;

  glyphIdx := FT_Get_Char_Index(FFace, ACharCode);
  if glyphIdx = 0 then Exit;

  err := FT_Load_Glyph(FFace, glyphIdx, FT_LOAD_COLOR);
  if err <> 0 then Exit;

  slot := FFace^.glyph;
  err := FT_Render_Glyph(slot, FT_RENDER_MODE_NORMAL);
  if err <> 0 then Exit;

  srcW := slot^.bitmap.width;
  srcH := slot^.bitmap.rows;
  srcPitch := slot^.bitmap.pitch;
  srcBuf := PByte(slot^.bitmap.buffer);

  if (srcW <= 0) or (srcH <= 0) or (srcBuf = nil) or (Ord(slot^.bitmap.pixel_mode) <> FT_PIXEL_MODE_BGRA_VAL) then
    Exit;

  dstH := ATargetHeight;
  dstW := Round(Double(srcW) * dstH / Double(srcH));
  if dstW < 8 then dstW := 8;

  dstImg := TFloriaImage.Create(dstW, dstH, fpfBGRA32);
  dstImg.IsPremultiplied := True;
  dstPixels := PByte(dstImg.PixelBuffer);
  dstStride := dstImg.Stride;

  if (dstW <= srcW) and (dstH <= srcH) then
  begin
    // Area-Averaging Box Integration: Integrates 100% of the native high-res glyph pixels
    // for continuous subpixel anti-aliased curves and smooth alpha transitions
    scaleX := Double(srcW) / Double(dstW);
    scaleY := Double(srcH) / Double(dstH);

    for dy := 0 to dstH - 1 do
    begin
      y0 := dy * scaleY;
      y1 := (dy + 1) * scaleY;
      sy0 := Floor(y0);
      sy1 := Ceil(y1) - 1;
      if sy0 < 0 then sy0 := 0;
      if sy1 >= srcH then sy1 := srcH - 1;

      for dx := 0 to dstW - 1 do
      begin
        x0 := dx * scaleX;
        x1 := (dx + 1) * scaleX;
        sx0 := Floor(x0);
        sx1 := Ceil(x1) - 1;
        if sx0 < 0 then sx0 := 0;
        if sx1 >= srcW then sx1 := srcW - 1;

        sumB := 0.0;
        sumG := 0.0;
        sumR := 0.0;
        sumA := 0.0;
        totalWeight := 0.0;

        for sy := sy0 to sy1 do
        begin
          yWeight := Min(Double(sy + 1), y1) - Max(Double(sy), y0);
          if yWeight <= 0.0 then Continue;

          for sx := sx0 to sx1 do
          begin
            xWeight := Min(Double(sx + 1), x1) - Max(Double(sx), x0);
            if xWeight <= 0.0 then Continue;

            weight := xWeight * yWeight;
            pPixel := PBgraPixel(srcBuf + (sy * srcPitch) + (sx * 4));

            sumB := sumB + Double(pPixel^.B) * weight;
            sumG := sumG + Double(pPixel^.G) * weight;
            sumR := sumR + Double(pPixel^.R) * weight;
            sumA := sumA + Double(pPixel^.A) * weight;
            totalWeight := totalWeight + weight;
          end;
        end;

        dstPixel := PBgraPixel(dstPixels + (dy * dstStride) + (dx * 4));
        if totalWeight > 0.0001 then
        begin
          invWeight := 1.0 / totalWeight;
          b := Round(sumB * invWeight);
          g := Round(sumG * invWeight);
          r := Round(sumR * invWeight);
          a := Round(sumA * invWeight);

          if b > 255 then b := 255 else if b < 0 then b := 0;
          if g > 255 then g := 255 else if g < 0 then g := 0;
          if r > 255 then r := 255 else if r < 0 then r := 0;
          if a > 255 then a := 255 else if a < 0 then a := 0;

          dstPixel^.B := Byte(b);
          dstPixel^.G := Byte(g);
          dstPixel^.R := Byte(r);
          dstPixel^.A := Byte(a);
        end
        else
        begin
          dstPixel^.B := 0;
          dstPixel^.G := 0;
          dstPixel^.R := 0;
          dstPixel^.A := 0;
        end;
      end;
    end;
  end
  else
  begin
    // Bilinear interpolation fallback for magnification (dstW > srcW or dstH > srcH)
    for dy := 0 to dstH - 1 do
    begin
      srcY_fp := (Int64(dy) * srcH shl 16) div dstH;
      sy0 := srcY_fp shr 16;
      if sy0 >= srcH then sy0 := srcH - 1;
      sy1 := sy0 + 1;
      if sy1 >= srcH then sy1 := srcH - 1;

      fy := (srcY_fp shr 8) and $FF;
      invFy := 255 - fy;

      row0 := srcBuf + (sy0 * srcPitch);
      row1 := srcBuf + (sy1 * srcPitch);

      for dx := 0 to dstW - 1 do
      begin
        srcX_fp := (Int64(dx) * srcW shl 16) div dstW;
        sx0 := srcX_fp shr 16;
        if sx0 >= srcW then sx0 := srcW - 1;
        sx1 := sx0 + 1;
        if sx1 >= srcW then sx1 := srcW - 1;

        fx := (srcX_fp shr 8) and $FF;
        invFx := 255 - fx;

        p00 := PBgraPixel(row0 + sx0 * 4);
        p10 := PBgraPixel(row0 + sx1 * 4);
        p01 := PBgraPixel(row1 + sx0 * 4);
        p11 := PBgraPixel(row1 + sx1 * 4);

        w00 := (invFx * invFy) shr 8;
        w10 := (fx * invFy) shr 8;
        w01 := (invFx * fy) shr 8;
        w11 := (fx * fy) shr 8;

        b := (p00^.B * w00 + p10^.B * w10 + p01^.B * w01 + p11^.B * w11 + 128) shr 8;
        g := (p00^.G * w00 + p10^.G * w10 + p01^.G * w01 + p11^.G * w11 + 128) shr 8;
        r := (p00^.R * w00 + p10^.R * w10 + p01^.R * w01 + p11^.R * w11 + 128) shr 8;
        a := (p00^.A * w00 + p10^.A * w10 + p01^.A * w01 + p11^.A * w11 + 128) shr 8;

        if b > 255 then b := 255;
        if g > 255 then g := 255;
        if r > 255 then r := 255;
        if a > 255 then a := 255;

        dstPixel := PBgraPixel(dstPixels + (dy * dstStride) + (dx * 4));
        dstPixel^.B := Byte(b);
        dstPixel^.G := Byte(g);
        dstPixel^.R := Byte(r);
        dstPixel^.A := Byte(a);
      end;
    end;
  end;

  Result := dstImg;
end;

function TFloriaEmojiEngine.GetEmojiImage(ACharCode: Cardinal; ATargetHeight: Integer): TFloriaImage;
var
  i: Integer;
  entry: PEmojiCacheEntry;
  newImg: TFloriaImage;
begin
  Result := nil;
  if not HasEmoji(ACharCode) then Exit;
  if ATargetHeight < 8 then ATargetHeight := 8;

  // Search cache
  for i := 0 to FCache.Count - 1 do
  begin
    entry := PEmojiCacheEntry(FCache[i]);
    if (entry^.CharCode = ACharCode) and (entry^.TargetHeight = ATargetHeight) then
      Exit(entry^.Image);
  end;

  // Render and cache
  newImg := RenderGlyphToImage(ACharCode, ATargetHeight);
  if Assigned(newImg) then
  begin
    New(entry);
    entry^.CharCode := ACharCode;
    entry^.TargetHeight := ATargetHeight;
    entry^.Image := newImg;
    FCache.Add(entry);
    Result := newImg;
  end;
end;

initialization

finalization
  if uEmojiEngine <> nil then
  begin
    uEmojiEngine.Free();
    uEmojiEngine := nil;
  end;

end.
