unit Floria.CSS.Values;

// Floria.CSS.Values
// =================
// Typed value representations and value parsers for the Floria CSS subsystem.
//
// Provides rich types for:
//   - TCSSColor       (32-bit RGBA, hex #RGB/#RGBA/#RRGGBB/#RRGGBBAA, rgb()/rgba(), named colors)
//   - TCSSUnit        (px, em, rem, %, pt, vw, vh, auto, etc.)
//   - TCSSLength      (value + unit, conversion to absolute pixels)
//   - TCSSBox         (4-sided box model for margin, padding, border-widths)
//   - TCSSBorderStyle (none, solid, dashed, dotted, double, etc.)
//   - TCSSBorderSide  (composite width, style, color)
//   - Layout enums    (TCSSDisplay, TCSSPosition, TCSSVisibility, TCSSOverflow,
//                      TCSSBoxSizing, TCSSFlexDirection, TCSSFlexWrap,
//                      TCSSJustifyContent, TCSSAlignItems, TCSSFontStyle,
//                      TCSSTextAlign, TCSSTextDecoration)
//
// All parser helpers support both raw strings and AST component value nodes
// (TObjectList of TCSSNode from Floria.CSS.AST).

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, Contnrs, SysUtils, Floria.CSS.Types, Floria.CSS.AST;

type
  // ── CSS Color ─────────────────────────────────────────────────────────────

  TCSSColor = record
    R : Byte;
    G : Byte;
    B : Byte;
    A : Byte;

    class function FromRGBA(const AR, AG, AB: Byte; const AA: Byte = 255): TCSSColor; static;
    class function FromHex(const AHex: AnsiString; out AColor: TCSSColor): Boolean; static;
    class function FromName(const AName: AnsiString; out AColor: TCSSColor): Boolean; static;
    class function TryParse(const AStr: AnsiString; out AColor: TCSSColor): Boolean; static;
    class function Transparent(): TCSSColor; static;
    class function Black(): TCSSColor; static;
    class function White(): TCSSColor; static;

    function ToHex(const AIncludeAlpha: Boolean = False): AnsiString;
    function ToRGBAString(): AnsiString;
    function Equals(const AOther: TCSSColor): Boolean;
  end;

  // ── CSS Units & Lengths ───────────────────────────────────────────────────

  TCSSUnit = (
    cuNone,      // unitless number (0, line-height: 1.5, opacity: 0.8)
    cuPx,        // pixels
    cuEm,        // relative to font-size of element
    cuRem,       // relative to font-size of root element
    cuPercent,   // percentage %
    cuPt,        // points (1pt = 1.333333px)
    cuVw,        // 1% of viewport width
    cuVh,        // 1% of viewport height
    cuAuto,      // 'auto' keyword
    cuInherit,   // 'inherit' keyword
    cuInitial,   // 'initial' keyword
    cuUnset      // 'unset' keyword
  );

  TCSSLength = record
    Value : Double;
    Unit_ : TCSSUnit;

    class function Px(const AVal: Double): TCSSLength; static;
    class function Em(const AVal: Double): TCSSLength; static;
    class function Rem(const AVal: Double): TCSSLength; static;
    class function Percent(const AVal: Double): TCSSLength; static;
    class function Pt(const AVal: Double): TCSSLength; static;
    class function None(const AVal: Double): TCSSLength; static;
    class function Auto(): TCSSLength; static;
    class function Zero(): TCSSLength; static;
    class function TryParse(const AStr: AnsiString; out ALength: TCSSLength): Boolean; static;

    function ToPixels(const ABaseFontSize: Double = 16.0; const AParentSize: Double = 0.0): Double;
    function IsAuto(): Boolean;
    function IsZero(): Boolean;
    function ToString(): AnsiString;
    function Equals(const AOther: TCSSLength): Boolean;
  end;

  // ── CSS Box Model (4 sides) ───────────────────────────────────────────────

  TCSSBox = record
    Top    : TCSSLength;
    Right  : TCSSLength;
    Bottom : TCSSLength;
    Left   : TCSSLength;

    class function All(const AVal: TCSSLength): TCSSBox; static;
    class function Symmetric(const AVert, AHoriz: TCSSLength): TCSSBox; static;
    class function TRBL(const ATop, ARight, ABottom, ALeft: TCSSLength): TCSSBox; static;
    class function Zero(): TCSSBox; static;
    function Equals(const AOther: TCSSBox): Boolean;
  end;

  // ── CSS Enumerated Types ──────────────────────────────────────────────────

  TCSSDisplay = (
    cdInline,
    cdBlock,
    cdInlineBlock,
    cdFlex,
    cdInlineFlex,
    cdGrid,
    cdNone
  );

  TCSSPosition = (
    cpStatic,
    cpRelative,
    cpAbsolute,
    cpFixed,
    cpSticky
  );

  TCSSVisibility = (
    cvVisible,
    cvHidden,
    cvCollapse
  );

  TCSSOverflow = (
    coVisible,
    coHidden,
    coScroll,
    coAuto
  );

  TCSSBorderStyle = (
    cbsNone,
    cbsHidden,
    cbsDotted,
    cbsDashed,
    cbsSolid,
    cbsDouble,
    cbsGroove,
    cbsRidge,
    cbsInset,
    cbsOutset
  );

  TCSSBoxSizing = (
    cbsContentBox,
    cbsBorderBox
  );

  TCSSFlexDirection = (
    cfdRow,
    cfdRowReverse,
    cfdColumn,
    cfdColumnReverse
  );

  TCSSFlexWrap = (
    cfwNowrap,
    cfwWrap,
    cfwWrapReverse
  );

  TCSSJustifyContent = (
    cjcFlexStart,
    cjcFlexEnd,
    cjcCenter,
    cjcSpaceBetween,
    cjcSpaceAround,
    cjcSpaceEvenly
  );

  TCSSAlignItems = (
    caiStretch,
    caiFlexStart,
    caiFlexEnd,
    caiCenter,
    caiBaseline
  );

  TCSSFontStyle = (
    cfsNormal,
    cfsItalic,
    cfsOblique
  );

  TCSSTextAlign = (
    ctaLeft,
    ctaRight,
    ctaCenter,
    ctaJustify
  );

  TCSSTextDecoration = (
    ctdNone,
    ctdUnderline,
    ctdOverline,
    ctdLineThrough
  );

  // ── Composite Border Side ─────────────────────────────────────────────────

  TCSSBorderSide = record
    Width : TCSSLength;
    Style : TCSSBorderStyle;
    Color : TCSSColor;
    function Equals(const AOther: TCSSBorderSide): Boolean;
  end;

