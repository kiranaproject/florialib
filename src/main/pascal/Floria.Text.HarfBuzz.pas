unit Floria.Text.HarfBuzz;

// Floria.Text.HarfBuzz
// ====================
// Dynamic loader and OpenType text shaping engine using HarfBuzz (libharfbuzz.so.0).
//
// Capabilities:
// - Dynamic loading of HarfBuzz via dynlibs (zero hard binary dependency;
//   falls back gracefully to 1:1 character metrics if HarfBuzz is unavailable).
// - OpenType GSUB & GPOS shaping: ligatures (liga, calt), cursive Arabic joining,
//   Indic conjuncts & reordering, Thai tone stacking, and kerning.
// - Integration with Floria.Unicode.BiDi: shapes visual unidirectional runs
//   with explicit HB_DIRECTION_LTR and HB_DIRECTION_RTL.
// - High-level API: FloriaShapeRun and FloriaShapeText.

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, dynlibs,
  Floria.Font,
  Floria.Unicode.BiDi;

const
  HB_DIRECTION_INVALID = 0;
  HB_DIRECTION_LTR     = 4;
  HB_DIRECTION_RTL     = 5;
  HB_DIRECTION_TTB     = 6;
  HB_DIRECTION_BTT     = 7;

type
  // Opaque HarfBuzz pointers
  hb_blob_t   = Pointer;
  hb_face_t   = Pointer;
  hb_font_t   = Pointer;
  hb_buffer_t = Pointer;

  hb_direction_t = LongInt;
  hb_script_t    = LongInt;

  // HarfBuzz glyph info (specifies glyph ID and character cluster)
  hb_glyph_info_t = record
    codepoint : Cardinal; // Glyph index in font
    mask      : Cardinal;
    cluster   : Cardinal; // Character index in source text
    var1      : Cardinal;
    var2      : Cardinal;
  end;
  hb_glyph_info_p = ^hb_glyph_info_t;

  // HarfBuzz glyph position (scaled by font scale, e.g. 26.6 fixed point)
  hb_glyph_position_t = record
    x_advance : LongInt;
    y_advance : LongInt;
    x_offset  : LongInt;
    y_offset  : LongInt;
    var_      : Cardinal;
  end;
  hb_glyph_position_p = ^hb_glyph_position_t;

  // Floria Shaped Glyph (in device pixel coordinates)
  TFloriaShapedGlyph = record
    GlyphIndex : Cardinal; // Font glyph ID
    Cluster    : Cardinal; // Source character byte index
    XAdvance   : Double;   // In device pixels
    YAdvance   : Double;   // In device pixels
    XOffset    : Double;   // In device pixels
    YOffset    : Double;   // In device pixels
  end;
  TFloriaShapedRun = array of TFloriaShapedGlyph;

  // Function pointer signatures for dynamic HarfBuzz loading
  Thb_version_string              = function(): PChar; cdecl;
  Thb_buffer_create               = function(): hb_buffer_t; cdecl;
  Thb_buffer_destroy              = procedure(buffer: hb_buffer_t); cdecl;
  Thb_buffer_reset                = procedure(buffer: hb_buffer_t); cdecl;
  Thb_buffer_add_utf8             = procedure(buffer: hb_buffer_t; text: PChar; text_length: LongInt; item_offset: Cardinal; item_length: LongInt); cdecl;
  Thb_buffer_set_direction        = procedure(buffer: hb_buffer_t; direction: hb_direction_t); cdecl;
  Thb_buffer_set_script           = procedure(buffer: hb_buffer_t; script: hb_script_t); cdecl;
  Thb_buffer_guess_segment_properties = procedure(buffer: hb_buffer_t); cdecl;
  Thb_buffer_get_length           = function(buffer: hb_buffer_t): Cardinal; cdecl;
  Thb_buffer_get_glyph_infos      = function(buffer: hb_buffer_t; length: PCardinal): hb_glyph_info_p; cdecl;
  Thb_buffer_get_glyph_positions  = function(buffer: hb_buffer_t; length: PCardinal): hb_glyph_position_p; cdecl;
  Thb_blob_create_from_file       = function(file_name: PChar): hb_blob_t; cdecl;
  Thb_blob_destroy                = procedure(blob: hb_blob_t); cdecl;
  Thb_face_create                 = function(blob: hb_blob_t; index: Cardinal): hb_face_t; cdecl;
  Thb_face_destroy                = procedure(face: hb_face_t); cdecl;
  Thb_font_create                 = function(face: hb_face_t): hb_font_t; cdecl;
  Thb_font_destroy                = procedure(font: hb_font_t); cdecl;
  Thb_ot_font_set_funcs           = procedure(font: hb_font_t); cdecl;
  Thb_font_set_scale              = procedure(font: hb_font_t; x_scale: LongInt; y_scale: LongInt); cdecl;
  Thb_shape                       = procedure(font: hb_font_t; buffer: hb_buffer_t; features: Pointer; num_features: Cardinal); cdecl;

  // THarfBuzzEngine: Dynamic library loader and shaper manager
  THarfBuzzEngine = class
  private
    FLibHandle: TLibHandle;
    FAvailable: Boolean;
    FVersion  : string;
    procedure LoadSymbols();
  public
    // Function pointers
    hb_version_string              : Thb_version_string;
    hb_buffer_create               : Thb_buffer_create;
    hb_buffer_destroy              : Thb_buffer_destroy;
    hb_buffer_reset                : Thb_buffer_reset;
    hb_buffer_add_utf8             : Thb_buffer_add_utf8;
    hb_buffer_set_direction        : Thb_buffer_set_direction;
    hb_buffer_set_script           : Thb_buffer_set_script;
    hb_buffer_guess_segment_properties : Thb_buffer_guess_segment_properties;
    hb_buffer_get_length           : Thb_buffer_get_length;
    hb_buffer_get_glyph_infos      : Thb_buffer_get_glyph_infos;
    hb_buffer_get_glyph_positions  : Thb_buffer_get_glyph_positions;
    hb_blob_create_from_file       : Thb_blob_create_from_file;
    hb_blob_destroy                : Thb_blob_destroy;
    hb_face_create                 : Thb_face_create;
    hb_face_destroy                : Thb_face_destroy;
    hb_font_create                 : Thb_font_create;
    hb_font_destroy                : Thb_font_destroy;
    hb_ot_font_set_funcs           : Thb_ot_font_set_funcs;
    hb_font_set_scale              : Thb_font_set_scale;
    hb_shape                       : Thb_shape;

    constructor Create();
    destructor Destroy(); override;

    property Available: Boolean read FAvailable;
    property Version  : string  read FVersion;
  end;

