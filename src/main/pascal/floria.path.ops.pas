unit Floria.Path.Ops;

// Floria.Path.Ops
// ===============
// High-level 2D boolean path and polygon operations for Floria Toolkit.
// Powered by Angus Johnson's Clipper2 engine. Pure Object Pascal, zero dependencies.
//
// Key Features:
//   - TFloriaPath: rich OOP vector path and polygon class
//   - First-class Boolean Operators: Union, Difference, Intersect, XOR
//   - Polygon Offsetting & Inflation (Round, Miter, Square, Bevel joins)
//   - Path Simplification & Douglas-Peucker reduction
//   - Winding Rule Support: NonZero, EvenOdd, Positive, Negative
//   - Seamless interoperability:
//       * AggPas path_storage
//       * SVG path data strings & TSVGPathData
//       * Clipper2 TPathsD / TPaths64

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Math,
  agg_basics,
  agg_path_storage,
  agg_conv_curve,
  Floria.SVG.Types,
  Floria.SVG.Path,
  Floria.Path.Clipper.Core,
  Floria.Path.Clipper.Engine,
  Floria.Path.Clipper.Offset,
  Floria.Path.Clipper.RectClip,
  Floria.Path.Clipper;

type
  // Fill & winding rules
  TFloriaPathFillRule = (
    fpfrNonZero, // Standard non-zero winding rule
    fpfrEvenOdd, // Alternating even-odd rule
    fpfrPositive,// Positive winding count > 0
    fpfrNegative // Negative winding count < 0
  );

  // Line join styles for polygon offsetting
  TFloriaPathJoinType = (
    fpjtRound,   // Rounded corners
    fpjtMiter,   // Sharp mitered corners up to MiterLimit
    fpjtSquare,  // Squared bevels at offset distance
    fpjtBevel    // Flat beveled corners
  );

  // Path end styles for stroke expansion
  TFloriaPathEndType = (
    fpetPolygon, // Closed polygon (offset exterior / interior)
    fpetJoined,  // Closed path offset both sides
    fpetButt,    // Open path, flat ends at line endpoints
    fpetSquare,  // Open path, extended square ends
    fpetRound    // Open path, rounded semi-circle caps
  );

  // Forward declaration
  TFloriaPath = class;

  // -------------------------------------------------------------------------
  // TFloriaPath
  // -------------------------------------------------------------------------
  TFloriaPath = class
  private
    FPaths: TPathsD;
    FCurrentPath: TPathD;
    FHasCurrentSubpath: Boolean;

    function GetSubpathCount(): Integer;
    function GetTotalPointCount(): Integer;
    function GetIsEmpty(): Boolean;
    procedure FlushCurrentSubpath();
  public
    constructor Create(); overload;
    constructor Create(const ASVGPathData: string); overload;
    destructor Destroy(); override;

    function Clone(): TFloriaPath;
    procedure Clear();

    // --- Path Construction ---
    procedure MoveTo(const X, Y: Double);
    procedure LineTo(const X, Y: Double);
    procedure QuadTo(const Cx, Cy, X, Y: Double; Tolerance: Double = 0.25);
    procedure CubicTo(const C1x, C1y, C2x, C2y, X, Y: Double; Tolerance: Double = 0.25);
    procedure ArcTo(const Rx, Ry, AngleDeg: Double; const LargeArc, Sweep: Boolean; const X, Y: Double);
    procedure Close();

    // --- Basic Shape Generators ---
    procedure AddRect(const X, Y, W, H: Double);
    procedure AddRoundedRect(const X, Y, W, H, Rx, Ry: Double; Steps: Integer = 12);
    procedure AddCircle(const Cx, Cy, Radius: Double; Steps: Integer = 36);
    procedure AddEllipse(const Cx, Cy, Rx, Ry: Double; Steps: Integer = 36);
    procedure AddPolygon(const Points: array of TPointD);
    procedure AddPath(APath: TFloriaPath);

    // --- Inspection ---
    property SubpathCount: Integer read GetSubpathCount;
    property TotalPointCount: Integer read GetTotalPointCount;
    property IsEmpty: Boolean read GetIsEmpty;
    function GetBounds(): TRectD;
    procedure Translate(const DX, DY: Double);
    function GetArea(): Double;
    property Bounds: TRectD read GetBounds;

    // --- Boolean Operations (Returns new TFloriaPath) ---
    function Union(AOther: TFloriaPath; AFillRule: TFloriaPathFillRule = fpfrNonZero): TFloriaPath;
    function Difference(AOther: TFloriaPath; AFillRule: TFloriaPathFillRule = fpfrNonZero): TFloriaPath;
    function Intersect(AOther: TFloriaPath; AFillRule: TFloriaPathFillRule = fpfrNonZero): TFloriaPath;
    function XorOp(AOther: TFloriaPath; AFillRule: TFloriaPathFillRule = fpfrNonZero): TFloriaPath;

    // --- Inflation, Offsetting & Simplification ---
    function Inflate(const ADelta: Double;
                     AJoinType: TFloriaPathJoinType = fpjtRound;
                     AEndType: TFloriaPathEndType = fpetPolygon;
                     const MiterLimit: Double = 2.0;
                     const ArcTolerance: Double = 0.0): TFloriaPath;
    function Simplify(const ATolerance: Double = 0.25): TFloriaPath;

    // --- Interoperability: Clipper TPathsD ---
    function ToPathsD(): TPathsD;
    procedure FromPathsD(const APaths: TPathsD);

    // --- Interoperability: AggPas path_storage ---
    procedure ExportToAggPath(var APathStorage: path_storage);
    procedure ImportFromAggPath(var APathStorage: path_storage);
    function ToAggPath(): path_storage;
    class function FromAggPath(var APathStorage: path_storage): TFloriaPath; static;

    // --- Interoperability: SVG ---
    function ToSVGString(): string;
    procedure FromSVGString(const AData: string);
    function ToSVGPathData(): TSVGPathData;
    procedure FromSVGPathData(APathData: TSVGPathData);
  end;

  // -------------------------------------------------------------------------
  // Free-standing Boolean Operations on TFloriaPath
  // -------------------------------------------------------------------------
  function PathUnion(const PathA, PathB: TFloriaPath; FillRule: TFloriaPathFillRule = fpfrNonZero): TFloriaPath;
  function PathDifference(const PathA, PathB: TFloriaPath; FillRule: TFloriaPathFillRule = fpfrNonZero): TFloriaPath;
  function PathIntersect(const PathA, PathB: TFloriaPath; FillRule: TFloriaPathFillRule = fpfrNonZero): TFloriaPath;
  function PathXor(const PathA, PathB: TFloriaPath; FillRule: TFloriaPathFillRule = fpfrNonZero): TFloriaPath;
  function PathInflate(const Path: TFloriaPath; Delta: Double;
                       JoinType: TFloriaPathJoinType = fpjtRound;
                       EndType: TFloriaPathEndType = fpetPolygon;
                       MiterLimit: Double = 2.0): TFloriaPath;
  function PathSimplify(const Path: TFloriaPath; Tolerance: Double = 0.25): TFloriaPath;

  // -------------------------------------------------------------------------
  // Direct Boolean Operations on AggPas path_storage
  // -------------------------------------------------------------------------
  function PathUnion(var PathA, PathB: path_storage; FillRule: TFloriaPathFillRule = fpfrNonZero): path_storage; overload;
  function PathDifference(var PathA, PathB: path_storage; FillRule: TFloriaPathFillRule = fpfrNonZero): path_storage; overload;
  function PathIntersect(var PathA, PathB: path_storage; FillRule: TFloriaPathFillRule = fpfrNonZero): path_storage; overload;
  function PathXor(var PathA, PathB: path_storage; FillRule: TFloriaPathFillRule = fpfrNonZero): path_storage; overload;