// ── Enum Parser & Formatter Functions ───────────────────────────────────────

function TryParseDisplay(const AStr: AnsiString; out AVal: TCSSDisplay): Boolean;
function DisplayToString(const AVal: TCSSDisplay): AnsiString;

function TryParsePosition(const AStr: AnsiString; out AVal: TCSSPosition): Boolean;
function PositionToString(const AVal: TCSSPosition): AnsiString;

function TryParseVisibility(const AStr: AnsiString; out AVal: TCSSVisibility): Boolean;
function VisibilityToString(const AVal: TCSSVisibility): AnsiString;

function TryParseOverflow(const AStr: AnsiString; out AVal: TCSSOverflow): Boolean;
function OverflowToString(const AVal: TCSSOverflow): AnsiString;

function TryParseBorderStyle(const AStr: AnsiString; out AVal: TCSSBorderStyle): Boolean;
function BorderStyleToString(const AVal: TCSSBorderStyle): AnsiString;

function TryParseBoxSizing(const AStr: AnsiString; out AVal: TCSSBoxSizing): Boolean;
function BoxSizingToString(const AVal: TCSSBoxSizing): AnsiString;

function TryParseFlexDirection(const AStr: AnsiString; out AVal: TCSSFlexDirection): Boolean;
function FlexDirectionToString(const AVal: TCSSFlexDirection): AnsiString;

function TryParseFlexWrap(const AStr: AnsiString; out AVal: TCSSFlexWrap): Boolean;
function FlexWrapToString(const AVal: TCSSFlexWrap): AnsiString;

function TryParseJustifyContent(const AStr: AnsiString; out AVal: TCSSJustifyContent): Boolean;
function JustifyContentToString(const AVal: TCSSJustifyContent): AnsiString;

function TryParseAlignItems(const AStr: AnsiString; out AVal: TCSSAlignItems): Boolean;
function AlignItemsToString(const AVal: TCSSAlignItems): AnsiString;

function TryParseFontStyle(const AStr: AnsiString; out AVal: TCSSFontStyle): Boolean;
function FontStyleToString(const AVal: TCSSFontStyle): AnsiString;

function TryParseTextAlign(const AStr: AnsiString; out AVal: TCSSTextAlign): Boolean;
function TextAlignToString(const AVal: TCSSTextAlign): AnsiString;

function TryParseTextDecoration(const AStr: AnsiString; out AVal: TCSSTextDecoration): Boolean;
function TextDecorationToString(const AVal: TCSSTextDecoration): AnsiString;

// ── AST Node Parsers ────────────────────────────────────────────────────────

function ParseColorFromNode(const ANode: TCSSNode; out AColor: TCSSColor): Boolean;
function ParseColorFromNodes(const ANodes: TObjectList; out AColor: TCSSColor): Boolean;

function ParseLengthFromNode(const ANode: TCSSNode; out ALength: TCSSLength): Boolean;
function ParseLengthFromNodes(const ANodes: TObjectList; out ALength: TCSSLength): Boolean;

function ParseBoxFromNodes(const ANodes: TObjectList; out ABox: TCSSBox): Boolean;

function ParseBorderSideFromNodes(const ANodes: TObjectList; out ABorder: TCSSBorderSide): Boolean;

implementation

var
  CSSFormatSettings: TFormatSettings;

// ── Helper Utilities ────────────────────────────────────────────────────────

function HexVal(const C: Char): Integer;
begin
  case C of
    '0'..'9': Result := Ord(C) - Ord('0');
    'a'..'f': Result := Ord(C) - Ord('a') + 10;
    'A'..'F': Result := Ord(C) - Ord('A') + 10;
  else
    Result := -1;
  end;
end;

function TrimString(const S: AnsiString): AnsiString;
begin
  Result := Trim(S);
end;

function FilterWhitespaceNodes(const ANodes: TObjectList): TObjectList;
var
  I   : Integer;
  Node: TCSSNode;
begin
  Result := TObjectList.Create(False); // does not own nodes
  if ANodes = nil then
    Exit;
  for I := 0 to ANodes.Count - 1 do
  begin
    Node := TCSSNode(ANodes[I]);
    if (Node.NodeType = cntPreservedToken) and
       (TCSSPreservedToken(Node).Token.TokenType = cttWhitespace) then
      Continue;
    Result.Add(Node);
  end;
end;

// ── TCSSColor ───────────────────────────────────────────────────────────────

class function TCSSColor.FromRGBA(const AR, AG, AB: Byte; const AA: Byte): TCSSColor;
begin
  Result.R := AR;
  Result.G := AG;
  Result.B := AB;
  Result.A := AA;
end;

class function TCSSColor.Transparent(): TCSSColor;
begin
  Result := FromRGBA(0, 0, 0, 0);
end;

class function TCSSColor.Black(): TCSSColor;
begin
  Result := FromRGBA(0, 0, 0, 255);
end;

class function TCSSColor.White(): TCSSColor;
begin
  Result := FromRGBA(255, 255, 255, 255);
end;

class function TCSSColor.FromHex(const AHex: AnsiString; out AColor: TCSSColor): Boolean;
var
  S      : AnsiString;
  Len    : Integer;
  V      : array[1..8] of Integer;
  I      : Integer;
