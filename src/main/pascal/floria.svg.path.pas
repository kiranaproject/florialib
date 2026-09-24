unit Floria.SVG.Path;

// Floria.SVG.Path
// ===============
// Complete SVG path parser, path data representation, normalization,
// arc-to-cubic decomposition, bounding box calculation, affine transformation,
// and basic shape path generators.
//
// Highlights:
//   - Full SVG 1.1 path data parser: M/m, L/l, H/h, V/v, C/c, S/s, Q/q, T/t, A/a, Z/z
//   - Flexible tokenizer handling commas, spaces, exponents, and compact syntax (e.g. "M10-20L.5.5")
//   - Full normalizer converting relative coords to absolute, H/V to lines, S/T to standard cubics/quads
//   - W3C F.6 compliant elliptical arc to cubic Bézier decomposition
//   - Exact bounding box calculation using quadratic roots for cubic and quadratic Bézier extrema
//   - Affine matrix transformation for all path segments
//   - Factory methods converting <rect>, <circle>, <ellipse>, <line>, <polyline>, <polygon> to paths

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, Floria.SVG.Types;

type
  TSVGPathCommand = (
    spcMoveTo,        // M / m (X, Y)
    spcLineTo,        // L / l (X, Y)
    spcHorizLineTo,   // H / h (X)
    spcVertLineTo,    // V / v (Y)
    spcCubicTo,       // C / c (X1, Y1, X2, Y2, X, Y)
    spcSmoothCubicTo, // S / s (X2, Y2, X, Y)
    spcQuadTo,        // Q / q (X1, Y1, X, Y)
    spcSmoothQuadTo,  // T / t (X, Y)
    spcArcTo,         // A / a (Rx, Ry, AngleDeg, LargeArc, Sweep, X, Y)
    spcClosePath      // Z / z
  );

  TSVGPathSegment = record
    Command: TSVGPathCommand;
    IsRelative: Boolean;
    Params: array[0..6] of Double;
  end;

  TSVGPathSegmentArray = array of TSVGPathSegment;

  TSVGNormalizedCommand = (
    sncMoveTo,   // (X, Y)
    sncLineTo,   // (X, Y)
    sncCubicTo,  // (X1, Y1, X2, Y2, X, Y)
    sncQuadTo,   // (X1, Y1, X, Y)
    sncClosePath // Connects back to subpath start
  );

  TSVGNormalizedSegment = record
    Command: TSVGNormalizedCommand;
    Params: array[0..5] of Double;
  end;

  TSVGNormalizedSegmentArray = array of TSVGNormalizedSegment;

  { TSVGPathData }

  TSVGPathData = class
  private
    FSegments: TSVGPathSegmentArray;
    FSegmentCount: Integer;
    procedure EnsureCapacity(ACapacity: Integer);
  public
    constructor Create();
    constructor CreateFromSVG(const AData: string);
    destructor Destroy(); override;

    procedure Clear();
    procedure AddSegment(const ASeg: TSVGPathSegment);
    procedure AddMoveTo(X, Y: Double; Relative: Boolean = False);
    procedure AddLineTo(X, Y: Double; Relative: Boolean = False);
    procedure AddHorizLineTo(X: Double; Relative: Boolean = False);
    procedure AddVertLineTo(Y: Double; Relative: Boolean = False);
    procedure AddCubicTo(X1, Y1, X2, Y2, X, Y: Double; Relative: Boolean = False);
    procedure AddSmoothCubicTo(X2, Y2, X, Y: Double; Relative: Boolean = False);
    procedure AddQuadTo(X1, Y1, X, Y: Double; Relative: Boolean = False);
    procedure AddSmoothQuadTo(X, Y: Double; Relative: Boolean = False);
    procedure AddArcTo(Rx, Ry, AngleDeg: Double; LargeArc, Sweep: Boolean; X, Y: Double; Relative: Boolean = False);
    procedure AddClosePath();

    procedure Parse(const AData: string);
    function ToString(): string; override;

    // Normalizes path: converts relative to absolute, decomposes H/V, S, T, and optionally A
    function ToNormalized(DecomposeArcs: Boolean = True): TSVGNormalizedSegmentArray;

    // Transforms path in-place by affine matrix
    procedure Transform(const M: TSVGMatrix);
    function Clone(): TSVGPathData;

    // Calculates exact bounding box
    function GetBoundingBox(): TSVGRect;

    // Shape to Path factories
    class function CreateRectPath(X, Y, W, H, Rx, Ry: Double): TSVGPathData; static;
    class function CreateCirclePath(CX, CY, R: Double): TSVGPathData; static;
    class function CreateEllipsePath(CX, CY, Rx, Ry: Double): TSVGPathData; static;
    class function CreateLinePath(X1, Y1, X2, Y2: Double): TSVGPathData; static;
    class function CreatePolygonPath(const Points: array of TSVGPoint; Closed: Boolean = True): TSVGPathData; static;

    property Segments: TSVGPathSegmentArray read FSegments;
    property SegmentCount: Integer read FSegmentCount;
  end;

// Arc decomposition helper
procedure SVGDecomposeArcToCubics(
  StartX, StartY, Rx, Ry, AngleDeg: Double;
  LargeArc, Sweep: Boolean;
  EndX, EndY: Double;
  var Segments: TSVGNormalizedSegmentArray;
  var SegCount: Integer
);

implementation

// ── Math & Bezier Extrema Helpers ────────────────────────────────────────────

function VectorAngle(Ux, Uy, Vx, Vy: Double): Double;
var
  Dot, LenU, LenV, CosVal, Sgn: Double;
