unit Floria.SVG.Types;

// Floria.SVG.Types
// ================
// Core types, mathematical primitives, coordinate transformations, unit parsing,
// and presentation attributes for the Floria SVG subsystem.
//
// Highlights:
//   - TSVGPoint, TSVGRect geometric primitives
//   - TSVGMatrix 2D affine transform record (3x2) with multiplication, inversion,
//     translation, scaling, rotation, skewing, point/rect mapping
//   - Full SVG transform attribute parser: matrix(), translate(), scale(),
//     rotate(), skewX(), skewY() with chaining support
//   - TSVGLength with unit conversions (px, pt, pc, mm, cm, in, em, ex, %)
//   - TSVGViewBox & TSVGPreserveAspectRatio with W3C viewport matrix derivation
//   - TSVGPaint (none, currentColor, color, uri) and paint attribute parsers

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, Floria.CSS.Types, Floria.CSS.Values;

type
  // ── Geometric Primitives ───────────────────────────────────────────────────

  TSVGPoint = record
    X: Double;
    Y: Double;
  end;

  TSVGRect = record
    X: Double;
    Y: Double;
    Width: Double;
    Height: Double;
  end;

  // ── 2D Affine Transformation Matrix ────────────────────────────────────────
  // Represents transformation:
  //   [ X' ]   [ A  C  E ] [ X ]
  //   [ Y' ] = [ B  D  F ] [ Y ]
  //   [ 1  ]   [ 0  0  1 ] [ 1 ]
  // Where:
  //   X' = A * X + C * Y + E
  //   Y' = B * X + D * Y + F

  TSVGMatrix = record
    A, B, C, D, E, F: Double;
  end;

  // ── Units & Lengths ────────────────────────────────────────────────────────

  TSVGUnit = (
    suNone,     // User units (pixels)
    suPX,       // Pixels
    suPT,       // Points (1pt = 1.333333px)
    suPC,       // Picas (1pc = 16px)
    suMM,       // Millimeters (1mm = 3.779528px)
    suCM,       // Centimeters (1cm = 37.79528px)
    suIN,       // Inches (1in = 96px)
    suEM,       // Relative to font size
    suEX,       // Relative to x-height (0.5 em)
    suPercent   // Percentage of viewport
  );

  TSVGLength = record
    Value: Double;
    UnitType: TSVGUnit;
    Specified: Boolean;
  end;

  // ── ViewBox & Aspect Ratio ─────────────────────────────────────────────────

  TSVGViewBox = record
    HasValue: Boolean;
    MinX: Double;
    MinY: Double;
    Width: Double;
    Height: Double;
  end;

  TSVGPreserveAspectRatioAlign = (
    paraNone,
    paraXMinYMin,
    paraXMidYMin,
    paraXMaxYMin,
    paraXMinYMid,
    paraXMidYMid,
    paraXMaxYMid,
    paraXMinYMax,
    paraXMidYMax,
    paraXMaxYMax
  );

  TSVGMeetOrSlice = (
    mosMeet,
    mosSlice
  );

  TSVGPreserveAspectRatio = record
    Align: TSVGPreserveAspectRatioAlign;
    MeetOrSlice: TSVGMeetOrSlice;
  end;

  // ── Paint & Presentation Types ─────────────────────────────────────────────

  TSVGPaintKind = (
    pkNone,
    pkCurrentColor,
    pkColor,
    pkUri
  );

  TSVGPaint = record
    Kind: TSVGPaintKind;
    Color: TCSSColor;
    UriId: string;
  end;

  TSVGLineCap = (
    slcButt,
    slcRound,
    slcSquare
  );

  TSVGLineJoin = (
    sljMiter,
    sljRound,
    sljBevel
  );

  TSVGFillRule = (
    sfrNonZero,
    sfrEvenOdd
  );

  TSVGVisibility = (
    svVisible,
    svHidden,
    svCollapse
  );

  TSVGDisplay = (
    sdInline,
    sdBlock,
    sdNone
  );

// ── Constructor Helpers ──────────────────────────────────────────────────────