begin
  Result := False;
  S := TrimString(AHex);
  if (Length(S) > 0) and (S[1] = '#') then
    Delete(S, 1, 1);
  Len := Length(S);
  if not (Len in [3, 4, 6, 8]) then
    Exit;

  for I := 1 to Len do
  begin
    V[I] := HexVal(S[I]);
    if V[I] < 0 then
      Exit;
  end;

  case Len of
    3: // #RGB -> RRGGBB FF
      AColor := FromRGBA((V[1] shl 4) or V[1], (V[2] shl 4) or V[2], (V[3] shl 4) or V[3], 255);
    4: // #RGBA -> RRGGBBAA
      AColor := FromRGBA((V[1] shl 4) or V[1], (V[2] shl 4) or V[2], (V[3] shl 4) or V[3], (V[4] shl 4) or V[4]);
    6: // #RRGGBB
      AColor := FromRGBA((V[1] shl 4) or V[2], (V[3] shl 4) or V[4], (V[5] shl 4) or V[6], 255);
    8: // #RRGGBBAA
      AColor := FromRGBA((V[1] shl 4) or V[2], (V[3] shl 4) or V[4], (V[5] shl 4) or V[6], (V[7] shl 4) or V[8]);
  end;
  Result := True;
end;

class function TCSSColor.FromName(const AName: AnsiString; out AColor: TCSSColor): Boolean;
var
  S: AnsiString;
begin
  Result := True;
  S := LowerCase(TrimString(AName));
  if S = 'transparent' then AColor := Transparent()
  else if S = 'black' then AColor := FromRGBA(0, 0, 0, 255)
  else if S = 'white' then AColor := FromRGBA(255, 255, 255, 255)
  else if S = 'red' then AColor := FromRGBA(255, 0, 0, 255)
  else if S = 'green' then AColor := FromRGBA(0, 128, 0, 255)
  else if S = 'blue' then AColor := FromRGBA(0, 0, 255, 255)
  else if S = 'yellow' then AColor := FromRGBA(255, 255, 0, 255)
  else if S = 'cyan' then AColor := FromRGBA(0, 255, 255, 255)
  else if S = 'magenta' then AColor := FromRGBA(255, 0, 255, 255)
  else if (S = 'gray') or (S = 'grey') then AColor := FromRGBA(128, 128, 128, 255)
  else if (S = 'lightgray') or (S = 'lightgrey') then AColor := FromRGBA(211, 211, 211, 255)
  else if (S = 'darkgray') or (S = 'darkgrey') then AColor := FromRGBA(169, 169, 169, 255)
  else if S = 'silver' then AColor := FromRGBA(192, 192, 192, 255)
  else if S = 'maroon' then AColor := FromRGBA(128, 0, 0, 255)
  else if S = 'olive' then AColor := FromRGBA(128, 128, 0, 255)
  else if S = 'lime' then AColor := FromRGBA(0, 255, 0, 255)
  else if S = 'aqua' then AColor := FromRGBA(0, 255, 255, 255)
  else if S = 'teal' then AColor := FromRGBA(0, 128, 128, 255)
  else if S = 'navy' then AColor := FromRGBA(0, 0, 128, 255)
  else if S = 'fuchsia' then AColor := FromRGBA(255, 0, 255, 255)
  else if S = 'purple' then AColor := FromRGBA(128, 0, 128, 255)
  else if S = 'orange' then AColor := FromRGBA(255, 165, 0, 255)
  else if S = 'pink' then AColor := FromRGBA(255, 192, 203, 255)
  else if S = 'brown' then AColor := FromRGBA(165, 42, 42, 255)
  else if S = 'gold' then AColor := FromRGBA(255, 215, 0, 255)
  else if S = 'indigo' then AColor := FromRGBA(75, 0, 130, 255)
  else if S = 'violet' then AColor := FromRGBA(238, 130, 238, 255)
  else
    Result := False;
end;

function ParseChannelVal(const S: AnsiString; out Val: Byte): Boolean;
var
  Trimmed: AnsiString;
  D      : Double;
  IntVal : Integer;
begin
  Result := False;
  Trimmed := TrimString(S);
  if Length(Trimmed) = 0 then
    Exit;
  if Trimmed[Length(Trimmed)] = '%' then
  begin
    if TryStrToFloat(Copy(Trimmed, 1, Length(Trimmed) - 1), D, CSSFormatSettings) then
    begin
      if D < 0 then D := 0 else if D > 100 then D := 100;
      Val := Round(D * 255.0 / 100.0);
      Result := True;
    end;
  end
  else
  begin
    if TryStrToInt(Trimmed, IntVal) then
    begin
      if IntVal < 0 then IntVal := 0 else if IntVal > 255 then IntVal := 255;
      Val := Byte(IntVal);
      Result := True;
    end
    else if TryStrToFloat(Trimmed, D, CSSFormatSettings) then
    begin
      if D < 0 then D := 0 else if D > 255 then D := 255;
      Val := Round(D);
      Result := True;
    end;
  end;
end;

function ParseAlphaVal(const S: AnsiString; out Val: Byte): Boolean;
var
  Trimmed: AnsiString;
  D      : Double;
begin
  Result := False;
  Trimmed := TrimString(S);
  if Length(Trimmed) = 0 then
    Exit;
  if Trimmed[Length(Trimmed)] = '%' then
  begin
    if TryStrToFloat(Copy(Trimmed, 1, Length(Trimmed) - 1), D, CSSFormatSettings) then
    begin
      if D < 0 then D := 0 else if D > 100 then D := 100;
      Val := Round(D * 255.0 / 100.0);
      Result := True;
    end;
  end
  else
  begin
    if TryStrToFloat(Trimmed, D, CSSFormatSettings) then
    begin
      if D < 0.0 then D := 0.0 else if D > 1.0 then D := 1.0;
      Val := Round(D * 255.0);
      Result := True;
    end;
  end;
end;

function ParseRgbFunctionString(const S: AnsiString; out AColor: TCSSColor): Boolean;
var
  ParenOpen, ParenClose: Integer;
  ArgsStr              : AnsiString;
  Parts                : TStringList;
  I                    : Integer;
  CurPart              : AnsiString;
  R, G, B, A           : Byte;
  SlashPos             : Integer;
  AlphaPart            : AnsiString;