// Singleton accessor for HarfBuzz engine
function FloriaHarfBuzz(): THarfBuzzEngine;

// Shapes a single unidirectional run with a specific direction (LTR or RTL)
function FloriaShapeRun(AFont: TFloriaFont; const AText: string;
                        ADirection: TFloriaBiDiDirection): TFloriaShapedRun;

// Full text shaping pipeline: resolves BiDi runs, then shapes each run into
// visual order with accurate font metrics, ligatures, and glyph positioning.
function FloriaShapeText(AFont: TFloriaFont; const AText: string;
                         ABaseDir: TFloriaBiDiBaseDir = fbbAuto): TFloriaShapedRun;

// Calculates total horizontal width of a shaped run
function FloriaShapedRunWidth(const ARun: TFloriaShapedRun): Double;

implementation

var
  gHarfBuzzInstance: THarfBuzzEngine = nil;

function FloriaHarfBuzz(): THarfBuzzEngine;
begin
  if not Assigned(gHarfBuzzInstance) then
    gHarfBuzzInstance := THarfBuzzEngine.Create();
  Result := gHarfBuzzInstance;
end;

// ============================================================================
// THarfBuzzEngine Dynamic Loader
// ============================================================================

constructor THarfBuzzEngine.Create();
const
  LIB_CANDIDATES: array[0..3] of string = (
    'libharfbuzz.so.0',
    'libharfbuzz.so',
    'libharfbuzz.dylib',
    'harfbuzz.dll'
  );
var
  I: Integer;
begin
  inherited Create();
  FLibHandle := NilHandle;
  FAvailable := False;
  FVersion   := '';

  for I := Low(LIB_CANDIDATES) to High(LIB_CANDIDATES) do
  begin
    FLibHandle := SafeLoadLibrary(LIB_CANDIDATES[I]);
    if FLibHandle <> NilHandle then
      Break;
  end;

  if FLibHandle <> NilHandle then
    LoadSymbols();
end;

destructor THarfBuzzEngine.Destroy();
begin
  if FLibHandle <> NilHandle then
  begin
    UnloadLibrary(FLibHandle);
    FLibHandle := NilHandle;
  end;
  inherited Destroy();
end;