implementation

// ---------------------------------------------------------------------------
// Conversion Helpers for Clipper Enums
// ---------------------------------------------------------------------------

function ToClipperFillRule(FR: TFloriaPathFillRule): TFillRule; inline;
begin
  case FR of
    fpfrNonZero:  Result := frNonZero;
    fpfrEvenOdd:  Result := frEvenOdd;
    fpfrPositive: Result := frPositive;
    fpfrNegative: Result := frNegative;
  else
    Result := frNonZero;
  end;
end;

function ToClipperJoinType(JT: TFloriaPathJoinType): TJoinType; inline;
begin
  case JT of
    fpjtRound:  Result := jtRound;
    fpjtMiter:  Result := jtMiter;
    fpjtSquare: Result := jtSquare;
    fpjtBevel:  Result := jtBevel;
  else
    Result := jtRound;
  end;
end;

function ToClipperEndType(ET: TFloriaPathEndType): TEndType; inline;
begin
  case ET of
    fpetPolygon: Result := etPolygon;
    fpetJoined:  Result := etJoined;
    fpetButt:    Result := etButt;
    fpetSquare:  Result := etSquare;
    fpetRound:   Result := etRound;
  else
    Result := etPolygon;
  end;
end;

// ---------------------------------------------------------------------------
// Adaptive de Casteljau Subdivision for Bézier Curves
// ---------------------------------------------------------------------------