begin
  Result := False;
  ParenOpen := Pos('(', S);
  ParenClose := LastDelimiter(')', S);
  if (ParenOpen <= 0) or (ParenClose <= ParenOpen) then
    Exit;

  ArgsStr := Copy(S, ParenOpen + 1, ParenClose - ParenOpen - 1);
  Parts := TStringList.Create();
  try
    // Handle modern slash notation: rgb(255 0 0 / 0.5)
    SlashPos := Pos('/', ArgsStr);
    AlphaPart := '';
    if SlashPos > 0 then
    begin
      AlphaPart := TrimString(Copy(ArgsStr, SlashPos + 1, Length(ArgsStr) - SlashPos));
      ArgsStr := Copy(ArgsStr, 1, SlashPos - 1);
    end;

    // Split either by comma or whitespace
    if Pos(',', ArgsStr) > 0 then
    begin
      // Comma-separated: rgb(r, g, b) or rgba(r, g, b, a)
      Parts.Delimiter := ',';
      Parts.StrictDelimiter := True;
      Parts.DelimitedText := ArgsStr;
    end
    else
    begin
      // Space-separated: rgb(r g b)
      Parts.Delimiter := ' ';
      Parts.StrictDelimiter := False;
      Parts.DelimitedText := ArgsStr;
    end;

    // Remove empty items
    I := 0;
    while I < Parts.Count do
    begin
      if TrimString(Parts[I]) = '' then
        Parts.Delete(I)
      else
        Inc(I);
    end;

    if Parts.Count < 3 then
      Exit;

    if not ParseChannelVal(Parts[0], R) then Exit;
    if not ParseChannelVal(Parts[1], G) then Exit;
    if not ParseChannelVal(Parts[2], B) then Exit;

    A := 255;
    if AlphaPart <> '' then
    begin
      if not ParseAlphaVal(AlphaPart, A) then Exit;
    end
    else if Parts.Count >= 4 then
    begin
      if not ParseAlphaVal(Parts[3], A) then Exit;
    end;

    AColor := TCSSColor.FromRGBA(R, G, B, A);
    Result := True;
  finally
    Parts.Free();
  end;
end;

class function TCSSColor.TryParse(const AStr: AnsiString; out AColor: TCSSColor): Boolean;
var
  S: AnsiString;
begin
  S := TrimString(AStr);
  if Length(S) = 0 then
  begin
    Result := False;
    Exit;
  end;

  if S[1] = '#' then
    Result := FromHex(S, AColor)
  else if (Pos('rgb(', LowerCase(S)) = 1) or (Pos('rgba(', LowerCase(S)) = 1) then
    Result := ParseRgbFunctionString(S, AColor)
  else
    Result := FromName(S, AColor);
end;

function TCSSColor.ToHex(const AIncludeAlpha: Boolean): AnsiString;
begin
  if AIncludeAlpha then
    Result := LowerCase(Format('#%.2x%.2x%.2x%.2x', [R, G, B, A]))
  else
    Result := LowerCase(Format('#%.2x%.2x%.2x', [R, G, B]));
end;

function TCSSColor.ToRGBAString(): AnsiString;
begin
  if A = 255 then
    Result := Format('rgb(%d, %d, %d)', [R, G, B])
  else
    Result := Format('rgba(%d, %d, %d, %.3f)', [R, G, B, A / 255.0]);
end;

function TCSSColor.Equals(const AOther: TCSSColor): Boolean;
begin
  Result := (R = AOther.R) and (G = AOther.G) and (B = AOther.B) and (A = AOther.A);
end;

// ── TCSSLength ──────────────────────────────────────────────────────────────

class function TCSSLength.Px(const AVal: Double): TCSSLength;
begin
  Result.Value := AVal;
  Result.Unit_ := cuPx;
end;

class function TCSSLength.Em(const AVal: Double): TCSSLength;
begin
  Result.Value := AVal;
  Result.Unit_ := cuEm;
end;

class function TCSSLength.Rem(const AVal: Double): TCSSLength;
begin
  Result.Value := AVal;
  Result.Unit_ := cuRem;
end;

class function TCSSLength.Percent(const AVal: Double): TCSSLength;
begin
  Result.Value := AVal;
  Result.Unit_ := cuPercent;
end;

class function TCSSLength.Pt(const AVal: Double): TCSSLength;
begin
  Result.Value := AVal;
  Result.Unit_ := cuPt;
end;

class function TCSSLength.None(const AVal: Double): TCSSLength;
begin
  Result.Value := AVal;
  Result.Unit_ := cuNone;
end;

class function TCSSLength.Auto(): TCSSLength;
begin
  Result.Value := 0.0;
  Result.Unit_ := cuAuto;
end;

class function TCSSLength.Zero(): TCSSLength;
begin
  Result.Value := 0.0;
  Result.Unit_ := cuPx;
end;

class function TCSSLength.TryParse(const AStr: AnsiString; out ALength: TCSSLength): Boolean;
var
  S      : AnsiString;
  UnitStr: AnsiString;
  NumStr : AnsiString;
  D      : Double;
  I      : Integer;
