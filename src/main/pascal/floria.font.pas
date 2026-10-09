unit Floria.Font;

// Floria.Font
// ===========
// FreeType font engine and cache manager built on top of AggPas
// (agg_font_freetype, agg_font_cache_manager).
// Supports DPI scaling, stem darkening (gamma correction), system font detection,
// fontconfig matching, and fallback font chaining (e.g. CJK glyph fallback).

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Process,
  agg_gamma_functions,
  agg_font_freetype,
  agg_font_cache_manager;

type
  // Forward declarations
  TFloriaFont = class;
  TFloriaFontManager = class;

  // TFloriaFont: Encapsulates a loaded FreeType font with metrics and cache
  TFloriaFont = class
  private
    FFamilyName  : string;
    FSize        : Double;   // Font size in points (pt)
    FDPI         : Double;   // Monitor DPI
    FGamma       : Double;   // Stem gamma factor for FreeType rasterizer
    FBold        : Boolean;
    FItalic      : Boolean;
    FFontPath    : string;
    FFaceIndex   : Cardinal;
    FFontDesc    : string;
    FGamPower    : gamma_power;
    FEngine      : font_engine_freetype_int32;
    FCacheManager: font_cache_manager;
    FLoaded          : Boolean;
    FAscent          : Double;   // In device pixels
    FDescent         : Double;   // In device pixels
    FHeight          : Double;   // In device pixels
    FFallbackFont    : TFloriaFont;
    FFallbackIndex   : Integer;
    FDynamicLatinFont: TFloriaFont;
    procedure LoadFont();
    procedure SetGamma(AValue: Double);
    function GetFallbackFont(): TFloriaFont;
    function GetDynamicLatinFont(): TFloriaFont;
  public
    constructor Create(const AFamily: string; ASize: Double; ABold, AItalic: Boolean;
                       const APath: string; AFaceIndex: Cardinal = 0; ADPI: Double = 96.0; AGamma: Double = 0.75);
    destructor Destroy(); override;

    function GetTextWidth(const AText: string): Double;
    function CacheManagerPtr(): font_cache_manager_ptr;

    property FamilyName      : string       read FFamilyName;
    property Size            : Double       read FSize;
    property DPI             : Double       read FDPI;
    property Gamma           : Double       read FGamma write SetGamma;
    property Bold            : Boolean      read FBold;
    property Italic          : Boolean      read FItalic;
    property FontPath        : string       read FFontPath;
    property FaceIndex       : Cardinal     read FFaceIndex;
    property FontDesc        : string       read FFontDesc;
    property Loaded          : Boolean      read FLoaded;
    property Ascent          : Double       read FAscent;
    property Descent         : Double       read FDescent;
    property Height          : Double       read FHeight;
    property FallbackFont    : TFloriaFont  read GetFallbackFont write FFallbackFont;
    property FallbackIndex   : Integer      read FFallbackIndex write FFallbackIndex;
    property DynamicLatinFont: TFloriaFont  read GetDynamicLatinFont;
  end;

  // TFloriaFontManager: Centralized font management, DPI scaling, and persistent cache
  TFloriaFontManager = class
  private
    FCache                   : TFPList;
    FDefaultFontDesc         : string;
    FSystemFont              : TFloriaFont;
    FScreenDPI               : Double;
    FFontGamma               : Double;
    FDynamicLatinSwap        : Boolean;
    FFallbackFamilies        : TStringList;
    function DetectScreenDPI(): Double;
    function DetectSystemFontDesc(): string;
    function DetectFallbackFontFamily(): string;
    function DetectSymbolFallbackFontFamily(): string;
    function ResolveFontFile(const AFamily: string; ABold, AItalic: Boolean; out AFaceIndex: Cardinal): string;
    function BuildCanonicalDesc(const AFamily: string; ASize: Double; ABold, AItalic: Boolean; AFaceIndex: Cardinal): string;
    procedure ParseFontDesc(ADesc: string; out AFamily: string; out ASize: Double; out ABold, AItalic: Boolean);
    procedure SetScreenDPI(AValue: Double);
    procedure SetFontGamma(AValue: Double);
    procedure InitFallbackFamilies();
    function GetFallbackFontFamily(): string;
    procedure SetFallbackFontFamily(const AValue: string);
    function GetSymbolFallbackFontFamily(): string;
    procedure SetSymbolFallbackFontFamily(const AValue: string);
  public
    constructor Create();
    destructor Destroy(); override;

    function GetFont(const AFontDesc: string): TFloriaFont;
    function GetSystemFont(): TFloriaFont;
    function GetFallbackFont(ASize: Double): TFloriaFont;
    function GetSymbolFallbackFont(ASize: Double): TFloriaFont;
    function FallbackFontCount(): Integer;
    function GetFallbackFontAt(AIndex: Integer; ASize: Double): TFloriaFont;
    function IndexOfFallbackFamily(const AFamily: string): Integer;
    procedure SetSystemFontDesc(const AFontDesc: string);

    property SystemFont              : TFloriaFont read GetSystemFont;
    property DefaultFontDesc         : string      read FDefaultFontDesc write SetSystemFontDesc;
    property ScreenDPI               : Double      read FScreenDPI write SetScreenDPI;
    property FontGamma               : Double      read FFontGamma write SetFontGamma;
    property DynamicLatinSwap        : Boolean     read FDynamicLatinSwap write FDynamicLatinSwap;
    property FallbackFontFamily      : string      read GetFallbackFontFamily write SetFallbackFontFamily;
    property SymbolFallbackFontFamily: string      read GetSymbolFallbackFontFamily write SetSymbolFallbackFontFamily;
  end;

  // Backward-compatibility aliases
  TFtFont = TFloriaFont;
  TFtFontManager = TFloriaFontManager;