procedure SubdivideCubic(const P0x, P0y, P1x, P1y, P2x, P2y, P3x, P3y: Double;
                         ToleranceSq: Double; var Path: TPathD; Depth: Integer = 0);
var
  D1, D2: Double;
  Vx, Vy, L2, InvL: Double;
  Mid01X, Mid01Y, Mid12X, Mid12Y, Mid23X, Mid23Y: Double;
  MidA_X, MidA_Y, MidB_X, MidB_Y, CenterX, CenterY: Double;
  Len: Integer;
begin
  // Calculate distance from P1 and P2 to line segment (P0, P3)
  Vx := P3x - P0x;
  Vy := P3y - P0y;
  L2 := Vx * Vx + Vy * Vy;

  if (L2 < 1e-6) or (Depth >= 10) then
  begin
    Len := Length(Path);
    SetLength(Path, Len + 1);
    Path[Len].X := P3x;
    Path[Len].Y := P3y;
    Exit;
  end;

  InvL := 1.0 / Sqrt(L2);
  Vx := Vx * InvL;
  Vy := Vy * InvL;

  // Perpendicular distance squared from line
  D1 := Sqr((P1x - P0x) * (-Vy) + (P1y - P0y) * Vx);
  D2 := Sqr((P2x - P0x) * (-Vy) + (P2y - P0y) * Vx);

  if (D1 <= ToleranceSq) and (D2 <= ToleranceSq) then
  begin
    Len := Length(Path);
    SetLength(Path, Len + 1);
    Path[Len].X := P3x;
    Path[Len].Y := P3y;
  end
  else
  begin
    // Split at t = 0.5 using de Casteljau
    Mid01X := (P0x + P1x) * 0.5; Mid01Y := (P0y + P1y) * 0.5;
    Mid12X := (P1x + P2x) * 0.5; Mid12Y := (P1y + P2y) * 0.5;
    Mid23X := (P2x + P3x) * 0.5; Mid23Y := (P2y + P3y) * 0.5;

    MidA_X := (Mid01X + Mid12X) * 0.5; MidA_Y := (Mid01Y + Mid12Y) * 0.5;
    MidB_X := (Mid12X + Mid23X) * 0.5; MidB_Y := (Mid12Y + Mid23Y) * 0.5;

    CenterX := (MidA_X + MidB_X) * 0.5; CenterY := (MidA_Y + MidB_Y) * 0.5;

    SubdivideCubic(P0x, P0y, Mid01X, Mid01Y, MidA_X, MidA_Y, CenterX, CenterY,
                   ToleranceSq, Path, Depth + 1);
    SubdivideCubic(CenterX, CenterY, MidB_X, MidB_Y, Mid23X, Mid23Y, P3x, P3y,
                   ToleranceSq, Path, Depth + 1);
  end;
end;

// ---------------------------------------------------------------------------
// TFloriaPath Implementation
// ---------------------------------------------------------------------------

constructor TFloriaPath.Create();
begin
  inherited Create();
  SetLength(FPaths, 0);
  SetLength(FCurrentPath, 0);
  FHasCurrentSubpath := False;
end;

constructor TFloriaPath.Create(const ASVGPathData: string);
begin
  Create();
  FromSVGString(ASVGPathData);
end;

destructor TFloriaPath.Destroy();
begin
  Clear();
  inherited Destroy();
end;

function TFloriaPath.Clone(): TFloriaPath;
begin
  FlushCurrentSubpath();
  Result := TFloriaPath.Create();
  Result.FPaths := Copy(FPaths);
end;

procedure TFloriaPath.Clear();
begin
  SetLength(FPaths, 0);
  SetLength(FCurrentPath, 0);
  FHasCurrentSubpath := False;
end;

procedure TFloriaPath.FlushCurrentSubpath();
var
  L: Integer;
begin
  if FHasCurrentSubpath and (Length(FCurrentPath) > 0) then
  begin
    L := Length(FPaths);
    SetLength(FPaths, L + 1);
    FPaths[L] := Copy(FCurrentPath);
    SetLength(FCurrentPath, 0);
    FHasCurrentSubpath := False;
  end;
end;

procedure TFloriaPath.MoveTo(const X, Y: Double);
var
  Pt: TPointD;
begin
  FlushCurrentSubpath();
  Pt.X := X;
  Pt.Y := Y;
  SetLength(FCurrentPath, 1);
  FCurrentPath[0] := Pt;
  FHasCurrentSubpath := True;