begin
  Result := False;
  S := LowerCase(TrimString(AStr));
  if Length(S) = 0 then
    Exit;

  if S = 'auto' then
  begin
    ALength := Auto();
    Result := True;
    Exit;
  end;
  if S = 'inherit' then
  begin
    ALength.Value := 0;
    ALength.Unit_ := cuInherit;
    Result := True;
    Exit;
  end;
  if S = 'initial' then
  begin
    ALength.Value := 0;
    ALength.Unit_ := cuInitial;
    Result := True;
    Exit;
  end;
  if S = 'unset' then
  begin
    ALength.Value := 0;
    ALength.Unit_ := cuUnset;
    Result := True;
    Exit;
  end;

  // Split numeric prefix and unit suffix
  I := 1;
  if (I <= Length(S)) and ((S[I] = '+') or (S[I] = '-')) then
    Inc(I);
  while I <= Length(S) do
  begin
    if S[I] in ['0'..'9', '.'] then
      Inc(I)
    else if (S[I] in ['e', 'E']) and (I < Length(S)) and
            ((S[I+1] in ['0'..'9']) or
             (((S[I+1] = '+') or (S[I+1] = '-')) and (I + 1 < Length(S)) and (S[I+2] in ['0'..'9']))) then
    begin
      Inc(I); // consume 'e'
      if (I <= Length(S)) and ((S[I] = '+') or (S[I] = '-')) then
        Inc(I);
    end
    else
      Break;
  end;

  NumStr := Copy(S, 1, I - 1);
  UnitStr := Copy(S, I, Length(S) - I + 1);

  if not TryStrToFloat(NumStr, D, CSSFormatSettings) then
    Exit;

  if UnitStr = 'px' then
    ALength := Px(D)
  else if UnitStr = 'em' then
    ALength := Em(D)
  else if UnitStr = 'rem' then
    ALength := Rem(D)
  else if UnitStr = '%' then
    ALength := Percent(D)
  else if UnitStr = 'pt' then
    ALength := Pt(D)
  else if UnitStr = 'vw' then
  begin
    ALength.Value := D;
    ALength.Unit_ := cuVw;
  end
  else if UnitStr = 'vh' then
  begin
    ALength.Value := D;
    ALength.Unit_ := cuVh;
  end
  else if UnitStr = '' then
  begin
    // In CSS, 0 can omit unit, or unitless numbers for line-height, opacity, etc.
    ALength := None(D);
  end
  else
    Exit;

  Result := True;
end;

function TCSSLength.ToPixels(const ABaseFontSize: Double; const AParentSize: Double): Double;
begin
  case Unit_ of
    cuPx:      Result := Value;
    cuEm,
    cuRem:     Result := Value * ABaseFontSize;
    cuPt:      Result := Value * (96.0 / 72.0); // 1pt = 1/72 inch, 96 DPI
    cuPercent: Result := (Value / 100.0) * AParentSize;
    cuNone:    Result := Value;
  else
    Result := 0.0;
  end;
end;

function TCSSLength.IsAuto(): Boolean;
begin
  Result := Unit_ = cuAuto;
end;

function TCSSLength.IsZero(): Boolean;
begin
  Result := (Value = 0.0) and (Unit_ in [cuNone, cuPx, cuEm, cuRem, cuPt]);
end;

function TCSSLength.ToString(): AnsiString;
begin
  case Unit_ of
    cuNone:    Result := FloatToStr(Value, CSSFormatSettings);
    cuPx:      Result := FloatToStr(Value, CSSFormatSettings) + 'px';
    cuEm:      Result := FloatToStr(Value, CSSFormatSettings) + 'em';
    cuRem:     Result := FloatToStr(Value, CSSFormatSettings) + 'rem';
    cuPercent: Result := FloatToStr(Value, CSSFormatSettings) + '%';
    cuPt:      Result := FloatToStr(Value, CSSFormatSettings) + 'pt';
    cuVw:      Result := FloatToStr(Value, CSSFormatSettings) + 'vw';
    cuVh:      Result := FloatToStr(Value, CSSFormatSettings) + 'vh';
    cuAuto:    Result := 'auto';
    cuInherit: Result := 'inherit';
    cuInitial: Result := 'initial';
    cuUnset:   Result := 'unset';
  else
    Result := FloatToStr(Value, CSSFormatSettings);
  end;
end;

function TCSSLength.Equals(const AOther: TCSSLength): Boolean;
begin
  Result := (Unit_ = AOther.Unit_) and (Abs(Value - AOther.Value) < 0.00001);
end;

// ── TCSSBox ─────────────────────────────────────────────────────────────────

class function TCSSBox.All(const AVal: TCSSLength): TCSSBox;
begin
  Result.Top    := AVal;
  Result.Right  := AVal;
  Result.Bottom := AVal;
  Result.Left   := AVal;
end;

class function TCSSBox.Symmetric(const AVert, AHoriz: TCSSLength): TCSSBox;
begin
  Result.Top    := AVert;
  Result.Right  := AHoriz;
  Result.Bottom := AVert;
  Result.Left   := AHoriz;
end;

class function TCSSBox.TRBL(const ATop, ARight, ABottom, ALeft: TCSSLength): TCSSBox;
begin
  Result.Top    := ATop;
  Result.Right  := ARight;
  Result.Bottom := ABottom;
  Result.Left   := ALeft;
end;

class function TCSSBox.Zero(): TCSSBox;
begin
  Result := All(TCSSLength.Zero());
end;

function TCSSBox.Equals(const AOther: TCSSBox): Boolean;
begin
  Result := Top.Equals(AOther.Top) and
            Right.Equals(AOther.Right) and
            Bottom.Equals(AOther.Bottom) and
            Left.Equals(AOther.Left);
end;

// ── TCSSBorderSide ──────────────────────────────────────────────────────────

function TCSSBorderSide.Equals(const AOther: TCSSBorderSide): Boolean;
begin
  Result := Width.Equals(AOther.Width) and
            (Style = AOther.Style) and
            Color.Equals(AOther.Color);
end;

// ── Enum Parser & Formatter Implementations ─────────────────────────────────

function TryParseDisplay(const AStr: AnsiString; out AVal: TCSSDisplay): Boolean;
var
  S: AnsiString;
begin
  Result := True;
  S := LowerCase(TrimString(AStr));
  if S = 'inline' then AVal := cdInline
  else if S = 'block' then AVal := cdBlock
  else if S = 'inline-block' then AVal := cdInlineBlock
  else if S = 'flex' then AVal := cdFlex
  else if S = 'inline-flex' then AVal := cdInlineFlex
  else if S = 'grid' then AVal := cdGrid
  else if S = 'none' then AVal := cdNone
  else Result := False;
end;

function DisplayToString(const AVal: TCSSDisplay): AnsiString;
begin
  case AVal of
    cdInline:      Result := 'inline';
    cdBlock:       Result := 'block';
    cdInlineBlock: Result := 'inline-block';
    cdFlex:        Result := 'flex';
    cdInlineFlex:  Result := 'inline-flex';
    cdGrid:        Result := 'grid';
    cdNone:        Result := 'none';
  end;
end;

function TryParsePosition(const AStr: AnsiString; out AVal: TCSSPosition): Boolean;
var
  S: AnsiString;