function SVGPoint(AX, AY: Double): TSVGPoint;
function SVGRect(AX, AY, AW, AH: Double): TSVGRect;

// ── Matrix Functions ─────────────────────────────────────────────────────────

function SVGMatrixIdentity(): TSVGMatrix;
function SVGMatrix(AA, AB, AC, AD, AE, AF: Double): TSVGMatrix;
function SVGMatrixMultiply(const M1, M2: TSVGMatrix): TSVGMatrix;
function SVGMatrixTranslate(TX, TY: Double): TSVGMatrix;
function SVGMatrixScale(SX, SY: Double): TSVGMatrix;
function SVGMatrixRotate(AngleDeg: Double): TSVGMatrix;
function SVGMatrixRotateAt(AngleDeg, CX, CY: Double): TSVGMatrix;
function SVGMatrixSkewX(AngleDeg: Double): TSVGMatrix;
function SVGMatrixSkewY(AngleDeg: Double): TSVGMatrix;
function SVGMatrixTransformPoint(const M: TSVGMatrix; const Pt: TSVGPoint): TSVGPoint;
function SVGMatrixTransformRect(const M: TSVGMatrix; const R: TSVGRect): TSVGRect;
function SVGMatrixInvert(const M: TSVGMatrix; out Inv: TSVGMatrix): Boolean;
function SVGMatrixIsIdentity(const M: TSVGMatrix): Boolean;

// ── Transform Parsing ────────────────────────────────────────────────────────

function SVGParseTransform(const AStr: string): TSVGMatrix;

// ── Length Functions ─────────────────────────────────────────────────────────

function SVGLength(AValue: Double; AUnit: TSVGUnit = suNone): TSVGLength;
function SVGParseLength(const S: string; DefaultUnit: TSVGUnit = suNone): TSVGLength;
function SVGLengthToPixels(const L: TSVGLength; BaseDim: Double = 0.0; FontEm: Double = 16.0): Double;

// ── ViewBox Functions ────────────────────────────────────────────────────────

function SVGParseViewBox(const S: string): TSVGViewBox;
function SVGParsePreserveAspectRatio(const S: string): TSVGPreserveAspectRatio;
function SVGCalculateViewBoxTransform(const AViewBox: TSVGViewBox; const AAlign: TSVGPreserveAspectRatio; TargetW, TargetH: Double): TSVGMatrix;

// ── Paint & Presentation Parsing ─────────────────────────────────────────────

function SVGParsePaint(const S: string): TSVGPaint;
function SVGParseLineCap(const S: string): TSVGLineCap;
function SVGParseLineJoin(const S: string): TSVGLineJoin;
function SVGParseFillRule(const S: string): TSVGFillRule;
function SVGParseVisibility(const S: string): TSVGVisibility;
function SVGParseDisplay(const S: string): TSVGDisplay;

implementation

// ── Geometric Primitives ─────────────────────────────────────────────────────

function SVGPoint(AX, AY: Double): TSVGPoint;
begin
  Result.X := AX;
  Result.Y := AY;
end;

function SVGRect(AX, AY, AW, AH: Double): TSVGRect;
begin
  Result.X := AX;
  Result.Y := AY;
  Result.Width := AW;
  Result.Height := AH;
end;

// ── Matrix Implementation ────────────────────────────────────────────────────

function SVGMatrixIdentity(): TSVGMatrix;
begin
  Result.A := 1.0; Result.B := 0.0;
  Result.C := 0.0; Result.D := 1.0;
  Result.E := 0.0; Result.F := 0.0;
end;

function SVGMatrix(AA, AB, AC, AD, AE, AF: Double): TSVGMatrix;
begin
  Result.A := AA; Result.B := AB;
  Result.C := AC; Result.D := AD;
  Result.E := AE; Result.F := AF;
end;