function UTF8CharToUnicode(p: PChar; out CharLen: LongInt): Cardinal;
function FloriaFontManager(): TFloriaFontManager;
function FloriaGetSystemFont(): TFloriaFont;
function FloriaGetFallbackFont(ASize: Double): TFloriaFont;
function FloriaGetSymbolFallbackFont(ASize: Double): TFloriaFont;
function FloriaGetScreenDPI(): Double;
procedure FloriaSetScreenDPI(ADPI: Double);
function FloriaGetFontGamma(): Double;
procedure FloriaSetFontGamma(AGamma: Double);

// Backward-compatibility alias functions
function FtFontManager(): TFtFontManager;
function FtGetSystemFont(): TFtFont;
function FtGetFallbackFont(ASize: Double): TFtFont;
function FtGetSymbolFallbackFont(ASize: Double): TFtFont;
function FtGetScreenDPI(): Double;
procedure FtSetScreenDPI(ADPI: Double);
function FtGetFontGamma(): Double;
procedure FtSetFontGamma(AGamma: Double);

implementation

uses
  Floria.Unicode.BiDi;

var
  uFontManager: TFloriaFontManager = nil;

function UTF8CharToUnicode(p: PChar; out CharLen: LongInt): Cardinal;
begin
  if p = nil then
  begin
    CharLen := 0;
    Exit(0);
  end;
  if Ord(p^) < %11000000 then
  begin
    Result := Ord(p^);
    CharLen := 1;
    Exit;
  end
  else if ((Ord(p^) and %11100000) = %11000000) then
  begin
    if (Ord(p[1]) and %11000000) = %10000000 then
    begin
      Result := ((Ord(p^) and %00011111) shl 6) or (Ord(p[1]) and %00111111);
      CharLen := 2;
      Exit;
    end;
  end
  else if ((Ord(p^) and %11110000) = %11100000) then
  begin
    if ((Ord(p[1]) and %11000000) = %10000000) and
       ((Ord(p[2]) and %11000000) = %10000000) then
    begin
      Result := ((Ord(p^) and %00001111) shl 12) or
                ((Ord(p[1]) and %00111111) shl 6) or
                (Ord(p[2]) and %00111111);
      CharLen := 3;
      Exit;
    end;
  end
  else if ((Ord(p^) and %11111000) = %11110000) then
  begin
    if ((Ord(p[1]) and %11000000) = %10000000) and
       ((Ord(p[2]) and %11000000) = %10000000) and
       ((Ord(p[3]) and %11000000) = %10000000) then
    begin
      Result := ((Ord(p^) and %00000111) shl 18) or
                ((Ord(p[1]) and %00111111) shl 12) or
                ((Ord(p[2]) and %00111111) shl 6) or
                (Ord(p[3]) and %00111111);
      CharLen := 4;
      Exit;
    end;
  end;
  Result := Ord(p^);
  CharLen := 1;
end;

function FindLastChar(const S: string; Ch: Char): Integer;
var
  i: Integer;
begin
  for i := Length(S) downto 1 do
    if S[i] = Ch then Exit(i);
  Result := 0;
end;

// ============================================================================
// TFloriaFont
// ============================================================================

constructor TFloriaFont.Create(const AFamily: string; ASize: Double; ABold, AItalic: Boolean;
                              const APath: string; AFaceIndex: Cardinal = 0; ADPI: Double = 96.0; AGamma: Double = 0.75);
var
  px: Double;