begin
  Result := True;
  S := LowerCase(TrimString(AStr));
  if S = 'static' then AVal := cpStatic
  else if S = 'relative' then AVal := cpRelative
  else if S = 'absolute' then AVal := cpAbsolute
  else if S = 'fixed' then AVal := cpFixed
  else if S = 'sticky' then AVal := cpSticky
  else Result := False;
end;

function PositionToString(const AVal: TCSSPosition): AnsiString;
begin
  case AVal of
    cpStatic:   Result := 'static';
    cpRelative: Result := 'relative';
    cpAbsolute: Result := 'absolute';
    cpFixed:    Result := 'fixed';
    cpSticky:   Result := 'sticky';
  end;
end;

function TryParseVisibility(const AStr: AnsiString; out AVal: TCSSVisibility): Boolean;
var
  S: AnsiString;
begin
  Result := True;
  S := LowerCase(TrimString(AStr));
  if S = 'visible' then AVal := cvVisible
  else if S = 'hidden' then AVal := cvHidden
  else if S = 'collapse' then AVal := cvCollapse
  else Result := False;
end;

function VisibilityToString(const AVal: TCSSVisibility): AnsiString;
begin
  case AVal of
    cvVisible:  Result := 'visible';
    cvHidden:   Result := 'hidden';
    cvCollapse: Result := 'collapse';
  end;
end;

function TryParseOverflow(const AStr: AnsiString; out AVal: TCSSOverflow): Boolean;
var
  S: AnsiString;
begin
  Result := True;
  S := LowerCase(TrimString(AStr));
  if S = 'visible' then AVal := coVisible
  else if S = 'hidden' then AVal := coHidden
  else if S = 'scroll' then AVal := coScroll
  else if S = 'auto' then AVal := coAuto
  else Result := False;
end;

function OverflowToString(const AVal: TCSSOverflow): AnsiString;
begin
  case AVal of
    coVisible: Result := 'visible';
    coHidden:  Result := 'hidden';
    coScroll:  Result := 'scroll';
    coAuto:    Result := 'auto';
  end;
end;

function TryParseBorderStyle(const AStr: AnsiString; out AVal: TCSSBorderStyle): Boolean;
var
  S: AnsiString;
begin
  Result := True;
  S := LowerCase(TrimString(AStr));
  if S = 'none' then AVal := cbsNone
  else if S = 'hidden' then AVal := cbsHidden
  else if S = 'dotted' then AVal := cbsDotted
  else if S = 'dashed' then AVal := cbsDashed
  else if S = 'solid' then AVal := cbsSolid
  else if S = 'double' then AVal := cbsDouble
  else if S = 'groove' then AVal := cbsGroove
  else if S = 'ridge' then AVal := cbsRidge
  else if S = 'inset' then AVal := cbsInset
  else if S = 'outset' then AVal := cbsOutset
  else Result := False;
end;

function BorderStyleToString(const AVal: TCSSBorderStyle): AnsiString;
begin
  case AVal of
    cbsNone:   Result := 'none';
    cbsHidden: Result := 'hidden';
    cbsDotted: Result := 'dotted';
    cbsDashed: Result := 'dashed';
    cbsSolid:  Result := 'solid';
    cbsDouble: Result := 'double';
    cbsGroove: Result := 'groove';
    cbsRidge:  Result := 'ridge';
    cbsInset:  Result := 'inset';
    cbsOutset: Result := 'outset';
  end;
end;

function TryParseBoxSizing(const AStr: AnsiString; out AVal: TCSSBoxSizing): Boolean;
var
  S: AnsiString;
begin
  Result := True;
  S := LowerCase(TrimString(AStr));
  if S = 'content-box' then AVal := cbsContentBox
  else if S = 'border-box' then AVal := cbsBorderBox
  else Result := False;
end;

function BoxSizingToString(const AVal: TCSSBoxSizing): AnsiString;
begin
  case AVal of
    cbsContentBox: Result := 'content-box';
    cbsBorderBox:  Result := 'border-box';
  end;
end;

function TryParseFlexDirection(const AStr: AnsiString; out AVal: TCSSFlexDirection): Boolean;
var
  S: AnsiString;
begin
  Result := True;
  S := LowerCase(TrimString(AStr));
  if S = 'row' then AVal := cfdRow
  else if S = 'row-reverse' then AVal := cfdRowReverse
  else if S = 'column' then AVal := cfdColumn
  else if S = 'column-reverse' then AVal := cfdColumnReverse
  else Result := False;
end;

function FlexDirectionToString(const AVal: TCSSFlexDirection): AnsiString;
begin
  case AVal of
    cfdRow:           Result := 'row';
    cfdRowReverse:    Result := 'row-reverse';
    cfdColumn:        Result := 'column';
    cfdColumnReverse: Result := 'column-reverse';
  end;
end;

function TryParseFlexWrap(const AStr: AnsiString; out AVal: TCSSFlexWrap): Boolean;
var
  S: AnsiString;
begin
  Result := True;
  S := LowerCase(TrimString(AStr));
  if S = 'nowrap' then AVal := cfwNowrap
  else if S = 'wrap' then AVal := cfwWrap
  else if S = 'wrap-reverse' then AVal := cfwWrapReverse
  else Result := False;
end;

function FlexWrapToString(const AVal: TCSSFlexWrap): AnsiString;
begin
  case AVal of
    cfwNowrap:      Result := 'nowrap';
    cfwWrap:        Result := 'wrap';
    cfwWrapReverse: Result := 'wrap-reverse';
  end;
end;

function TryParseJustifyContent(const AStr: AnsiString; out AVal: TCSSJustifyContent): Boolean;
var
  S: AnsiString;
begin
  Result := True;
  S := LowerCase(TrimString(AStr));
  if S = 'flex-start' then AVal := cjcFlexStart
  else if S = 'flex-end' then AVal := cjcFlexEnd
  else if S = 'center' then AVal := cjcCenter
  else if S = 'space-between' then AVal := cjcSpaceBetween
  else if S = 'space-around' then AVal := cjcSpaceAround
  else if S = 'space-evenly' then AVal := cjcSpaceEvenly
  else Result := False;