function SVGMatrixMultiply(const M1, M2: TSVGMatrix): TSVGMatrix;
begin
  Result.A := M1.A * M2.A + M1.C * M2.B;
  Result.B := M1.B * M2.A + M1.D * M2.B;
  Result.C := M1.A * M2.C + M1.C * M2.D;
  Result.D := M1.B * M2.C + M1.D * M2.D;
  Result.E := M1.A * M2.E + M1.C * M2.F + M1.E;
  Result.F := M1.B * M2.E + M1.D * M2.F + M1.F;
end;

function SVGMatrixTranslate(TX, TY: Double): TSVGMatrix;
begin
  Result.A := 1.0; Result.B := 0.0;
  Result.C := 0.0; Result.D := 1.0;
  Result.E := TX;  Result.F := TY;
end;

function SVGMatrixScale(SX, SY: Double): TSVGMatrix;
begin
  Result.A := SX;  Result.B := 0.0;
  Result.C := 0.0; Result.D := SY;
  Result.E := 0.0; Result.F := 0.0;
end;

function SVGMatrixRotate(AngleDeg: Double): TSVGMatrix;
var
  Rad, CosVal, SinVal: Double;
begin
  Rad := DegToRad(AngleDeg);
  CosVal := Cos(Rad);
  SinVal := Sin(Rad);
  Result.A := CosVal;  Result.B := SinVal;
  Result.C := -SinVal; Result.D := CosVal;
  Result.E := 0.0;     Result.F := 0.0;
end;

function SVGMatrixRotateAt(AngleDeg, CX, CY: Double): TSVGMatrix;
var
  T1, R, T2, Temp: TSVGMatrix;
begin
  T1 := SVGMatrixTranslate(CX, CY);
  R  := SVGMatrixRotate(AngleDeg);
  T2 := SVGMatrixTranslate(-CX, -CY);
  Temp := SVGMatrixMultiply(T1, R);
  Result := SVGMatrixMultiply(Temp, T2);
end;

function SVGMatrixSkewX(AngleDeg: Double): TSVGMatrix;
var
  Rad: Double;
begin
  Rad := DegToRad(AngleDeg);
  Result.A := 1.0;      Result.B := 0.0;
  Result.C := Tan(Rad); Result.D := 1.0;
  Result.E := 0.0;      Result.F := 0.0;
end;

function SVGMatrixSkewY(AngleDeg: Double): TSVGMatrix;
var
  Rad: Double;
begin
  Rad := DegToRad(AngleDeg);
  Result.A := 1.0; Result.B := Tan(Rad);
  Result.C := 0.0; Result.D := 1.0;
  Result.E := 0.0; Result.F := 0.0;
end;

function SVGMatrixTransformPoint(const M: TSVGMatrix; const Pt: TSVGPoint): TSVGPoint;
begin
  Result.X := M.A * Pt.X + M.C * Pt.Y + M.E;
  Result.Y := M.B * Pt.X + M.D * Pt.Y + M.F;
end;

function SVGMatrixTransformRect(const M: TSVGMatrix; const R: TSVGRect): TSVGRect;
var
  P1, P2, P3, P4: TSVGPoint;
  MinX, MaxX, MinY, MaxY: Double;
begin
  P1 := SVGMatrixTransformPoint(M, SVGPoint(R.X, R.Y));
  P2 := SVGMatrixTransformPoint(M, SVGPoint(R.X + R.Width, R.Y));
  P3 := SVGMatrixTransformPoint(M, SVGPoint(R.X + R.Width, R.Y + R.Height));
  P4 := SVGMatrixTransformPoint(M, SVGPoint(R.X, R.Y + R.Height));

  MinX := Min(Min(P1.X, P2.X), Min(P3.X, P4.X));
  MaxX := Max(Max(P1.X, P2.X), Max(P3.X, P4.X));
  MinY := Min(Min(P1.Y, P2.Y), Min(P3.Y, P4.Y));
  MaxY := Max(Max(P1.Y, P2.Y), Max(P3.Y, P4.Y));

  Result.X := MinX;
  Result.Y := MinY;
  Result.Width := MaxX - MinX;
  Result.Height := MaxY - MinY;
end;

function SVGMatrixInvert(const M: TSVGMatrix; out Inv: TSVGMatrix): Boolean;
var
  Det: Double;