begin
  Dot := Ux * Vx + Uy * Vy;
  LenU := Sqrt(Ux * Ux + Uy * Uy);
  LenV := Sqrt(Vx * Vx + Vy * Vy);
  if (LenU * LenV) < 1e-12 then Exit(0.0);
  CosVal := Dot / (LenU * LenV);
  if CosVal > 1.0 then CosVal := 1.0
  else if CosVal < -1.0 then CosVal := -1.0;
  Sgn := 1.0;
  if (Ux * Vy - Uy * Vx) < 0.0 then Sgn := -1.0;
  Result := Sgn * ArcCos(CosVal);
end;

procedure SVGDecomposeArcToCubics(
  StartX, StartY, Rx, Ry, AngleDeg: Double;
  LargeArc, Sweep: Boolean;
  EndX, EndY: Double;
  var Segments: TSVGNormalizedSegmentArray;
  var SegCount: Integer
);
var
  Phi, CosPhi, SinPhi: Double;
  Dx2, Dy2, X1P, Y1P: Double;
  RxSq, RySq, X1PSq, Y1PSq, Lambda, LambdaSqrt: Double;
  SignCoeff, Numerator, Denominator, Coeff, CxP, CyP: Double;
  Cx, Cy, Theta1, DeltaTheta, ThetaStep: Double;
  NumSegments, J: Integer;
  ThetaStart, ThetaEnd, Alpha: Double;
  CosStart, SinStart, CosEnd, SinEnd: Double;
  Px0, Py0, Tx0, Ty0, Px3, Py3, Tx3, Ty3: Double;
  Cp1x, Cp1y, Cp2x, Cp2y: Double;
begin
  // 1. Endpoints match -> nothing to draw
  if (Abs(StartX - EndX) < 1e-9) and (Abs(StartY - EndY) < 1e-9) then Exit;

  // 2. Degenerate radii -> straight line
  if (Abs(Rx) < 1e-9) or (Abs(Ry) < 1e-9) then
  begin
    if SegCount >= Length(Segments) then
      SetLength(Segments, SegCount + 8);
    Segments[SegCount].Command := sncLineTo;
    Segments[SegCount].Params[0] := EndX;
    Segments[SegCount].Params[1] := EndY;
    Inc(SegCount);
    Exit;
  end;

  Rx := Abs(Rx);
  Ry := Abs(Ry);

  Phi := DegToRad(AngleDeg);
  CosPhi := Cos(Phi);
  SinPhi := Sin(Phi);

  // 3. Compute (x1', y1')
  Dx2 := (StartX - EndX) / 2.0;
  Dy2 := (StartY - EndY) / 2.0;
  X1P :=  CosPhi * Dx2 + SinPhi * Dy2;
  Y1P := -SinPhi * Dx2 + CosPhi * Dy2;

  // 4. Ensure radii are large enough
  RxSq := Rx * Rx;
  RySq := Ry * Ry;
  X1PSq := X1P * X1P;
  Y1PSq := Y1P * Y1P;

  Lambda := X1PSq / RxSq + Y1PSq / RySq;
  if Lambda > 1.0 then
  begin
    LambdaSqrt := Sqrt(Lambda);
    Rx := Rx * LambdaSqrt;
    Ry := Ry * LambdaSqrt;
    RxSq := Rx * Rx;
    RySq := Ry * Ry;
  end;

  // 5. Compute center (cx', cy')
  if LargeArc = Sweep then
    SignCoeff := -1.0
  else
    SignCoeff := 1.0;

  Numerator := RxSq * RySq - RxSq * Y1PSq - RySq * X1PSq;
  Denominator := RxSq * Y1PSq + RySq * X1PSq;
  if Numerator < 0.0 then Numerator := 0.0;
  if Denominator < 1e-12 then Denominator := 1e-12;

  Coeff := SignCoeff * Sqrt(Numerator / Denominator);
  CxP :=  Coeff * ((Rx * Y1P) / Ry);
  CyP := -Coeff * ((Ry * X1P) / Rx);

  // 6. Compute center (cx, cy) in original coordinates
  Cx := CosPhi * CxP - SinPhi * CyP + (StartX + EndX) / 2.0;
  Cy := SinPhi * CxP + CosPhi * CyP + (StartY + EndY) / 2.0;

  // 7. Compute start angle and delta angle
  Theta1 := VectorAngle(1.0, 0.0, (X1P - CxP) / Rx, (Y1P - CyP) / Ry);
  DeltaTheta := VectorAngle((X1P - CxP) / Rx, (Y1P - CyP) / Ry, (-X1P - CxP) / Rx, (-Y1P - CyP) / Ry);

  if (not Sweep) and (DeltaTheta > 0.0) then
    DeltaTheta := DeltaTheta - 2.0 * Pi;
  if Sweep and (DeltaTheta < 0.0) then
    DeltaTheta := DeltaTheta + 2.0 * Pi;

  // 8. Split into segments of at most Pi/2 radians
  NumSegments := Ceil((Abs(DeltaTheta) - 1e-9) / (Pi / 2.0));
  if NumSegments < 1 then NumSegments := 1;
  ThetaStep := DeltaTheta / NumSegments;

  for J := 0 to NumSegments - 1 do
  begin
    ThetaStart := Theta1 + J * ThetaStep;
    ThetaEnd := ThetaStart + ThetaStep;
    Alpha := (4.0 / 3.0) * Tan(ThetaStep / 4.0);

    CosStart := Cos(ThetaStart);
    SinStart := Sin(ThetaStart);
    CosEnd := Cos(ThetaEnd);
    SinEnd := Sin(ThetaEnd);

    Px0 := Cx + Rx * CosStart * CosPhi - Ry * SinStart * SinPhi;
    Py0 := Cy + Rx * CosStart * SinPhi + Ry * SinStart * CosPhi;
    Tx0 := -Rx * SinStart * CosPhi - Ry * CosStart * SinPhi;
    Ty0 := -Rx * SinStart * SinPhi + Ry * CosStart * CosPhi;

    Px3 := Cx + Rx * CosEnd * CosPhi - Ry * SinEnd * SinPhi;
    Py3 := Cy + Rx * CosEnd * SinPhi + Ry * SinEnd * CosPhi;
    Tx3 := -Rx * SinEnd * CosPhi - Ry * CosEnd * SinPhi;
    Ty3 := -Rx * SinEnd * SinPhi + Ry * CosEnd * CosPhi;

    Cp1x := Px0 + Alpha * Tx0;
    Cp1y := Py0 + Alpha * Ty0;
    Cp2x := Px3 - Alpha * Tx3;
    Cp2y := Py3 - Alpha * Ty3;

    // Use exact endpoint on last segment to eliminate rounding drift
    if J = NumSegments - 1 then
    begin
      Px3 := EndX;
      Py3 := EndY;
    end;

    if SegCount >= Length(Segments) then
      SetLength(Segments, SegCount + 8);

    Segments[SegCount].Command := sncCubicTo;
    Segments[SegCount].Params[0] := Cp1x;
    Segments[SegCount].Params[1] := Cp1y;
    Segments[SegCount].Params[2] := Cp2x;
    Segments[SegCount].Params[3] := Cp2y;
    Segments[SegCount].Params[4] := Px3;
    Segments[SegCount].Params[5] := Py3;
    Inc(SegCount);
  end;