end;

function JustifyContentToString(const AVal: TCSSJustifyContent): AnsiString;
begin
  case AVal of
    cjcFlexStart:    Result := 'flex-start';
    cjcFlexEnd:      Result := 'flex-end';
    cjcCenter:       Result := 'center';
    cjcSpaceBetween: Result := 'space-between';
    cjcSpaceAround:  Result := 'space-around';
    cjcSpaceEvenly:  Result := 'space-evenly';
  end;
end;

function TryParseAlignItems(const AStr: AnsiString; out AVal: TCSSAlignItems): Boolean;
var
  S: AnsiString;
begin
  Result := True;
  S := LowerCase(TrimString(AStr));
  if S = 'stretch' then AVal := caiStretch
  else if S = 'flex-start' then AVal := caiFlexStart
  else if S = 'flex-end' then AVal := caiFlexEnd
  else if S = 'center' then AVal := caiCenter
  else if S = 'baseline' then AVal := caiBaseline
  else Result := False;
end;

function AlignItemsToString(const AVal: TCSSAlignItems): AnsiString;
begin
  case AVal of
    caiStretch:   Result := 'stretch';
    caiFlexStart: Result := 'flex-start';
    caiFlexEnd:   Result := 'flex-end';
    caiCenter:    Result := 'center';
    caiBaseline:  Result := 'baseline';
  end;
end;

function TryParseFontStyle(const AStr: AnsiString; out AVal: TCSSFontStyle): Boolean;
var
  S: AnsiString;
begin
  Result := True;
  S := LowerCase(TrimString(AStr));
  if S = 'normal' then AVal := cfsNormal
  else if S = 'italic' then AVal := cfsItalic
  else if S = 'oblique' then AVal := cfsOblique
  else Result := False;
end;

function FontStyleToString(const AVal: TCSSFontStyle): AnsiString;
begin
  case AVal of
    cfsNormal:  Result := 'normal';
    cfsItalic:  Result := 'italic';
    cfsOblique: Result := 'oblique';
  end;
end;

function TryParseTextAlign(const AStr: AnsiString; out AVal: TCSSTextAlign): Boolean;
var
  S: AnsiString;
begin
  Result := True;
  S := LowerCase(TrimString(AStr));
  if S = 'left' then AVal := ctaLeft
  else if S = 'right' then AVal := ctaRight
  else if S = 'center' then AVal := ctaCenter
  else if S = 'justify' then AVal := ctaJustify
  else Result := False;
end;

function TextAlignToString(const AVal: TCSSTextAlign): AnsiString;
begin
  case AVal of
    ctaLeft:    Result := 'left';
    ctaRight:   Result := 'right';
    ctaCenter:  Result := 'center';
    ctaJustify: Result := 'justify';
  end;
end;

function TryParseTextDecoration(const AStr: AnsiString; out AVal: TCSSTextDecoration): Boolean;
var
  S: AnsiString;
begin
  Result := True;
  S := LowerCase(TrimString(AStr));
  if S = 'none' then AVal := ctdNone
  else if S = 'underline' then AVal := ctdUnderline
  else if S = 'overline' then AVal := ctdOverline
  else if S = 'line-through' then AVal := ctdLineThrough
  else Result := False;
end;

function TextDecorationToString(const AVal: TCSSTextDecoration): AnsiString;
begin
  case AVal of
    ctdNone:        Result := 'none';
    ctdUnderline:   Result := 'underline';
    ctdOverline:    Result := 'overline';
    ctdLineThrough: Result := 'line-through';
  end;
end;

// ── AST Node Parsers ────────────────────────────────────────────────────────

function ParseColorFromNode(const ANode: TCSSNode; out AColor: TCSSColor): Boolean;
var
  Tok: TCSSToken;
  Fn : TCSSFunctionBlock;
  FnStr: AnsiString;
  I  : Integer;
  ChildTok: TCSSToken;
begin
  Result := False;
  if ANode = nil then
    Exit;

  if ANode.NodeType = cntPreservedToken then
  begin
    Tok := TCSSPreservedToken(ANode).Token;
    case Tok.TokenType of
      cttHash:
        Result := TCSSColor.FromHex(Tok.Value, AColor);
      cttIdent:
        Result := TCSSColor.FromName(Tok.Value, AColor);
    end;
  end
  else if ANode.NodeType = cntFunction then
  begin
    Fn := TCSSFunctionBlock(ANode);
    if (LowerCase(Fn.Name) = 'rgb') or (LowerCase(Fn.Name) = 'rgba') then
    begin
      // Reconstruct string representation from child tokens and parse
      FnStr := Fn.Name + '(';
      for I := 0 to Fn.Children.Count - 1 do
      begin
        if TCSSNode(Fn.Children[I]).NodeType = cntPreservedToken then
        begin
          ChildTok := TCSSPreservedToken(Fn.Children[I]).Token;
          case ChildTok.TokenType of
            cttNumber, cttPercentage, cttDimension:
              FnStr := FnStr + ChildTok.Value;
            cttComma:
              FnStr := FnStr + ',';
            cttDelim:
              FnStr := FnStr + ChildTok.Value;
            cttWhitespace:
              FnStr := FnStr + ' ';
          else
            FnStr := FnStr + ChildTok.Value;
          end;
        end;
      end;
      FnStr := FnStr + ')';
      Result := ParseRgbFunctionString(FnStr, AColor);
    end;
  end;
end;

function ParseColorFromNodes(const ANodes: TObjectList; out AColor: TCSSColor): Boolean;
var
  Filtered: TObjectList;
begin
  Result := False;
  if (ANodes = nil) or (ANodes.Count = 0) then
    Exit;
  Filtered := FilterWhitespaceNodes(ANodes);
  try
    if Filtered.Count = 1 then
      Result := ParseColorFromNode(TCSSNode(Filtered[0]), AColor);
  finally
    Filtered.Free();
  end;
end;

function ParseLengthFromNode(const ANode: TCSSNode; out ALength: TCSSLength): Boolean;
var
  Tok: TCSSToken;
  UnitLow: AnsiString;