procedure THarfBuzzEngine.LoadSymbols();
begin
  Pointer(hb_version_string)              := GetProcedureAddress(FLibHandle, 'hb_version_string');
  Pointer(hb_buffer_create)               := GetProcedureAddress(FLibHandle, 'hb_buffer_create');
  Pointer(hb_buffer_destroy)              := GetProcedureAddress(FLibHandle, 'hb_buffer_destroy');
  Pointer(hb_buffer_reset)                := GetProcedureAddress(FLibHandle, 'hb_buffer_reset');
  Pointer(hb_buffer_add_utf8)             := GetProcedureAddress(FLibHandle, 'hb_buffer_add_utf8');
  Pointer(hb_buffer_set_direction)        := GetProcedureAddress(FLibHandle, 'hb_buffer_set_direction');
  Pointer(hb_buffer_set_script)           := GetProcedureAddress(FLibHandle, 'hb_buffer_set_script');
  Pointer(hb_buffer_guess_segment_properties) := GetProcedureAddress(FLibHandle, 'hb_buffer_guess_segment_properties');
  Pointer(hb_buffer_get_length)           := GetProcedureAddress(FLibHandle, 'hb_buffer_get_length');
  Pointer(hb_buffer_get_glyph_infos)      := GetProcedureAddress(FLibHandle, 'hb_buffer_get_glyph_infos');
  Pointer(hb_buffer_get_glyph_positions)  := GetProcedureAddress(FLibHandle, 'hb_buffer_get_glyph_positions');
  Pointer(hb_blob_create_from_file)       := GetProcedureAddress(FLibHandle, 'hb_blob_create_from_file');
  Pointer(hb_blob_destroy)                := GetProcedureAddress(FLibHandle, 'hb_blob_destroy');
  Pointer(hb_face_create)                 := GetProcedureAddress(FLibHandle, 'hb_face_create');
  Pointer(hb_face_destroy)                := GetProcedureAddress(FLibHandle, 'hb_face_destroy');
  Pointer(hb_font_create)                 := GetProcedureAddress(FLibHandle, 'hb_font_create');
  Pointer(hb_font_destroy)                := GetProcedureAddress(FLibHandle, 'hb_font_destroy');
  Pointer(hb_ot_font_set_funcs)           := GetProcedureAddress(FLibHandle, 'hb_ot_font_set_funcs');
  Pointer(hb_font_set_scale)              := GetProcedureAddress(FLibHandle, 'hb_font_set_scale');
  Pointer(hb_shape)                       := GetProcedureAddress(FLibHandle, 'hb_shape');

  if Assigned(hb_buffer_create) and
     Assigned(hb_buffer_destroy) and
     Assigned(hb_buffer_add_utf8) and
     Assigned(hb_shape) and
     Assigned(hb_blob_create_from_file) and
     Assigned(hb_face_create) and
     Assigned(hb_font_create) and
     Assigned(hb_ot_font_set_funcs) and
     Assigned(hb_font_set_scale) and
     Assigned(hb_buffer_get_glyph_infos) and
     Assigned(hb_buffer_get_glyph_positions) then
  begin
    FAvailable := True;
    if Assigned(hb_version_string) then
      FVersion := StrPas(hb_version_string())
    else
      FVersion := 'Unknown';
  end
  else
    FAvailable := False;
end;

// ============================================================================
// Fallback Simple Shaper (1:1 character to glyph metrics)
// ============================================================================

function FallbackSimpleShape(AFont: TFloriaFont; const AText: string): TFloriaShapedRun;
var
  P: PChar;
  CP: Cardinal;
  Count: Integer;
  PixelHeight: Double;
  DefaultAdv: Double;
begin
  SetLength(Result, 0);
  if (AFont = nil) or (AText = '') then Exit;

  PixelHeight := AFont.Size * (AFont.DPI / 72.0);
  DefaultAdv  := PixelHeight * 0.55;

  P := PChar(AText);
  Count := 0;
  while FloriaUTF8NextChar(P, CP) do
  begin
    SetLength(Result, Count + 1);
    Result[Count].GlyphIndex := CP; // Fallback uses Unicode code point
    Result[Count].Cluster    := Count;
    Result[Count].XAdvance   := DefaultAdv;
    Result[Count].YAdvance   := 0.0;
    Result[Count].XOffset    := 0.0;
    Result[Count].YOffset    := 0.0;
    Inc(Count);
  end;
end;

// ============================================================================
// Shaping Implementations
// ============================================================================

function FloriaShapeRun(AFont: TFloriaFont; const AText: string;
                        ADirection: TFloriaBiDiDirection): TFloriaShapedRun;
var
  HB: THarfBuzzEngine;
  Blob: hb_blob_t;
  Face: hb_face_t;
  Font: hb_font_t;
  Buffer: hb_buffer_t;
  GlyphCount: Cardinal;
  Infos: hb_glyph_info_p;
  Positions: hb_glyph_position_p;
  I: Integer;
  PixelHeight: Double;
  ScaleVal: LongInt;
  HBDirection: hb_direction_t;