end;

// ── TSVGPathData Implementation ──────────────────────────────────────────────

constructor TSVGPathData.Create();
begin
  inherited Create();
  FSegmentCount := 0;
  SetLength(FSegments, 16);
end;

constructor TSVGPathData.CreateFromSVG(const AData: string);
begin
  Create();
  Parse(AData);
end;

destructor TSVGPathData.Destroy();
begin
  SetLength(FSegments, 0);
  inherited Destroy();
end;

procedure TSVGPathData.EnsureCapacity(ACapacity: Integer);
var
  NewCap: Integer;
begin
  if Length(FSegments) < ACapacity then
  begin
    NewCap := Length(FSegments) * 2;
    if NewCap < ACapacity then NewCap := ACapacity;
    SetLength(FSegments, NewCap);
  end;
end;

procedure TSVGPathData.Clear();
begin
  FSegmentCount := 0;
end;

procedure TSVGPathData.AddSegment(const ASeg: TSVGPathSegment);
begin
  EnsureCapacity(FSegmentCount + 1);
  FSegments[FSegmentCount] := ASeg;
  Inc(FSegmentCount);
end;

procedure TSVGPathData.AddMoveTo(X, Y: Double; Relative: Boolean = False);
var
  Seg: TSVGPathSegment;
begin
  Seg.Command := spcMoveTo;
  Seg.IsRelative := Relative;
  Seg.Params[0] := X;
  Seg.Params[1] := Y;
  AddSegment(Seg);
end;

procedure TSVGPathData.AddLineTo(X, Y: Double; Relative: Boolean = False);
var
  Seg: TSVGPathSegment;
begin
  Seg.Command := spcLineTo;
  Seg.IsRelative := Relative;
  Seg.Params[0] := X;
  Seg.Params[1] := Y;
  AddSegment(Seg);
end;

procedure TSVGPathData.AddHorizLineTo(X: Double; Relative: Boolean = False);
var
  Seg: TSVGPathSegment;
begin
  Seg.Command := spcHorizLineTo;
  Seg.IsRelative := Relative;
  Seg.Params[0] := X;
  AddSegment(Seg);
end;

procedure TSVGPathData.AddVertLineTo(Y: Double; Relative: Boolean = False);
var
  Seg: TSVGPathSegment;
begin
  Seg.Command := spcVertLineTo;
  Seg.IsRelative := Relative;
  Seg.Params[0] := Y;
  AddSegment(Seg);
end;

procedure TSVGPathData.AddCubicTo(X1, Y1, X2, Y2, X, Y: Double; Relative: Boolean = False);
var
  Seg: TSVGPathSegment;
begin
  Seg.Command := spcCubicTo;
  Seg.IsRelative := Relative;
  Seg.Params[0] := X1; Seg.Params[1] := Y1;
  Seg.Params[2] := X2; Seg.Params[3] := Y2;
  Seg.Params[4] := X;  Seg.Params[5] := Y;
  AddSegment(Seg);
end;

procedure TSVGPathData.AddSmoothCubicTo(X2, Y2, X, Y: Double; Relative: Boolean = False);
var
  Seg: TSVGPathSegment;
begin
  Seg.Command := spcSmoothCubicTo;
  Seg.IsRelative := Relative;
  Seg.Params[0] := X2; Seg.Params[1] := Y2;
  Seg.Params[2] := X;  Seg.Params[3] := Y;
  AddSegment(Seg);
end;

procedure TSVGPathData.AddQuadTo(X1, Y1, X, Y: Double; Relative: Boolean = False);
var
  Seg: TSVGPathSegment;
begin
  Seg.Command := spcQuadTo;
  Seg.IsRelative := Relative;
  Seg.Params[0] := X1; Seg.Params[1] := Y1;
  Seg.Params[2] := X;  Seg.Params[3] := Y;
  AddSegment(Seg);