begin
  Result := False;
  if ANode = nil then
    Exit;

  if ANode.NodeType = cntPreservedToken then
  begin
    Tok := TCSSPreservedToken(ANode).Token;
    case Tok.TokenType of
      cttDimension:
      begin
        UnitLow := LowerCase(Tok.Unit_);
        if UnitLow = 'px' then
          ALength := TCSSLength.Px(Tok.NumericVal)
        else if UnitLow = 'em' then
          ALength := TCSSLength.Em(Tok.NumericVal)
        else if UnitLow = 'rem' then
          ALength := TCSSLength.Rem(Tok.NumericVal)
        else if UnitLow = 'pt' then
          ALength := TCSSLength.Pt(Tok.NumericVal)
        else if UnitLow = 'vw' then
        begin
          ALength.Value := Tok.NumericVal;
          ALength.Unit_ := cuVw;
        end
        else if UnitLow = 'vh' then
        begin
          ALength.Value := Tok.NumericVal;
          ALength.Unit_ := cuVh;
        end
        else
          Exit;
        Result := True;
      end;
      cttPercentage:
      begin
        ALength := TCSSLength.Percent(Tok.NumericVal);
        Result := True;
      end;
      cttNumber:
      begin
        ALength := TCSSLength.None(Tok.NumericVal);
        Result := True;
      end;
      cttIdent:
      begin
        Result := TCSSLength.TryParse(Tok.Value, ALength);
      end;
    end;
  end;
end;

function ParseLengthFromNodes(const ANodes: TObjectList; out ALength: TCSSLength): Boolean;
var
  Filtered: TObjectList;
begin
  Result := False;
  if (ANodes = nil) or (ANodes.Count = 0) then
    Exit;
  Filtered := FilterWhitespaceNodes(ANodes);
  try
    if Filtered.Count = 1 then
      Result := ParseLengthFromNode(TCSSNode(Filtered[0]), ALength);
  finally
    Filtered.Free();
  end;
end;

function ParseBoxFromNodes(const ANodes: TObjectList; out ABox: TCSSBox): Boolean;
var
  Filtered: TObjectList;
  Lens    : array[0..3] of TCSSLength;
  I       : Integer;
begin
  Result := False;
  if (ANodes = nil) or (ANodes.Count = 0) then
    Exit;

  Filtered := FilterWhitespaceNodes(ANodes);
  try
    if not (Filtered.Count in [1, 2, 3, 4]) then
      Exit;

    for I := 0 to Filtered.Count - 1 do
    begin
      if not ParseLengthFromNode(TCSSNode(Filtered[I]), Lens[I]) then
        Exit;
    end;

    case Filtered.Count of
      1: // all 4 sides
        ABox := TCSSBox.All(Lens[0]);
      2: // top/bottom, right/left
        ABox := TCSSBox.Symmetric(Lens[0], Lens[1]);
      3: // top, right/left, bottom
        ABox := TCSSBox.TRBL(Lens[0], Lens[1], Lens[2], Lens[1]);
      4: // top, right, bottom, left
        ABox := TCSSBox.TRBL(Lens[0], Lens[1], Lens[2], Lens[3]);
    end;
    Result := True;
  finally
    Filtered.Free();
  end;
end;

function ParseBorderSideFromNodes(const ANodes: TObjectList; out ABorder: TCSSBorderSide): Boolean;
var
  Filtered: TObjectList;
  I       : Integer;
  Node    : TCSSNode;
  L       : TCSSLength;
  C       : TCSSColor;
  BS      : TCSSBorderStyle;
  HaveW   : Boolean;
  HaveS   : Boolean;
  HaveC   : Boolean;
  Tok     : TCSSToken;
begin
  Result := False;
  if (ANodes = nil) or (ANodes.Count = 0) then
    Exit;

  // Defaults for border
  ABorder.Width := TCSSLength.Px(3); // 'medium' standard default
  ABorder.Style := cbsNone;
  ABorder.Color := TCSSColor.Black();

  HaveW := False;
  HaveS := False;
  HaveC := False;

  Filtered := FilterWhitespaceNodes(ANodes);
  try
    if Filtered.Count > 3 then
      Exit;

    for I := 0 to Filtered.Count - 1 do
    begin
      Node := TCSSNode(Filtered[I]);
      // Try style keyword first if it's an ident
      if (not HaveS) and (Node.NodeType = cntPreservedToken) then
      begin
        Tok := TCSSPreservedToken(Node).Token;
        if (Tok.TokenType = cttIdent) and TryParseBorderStyle(Tok.Value, BS) then
        begin
          ABorder.Style := BS;
          HaveS := True;
          Continue;
        end;
      end;

      // Try width
      if (not HaveW) and ParseLengthFromNode(Node, L) then
      begin
        ABorder.Width := L;
        HaveW := True;
        Continue;
      end;

      // Try color
      if (not HaveC) and ParseColorFromNode(Node, C) then
      begin
        ABorder.Color := C;
        HaveC := True;
        Continue;
      end;

      // Also check standard width keywords: thin (1px), medium (3px), thick (5px)
      if (not HaveW) and (Node.NodeType = cntPreservedToken) then
      begin
        Tok := TCSSPreservedToken(Node).Token;
        if Tok.TokenType = cttIdent then
        begin
          if LowerCase(Tok.Value) = 'thin' then
          begin
            ABorder.Width := TCSSLength.Px(1);
            HaveW := True;
            Continue;
          end
          else if LowerCase(Tok.Value) = 'medium' then
          begin
            ABorder.Width := TCSSLength.Px(3);
            HaveW := True;
            Continue;
          end
          else if LowerCase(Tok.Value) = 'thick' then
          begin
            ABorder.Width := TCSSLength.Px(5);
            HaveW := True;
            Continue;
          end;
        end;
      end;

      // Unrecognized component
      Exit;
    end;

    // At least one component must be valid
    Result := HaveW or HaveS or HaveC;
  finally
    Filtered.Free();
  end;
end;

initialization
  CSSFormatSettings := DefaultFormatSettings;
  CSSFormatSettings.DecimalSeparator := '.';

end.