end;

procedure TFloriaPath.LineTo(const X, Y: Double);
var
  L: Integer;
  Pt: TPointD;
begin
  Pt.X := X;
  Pt.Y := Y;
  if not FHasCurrentSubpath then
  begin
    MoveTo(0.0, 0.0);
  end;
  L := Length(FCurrentPath);
  SetLength(FCurrentPath, L + 1);
  FCurrentPath[L] := Pt;
end;

procedure TFloriaPath.QuadTo(const Cx, Cy, X, Y: Double; Tolerance: Double = 0.25);
var
  P0x, P0y: Double;
  C1x, C1y, C2x, C2y: Double;
begin
  if not FHasCurrentSubpath or (Length(FCurrentPath) = 0) then
    MoveTo(0.0, 0.0);

  P0x := FCurrentPath[High(FCurrentPath)].X;
  P0y := FCurrentPath[High(FCurrentPath)].Y;

  // Degree elevation from quadratic (P0, C, P3) to cubic:
  // C1 = P0 + 2/3 * (C - P0)
  // C2 = P3 + 2/3 * (C - P3)
  C1x := P0x + (2.0 / 3.0) * (Cx - P0x);
  C1y := P0y + (2.0 / 3.0) * (Cy - P0y);
  C2x := X + (2.0 / 3.0) * (Cx - X);
  C2y := Y + (2.0 / 3.0) * (Cy - Y);

  CubicTo(C1x, C1y, C2x, C2y, X, Y, Tolerance);
end;

procedure TFloriaPath.CubicTo(const C1x, C1y, C2x, C2y, X, Y: Double; Tolerance: Double = 0.25);
var
  P0x, P0y: Double;
begin
  if not FHasCurrentSubpath or (Length(FCurrentPath) = 0) then
    MoveTo(0.0, 0.0);

  P0x := FCurrentPath[High(FCurrentPath)].X;
  P0y := FCurrentPath[High(FCurrentPath)].Y;

  SubdivideCubic(P0x, P0y, C1x, C1y, C2x, C2y, X, Y, Sqr(Tolerance), FCurrentPath, 0);
end;

procedure TFloriaPath.ArcTo(const Rx, Ry, AngleDeg: Double; const LargeArc, Sweep: Boolean; const X, Y: Double);
var
  SvgData: TSVGPathData;
  CurX, CurY: Double;
  NormSegs: TSVGNormalizedSegmentArray;
  I: Integer;
begin
  if not FHasCurrentSubpath or (Length(FCurrentPath) = 0) then
    MoveTo(0.0, 0.0);

  CurX := FCurrentPath[High(FCurrentPath)].X;
  CurY := FCurrentPath[High(FCurrentPath)].Y;

  SvgData := TSVGPathData.Create();
  try
    SvgData.AddMoveTo(CurX, CurY);
    SvgData.AddArcTo(Rx, Ry, AngleDeg, LargeArc, Sweep, X, Y);
    NormSegs := SvgData.ToNormalized(True);

    // Skip the first MoveTo since we're already at CurX, CurY
    for I := 1 to High(NormSegs) do
    begin
      case NormSegs[I].Command of
        sncLineTo:
          LineTo(NormSegs[I].Params[0], NormSegs[I].Params[1]);
        sncCubicTo:
          CubicTo(NormSegs[I].Params[0], NormSegs[I].Params[1],
                  NormSegs[I].Params[2], NormSegs[I].Params[3],
                  NormSegs[I].Params[4], NormSegs[I].Params[5]);
      end;
    end;
  finally
    SvgData.Free();
  end;
end;

procedure TFloriaPath.Close();
begin
  if FHasCurrentSubpath and (Length(FCurrentPath) > 1) then
  begin
    // If last point duplicates start point, remove it for clean polygon topology
    while (Length(FCurrentPath) > 1) and
          (Abs(FCurrentPath[High(FCurrentPath)].X - FCurrentPath[0].X) < 1e-4) and
          (Abs(FCurrentPath[High(FCurrentPath)].Y - FCurrentPath[0].Y) < 1e-4) do
    begin
      SetLength(FCurrentPath, Length(FCurrentPath) - 1);
    end;
  end;
  FlushCurrentSubpath();
end;

procedure TFloriaPath.AddRect(const X, Y, W, H: Double);
begin
  MoveTo(X, Y);
  LineTo(X + W, Y);
  LineTo(X + W, Y + H);
  LineTo(X, Y + H);
  Close();
end;