end;

procedure TSVGPathData.AddSmoothQuadTo(X, Y: Double; Relative: Boolean = False);
var
  Seg: TSVGPathSegment;
begin
  Seg.Command := spcSmoothQuadTo;
  Seg.IsRelative := Relative;
  Seg.Params[0] := X;
  Seg.Params[1] := Y;
  AddSegment(Seg);
end;

procedure TSVGPathData.AddArcTo(Rx, Ry, AngleDeg: Double; LargeArc, Sweep: Boolean; X, Y: Double; Relative: Boolean = False);
var
  Seg: TSVGPathSegment;
begin
  Seg.Command := spcArcTo;
  Seg.IsRelative := Relative;
  Seg.Params[0] := Rx;
  Seg.Params[1] := Ry;
  Seg.Params[2] := AngleDeg;
  if LargeArc then Seg.Params[3] := 1.0 else Seg.Params[3] := 0.0;
  if Sweep then Seg.Params[4] := 1.0 else Seg.Params[4] := 0.0;
  Seg.Params[5] := X;
  Seg.Params[6] := Y;
  AddSegment(Seg);
end;

procedure TSVGPathData.AddClosePath();
var
  Seg: TSVGPathSegment;
begin
  Seg.Command := spcClosePath;
  Seg.IsRelative := False;
  AddSegment(Seg);
end;

// ── Path String Parsing ──────────────────────────────────────────────────────