begin
  inherited Create();
  FFamilyName := AFamily;
  FSize := ASize;
  FDPI := ADPI;
  FGamma := AGamma;
  FBold := ABold;
  FItalic := AItalic;
  FFontPath := APath;
  FFaceIndex := AFaceIndex;
  FFallbackFont := nil;
  FFallbackIndex := -1;
  FDynamicLatinFont := nil;
  FLoaded := False;

  px := FSize * (FDPI / 72.0);
  FAscent := px * 0.8;
  FDescent := px * 0.2;
  FHeight := px;

  FEngine.Construct();
  FCacheManager.Construct(@FEngine);

  if FFontPath <> '' then
    LoadFont();
end;

destructor TFloriaFont.Destroy();
begin
  FCacheManager.Destruct();
  FEngine.Destruct();
  inherited Destroy();
end;

procedure TFloriaFont.LoadFont();
var
  pixelHeight: Double;
begin
  if not FileExists(FFontPath) then Exit;

  FLoaded := FEngine.load_font(PChar(FFontPath), FFaceIndex, glyph_ren_agg_gray8);
  if FLoaded then
  begin
    // Convert point size (pt) to device pixel height based on screen DPI
    pixelHeight := FSize * (FDPI / 72.0);
    FEngine.height_(pixelHeight);
    FEngine.flip_y_(True);
    FEngine.hinting_(True);

    // Stem darkening / gamma correction for solid font strokes matching desktop standards
    if FGamma > 0.0 then
    begin
      FGamPower.Construct(FGamma);
      FEngine.gamma_(@FGamPower);
    end;

    FAscent := FEngine._ascender();
    FDescent := Abs(FEngine._descender());
    FHeight := FEngine._height();
  end;
end;

procedure TFloriaFont.SetGamma(AValue: Double);
begin
  if (AValue <= 0.0) or (Abs(FGamma - AValue) < 0.001) then Exit;
  FGamma := AValue;
  if FLoaded then
  begin
    FGamPower.Construct(FGamma);
    FEngine.gamma_(@FGamPower);
    // Reset cache so existing glyphs are re-rasterized with the new gamma
    FCacheManager.Destruct();
    FCacheManager.Construct(@FEngine);
  end;
end;

function TFloriaFont.GetFallbackFont(): TFloriaFont;
var
  mgr: TFloriaFontManager;
  nextIdx: Integer;
begin
  if Assigned(FFallbackFont) then
    Exit(FFallbackFont);

  mgr := FloriaFontManager();
  if FFallbackIndex >= 0 then
  begin
    nextIdx := FFallbackIndex + 1;
    if nextIdx < mgr.FallbackFontCount() then
      FFallbackFont := mgr.GetFallbackFontAt(nextIdx, FSize)
    else
      FFallbackFont := nil;
  end
  else
  begin
    // Check if this font family matches one of the fallback families
    nextIdx := mgr.IndexOfFallbackFamily(FFamilyName);
    if nextIdx >= 0 then
    begin
      Inc(nextIdx);
      if nextIdx < mgr.FallbackFontCount() then
        FFallbackFont := mgr.GetFallbackFontAt(nextIdx, FSize)
      else
        FFallbackFont := nil;
    end
    else
      FFallbackFont := mgr.GetFallbackFontAt(0, FSize);
  end;

  Result := FFallbackFont;
end;

function TFloriaFont.GetDynamicLatinFont(): TFloriaFont;
var
  mgr: TFloriaFontManager;
  sysFont: TFloriaFont;
  famLower: string;
  isScript: Boolean;
begin
  if Assigned(FDynamicLatinFont) then
    Exit(FDynamicLatinFont);

  mgr := FloriaFontManager();
  if not mgr.DynamicLatinSwap then
    Exit(nil);

  sysFont := mgr.GetSystemFont();
  if not Assigned(sysFont) or not sysFont.Loaded then
    Exit(nil);

  // If this font itself IS the system font (e.g. Ubuntu), no swap needed
  if SameText(FFamilyName, sysFont.FamilyName) then
    Exit(nil);

  famLower := LowerCase(FFamilyName);
  isScript := (Pos('cjk', famLower) > 0) or
              (Pos('thai', famLower) > 0) or
              (Pos('arabic', famLower) > 0) or
              (Pos('devanagari', famLower) > 0) or
              (Pos('hebrew', famLower) > 0) or
              (Pos('korean', famLower) > 0) or
              (Pos('japanese', famLower) > 0) or
              (Pos('chinese', famLower) > 0) or
              (Pos('hangul', famLower) > 0) or
              (Pos('bengali', famLower) > 0) or
              (Pos('tamil', famLower) > 0) or
              (Pos('telugu', famLower) > 0) or
              (Pos('gujarati', famLower) > 0) or
              (Pos('kannada', famLower) > 0) or
              (Pos('malayalam', famLower) > 0) or
              (Pos('myanmar', famLower) > 0) or
              (Pos('khmer', famLower) > 0) or
              (Pos('sinhala', famLower) > 0) or
              (Pos('gurmukhi', famLower) > 0) or
              (Pos('droid sans fallback', famLower) > 0);

  if isScript then
  begin
    // Resolve system font at the exact size and style of this font
    FDynamicLatinFont := mgr.GetFont(mgr.BuildCanonicalDesc(sysFont.FamilyName, FSize, FBold, FItalic, 0));
    Result := FDynamicLatinFont;
  end
  else
    Result := nil;