procedure TFloriaPath.AddRoundedRect(const X, Y, W, H, Rx, Ry: Double; Steps: Integer = 12);
var
  EffectiveRx, EffectiveRy: Double;
  I: Integer;
  Angle: Double;
  CX, CY: Double;
begin
  if (W <= 0) or (H <= 0) then Exit;

  EffectiveRx := Min(Max(0.0, Rx), W * 0.5);
  EffectiveRy := Min(Max(0.0, Ry), H * 0.5);

  if (EffectiveRx <= 0.0) or (EffectiveRy <= 0.0) then
  begin
    AddRect(X, Y, W, H);
    Exit;
  end;

  if Steps < 4 then Steps := 4;

  // Top-left straight start
  MoveTo(X + EffectiveRx, Y);
  // Top edge
  LineTo(X + W - EffectiveRx, Y);

  // Top-right corner arc
  CX := X + W - EffectiveRx;
  CY := Y + EffectiveRy;
  for I := 1 to Steps do
  begin
    Angle := -Pi * 0.5 + (Pi * 0.5) * (I / Steps);
    LineTo(CX + EffectiveRx * Cos(Angle), CY + EffectiveRy * Sin(Angle));
  end;

  // Right edge
  LineTo(X + W, Y + H - EffectiveRy);

  // Bottom-right corner arc
  CX := X + W - EffectiveRx;
  CY := Y + H - EffectiveRy;
  for I := 1 to Steps do
  begin
    Angle := 0.0 + (Pi * 0.5) * (I / Steps);
    LineTo(CX + EffectiveRx * Cos(Angle), CY + EffectiveRy * Sin(Angle));
  end;

  // Bottom edge
  LineTo(X + EffectiveRx, Y + H);

  // Bottom-left corner arc
  CX := X + EffectiveRx;
  CY := Y + H - EffectiveRy;
  for I := 1 to Steps do
  begin
    Angle := Pi * 0.5 + (Pi * 0.5) * (I / Steps);
    LineTo(CX + EffectiveRx * Cos(Angle), CY + EffectiveRy * Sin(Angle));
  end;

  // Left edge
  LineTo(X, Y + EffectiveRy);

  // Top-left corner arc
  CX := X + EffectiveRx;
  CY := Y + EffectiveRy;
  for I := 1 to Steps do
  begin
    Angle := Pi + (Pi * 0.5) * (I / Steps);
    LineTo(CX + EffectiveRx * Cos(Angle), CY + EffectiveRy * Sin(Angle));
  end;

  Close();
end;

procedure TFloriaPath.AddCircle(const Cx, Cy, Radius: Double; Steps: Integer = 36);
begin
  AddEllipse(Cx, Cy, Radius, Radius, Steps);
end;

procedure TFloriaPath.AddEllipse(const Cx, Cy, Rx, Ry: Double; Steps: Integer = 36);
var
  I: Integer;
  Angle: Double;
begin
  if (Rx <= 0) or (Ry <= 0) then Exit;
  if Steps < 8 then Steps := 8;

  MoveTo(Cx + Rx, Cy);
  for I := 1 to Steps do
  begin
    Angle := (2.0 * Pi) * (I / Steps);
    LineTo(Cx + Rx * Cos(Angle), Cy + Ry * Sin(Angle));
  end;
  Close();
end;

procedure TFloriaPath.AddPolygon(const Points: array of TPointD);
var
  I: Integer;
begin
  if Length(Points) < 3 then Exit;
  MoveTo(Points[0].X, Points[0].Y);
  for I := 1 to High(Points) do
    LineTo(Points[I].X, Points[I].Y);
  Close();
end;

procedure TFloriaPath.AddPath(APath: TFloriaPath);
var
  OtherPaths: TPathsD;
  I: Integer;
  L: Integer;
begin
  if APath = nil then Exit;
  APath.FlushCurrentSubpath();
  OtherPaths := APath.ToPathsD();
  if Length(OtherPaths) = 0 then Exit;

  FlushCurrentSubpath();
  L := Length(FPaths);
  SetLength(FPaths, L + Length(OtherPaths));
  for I := 0 to High(OtherPaths) do
    FPaths[L + I] := Copy(OtherPaths[I]);
end;

function TFloriaPath.GetSubpathCount(): Integer;
begin
  FlushCurrentSubpath();
  Result := Length(FPaths);
end;

function TFloriaPath.GetTotalPointCount(): Integer;
var
  I: Integer;
begin
  FlushCurrentSubpath();
  Result := 0;
  for I := 0 to High(FPaths) do
    Inc(Result, Length(FPaths[I]));