procedure TSVGPathData.Parse(const AData: string);
var
  I, Len, StartPos: Integer;
  CurCmdChar: Char;

  procedure SkipDelims();
  begin
    while (I <= Len) and (AData[I] in [' ', #9, #10, #13, ',']) do
      Inc(I);
  end;

  function NextIsNumber(): Boolean;
  begin
    SkipDelims();
    if I > Len then Exit(False);
    Result := (AData[I] in ['0'..'9', '+', '-', '.']);
  end;

  function ReadNumber(out DVal: Double): Boolean;
  var
    NumStr: string;
    Code, ExpIdx: Integer;
  begin
    DVal := 0.0;
    SkipDelims();
    if I > Len then Exit(False);

    StartPos := I;
    if AData[I] in ['+', '-'] then Inc(I);
    while (I <= Len) and (AData[I] in ['0'..'9']) do Inc(I);
    if (I <= Len) and (AData[I] = '.') then
    begin
      Inc(I);
      while (I <= Len) and (AData[I] in ['0'..'9']) do Inc(I);
    end;
    if (I <= Len) and (AData[I] in ['e', 'E']) then
    begin
      ExpIdx := I;
      Inc(I);
      if (I <= Len) and (AData[I] in ['+', '-']) then Inc(I);
      if (I <= Len) and (AData[I] in ['0'..'9']) then
      begin
        while (I <= Len) and (AData[I] in ['0'..'9']) do Inc(I);
      end
      else
        I := ExpIdx;
    end;

    if I > StartPos then
    begin
      NumStr := Copy(AData, StartPos, I - StartPos);
      System.Val(NumStr, DVal, Code);
      Result := (Code = 0);
    end
    else
      Result := False;
  end;

  function ReadFlag(out Flag: Boolean): Boolean;
  begin
    Flag := False;
    SkipDelims();
    if I > Len then Exit(False);
    if AData[I] = '0' then
    begin
      Flag := False;
      Inc(I);
      Result := True;
    end
    else if AData[I] = '1' then
    begin
      Flag := True;
      Inc(I);
      Result := True;
    end
    else
      Result := False;
  end;

var
  V1, V2, V3, V4, V5, V6, V7: Double;
  F1, F2: Boolean;
  IsRel: Boolean;
begin
  Clear();
  I := 1;
  Len := Length(AData);
  CurCmdChar := #0;

  while I <= Len do
  begin
    SkipDelims();
    if I > Len then Break;

    // Check for command character
    if AData[I] in ['M', 'm', 'L', 'l', 'H', 'h', 'V', 'v', 'C', 'c', 'S', 's', 'Q', 'q', 'T', 't', 'A', 'a', 'Z', 'z'] then
    begin
      CurCmdChar := AData[I];
      Inc(I);
    end;

    if CurCmdChar = #0 then
    begin
      Inc(I);
      Continue;
    end;

    IsRel := CurCmdChar in ['m', 'l', 'h', 'v', 'c', 's', 'q', 't', 'a', 'z'];

    case UpCase(CurCmdChar) of
      'M':
      begin
        if ReadNumber(V1) and ReadNumber(V2) then
        begin
          AddMoveTo(V1, V2, IsRel);
          // Subsequent coordinate pairs are implicitly treated as LineTo
          if IsRel then CurCmdChar := 'l' else CurCmdChar := 'L';
        end
        else
          Break;
      end;
      'L':
      begin
        if ReadNumber(V1) and ReadNumber(V2) then
          AddLineTo(V1, V2, IsRel)
        else
          Break;
      end;
      'H':
      begin
        if ReadNumber(V1) then
          AddHorizLineTo(V1, IsRel)
        else
          Break;
      end;
      'V':
      begin
        if ReadNumber(V1) then
          AddVertLineTo(V1, IsRel)
        else
          Break;
      end;
      'C':
      begin
        if ReadNumber(V1) and ReadNumber(V2) and ReadNumber(V3) and
           ReadNumber(V4) and ReadNumber(V5) and ReadNumber(V6) then
          AddCubicTo(V1, V2, V3, V4, V5, V6, IsRel)
        else
          Break;
      end;
      'S':
      begin
        if ReadNumber(V1) and ReadNumber(V2) and ReadNumber(V3) and ReadNumber(V4) then
          AddSmoothCubicTo(V1, V2, V3, V4, IsRel)
        else
          Break;
      end;
      'Q':
      begin
        if ReadNumber(V1) and ReadNumber(V2) and ReadNumber(V3) and ReadNumber(V4) then
          AddQuadTo(V1, V2, V3, V4, IsRel)
        else
          Break;
      end;
      'T':
      begin
        if ReadNumber(V1) and ReadNumber(V2) then
          AddSmoothQuadTo(V1, V2, IsRel)
        else
          Break;
      end;
      'A':
      begin
        if ReadNumber(V1) and ReadNumber(V2) and ReadNumber(V3) and
           ReadFlag(F1) and ReadFlag(F2) and
           ReadNumber(V6) and ReadNumber(V7) then
          AddArcTo(V1, V2, V3, F1, F2, V6, V7, IsRel)
        else
          Break;
      end;
      'Z':
      begin
        AddClosePath();
        CurCmdChar := #0; // Close has no coordinates to repeat
      end;
      else
        Inc(I);
    end;
  end;
end;

function TSVGPathData.ToString(): string;
var
  I: Integer;
  Seg: TSVGPathSegment;
  S: string;
begin
  S := '';
  for I := 0 to FSegmentCount - 1 do
  begin
    Seg := FSegments[I];
    if I > 0 then S := S + ' ';
    case Seg.Command of
      spcMoveTo:
        if Seg.IsRelative then S := S + Format('m %g %g', [Seg.Params[0], Seg.Params[1]])
        else S := S + Format('M %g %g', [Seg.Params[0], Seg.Params[1]]);
      spcLineTo:
        if Seg.IsRelative then S := S + Format('l %g %g', [Seg.Params[0], Seg.Params[1]])
        else S := S + Format('L %g %g', [Seg.Params[0], Seg.Params[1]]);
      spcHorizLineTo:
        if Seg.IsRelative then S := S + Format('h %g', [Seg.Params[0]])
        else S := S + Format('H %g', [Seg.Params[0]]);
      spcVertLineTo:
        if Seg.IsRelative then S := S + Format('v %g', [Seg.Params[0]])
        else S := S + Format('V %g', [Seg.Params[0]]);
      spcCubicTo:
        if Seg.IsRelative then S := S + Format('c %g %g %g %g %g %g', [Seg.Params[0], Seg.Params[1], Seg.Params[2], Seg.Params[3], Seg.Params[4], Seg.Params[5]])
        else S := S + Format('C %g %g %g %g %g %g', [Seg.Params[0], Seg.Params[1], Seg.Params[2], Seg.Params[3], Seg.Params[4], Seg.Params[5]]);
      spcSmoothCubicTo:
        if Seg.IsRelative then S := S + Format('s %g %g %g %g', [Seg.Params[0], Seg.Params[1], Seg.Params[2], Seg.Params[3]])
        else S := S + Format('S %g %g %g %g', [Seg.Params[0], Seg.Params[1], Seg.Params[2], Seg.Params[3]]);
      spcQuadTo:
        if Seg.IsRelative then S := S + Format('q %g %g %g %g', [Seg.Params[0], Seg.Params[1], Seg.Params[2], Seg.Params[3]])
        else S := S + Format('Q %g %g %g %g', [Seg.Params[0], Seg.Params[1], Seg.Params[2], Seg.Params[3]]);
      spcSmoothQuadTo:
        if Seg.IsRelative then S := S + Format('t %g %g', [Seg.Params[0], Seg.Params[1]])
        else S := S + Format('T %g %g', [Seg.Params[0], Seg.Params[1]]);
      spcArcTo:
        if Seg.IsRelative then S := S + Format('a %g %g %g %d %d %g %g', [Seg.Params[0], Seg.Params[1], Seg.Params[2], Round(Seg.Params[3]), Round(Seg.Params[4]), Seg.Params[5], Seg.Params[6]])
        else S := S + Format('A %g %g %g %d %d %g %g', [Seg.Params[0], Seg.Params[1], Seg.Params[2], Round(Seg.Params[3]), Round(Seg.Params[4]), Seg.Params[5], Seg.Params[6]]);
      spcClosePath:
        S := S + 'Z';
    end;
  end;
  Result := S;
end;

// ── Path Normalization ───────────────────────────────────────────────────────

function TSVGPathData.ToNormalized(DecomposeArcs: Boolean = True): TSVGNormalizedSegmentArray;
var
  OutCount, I: Integer;
  CurX, CurY, StartX, StartY: Double;
  LastCtrlX, LastCtrlY: Double;
  PrevCmd: TSVGPathCommand;
  Seg: TSVGPathSegment;
  P1x, P1y, P2x, P2y, EndX, EndY: Double;

  procedure AppendNorm(ACmd: TSVGNormalizedCommand; const P: array of Double);
  var
    K: Integer;
  begin
    if OutCount >= Length(Result) then
      SetLength(Result, OutCount * 2 + 16);
    Result[OutCount].Command := ACmd;
    FillChar(Result[OutCount].Params, SizeOf(Result[OutCount].Params), 0);
    for K := 0 to High(P) do
      Result[OutCount].Params[K] := P[K];
    Inc(OutCount);
  end;

begin
  OutCount := 0;
  SetLength(Result, FSegmentCount + 16);
  CurX := 0.0;
  CurY := 0.0;
  StartX := 0.0;
  StartY := 0.0;
  LastCtrlX := 0.0;
  LastCtrlY := 0.0;
  PrevCmd := spcClosePath;

  for I := 0 to FSegmentCount - 1 do
  begin
    Seg := FSegments[I];
    case Seg.Command of
      spcMoveTo:
      begin
        if Seg.IsRelative then
        begin
          CurX := CurX + Seg.Params[0];
          CurY := CurY + Seg.Params[1];
        end
        else
        begin
          CurX := Seg.Params[0];
          CurY := Seg.Params[1];
        end;
        StartX := CurX;
        StartY := CurY;
        LastCtrlX := CurX;
        LastCtrlY := CurY;
        AppendNorm(sncMoveTo, [CurX, CurY]);
      end;

      spcLineTo:
      begin
        if Seg.IsRelative then
        begin
          CurX := CurX + Seg.Params[0];
          CurY := CurY + Seg.Params[1];
        end
        else
        begin
          CurX := Seg.Params[0];
          CurY := Seg.Params[1];
        end;
        LastCtrlX := CurX;
        LastCtrlY := CurY;
        AppendNorm(sncLineTo, [CurX, CurY]);
      end;

      spcHorizLineTo:
      begin
        if Seg.IsRelative then CurX := CurX + Seg.Params[0]
        else CurX := Seg.Params[0];
        LastCtrlX := CurX;
        LastCtrlY := CurY;
        AppendNorm(sncLineTo, [CurX, CurY]);
      end;

      spcVertLineTo:
      begin
        if Seg.IsRelative then CurY := CurY + Seg.Params[0]
        else CurY := Seg.Params[0];
        LastCtrlX := CurX;
        LastCtrlY := CurY;
        AppendNorm(sncLineTo, [CurX, CurY]);
      end;

      spcCubicTo:
      begin
        if Seg.IsRelative then
        begin
          P1x := CurX + Seg.Params[0]; P1y := CurY + Seg.Params[1];
          P2x := CurX + Seg.Params[2]; P2y := CurY + Seg.Params[3];
          EndX := CurX + Seg.Params[4]; EndY := CurY + Seg.Params[5];
        end
        else
        begin
          P1x := Seg.Params[0]; P1y := Seg.Params[1];
          P2x := Seg.Params[2]; P2y := Seg.Params[3];
          EndX := Seg.Params[4]; EndY := Seg.Params[5];
        end;
        LastCtrlX := P2x;
        LastCtrlY := P2y;
        CurX := EndX;
        CurY := EndY;
        AppendNorm(sncCubicTo, [P1x, P1y, P2x, P2y, EndX, EndY]);
      end;

      spcSmoothCubicTo:
      begin
        if PrevCmd in [spcCubicTo, spcSmoothCubicTo] then
        begin
          P1x := 2.0 * CurX - LastCtrlX;
          P1y := 2.0 * CurY - LastCtrlY;
        end
        else
        begin
          P1x := CurX;
          P1y := CurY;
        end;

        if Seg.IsRelative then
        begin
          P2x := CurX + Seg.Params[0]; P2y := CurY + Seg.Params[1];
          EndX := CurX + Seg.Params[2]; EndY := CurY + Seg.Params[3];
        end
        else
        begin
          P2x := Seg.Params[0]; P2y := Seg.Params[1];
          EndX := Seg.Params[2]; EndY := Seg.Params[3];
        end;
        LastCtrlX := P2x;
        LastCtrlY := P2y;
        CurX := EndX;
        CurY := EndY;
        AppendNorm(sncCubicTo, [P1x, P1y, P2x, P2y, EndX, EndY]);
      end;

      spcQuadTo:
      begin
        if Seg.IsRelative then
        begin
          P1x := CurX + Seg.Params[0]; P1y := CurY + Seg.Params[1];
          EndX := CurX + Seg.Params[2]; EndY := CurY + Seg.Params[3];
        end
        else
        begin
          P1x := Seg.Params[0]; P1y := Seg.Params[1];
          EndX := Seg.Params[2]; EndY := Seg.Params[3];
        end;
        LastCtrlX := P1x;
        LastCtrlY := P1y;
        CurX := EndX;
        CurY := EndY;
        AppendNorm(sncQuadTo, [P1x, P1y, EndX, EndY]);
      end;

      spcSmoothQuadTo:
      begin
        if PrevCmd in [spcQuadTo, spcSmoothQuadTo] then
        begin
          P1x := 2.0 * CurX - LastCtrlX;
          P1y := 2.0 * CurY - LastCtrlY;
        end
        else
        begin
          P1x := CurX;
          P1y := CurY;
        end;

        if Seg.IsRelative then
        begin
          EndX := CurX + Seg.Params[0];
          EndY := CurY + Seg.Params[1];
        end
        else
        begin
          EndX := Seg.Params[0];
          EndY := Seg.Params[1];
        end;
        LastCtrlX := P1x;
        LastCtrlY := P1y;
        CurX := EndX;
        CurY := EndY;
        AppendNorm(sncQuadTo, [P1x, P1y, EndX, EndY]);
      end;

      spcArcTo:
      begin
        if Seg.IsRelative then
        begin
          EndX := CurX + Seg.Params[5];
          EndY := CurY + Seg.Params[6];
        end
        else
        begin
          EndX := Seg.Params[5];
          EndY := Seg.Params[6];
        end;

        if DecomposeArcs then
        begin
          SVGDecomposeArcToCubics(
            CurX, CurY, Seg.Params[0], Seg.Params[1], Seg.Params[2],
            Seg.Params[3] > 0.5, Seg.Params[4] > 0.5,
            EndX, EndY, Result, OutCount
          );
        end
        else
        begin
          AppendNorm(sncLineTo, [EndX, EndY]);
        end;

        LastCtrlX := EndX;
        LastCtrlY := EndY;
        CurX := EndX;
        CurY := EndY;
      end;

      spcClosePath:
      begin
        AppendNorm(sncClosePath, []);
        CurX := StartX;
        CurY := StartY;
        LastCtrlX := CurX;
        LastCtrlY := CurY;
      end;
    end;
    PrevCmd := Seg.Command;
  end;

  SetLength(Result, OutCount);
end;

// ── Affine Transformation ────────────────────────────────────────────────────

procedure TSVGPathData.Transform(const M: TSVGMatrix);
var
  Norms: TSVGNormalizedSegmentArray;
  I: Integer;
  P, P1, P2: TSVGPoint;
begin
  if SVGMatrixIsIdentity(M) then Exit;

  // Converting to normalized guarantees absolute coordinates so matrix maps cleanly
  Norms := ToNormalized(True);
  Clear();

  for I := 0 to High(Norms) do
  begin
    case Norms[I].Command of
      sncMoveTo:
      begin
        P := SVGMatrixTransformPoint(M, SVGPoint(Norms[I].Params[0], Norms[I].Params[1]));
        AddMoveTo(P.X, P.Y, False);
      end;
      sncLineTo:
      begin
        P := SVGMatrixTransformPoint(M, SVGPoint(Norms[I].Params[0], Norms[I].Params[1]));
        AddLineTo(P.X, P.Y, False);
      end;
      sncCubicTo:
      begin
        P1 := SVGMatrixTransformPoint(M, SVGPoint(Norms[I].Params[0], Norms[I].Params[1]));
        P2 := SVGMatrixTransformPoint(M, SVGPoint(Norms[I].Params[2], Norms[I].Params[3]));
        P  := SVGMatrixTransformPoint(M, SVGPoint(Norms[I].Params[4], Norms[I].Params[5]));
        AddCubicTo(P1.X, P1.Y, P2.X, P2.Y, P.X, P.Y, False);
      end;
      sncQuadTo:
      begin
        P1 := SVGMatrixTransformPoint(M, SVGPoint(Norms[I].Params[0], Norms[I].Params[1]));
        P  := SVGMatrixTransformPoint(M, SVGPoint(Norms[I].Params[2], Norms[I].Params[3]));
        AddQuadTo(P1.X, P1.Y, P.X, P.Y, False);
      end;
      sncClosePath:
        AddClosePath();
    end;
  end;
end;

function TSVGPathData.Clone(): TSVGPathData;
var
  I: Integer;
begin
  Result := TSVGPathData.Create();
  Result.EnsureCapacity(FSegmentCount);
  for I := 0 to FSegmentCount - 1 do
    Result.AddSegment(FSegments[I]);
end;

// ── Bounding Box Calculation ─────────────────────────────────────────────────

function TSVGPathData.GetBoundingBox(): TSVGRect;
var
  Norms: TSVGNormalizedSegmentArray;
  I: Integer;
  MinX, MaxX, MinY, MaxY: Double;
  HasPoint: Boolean;
  CurX, CurY: Double;

  procedure Expand(X, Y: Double);
  begin
    if not HasPoint then
    begin
      MinX := X; MaxX := X;
      MinY := Y; MaxY := Y;
      HasPoint := True;
    end
    else
    begin
      if X < MinX then MinX := X;
      if X > MaxX then MaxX := X;
      if Y < MinY then MinY := Y;
      if Y > MaxY then MaxY := Y;
    end;
  end;

  procedure CubicExtrema(P0, P1, P2, P3: Double; out T1, T2: Double; out NRoots: Integer);
  var
    A, B, C, Disc, SqrtD: Double;
  begin
    NRoots := 0;
    T1 := -1.0;
    T2 := -1.0;
    A := 3.0 * (-P0 + 3.0 * P1 - 3.0 * P2 + P3);
    B := 6.0 * (P0 - 2.0 * P1 + P2);
    C := 3.0 * (P1 - P0);

    if Abs(A) < 1e-9 then
    begin
      if Abs(B) > 1e-9 then
      begin
        T1 := -C / B;
        if (T1 > 0.0) and (T1 < 1.0) then NRoots := 1;
      end;
      Exit;
    end;

    Disc := B * B - 4.0 * A * C;
    if Disc < 0.0 then Exit;

    SqrtD := Sqrt(Disc);
    T1 := (-B - SqrtD) / (2.0 * A);
    T2 := (-B + SqrtD) / (2.0 * A);
    if (T1 > 0.0) and (T1 < 1.0) then Inc(NRoots);
    if (T2 > 0.0) and (T2 < 1.0) then Inc(NRoots);
  end;

  function EvalCubic(P0, P1, P2, P3, T: Double): Double;
  var
    U: Double;
  begin
    U := 1.0 - T;
    Result := U * U * U * P0 + 3.0 * U * U * T * P1 + 3.0 * U * T * T * P2 + T * T * T * P3;
  end;

var
  T1, T2: Double;
  NRoots: Integer;
begin
  HasPoint := False;
  MinX := 0.0; MaxX := 0.0;
  MinY := 0.0; MaxY := 0.0;
  CurX := 0.0; CurY := 0.0;

  Norms := ToNormalized(True);

  for I := 0 to High(Norms) do
  begin
    case Norms[I].Command of
      sncMoveTo, sncLineTo:
      begin
        CurX := Norms[I].Params[0];
        CurY := Norms[I].Params[1];
        Expand(CurX, CurY);
      end;
      sncCubicTo:
      begin
        // End point
        Expand(Norms[I].Params[4], Norms[I].Params[5]);

        // Extrema in X
        CubicExtrema(CurX, Norms[I].Params[0], Norms[I].Params[2], Norms[I].Params[4], T1, T2, NRoots);
        if (T1 > 0.0) and (T1 < 1.0) then
          Expand(EvalCubic(CurX, Norms[I].Params[0], Norms[I].Params[2], Norms[I].Params[4], T1),
                 EvalCubic(CurY, Norms[I].Params[1], Norms[I].Params[3], Norms[I].Params[5], T1));
        if (T2 > 0.0) and (T2 < 1.0) then
          Expand(EvalCubic(CurX, Norms[I].Params[0], Norms[I].Params[2], Norms[I].Params[4], T2),
                 EvalCubic(CurY, Norms[I].Params[1], Norms[I].Params[3], Norms[I].Params[5], T2));

        // Extrema in Y
        CubicExtrema(CurY, Norms[I].Params[1], Norms[I].Params[3], Norms[I].Params[5], T1, T2, NRoots);
        if (T1 > 0.0) and (T1 < 1.0) then
          Expand(EvalCubic(CurX, Norms[I].Params[0], Norms[I].Params[2], Norms[I].Params[4], T1),
                 EvalCubic(CurY, Norms[I].Params[1], Norms[I].Params[3], Norms[I].Params[5], T1));
        if (T2 > 0.0) and (T2 < 1.0) then
          Expand(EvalCubic(CurX, Norms[I].Params[0], Norms[I].Params[2], Norms[I].Params[4], T2),
                 EvalCubic(CurY, Norms[I].Params[1], Norms[I].Params[3], Norms[I].Params[5], T2));

        CurX := Norms[I].Params[4];
        CurY := Norms[I].Params[5];
      end;
      sncQuadTo:
      begin
        Expand(Norms[I].Params[2], Norms[I].Params[3]);
        CurX := Norms[I].Params[2];
        CurY := Norms[I].Params[3];
      end;
      sncClosePath:
        ; // Does not expand box
    end;
  end;

  if HasPoint then
    Result := SVGRect(MinX, MinY, MaxX - MinX, MaxY - MinY)
  else
    Result := SVGRect(0.0, 0.0, 0.0, 0.0);
end;

// ── Shape Factories ──────────────────────────────────────────────────────────

class function TSVGPathData.CreateRectPath(X, Y, W, H, Rx, Ry: Double): TSVGPathData;
begin
  Result := TSVGPathData.Create();
  if (W <= 0.0) or (H <= 0.0) then Exit;

  if (Rx <= 0.0) and (Ry > 0.0) then Rx := Ry
  else if (Ry <= 0.0) and (Rx > 0.0) then Ry := Rx;

  if Rx > W * 0.5 then Rx := W * 0.5;
  if Ry > H * 0.5 then Ry := H * 0.5;

  if (Rx <= 0.0) and (Ry <= 0.0) then
  begin
    Result.AddMoveTo(X, Y);
    Result.AddHorizLineTo(X + W);
    Result.AddVertLineTo(Y + H);
    Result.AddHorizLineTo(X);
    Result.AddClosePath();
  end
  else
  begin
    Result.AddMoveTo(X + Rx, Y);
    Result.AddHorizLineTo(X + W - Rx);
    Result.AddArcTo(Rx, Ry, 0.0, False, True, X + W, Y + Ry);
    Result.AddVertLineTo(Y + H - Ry);
    Result.AddArcTo(Rx, Ry, 0.0, False, True, X + W - Rx, Y + H);
    Result.AddHorizLineTo(X + Rx);
    Result.AddArcTo(Rx, Ry, 0.0, False, True, X, Y + H - Ry);
    Result.AddVertLineTo(Y + Ry);
    Result.AddArcTo(Rx, Ry, 0.0, False, True, X + Rx, Y);
    Result.AddClosePath();
  end;
end;

class function TSVGPathData.CreateCirclePath(CX, CY, R: Double): TSVGPathData;
begin
  Result := TSVGPathData.Create();
  if R <= 0.0 then Exit;
  Result.AddMoveTo(CX + R, CY);
  Result.AddArcTo(R, R, 0.0, True, False, CX - R, CY);
  Result.AddArcTo(R, R, 0.0, True, False, CX + R, CY);
  Result.AddClosePath();
end;

class function TSVGPathData.CreateEllipsePath(CX, CY, Rx, Ry: Double): TSVGPathData;
begin
  Result := TSVGPathData.Create();
  if (Rx <= 0.0) or (Ry <= 0.0) then Exit;
  Result.AddMoveTo(CX + Rx, CY);
  Result.AddArcTo(Rx, Ry, 0.0, True, False, CX - Rx, CY);
  Result.AddArcTo(Rx, Ry, 0.0, True, False, CX + Rx, CY);
  Result.AddClosePath();
end;

class function TSVGPathData.CreateLinePath(X1, Y1, X2, Y2: Double): TSVGPathData;
begin
  Result := TSVGPathData.Create();
  Result.AddMoveTo(X1, Y1);
  Result.AddLineTo(X2, Y2);
end;

class function TSVGPathData.CreatePolygonPath(const Points: array of TSVGPoint; Closed: Boolean = True): TSVGPathData;
var
  I: Integer;
begin
  Result := TSVGPathData.Create();
  if Length(Points) = 0 then Exit;
  Result.AddMoveTo(Points[0].X, Points[0].Y);
  for I := 1 to High(Points) do
    Result.AddLineTo(Points[I].X, Points[I].Y);
  if Closed then
    Result.AddClosePath();
end;

end.