end;

function TFloriaFont.GetTextWidth(const AText: string): Double;
var
  str_: PChar;
  charLen: LongInt;
  charId: Cardinal;
  glyph, origGlyph, fbGlyph, latinGlyph: glyph_cache_ptr;
  first, foundFb: Boolean;
  x, y: Double;
  fb, latinFont: TFloriaFont;
  curCM, prevCM, latinCM: font_cache_manager_ptr;
  measText: string;
  depth: Integer;
begin
  if not FLoaded or (AText = '') then
    Exit(Length(AText) * (FSize * (FDPI / 72.0)) * 0.55);

  if TFloriaBiDi.HasRTL(AText) then
    measText := TFloriaBiDi.ProcessBidiAndShape(AText)
  else
    measText := AText;

  x := 0.0;
  y := 0.0;
  first := True;
  prevCM := nil;
  str_ := PChar(measText);

  latinFont := DynamicLatinFont;
  if Assigned(latinFont) and latinFont.Loaded then
    latinCM := latinFont.CacheManagerPtr()
  else
    latinCM := nil;

  while str_^ <> #0 do
  begin
    charId := UTF8CharToUnicode(str_, charLen);
    Inc(str_, charLen);

    glyph := nil;
    curCM := @FCacheManager;

    // Dynamic Latin swap: if active font is a script font, use system Latin font for ASCII/Latin
    if (latinCM <> nil) and (charId >= 33) and (charId <= 255) then
    begin
      latinGlyph := latinCM^.glyph(charId);
      if (latinGlyph <> nil) and (latinGlyph^.glyph_index <> 0) then
      begin
        glyph := latinGlyph;
        curCM := latinCM;
      end;
    end;

    if glyph = nil then
    begin
      glyph := FCacheManager.glyph(charId);
      curCM := @FCacheManager;
      if (glyph = nil) or (glyph^.glyph_index = 0) then
      begin
        origGlyph := glyph;
        fb := FallbackFont;
        depth := 0;
        foundFb := False;
        while Assigned(fb) and fb.Loaded and (fb <> Self) and (depth < 8) do
        begin
          fbGlyph := fb.CacheManagerPtr()^.glyph(charId);
          if (fbGlyph <> nil) and (fbGlyph^.glyph_index <> 0) then
          begin
            glyph := fbGlyph;
            curCM := fb.CacheManagerPtr();
            foundFb := True;
            Break;
          end;
          fb := fb.FallbackFont;
          Inc(depth);
        end;
        if not foundFb then
        begin
          glyph := origGlyph;
          curCM := @FCacheManager;
        end;
      end;
    end;

    if glyph <> nil then
    begin
      if (not first) and (prevCM = curCM) then
        curCM^.add_kerning(@x, @y);
      first := False;
      prevCM := curCM;
      x := x + glyph^.advance_x;
    end;
  end;

  Result := x;
end;

function TFloriaFont.CacheManagerPtr(): font_cache_manager_ptr;
begin
  Result := @FCacheManager;
end;

// ============================================================================
// TFloriaFontManager
// ============================================================================

constructor TFloriaFontManager.Create();
var
  envVal: string;
  valDbl: Double;
  code: Integer;
begin
  inherited Create();
  FCache := TFPList.Create();
  FScreenDPI := DetectScreenDPI();
  FDefaultFontDesc := DetectSystemFontDesc();
  FSystemFont := nil;
  FFontGamma := 0.75;

  envVal := GetEnvironmentVariable('FT_FONT_GAMMA');
  if envVal <> '' then
  begin
    Val(envVal, valDbl, code);
    if (code = 0) and (valDbl > 0.05) and (valDbl < 5.0) then
      FFontGamma := valDbl;
  end;

  FDynamicLatinSwap := True;
  envVal := GetEnvironmentVariable('FT_DYNAMIC_LATIN_SWAP');
  if (envVal = '0') or SameText(envVal, 'false') or SameText(envVal, 'no') then
    FDynamicLatinSwap := False;

  InitFallbackFamilies();