end;

function TFloriaPath.GetIsEmpty(): Boolean;
begin
  Result := (GetTotalPointCount() = 0);
end;

function TFloriaPath.GetBounds(): TRectD;
begin
  FlushCurrentSubpath();
  Result := Floria.Path.Clipper.Core.GetBounds(FPaths);
end;

procedure TFloriaPath.Translate(const DX, DY: Double);
var
  I, J: Integer;
begin
  FlushCurrentSubpath();
  for I := 0 to High(FPaths) do
    for J := 0 to High(FPaths[I]) do
    begin
      FPaths[I][J].X := FPaths[I][J].X + DX;
      FPaths[I][J].Y := FPaths[I][J].Y + DY;
    end;
end;

function TFloriaPath.GetArea(): Double;
begin
  FlushCurrentSubpath();
  Result := Floria.Path.Clipper.Core.Area(FPaths);
end;

// ---------------------------------------------------------------------------
// Boolean Operations
// ---------------------------------------------------------------------------

function TFloriaPath.Union(AOther: TFloriaPath; AFillRule: TFloriaPathFillRule = fpfrNonZero): TFloriaPath;
var
  Subj, Clip, Sol: TPathsD;
begin
  FlushCurrentSubpath();
  Subj := FPaths;
  if AOther <> nil then
  begin
    AOther.FlushCurrentSubpath();
    Clip := AOther.FPaths;
    Sol := Floria.Path.Clipper.Union(Subj, Clip, ToClipperFillRule(AFillRule));
  end
  else
  begin
    Sol := Floria.Path.Clipper.Union(Subj, ToClipperFillRule(AFillRule));
  end;

  Result := TFloriaPath.Create();
  Result.FromPathsD(Sol);
end;

function TFloriaPath.Difference(AOther: TFloriaPath; AFillRule: TFloriaPathFillRule = fpfrNonZero): TFloriaPath;
var
  Subj, Clip, Sol: TPathsD;
begin
  FlushCurrentSubpath();
  Subj := FPaths;
  if AOther <> nil then
  begin
    AOther.FlushCurrentSubpath();
    Clip := AOther.FPaths;
    Sol := Floria.Path.Clipper.Difference(Subj, Clip, ToClipperFillRule(AFillRule));
  end
  else
    Sol := Copy(Subj);

  Result := TFloriaPath.Create();
  Result.FromPathsD(Sol);
end;

function TFloriaPath.Intersect(AOther: TFloriaPath; AFillRule: TFloriaPathFillRule = fpfrNonZero): TFloriaPath;
var
  Subj, Clip, Sol: TPathsD;
begin
  FlushCurrentSubpath();
  Subj := FPaths;
  if AOther <> nil then
  begin
    AOther.FlushCurrentSubpath();
    Clip := AOther.FPaths;
    Sol := Floria.Path.Clipper.Intersect(Subj, Clip, ToClipperFillRule(AFillRule));
  end
  else
    SetLength(Sol, 0);

  Result := TFloriaPath.Create();
  Result.FromPathsD(Sol);
end;

function TFloriaPath.XorOp(AOther: TFloriaPath; AFillRule: TFloriaPathFillRule = fpfrNonZero): TFloriaPath;
var
  Subj, Clip, Sol: TPathsD;
begin
  FlushCurrentSubpath();
  Subj := FPaths;
  if AOther <> nil then
  begin
    AOther.FlushCurrentSubpath();
    Clip := AOther.FPaths;
    Sol := Floria.Path.Clipper.XOR_(Subj, Clip, ToClipperFillRule(AFillRule));
  end
  else
    Sol := Copy(Subj);

  Result := TFloriaPath.Create();
  Result.FromPathsD(Sol);
end;

function TFloriaPath.Inflate(const ADelta: Double;
                             AJoinType: TFloriaPathJoinType = fpjtRound;
                             AEndType: TFloriaPathEndType = fpetPolygon;
                             const MiterLimit: Double = 2.0;
                             const ArcTolerance: Double = 0.0): TFloriaPath;
var
  Sol: TPathsD;
begin
  FlushCurrentSubpath();
  Sol := Floria.Path.Clipper.InflatePaths(FPaths, ADelta,
           ToClipperJoinType(AJoinType), ToClipperEndType(AEndType),
           MiterLimit, 2, ArcTolerance);

  Result := TFloriaPath.Create();
  Result.FromPathsD(Sol);
end;

function TFloriaPath.Simplify(const ATolerance: Double = 0.25): TFloriaPath;
var
  Sol: TPathsD;