begin
  SetLength(Result, 0);
  if (AFont = nil) or (AText = '') then Exit;

  HB := FloriaHarfBuzz();
  // Fall back if HarfBuzz is not present on system or font path is empty
  if (not HB.Available) or (AFont.FontPath = '') or (not FileExists(AFont.FontPath)) then
    Exit(FallbackSimpleShape(AFont, AText));

  // 1. Create HarfBuzz font via OpenType font funcs
  Blob := HB.hb_blob_create_from_file(PChar(AFont.FontPath));
  if Blob = nil then
    Exit(FallbackSimpleShape(AFont, AText));

  Face := HB.hb_face_create(Blob, AFont.FaceIndex);
  Font := HB.hb_font_create(Face);
  HB.hb_ot_font_set_funcs(Font);

  // Set font scale to 26.6 fixed point (pixelHeight * 64)
  PixelHeight := AFont.Size * (AFont.DPI / 72.0);
  ScaleVal := Round(PixelHeight * 64.0);
  HB.hb_font_set_scale(Font, ScaleVal, ScaleVal);

  // 2. Prepare HarfBuzz buffer
  Buffer := HB.hb_buffer_create();
  try
    HB.hb_buffer_add_utf8(Buffer, PChar(AText), Length(AText), 0, Length(AText));

    if ADirection = fbdRTL then
      HBDirection := HB_DIRECTION_RTL
    else
      HBDirection := HB_DIRECTION_LTR;

    HB.hb_buffer_set_direction(Buffer, HBDirection);
    HB.hb_buffer_guess_segment_properties(Buffer);

    // 3. Shape the text!
    HB.hb_shape(Font, Buffer, nil, 0);

    // 4. Extract shaped glyphs
    GlyphCount := 0;
    Infos := HB.hb_buffer_get_glyph_infos(Buffer, @GlyphCount);
    Positions := HB.hb_buffer_get_glyph_positions(Buffer, @GlyphCount);

    SetLength(Result, GlyphCount);
    for I := 0 to Integer(GlyphCount) - 1 do
    begin
      Result[I].GlyphIndex := Infos[I].codepoint;
      Result[I].Cluster    := Infos[I].cluster;
      // Convert 26.6 fixed point back to device pixels
      Result[I].XAdvance   := Positions[I].x_advance / 64.0;
      Result[I].YAdvance   := Positions[I].y_advance / 64.0;
      Result[I].XOffset    := Positions[I].x_offset  / 64.0;
      Result[I].YOffset    := Positions[I].y_offset  / 64.0;
    end;
  finally
    HB.hb_buffer_destroy(Buffer);
    HB.hb_font_destroy(Font);
    HB.hb_face_destroy(Face);
    HB.hb_blob_destroy(Blob);
  end;
end;

function FloriaShapeText(AFont: TFloriaFont; const AText: string;
                         ABaseDir: TFloriaBiDiBaseDir = fbbAuto): TFloriaShapedRun;
var
  Runs: TFloriaBiDiRunArray;
  I, J: Integer;
  PartRun: TFloriaShapedRun;
  TotalGlyphs: Integer;
  Offset: Integer;
begin
  SetLength(Result, 0);
  if (AFont = nil) or (AText = '') then Exit;

  // 1. Resolve text into visual unidirectional runs via BiDi engine
  Runs := TFloriaBiDi.GetVisualRuns(AText, ABaseDir);
  if Length(Runs) = 0 then Exit;

  // Fast path: single run
  if Length(Runs) = 1 then
    Exit(FloriaShapeRun(AFont, Runs[0].Text, Runs[0].Direction));

  // Multi-run: shape each run and concatenate
  TotalGlyphs := 0;
  for I := 0 to High(Runs) do
  begin
    PartRun := FloriaShapeRun(AFont, Runs[I].Text, Runs[I].Direction);
    Offset := TotalGlyphs;
    TotalGlyphs := TotalGlyphs + Length(PartRun);
    SetLength(Result, TotalGlyphs);
    for J := 0 to High(PartRun) do
      Result[Offset + J] := PartRun[J];
  end;
end;

function FloriaShapedRunWidth(const ARun: TFloriaShapedRun): Double;
var
  I: Integer;
begin
  Result := 0.0;
  for I := 0 to High(ARun) do
    Result := Result + ARun[I].XAdvance;
end;

initialization

finalization
  if Assigned(gHarfBuzzInstance) then
  begin
    gHarfBuzzInstance.Free();
    gHarfBuzzInstance := nil;
  end;

end.