end;

destructor TFloriaFontManager.Destroy();
var
  i: Integer;
begin
  if Assigned(FFallbackFamilies) then
  begin
    FFallbackFamilies.Free();
    FFallbackFamilies := nil;
  end;

  for i := 0 to FCache.Count - 1 do
    TFloriaFont(FCache[i]).Free();
  FCache.Free();
  inherited Destroy();
end;

function TFloriaFontManager.DetectScreenDPI(): Double;
var
  envVal: string;
  valDbl: Double;
  outStr: string;
  lines: TStringList;
  i, p: Integer;
  line, dpiStr: string;
  code: Integer;
begin
  Result := 96.0;

  // 1. Explicit environment overrides: FT_DPI or FT_SCALE_FACTOR
  envVal := GetEnvironmentVariable('FT_DPI');
  if envVal <> '' then
  begin
    Val(envVal, valDbl, code);
    if (code = 0) and (valDbl > 0) then Exit(valDbl);
  end;

  envVal := GetEnvironmentVariable('FT_SCALE_FACTOR');
  if envVal <> '' then
  begin
    Val(envVal, valDbl, code);
    if (code = 0) and (valDbl > 0) then Exit(96.0 * valDbl);
  end;

  envVal := GetEnvironmentVariable('GDK_SCALE');
  if envVal <> '' then
  begin
    Val(envVal, valDbl, code);
    if (code = 0) and (valDbl > 0) then Exit(96.0 * valDbl);
  end;

  envVal := GetEnvironmentVariable('QT_SCALE_FACTOR');
  if envVal <> '' then
  begin
    Val(envVal, valDbl, code);
    if (code = 0) and (valDbl > 0) then Exit(96.0 * valDbl);
  end;

  // 2. Query Xft.dpi from xrdb
  if RunCommand('xrdb', ['-query'], outStr) and (outStr <> '') then
  begin
    lines := TStringList.Create();
    try
      lines.Text := outStr;
      for i := 0 to lines.Count - 1 do
      begin
        line := lines[i];
        p := Pos('Xft.dpi:', line);
        if p > 0 then
        begin
          dpiStr := Trim(Copy(line, p + Length('Xft.dpi:'), Length(line)));
          Val(dpiStr, valDbl, code);
          if (code = 0) and (valDbl > 0) then
          begin
            Result := valDbl;
            Exit;
          end;
        end;
      end;
    finally
      lines.Free();
    end;
  end;
end;

procedure TFloriaFontManager.SetScreenDPI(AValue: Double);
var
  i: Integer;
begin
  if AValue <= 0 then Exit;
  if Abs(FScreenDPI - AValue) < 0.1 then Exit;
  FScreenDPI := AValue;
  for i := 0 to FCache.Count - 1 do
    TFloriaFont(FCache[i]).Free();
  FCache.Clear();
  FSystemFont := nil;
end;

function TFloriaFontManager.DetectSystemFontDesc(): string;
var
  outStr: string;