begin
  FlushCurrentSubpath();
  Sol := Floria.Path.Clipper.SimplifyPaths(FPaths, ATolerance, True);

  Result := TFloriaPath.Create();
  Result.FromPathsD(Sol);
end;

// ---------------------------------------------------------------------------
// Interoperability
// ---------------------------------------------------------------------------

function TFloriaPath.ToPathsD(): TPathsD;
begin
  FlushCurrentSubpath();
  Result := Copy(FPaths);
end;

procedure TFloriaPath.FromPathsD(const APaths: TPathsD);
begin
  Clear();
  FPaths := Copy(APaths);
end;

procedure TFloriaPath.ExportToAggPath(var APathStorage: path_storage);
var
  I, J: Integer;
  P: TPathD;
begin
  FlushCurrentSubpath();
  APathStorage.remove_all();
  for I := 0 to High(FPaths) do
  begin
    P := FPaths[I];
    if Length(P) > 0 then
    begin
      APathStorage.move_to(P[0].X, P[0].Y);
      for J := 1 to High(P) do
        APathStorage.line_to(P[J].X, P[J].Y);
      APathStorage.close_polygon();
    end;
  end;
end;

procedure TFloriaPath.ImportFromAggPath(var APathStorage: path_storage);
var
  CurveConv: conv_curve;
  Cmd: unsigned;
  X, Y: Double;
begin
  Clear();
  CurveConv.Construct(@APathStorage);
  try
    CurveConv.approximation_scale_(1.0);
    CurveConv.rewind(0);
    Cmd := CurveConv.vertex(@X, @Y);
    while not is_stop(Cmd) do
    begin
      if is_move_to(Cmd) then
      begin
        MoveTo(X, Y);
      end
      else if is_vertex(Cmd) then
      begin
        LineTo(X, Y);
      end
      else if is_close(Cmd) then
      begin
        Close();
      end;
      Cmd := CurveConv.vertex(@X, @Y);
    end;
    FlushCurrentSubpath();
  finally
    CurveConv.Destruct();
  end;
end;

function TFloriaPath.ToAggPath(): path_storage;
begin
  Result.Construct();
  ExportToAggPath(Result);
end;

class function TFloriaPath.FromAggPath(var APathStorage: path_storage): TFloriaPath;
begin
  Result := TFloriaPath.Create();
  Result.ImportFromAggPath(APathStorage);
end;

function TFloriaPath.ToSVGString(): string;
var
  I, J: Integer;
  P: TPathD;
  FormatSettings: TFormatSettings;
begin
  FlushCurrentSubpath();
  FormatSettings.DecimalSeparator := '.';
  Result := '';
  for I := 0 to High(FPaths) do
  begin
    P := FPaths[I];
    if Length(P) > 0 then
    begin
      Result := Result + Format('M%.2f %.2f ', [P[0].X, P[0].Y], FormatSettings);
      for J := 1 to High(P) do
      begin
        Result := Result + Format('L%.2f %.2f ', [P[J].X, P[J].Y], FormatSettings);
      end;
      Result := Result + 'Z ';
    end;
  end;
  Result := Trim(Result);
end;

procedure TFloriaPath.FromSVGString(const AData: string);
var
  SvgData: TSVGPathData;
begin
  if Trim(AData) = '' then
  begin
    Clear();
    Exit;
  end;

  SvgData := TSVGPathData.CreateFromSVG(AData);
  try
    FromSVGPathData(SvgData);
  finally
    SvgData.Free();
  end;
end;

function TFloriaPath.ToSVGPathData(): TSVGPathData;
begin
  Result := TSVGPathData.CreateFromSVG(ToSVGString());
end;

procedure TFloriaPath.FromSVGPathData(APathData: TSVGPathData);
var
  NormSegs: TSVGNormalizedSegmentArray;
  I: Integer;
  Seg: TSVGNormalizedSegment;
begin
  Clear();
  if APathData = nil then Exit;

  NormSegs := APathData.ToNormalized(True);
  for I := 0 to High(NormSegs) do
  begin
    Seg := NormSegs[I];
    case Seg.Command of
      sncMoveTo:
        MoveTo(Seg.Params[0], Seg.Params[1]);
      sncLineTo:
        LineTo(Seg.Params[0], Seg.Params[1]);
      sncCubicTo:
        CubicTo(Seg.Params[0], Seg.Params[1],
                Seg.Params[2], Seg.Params[3],
                Seg.Params[4], Seg.Params[5]);
      sncQuadTo:
        QuadTo(Seg.Params[0], Seg.Params[1],
               Seg.Params[2], Seg.Params[3]);
      sncClosePath:
        Close();
    end;
  end;
  FlushCurrentSubpath();