begin
  Det := M.A * M.D - M.B * M.C;
  if Abs(Det) < 1e-12 then
  begin
    Inv := SVGMatrixIdentity();
    Exit(False);
  end;

  Inv.A := M.D / Det;
  Inv.B := -M.B / Det;
  Inv.C := -M.C / Det;
  Inv.D := M.A / Det;
  Inv.E := (M.C * M.F - M.D * M.E) / Det;
  Inv.F := (M.B * M.E - M.A * M.F) / Det;
  Result := True;
end;

function SVGMatrixIsIdentity(const M: TSVGMatrix): Boolean;
begin
  Result := (Abs(M.A - 1.0) < 1e-9) and (Abs(M.B) < 1e-9) and
            (Abs(M.C) < 1e-9) and (Abs(M.D - 1.0) < 1e-9) and
            (Abs(M.E) < 1e-9) and (Abs(M.F) < 1e-9);
end;

// ── Transform Parsing ────────────────────────────────────────────────────────

function ParseNumberList(const S: string; out Numbers: array of Double; MaxCount: Integer): Integer;
var
  I, Len, StartPos, Count, ExpStart: Integer;
  NumStr: string;
  DVal: Double;
  Code: Integer;
begin
  Count := 0;
  I := 1;
  Len := Length(S);

  while (I <= Len) and (Count < MaxCount) do
  begin
    // Skip whitespace and comma
    while (I <= Len) and ((S[I] in [' ', #9, #10, #13, ','])) do
      Inc(I);

    if I > Len then Break;

    StartPos := I;
    if S[I] in ['+', '-'] then Inc(I);
    while (I <= Len) and (S[I] in ['0'..'9']) do Inc(I);
    if (I <= Len) and (S[I] = '.') then
    begin
      Inc(I);
      while (I <= Len) and (S[I] in ['0'..'9']) do Inc(I);
    end;
    if (I <= Len) and (S[I] in ['e', 'E']) then
    begin
      ExpStart := I;
      Inc(I);
      if (I <= Len) and (S[I] in ['+', '-']) then Inc(I);
      if (I <= Len) and (S[I] in ['0'..'9']) then
      begin
        while (I <= Len) and (S[I] in ['0'..'9']) do Inc(I);
      end
      else
        I := ExpStart;
    end;

    if I > StartPos then
    begin
      NumStr := Copy(S, StartPos, I - StartPos);
      DVal := 0.0;
      System.Val(NumStr, DVal, Code);
      if Code = 0 then
      begin
        Numbers[Count] := DVal;
        Inc(Count);
      end;
    end
    else
      Inc(I);
  end;

  Result := Count;
end;

function SVGParseTransform(const AStr: string): TSVGMatrix;
var
  PosIdx, Len, OpenParen, CloseParen: Integer;
  CmdName, ArgStr: string;
  Args: array[0..5] of Double;
  ArgCount: Integer;
  CurMat: TSVGMatrix;
begin
  Result := SVGMatrixIdentity();
  PosIdx := 1;
  Len := Length(AStr);

  while PosIdx <= Len do
  begin
    // Skip whitespace and comma
    while (PosIdx <= Len) and (AStr[PosIdx] in [' ', #9, #10, #13, ',']) do
      Inc(PosIdx);

    if PosIdx > Len then Break;

    // Find opening paren
    OpenParen := PosIdx;
    while (OpenParen <= Len) and (AStr[OpenParen] <> '(') do
      Inc(OpenParen);

    if OpenParen > Len then Break;

    CmdName := LowerCase(Trim(Copy(AStr, PosIdx, OpenParen - PosIdx)));

    // Find closing paren
    CloseParen := OpenParen + 1;
    while (CloseParen <= Len) and (AStr[CloseParen] <> ')') do
      Inc(CloseParen);

    if CloseParen > Len then Break;

    ArgStr := Copy(AStr, OpenParen + 1, CloseParen - OpenParen - 1);
    PosIdx := CloseParen + 1;

    FillChar(Args, SizeOf(Args), 0);
    ArgCount := ParseNumberList(ArgStr, Args, 6);

    CurMat := SVGMatrixIdentity();
    if CmdName = 'matrix' then
    begin
      if ArgCount >= 6 then
        CurMat := SVGMatrix(Args[0], Args[1], Args[2], Args[3], Args[4], Args[5]);
    end
    else if CmdName = 'translate' then
    begin
      if ArgCount = 1 then
        CurMat := SVGMatrixTranslate(Args[0], 0.0)
      else if ArgCount >= 2 then
        CurMat := SVGMatrixTranslate(Args[0], Args[1]);
    end
    else if CmdName = 'scale' then
    begin
      if ArgCount = 1 then
        CurMat := SVGMatrixScale(Args[0], Args[0])
      else if ArgCount >= 2 then
        CurMat := SVGMatrixScale(Args[0], Args[1]);
    end
    else if CmdName = 'rotate' then
    begin
      if ArgCount = 1 then
        CurMat := SVGMatrixRotate(Args[0])
      else if ArgCount >= 3 then
        CurMat := SVGMatrixRotateAt(Args[0], Args[1], Args[2]);
    end
    else if CmdName = 'skewx' then
    begin
      if ArgCount >= 1 then
        CurMat := SVGMatrixSkewX(Args[0]);
    end
    else if CmdName = 'skewy' then
    begin
      if ArgCount >= 1 then
        CurMat := SVGMatrixSkewY(Args[0]);
    end;

    Result := SVGMatrixMultiply(Result, CurMat);
  end;
end;

// ── Length Functions ─────────────────────────────────────────────────────────

function SVGLength(AValue: Double; AUnit: TSVGUnit = suNone): TSVGLength;
begin
  Result.Value := AValue;
  Result.UnitType := AUnit;
  Result.Specified := True;
end;

function SVGParseLength(const S: string; DefaultUnit: TSVGUnit = suNone): TSVGLength;
var
  Trimmed, NumStr, UnitStr: string;
  I, Len, ExpStart: Integer;
  DVal: Double;
  Code: Integer;
begin
  Trimmed := Trim(S);
  Result.Value := 0.0;
  Result.UnitType := DefaultUnit;
  Result.Specified := False;

  if Trimmed = '' then Exit;

  Len := Length(Trimmed);
  I := 1;
  if Trimmed[I] in ['+', '-'] then Inc(I);
  while (I <= Len) and (Trimmed[I] in ['0'..'9']) do Inc(I);
  if (I <= Len) and (Trimmed[I] = '.') then
  begin
    Inc(I);
    while (I <= Len) and (Trimmed[I] in ['0'..'9']) do Inc(I);
  end;
  if (I <= Len) and (Trimmed[I] in ['e', 'E']) then
  begin
    ExpStart := I;
    Inc(I);
    if (I <= Len) and (Trimmed[I] in ['+', '-']) then Inc(I);
    if (I <= Len) and (Trimmed[I] in ['0'..'9']) then
    begin
      while (I <= Len) and (Trimmed[I] in ['0'..'9']) do Inc(I);
    end
    else
      I := ExpStart;
  end;

  NumStr := Copy(Trimmed, 1, I - 1);
  UnitStr := LowerCase(Trim(Copy(Trimmed, I, Len - I + 1)));

  DVal := 0.0;
  System.Val(NumStr, DVal, Code);
  if Code <> 0 then Exit;

  Result.Value := DVal;
  Result.Specified := True;

  if UnitStr = 'px' then Result.UnitType := suPX
  else if UnitStr = 'pt' then Result.UnitType := suPT
  else if UnitStr = 'pc' then Result.UnitType := suPC
  else if UnitStr = 'mm' then Result.UnitType := suMM
  else if UnitStr = 'cm' then Result.UnitType := suCM
  else if UnitStr = 'in' then Result.UnitType := suIN
  else if UnitStr = 'em' then Result.UnitType := suEM
  else if UnitStr = 'ex' then Result.UnitType := suEX
  else if UnitStr = '%' then Result.UnitType := suPercent
  else Result.UnitType := DefaultUnit;
end;

function SVGLengthToPixels(const L: TSVGLength; BaseDim: Double = 0.0; FontEm: Double = 16.0): Double;
begin
  case L.UnitType of
    suNone, suPX: Result := L.Value;
    suPT: Result := L.Value * (96.0 / 72.0);
    suPC: Result := L.Value * 16.0;
    suMM: Result := L.Value * (96.0 / 25.4);
    suCM: Result := L.Value * (960.0 / 25.4);
    suIN: Result := L.Value * 96.0;
    suEM: Result := L.Value * FontEm;
    suEX: Result := L.Value * (FontEm * 0.5);
    suPercent: Result := L.Value * 0.01 * BaseDim;
    else Result := L.Value;
  end;
end;

// ── ViewBox Functions ────────────────────────────────────────────────────────

function SVGParseViewBox(const S: string): TSVGViewBox;
var
  Vals: array[0..3] of Double;
  Count: Integer;
begin
  Result.HasValue := False;
  Result.MinX := 0.0;
  Result.MinY := 0.0;
  Result.Width := 0.0;
  Result.Height := 0.0;

  Count := ParseNumberList(S, Vals, 4);
  if Count = 4 then
  begin
    Result.MinX := Vals[0];
    Result.MinY := Vals[1];
    Result.Width := Vals[2];
    Result.Height := Vals[3];
    Result.HasValue := (Result.Width > 0.0) and (Result.Height > 0.0);
  end;
end;

function SVGParsePreserveAspectRatio(const S: string): TSVGPreserveAspectRatio;
var
  Tokens: TStringList;
  I: Integer;
  Tok: string;
begin
  Result.Align := paraXMidYMid;
  Result.MeetOrSlice := mosMeet;

  if Trim(S) = '' then Exit;

  Tokens := TStringList.Create();
  try
    Tokens.Delimiter := ' ';
    Tokens.StrictDelimiter := False;
    Tokens.DelimitedText := S;

    for I := 0 to Tokens.Count - 1 do
    begin
      Tok := LowerCase(Trim(Tokens[I]));
      if Tok = 'none' then Result.Align := paraNone
      else if Tok = 'xminymin' then Result.Align := paraXMinYMin
      else if Tok = 'xmidymin' then Result.Align := paraXMidYMin
      else if Tok = 'xmaxymin' then Result.Align := paraXMaxYMin
      else if Tok = 'xminymid' then Result.Align := paraXMinYMid
      else if Tok = 'xmidymid' then Result.Align := paraXMidYMid
      else if Tok = 'xmaxymid' then Result.Align := paraXMaxYMid
      else if Tok = 'xminymax' then Result.Align := paraXMinYMax
      else if Tok = 'xmidymax' then Result.Align := paraXMidYMax
      else if Tok = 'xmaxymax' then Result.Align := paraXMaxYMax
      else if Tok = 'meet' then Result.MeetOrSlice := mosMeet
      else if Tok = 'slice' then Result.MeetOrSlice := mosSlice;
    end;
  finally
    Tokens.Free();
  end;
end;

function SVGCalculateViewBoxTransform(const AViewBox: TSVGViewBox; const AAlign: TSVGPreserveAspectRatio; TargetW, TargetH: Double): TSVGMatrix;
var
  ScaleX, ScaleY, Scale, OffsetX, OffsetY: Double;
begin
  Result := SVGMatrixIdentity();
  if (not AViewBox.HasValue) or (AViewBox.Width <= 0.0) or (AViewBox.Height <= 0.0) or
     (TargetW <= 0.0) or (TargetH <= 0.0) then
    Exit;

  ScaleX := TargetW / AViewBox.Width;
  ScaleY := TargetH / AViewBox.Height;

  if AAlign.Align = paraNone then
  begin
    // Non-uniform scaling
    Result := SVGMatrix(ScaleX, 0.0, 0.0, ScaleY, -AViewBox.MinX * ScaleX, -AViewBox.MinY * ScaleY);
    Exit;
  end;

  if AAlign.MeetOrSlice = mosMeet then
    Scale := Min(ScaleX, ScaleY)
  else
    Scale := Max(ScaleX, ScaleY);

  case AAlign.Align of
    paraXMinYMin, paraXMinYMid, paraXMinYMax:
      OffsetX := 0.0;
    paraXMidYMin, paraXMidYMid, paraXMidYMax:
      OffsetX := (TargetW - AViewBox.Width * Scale) * 0.5;
    paraXMaxYMin, paraXMaxYMid, paraXMaxYMax:
      OffsetX := TargetW - AViewBox.Width * Scale;
    else
      OffsetX := 0.0;
  end;

  case AAlign.Align of
    paraXMinYMin, paraXMidYMin, paraXMaxYMin:
      OffsetY := 0.0;
    paraXMinYMid, paraXMidYMid, paraXMaxYMid:
      OffsetY := (TargetH - AViewBox.Height * Scale) * 0.5;
    paraXMinYMax, paraXMidYMax, paraXMaxYMax:
      OffsetY := TargetH - AViewBox.Height * Scale;
    else
      OffsetY := 0.0;
  end;

  Result := SVGMatrix(Scale, 0.0, 0.0, Scale, OffsetX - AViewBox.MinX * Scale, OffsetY - AViewBox.MinY * Scale);
end;

// ── Paint & Presentation Parsing ─────────────────────────────────────────────

function SVGParsePaint(const S: string): TSVGPaint;
var
  Trimmed, Low: string;
  P1, P2: Integer;
  Col: TCSSColor;
begin
  Trimmed := Trim(S);
  Low := LowerCase(Trimmed);
  Result.Kind := pkNone;
  Result.Color := TCSSColor.Transparent();
  Result.UriId := '';

  if (Trimmed = '') or (Low = 'none') then
    Result.Kind := pkNone
  else if Low = 'currentcolor' then
    Result.Kind := pkCurrentColor
  else if (Length(Low) > 4) and (Copy(Low, 1, 4) = 'url(') then
  begin
    Result.Kind := pkUri;
    P1 := Pos('#', Trimmed);
    if P1 > 0 then
    begin
      P2 := Pos(')', Trimmed);
      if P2 > P1 then
        Result.UriId := Trim(Copy(Trimmed, P1 + 1, P2 - P1 - 1))
      else
        Result.UriId := Trim(Copy(Trimmed, P1 + 1, MaxInt));
    end;
  end
  else if TCSSColor.TryParse(Trimmed, Col) or TCSSColor.FromHex('#' + Trimmed, Col) then
  begin
    Result.Kind := pkColor;
    Result.Color := Col;
  end;
end;

function SVGParseLineCap(const S: string): TSVGLineCap;
var
  Low: string;
begin
  Low := LowerCase(Trim(S));
  if Low = 'round' then Result := slcRound
  else if Low = 'square' then Result := slcSquare
  else Result := slcButt;
end;

function SVGParseLineJoin(const S: string): TSVGLineJoin;
var
  Low: string;
begin
  Low := LowerCase(Trim(S));
  if Low = 'round' then Result := sljRound
  else if Low = 'bevel' then Result := sljBevel
  else Result := sljMiter;
end;

function SVGParseFillRule(const S: string): TSVGFillRule;
var
  Low: string;
begin
  Low := LowerCase(Trim(S));
  if Low = 'evenodd' then Result := sfrEvenOdd
  else Result := sfrNonZero;
end;

function SVGParseVisibility(const S: string): TSVGVisibility;
var
  Low: string;
begin
  Low := LowerCase(Trim(S));
  if Low = 'hidden' then Result := svHidden
  else if Low = 'collapse' then Result := svCollapse
  else Result := svVisible;
end;

function SVGParseDisplay(const S: string): TSVGDisplay;
var
  Low: string;
begin
  Low := LowerCase(Trim(S));
  if Low = 'none' then Result := sdNone
  else if Low = 'block' then Result := sdBlock
  else Result := sdInline;
end;

end.