begin
  Result := '';

  // 1. Try desktop settings (MATE / GNOME / Cinnamon)
  if RunCommand('gsettings', ['get', 'org.mate.interface', 'font-name'], outStr) and (Trim(outStr) <> '') then
    Result := Trim(outStr)
  else if RunCommand('gsettings', ['get', 'org.gnome.desktop.interface', 'font-name'], outStr) and (Trim(outStr) <> '') then
    Result := Trim(outStr);

  // Strip single/double quotes if present
  if (Length(Result) >= 2) and (Result[1] in ['''', '"']) and (Result[Length(Result)] = Result[1]) then
    Result := Copy(Result, 2, Length(Result) - 2);

  if Result <> '' then Exit;

  // 2. Try fontconfig default sans-serif
  if RunCommand('fc-match', ['-f', '%{family}-%{size}', 'sans-serif'], outStr) and (Trim(outStr) <> '') then
  begin
    Result := Trim(outStr);
    if Result <> '' then Exit;
  end;

  // 3. Fallback default
  Result := 'Ubuntu-11';
end;

function TFloriaFontManager.BuildCanonicalDesc(const AFamily: string; ASize: Double; ABold, AItalic: Boolean; AFaceIndex: Cardinal): string;
begin
  Result := Format('%s-%.1f', [AFamily, ASize]);
  if AFaceIndex > 0 then Result := Result + Format(':face%d', [AFaceIndex]);
  if ABold then Result := Result + ':bold';
  if AItalic then Result := Result + ':italic';
end;

procedure TFloriaFontManager.ParseFontDesc(ADesc: string; out AFamily: string; out ASize: Double; out ABold, AItalic: Boolean);
var
  Parts: TStringList;
  Base: string;
  i, LastDash, LastSpace: Integer;
  Attr: string;
  SizeStr: string;
begin
  ADesc := Trim(ADesc);
  if (Length(ADesc) >= 2) and (ADesc[1] in ['''', '"']) and (ADesc[Length(ADesc)] = ADesc[1]) then
    ADesc := Copy(ADesc, 2, Length(ADesc) - 2);

  AFamily := 'Ubuntu';
  ASize := 11.0;
  ABold := False;
  AItalic := False;

  if ADesc = '' then Exit;

  Parts := TStringList.Create();
  try
    Parts.Delimiter := ':';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := ADesc;

    if Parts.Count > 0 then
    begin
      Base := Trim(Parts[0]);
      for i := 1 to Parts.Count - 1 do
      begin
        Attr := LowerCase(Trim(Parts[i]));
        if Pos('bold', Attr) > 0 then ABold := True;
        if Pos('italic', Attr) > 0 then AItalic := True;
      end;

      LastDash := FindLastChar(Base, '-');
      if LastDash > 0 then
      begin
        SizeStr := Copy(Base, LastDash + 1, Length(Base));
        if TryStrToFloat(SizeStr, ASize) then
          AFamily := Trim(Copy(Base, 1, LastDash - 1))
        else
          AFamily := Base;
      end
      else
      begin
        LastSpace := FindLastChar(Base, ' ');
        if LastSpace > 0 then
        begin
          SizeStr := Copy(Base, LastSpace + 1, Length(Base));
          if TryStrToFloat(SizeStr, ASize) then
            AFamily := Trim(Copy(Base, 1, LastSpace - 1))
          else
            AFamily := Base;
        end
        else
          AFamily := Base;
      end;
    end;
  finally
    Parts.Free();
  end;
end;

function TFloriaFontManager.ResolveFontFile(const AFamily: string; ABold, AItalic: Boolean; out AFaceIndex: Cardinal): string;
var
  Pattern: string;
  outPath, filePath, idxStr: string;
  colonPos: Integer;
  valIdx: LongInt;
const
  StandardDirs: array[0..9] of string = (
    '/usr/share/fonts/truetype/ubuntu/Ubuntu[wdth,wght].ttf',
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    '/usr/share/fonts/truetype/noto/NotoSansThai-Regular.ttf',
    '/usr/share/fonts/truetype/noto/NotoSansDevanagari-Regular.ttf',
    '/usr/share/fonts/truetype/noto/NotoSansArabic-Regular.ttf',
    '/usr/share/fonts/truetype/noto/NotoSansHebrew-Regular.ttf',
    '/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf',
    '/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/usr/share/fonts/truetype/freefont/FreeSans.ttf'
  );
var
  i: Integer;
begin
  Result := '';
  AFaceIndex := 0;
  Pattern := AFamily;
  if ABold then Pattern := Pattern + ':bold';
  if AItalic then Pattern := Pattern + ':italic';

  // Query fontconfig
  if RunCommand('fc-match', ['-f', '%{file}:%{index}', Pattern], outPath) then
  begin
    outPath := Trim(outPath);
    colonPos := FindLastChar(outPath, ':');
    if colonPos > 0 then
    begin
      idxStr := Copy(outPath, colonPos + 1, Length(outPath));
      filePath := Copy(outPath, 1, colonPos - 1);
      if TryStrToInt(idxStr, valIdx) and (valIdx >= 0) then
        AFaceIndex := Cardinal(valIdx)
      else
        AFaceIndex := 0;
      outPath := filePath;
    end;

    if (outPath <> '') and FileExists(outPath) then
      Exit(outPath);
  end;

  // Fallback to standard directories
  for i := Low(StandardDirs) to High(StandardDirs) do
    if FileExists(StandardDirs[i]) then
      Exit(StandardDirs[i]);
end;

function TFloriaFontManager.DetectFallbackFontFamily(): string;
var
  outStr: string;
begin
  Result := '';
  if RunCommand('fc-match', ['-f', '%{family}', 'Noto Sans CJK SC'], outStr) and (Trim(outStr) <> '') then
    Exit(Trim(outStr));
  if RunCommand('fc-match', ['-f', '%{family}', 'Droid Sans Fallback'], outStr) and (Trim(outStr) <> '') then
    Exit(Trim(outStr));
  if RunCommand('fc-match', ['-f', '%{family}', ':charset=4f60'], outStr) and (Trim(outStr) <> '') then
    Exit(Trim(outStr));
  Result := 'Noto Sans CJK SC';
end;

function TFloriaFontManager.DetectSymbolFallbackFontFamily(): string;
var
  outStr: string;
const
  CandidateFamilies: array[0..3] of string = (
    'DejaVu Sans',
    'Noto Sans Symbols2',
    'FreeSans',
    'DejaVu Sans Condensed'
  );
var
  i: Integer;
begin
  Result := '';
  // 1. Try fontconfig match for heavy checkmark (U+2714) specifically
  if RunCommand('fc-match', ['-f', '%{family}', ':charset=2714'], outStr) and (Trim(outStr) <> '') then
    Exit(Trim(outStr));

  // 2. Try known ubiquitous Linux symbol font candidates
  for i := Low(CandidateFamilies) to High(CandidateFamilies) do
  begin
    if RunCommand('fc-match', ['-f', '%{family}', CandidateFamilies[i]], outStr) and (Trim(outStr) <> '') then
      Exit(Trim(outStr));
  end;

  // 3. Fallback default
  Result := 'DejaVu Sans';
end;

procedure TFloriaFontManager.InitFallbackFamilies();
begin
  if not Assigned(FFallbackFamilies) then
    FFallbackFamilies := TStringList.Create();
  FFallbackFamilies.Clear();
  // 1. CJK (Chinese / Japanese / Korean ideographs & kana/hangul)
  FFallbackFamilies.Add(DetectFallbackFontFamily());
  // 2. Thai
  FFallbackFamilies.Add('Noto Sans Thai');
  // 3. Devanagari (Hindi, Sanskrit, Marathi)
  FFallbackFamilies.Add('Noto Sans Devanagari');
  // 4. Arabic (Arabic, Persian, Urdu)
  FFallbackFamilies.Add('Noto Sans Arabic');
  // 5. Hebrew (Hebrew, Yiddish)
  FFallbackFamilies.Add('Noto Sans Hebrew');
  // 6. Symbols, Dingbats, Checkmarks, Math
  FFallbackFamilies.Add(DetectSymbolFallbackFontFamily());
  // 7. Universal Wide Unicode
  FFallbackFamilies.Add('FreeSans');
end;

function TFloriaFontManager.GetFallbackFontFamily(): string;
begin
  if Assigned(FFallbackFamilies) and (FFallbackFamilies.Count > 0) then
    Result := FFallbackFamilies[0]
  else
    Result := 'Noto Sans CJK SC';
end;

procedure TFloriaFontManager.SetFallbackFontFamily(const AValue: string);
begin
  if Assigned(FFallbackFamilies) and (FFallbackFamilies.Count > 0) then
    FFallbackFamilies[0] := AValue;
end;

function TFloriaFontManager.GetSymbolFallbackFontFamily(): string;
begin
  if Assigned(FFallbackFamilies) and (FFallbackFamilies.Count > 5) then
    Result := FFallbackFamilies[5]
  else
    Result := 'DejaVu Sans';
end;

procedure TFloriaFontManager.SetSymbolFallbackFontFamily(const AValue: string);
begin
  if Assigned(FFallbackFamilies) and (FFallbackFamilies.Count > 5) then
    FFallbackFamilies[5] := AValue;
end;

function TFloriaFontManager.FallbackFontCount(): Integer;
begin
  if Assigned(FFallbackFamilies) then
    Result := FFallbackFamilies.Count
  else
    Result := 0;
end;

function TFloriaFontManager.GetFallbackFontAt(AIndex: Integer; ASize: Double): TFloriaFont;
var
  Desc: string;
  F: TFloriaFont;
begin
  if not Assigned(FFallbackFamilies) or (AIndex < 0) or (AIndex >= FFallbackFamilies.Count) then
    Exit(nil);
  Desc := Format('%s-%.1f', [FFallbackFamilies[AIndex], ASize]);
  F := GetFont(Desc);
  if Assigned(F) then
    F.FFallbackIndex := AIndex;
  Result := F;
end;

function TFloriaFontManager.IndexOfFallbackFamily(const AFamily: string): Integer;
var
  i: Integer;
  famLower, candLower: string;
begin
  famLower := LowerCase(AFamily);
  if Assigned(FFallbackFamilies) then
  begin
    for i := 0 to FFallbackFamilies.Count - 1 do
    begin
      candLower := LowerCase(FFallbackFamilies[i]);
      if (Pos(candLower, famLower) > 0) or (Pos(famLower, candLower) > 0) then
        Exit(i);
    end;
  end;
  Result := -1;
end;

function TFloriaFontManager.GetFallbackFont(ASize: Double): TFloriaFont;
begin
  Result := GetFallbackFontAt(0, ASize);
end;

function TFloriaFontManager.GetSymbolFallbackFont(ASize: Double): TFloriaFont;
begin
  Result := GetFallbackFontAt(5, ASize);
end;

function TFloriaFontManager.GetFont(const AFontDesc: string): TFloriaFont;
var
  Fam: string;
  Sz: Double;
  B, It: Boolean;
  CanonKey: string;
  i: Integer;
  FontPath: string;
  FaceIdx: Cardinal;
  NewFont: TFloriaFont;
begin
  if AFontDesc = '' then
    Exit(GetSystemFont());

  ParseFontDesc(AFontDesc, Fam, Sz, B, It);
  FontPath := ResolveFontFile(Fam, B, It, FaceIdx);
  CanonKey := BuildCanonicalDesc(Fam, Sz, B, It, FaceIdx);

  // Search cache
  for i := 0 to FCache.Count - 1 do
  begin
    NewFont := TFloriaFont(FCache[i]);
    if SameText(NewFont.FontDesc, CanonKey) and (Abs(NewFont.DPI - FScreenDPI) < 0.1) then
      Exit(NewFont);
  end;

  // Resolve font path and create
  NewFont := TFloriaFont.Create(Fam, Sz, B, It, FontPath, FaceIdx, FScreenDPI, FFontGamma);
  NewFont.FFontDesc := CanonKey;
  FCache.Add(NewFont);

  Result := NewFont;
end;

procedure TFloriaFontManager.SetFontGamma(AValue: Double);
var
  i: Integer;
begin
  if (AValue <= 0.0) or (Abs(FFontGamma - AValue) < 0.001) then Exit;
  FFontGamma := AValue;
  for i := 0 to FCache.Count - 1 do
    TFloriaFont(FCache[i]).Gamma := AValue;
end;

function TFloriaFontManager.GetSystemFont(): TFloriaFont;
begin
  if not Assigned(FSystemFont) then
    FSystemFont := GetFont(FDefaultFontDesc);
  Result := FSystemFont;
end;

procedure TFloriaFontManager.SetSystemFontDesc(const AFontDesc: string);
begin
  FDefaultFontDesc := AFontDesc;
  FSystemFont := nil; // Invalidate system font pointer to reload on next access
end;

function FloriaFontManager(): TFloriaFontManager;
begin
  if not Assigned(uFontManager) then
    uFontManager := TFloriaFontManager.Create();
  Result := uFontManager;
end;

function FloriaGetSystemFont(): TFloriaFont;
begin
  Result := FloriaFontManager().GetSystemFont();
end;

function FloriaGetScreenDPI(): Double;
begin
  Result := FloriaFontManager().ScreenDPI;
end;

procedure FloriaSetScreenDPI(ADPI: Double);
begin
  FloriaFontManager().ScreenDPI := ADPI;
end;

function FloriaGetFontGamma(): Double;
begin
  Result := FloriaFontManager().FontGamma;
end;

procedure FloriaSetFontGamma(AGamma: Double);
begin
  FloriaFontManager().FontGamma := AGamma;
end;

function FloriaGetFallbackFont(ASize: Double): TFloriaFont;
begin
  Result := FloriaFontManager().GetFallbackFont(ASize);
end;

function FloriaGetSymbolFallbackFont(ASize: Double): TFloriaFont;
begin
  Result := FloriaFontManager().GetSymbolFallbackFont(ASize);
end;

// Backward-compatibility wrappers
function FtFontManager(): TFtFontManager;
begin
  Result := FloriaFontManager();
end;

function FtGetSystemFont(): TFtFont;
begin
  Result := FloriaGetSystemFont();
end;

function FtGetFallbackFont(ASize: Double): TFtFont;
begin
  Result := FloriaGetFallbackFont(ASize);
end;

function FtGetSymbolFallbackFont(ASize: Double): TFtFont;
begin
  Result := FloriaGetSymbolFallbackFont(ASize);
end;

function FtGetScreenDPI(): Double;
begin
  Result := FloriaGetScreenDPI();
end;

procedure FtSetScreenDPI(ADPI: Double);
begin
  FloriaSetScreenDPI(ADPI);
end;

function FtGetFontGamma(): Double;
begin
  Result := FloriaGetFontGamma();
end;

procedure FtSetFontGamma(AGamma: Double);
begin
  FloriaSetFontGamma(AGamma);
end;

finalization
  if Assigned(uFontManager) then
  begin
    uFontManager.Free();
    uFontManager := nil;
  end;

end.