end;

// ---------------------------------------------------------------------------
// Standalone Functions
// ---------------------------------------------------------------------------

function PathUnion(const PathA, PathB: TFloriaPath; FillRule: TFloriaPathFillRule = fpfrNonZero): TFloriaPath;
begin
  if PathA = nil then
  begin
    if PathB = nil then Exit(TFloriaPath.Create());
    Exit(PathB.Clone());
  end;
  Result := PathA.Union(PathB, FillRule);
end;

function PathDifference(const PathA, PathB: TFloriaPath; FillRule: TFloriaPathFillRule = fpfrNonZero): TFloriaPath;
begin
  if PathA = nil then Exit(TFloriaPath.Create());
  Result := PathA.Difference(PathB, FillRule);
end;

function PathIntersect(const PathA, PathB: TFloriaPath; FillRule: TFloriaPathFillRule = fpfrNonZero): TFloriaPath;
begin
  if (PathA = nil) or (PathB = nil) then Exit(TFloriaPath.Create());
  Result := PathA.Intersect(PathB, FillRule);
end;

function PathXor(const PathA, PathB: TFloriaPath; FillRule: TFloriaPathFillRule = fpfrNonZero): TFloriaPath;
begin
  if PathA = nil then
  begin
    if PathB = nil then Exit(TFloriaPath.Create());
    Exit(PathB.Clone());
  end;
  Result := PathA.XorOp(PathB, FillRule);
end;

function PathInflate(const Path: TFloriaPath; Delta: Double;
                     JoinType: TFloriaPathJoinType = fpjtRound;
                     EndType: TFloriaPathEndType = fpetPolygon;
                     MiterLimit: Double = 2.0): TFloriaPath;
begin
  if Path = nil then Exit(TFloriaPath.Create());
  Result := Path.Inflate(Delta, JoinType, EndType, MiterLimit);
end;

function PathSimplify(const Path: TFloriaPath; Tolerance: Double = 0.25): TFloriaPath;
begin
  if Path = nil then Exit(TFloriaPath.Create());
  Result := Path.Simplify(Tolerance);
end;

// ---------------------------------------------------------------------------
// Direct Operations on AggPas path_storage
// ---------------------------------------------------------------------------

function PathUnion(var PathA, PathB: path_storage; FillRule: TFloriaPathFillRule = fpfrNonZero): path_storage;
var
  Fa, Fb, Fres: TFloriaPath;
begin
  Fa := TFloriaPath.FromAggPath(PathA);
  Fb := TFloriaPath.FromAggPath(PathB);
  try
    Fres := Fa.Union(Fb, FillRule);
    try
      Result := Fres.ToAggPath();
    finally
      Fres.Free();
    end;
  finally
    Fa.Free();
    Fb.Free();
  end;
end;

function PathDifference(var PathA, PathB: path_storage; FillRule: TFloriaPathFillRule = fpfrNonZero): path_storage;
var
  Fa, Fb, Fres: TFloriaPath;
begin
  Fa := TFloriaPath.FromAggPath(PathA);
  Fb := TFloriaPath.FromAggPath(PathB);
  try
    Fres := Fa.Difference(Fb, FillRule);
    try
      Result := Fres.ToAggPath();
    finally
      Fres.Free();
    end;
  finally
    Fa.Free();
    Fb.Free();
  end;
end;

function PathIntersect(var PathA, PathB: path_storage; FillRule: TFloriaPathFillRule = fpfrNonZero): path_storage;
var
  Fa, Fb, Fres: TFloriaPath;
begin
  Fa := TFloriaPath.FromAggPath(PathA);
  Fb := TFloriaPath.FromAggPath(PathB);
  try
    Fres := Fa.Intersect(Fb, FillRule);
    try
      Result := Fres.ToAggPath();
    finally
      Fres.Free();
    end;
  finally
    Fa.Free();
    Fb.Free();
  end;
end;

function PathXor(var PathA, PathB: path_storage; FillRule: TFloriaPathFillRule = fpfrNonZero): path_storage;
var
  Fa, Fb, Fres: TFloriaPath;
begin
  Fa := TFloriaPath.FromAggPath(PathA);
  Fb := TFloriaPath.FromAggPath(PathB);
  try
    Fres := Fa.XorOp(Fb, FillRule);
    try
      Result := Fres.ToAggPath();
    finally
      Fres.Free();
    end;
  finally
    Fa.Free();
    Fb.Free();
  end;
end;

end.
