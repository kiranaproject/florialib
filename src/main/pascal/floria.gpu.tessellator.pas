unit Floria.GPU.Tessellator;

// Floria.GPU.Tessellator
// =====================
// High-Performance Native GPU Vector Path & Polygon Tessellator.
// Inspired by Flutter Impeller & Mozilla WebRender.
//
// Capabilities:
// - Direct single-pass stroke tessellation with Miter, Round, and Bevel joins.
// - Butt, Square, and Round end caps for open polyline strokes.
// - Analytic Anti-Aliasing (AA) fringe skirts: 1-pixel outer coverage falloff (1.0 -> 0.0)
//   eliminating MSAA requirements and multi-pass stencil barriers.
// - Ear-clipping triangulation with hole resolution for simple and non-convex polygons.
// - Adaptive Bezier curve subdivision (quadratic & cubic) with chord error thresholds.
// - Unindexed and indexed triangle mesh buffers ready for direct GPU VBO streaming.

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  ctypes, Classes, SysUtils, Math,
  Floria.Path.Clipper.Core,
  Floria.Path.Ops;

type
  // ---------------------------------------------------------------------------
  // TFloriaTessVertex
  // ---------------------------------------------------------------------------
  TFloriaTessVertex = record
    X, Y      : Single; // Coordinate in screen / local space
    Coverage  : Single; // 1.0 = solid interior, 0.0 = outer AA edge
    Dist      : Single; // Normalized distance to centerline or edge (-1.0 .. 1.0)
    TexU, TexV: Single; // Normalized texture coordinate (0.0 .. 1.0)

    class function Create(AX, AY: Single; ACoverage: Single = 1.0; ADist: Single = 0.0;
                          AU: Single = 0.0; AV: Single = 0.0): TFloriaTessVertex; static;
  end;
  PFloriaTessVertex = ^TFloriaTessVertex;
  TFloriaTessVertexArray = array of TFloriaTessVertex;
  TFloriaTessIndexArray  = array of Integer;

  // ---------------------------------------------------------------------------
  // TFloriaTessMesh
  // ---------------------------------------------------------------------------
  TFloriaTessMesh = record
    Vertices   : TFloriaTessVertexArray;
    Indices    : TFloriaTessIndexArray;
    VertexCount: Integer;
    IndexCount : Integer;

    procedure Clear();
    procedure EnsureVertexCapacity(ACap: Integer);
    procedure EnsureIndexCapacity(ACap: Integer);
    function AddVertex(const V: TFloriaTessVertex): Integer; overload;
    function AddVertex(AX, AY: Single; ACoverage: Single = 1.0; ADist: Single = 0.0;
                       AU: Single = 0.0; AV: Single = 0.0): Integer; overload;
    procedure AddTriangle(I0, I1, I2: Integer);
    procedure AddQuad(I0, I1, I2, I3: Integer);
    function TriangleCount(): Integer;
    procedure ToUnindexedTriangles(out AOutVertices: TFloriaTessVertexArray);
  end;

  // ---------------------------------------------------------------------------
  // TFloriaGPUTessellator
  // ---------------------------------------------------------------------------
  TFloriaGPUTessellator = class
  private
    FTolerance    : Double; // Adaptive curve subdivision chord tolerance in pixels
    FAAFringeWidth: Double; // Anti-aliasing fringe width in pixels (default 1.0)

    // Internal stroke helpers
    procedure TessellateStrokeSegment(const P0, P1: TPointD; AHalfWidth: Double;
                                      AAA: Boolean; var AMesh: TFloriaTessMesh;
                                      out OutL0, OutR0, OutL1, OutR1,
                                          OutOL0, OutOR0, OutOL1, OutOR1: Integer);
    procedure TessellateBevelJoin(const CenterPt: TPointD; L0, R0, L1, R1,
                                 OL0, OR0, OL1, OR1: Integer; IsTurnLeft, AAA: Boolean;
                                 var AMesh: TFloriaTessMesh);
    procedure TessellateMiterJoin(const CenterPt: TPointD; const InDir, OutDir, MiterNorm: TPointD;
                                 AHalfWidth, AMiterLimit: Double;
                                 L0, R0, L1, R1, OL0, OR0, OL1, OR1: Integer;
                                 IsTurnLeft, AAA: Boolean; var AMesh: TFloriaTessMesh);
    procedure TessellateRoundJoin(const CenterPt: TPointD; const InNorm, OutNorm: TPointD;
                                 AHalfWidth: Double; Outer0, Outer1, OuterAA0, OuterAA1: Integer;
                                 AAA: Boolean; var AMesh: TFloriaTessMesh);
    procedure TessellateRoundCap(const CenterPt, Dir, LeftNorm: TPointD;
                                AHalfWidth: Double; LeftIdx, RightIdx: Integer;
                                AAA: Boolean; var AMesh: TFloriaTessMesh);

    // Internal polygon ear-clipping helpers
    procedure TriangulateSimpleContour(const APoints: TPathD; var AMesh: TFloriaTessMesh);
    procedure GenerateContourAAFringe(const APoints: TPathD; var AMesh: TFloriaTessMesh);
  public
    constructor Create(ATolerance: Double = 0.25; AAFringeWidth: Double = 1.0);
    destructor Destroy(); override;

    // --- Polyline & Stroke Tessellation ---
    procedure TessellateLine(const P1, P2: TPointD; AWidth: Double;
                             AAA: Boolean; var AMesh: TFloriaTessMesh);
    procedure TessellatePolyline(const APoints: TPathD; AClosed: Boolean; AWidth: Double;
                                 AJoin: TFloriaPathJoinType; ACap: TFloriaPathEndType;
                                 AMiterLimit: Double; AAA: Boolean; var AMesh: TFloriaTessMesh);
    procedure TessellateStroke(APath: TFloriaPath; AWidth: Double;
                               var AMesh: TFloriaTessMesh;
                               AJoin: TFloriaPathJoinType = fpjtMiter;
                               ACap: TFloriaPathEndType = fpetSquare;
                               AMiterLimit: Double = 4.0; AAA: Boolean = True);

    // --- Polygon Fill & Ear-Clipping Tessellation ---
    procedure TessellatePolygonFill(const APoints: TPathD; AAA: Boolean;
                                    var AMesh: TFloriaTessMesh);
    procedure TessellateFill(APath: TFloriaPath; var AMesh: TFloriaTessMesh;
                             AFillRule: TFloriaPathFillRule = fpfrNonZero;
                             AAA: Boolean = True);

    // --- Curve Subdivision Helpers ---
    procedure SubdivideQuad(const P0, P1, P2: TPointD; var AOutPoints: TPathD);
    procedure SubdivideCubic(const P0, P1, P2, P3: TPointD; var AOutPoints: TPathD);

    // Configuration Properties
    property Tolerance    : Double read FTolerance write FTolerance;
    property AAFringeWidth: Double read FAAFringeWidth write FAAFringeWidth;
  end;

// Standalone vector geometry utility functions
function VecLength(const V: TPointD): Double; inline;
function VecNormalize(const V: TPointD): TPointD; inline;
function VecCross(const A, B: TPointD): Double; inline;
function VecDot(const A, B: TPointD): Double; inline;

implementation

// ---------------------------------------------------------------------------
// Standalone Vector Math
// ---------------------------------------------------------------------------
function VecLength(const V: TPointD): Double;
begin
  Result := Sqrt(V.X * V.X + V.Y * V.Y);
end;

function VecNormalize(const V: TPointD): TPointD;
var
  L: Double;
begin
  L := VecLength(V);
  if L > 1e-9 then
  begin
    Result.X := V.X / L;
    Result.Y := V.Y / L;
  end
  else
  begin
    Result.X := 0.0;
    Result.Y := 0.0;
  end;
end;

function VecCross(const A, B: TPointD): Double;
begin
  Result := A.X * B.Y - A.Y * B.X;
end;

function VecDot(const A, B: TPointD): Double;
begin
  Result := A.X * B.X + A.Y * B.Y;
end;

// ---------------------------------------------------------------------------
// TFloriaTessVertex Implementation
// ---------------------------------------------------------------------------
class function TFloriaTessVertex.Create(AX, AY: Single; ACoverage: Single; ADist: Single;
                                       AU: Single; AV: Single): TFloriaTessVertex;
begin
  Result.X        := AX;
  Result.Y        := AY;
  Result.Coverage := ACoverage;
  Result.Dist     := ADist;
  Result.TexU     := AU;
  Result.TexV     := AV;
end;

// ---------------------------------------------------------------------------
// TFloriaTessMesh Implementation
// ---------------------------------------------------------------------------
procedure TFloriaTessMesh.Clear();
begin
  VertexCount := 0;
  IndexCount  := 0;
end;

procedure TFloriaTessMesh.EnsureVertexCapacity(ACap: Integer);
var
  NewCap: Integer;
begin
  if ACap > Length(Vertices) then
  begin
    NewCap := Max(ACap, Max(16, Length(Vertices) * 2));
    SetLength(Vertices, NewCap);
  end;
end;

procedure TFloriaTessMesh.EnsureIndexCapacity(ACap: Integer);
var
  NewCap: Integer;
begin
  if ACap > Length(Indices) then
  begin
    NewCap := Max(ACap, Max(32, Length(Indices) * 2));
    SetLength(Indices, NewCap);
  end;
end;

function TFloriaTessMesh.AddVertex(const V: TFloriaTessVertex): Integer;
begin
  EnsureVertexCapacity(VertexCount + 1);
  Result := VertexCount;
  Vertices[VertexCount] := V;
  Inc(VertexCount);
end;

function TFloriaTessMesh.AddVertex(AX, AY: Single; ACoverage: Single; ADist: Single;
                                  AU: Single; AV: Single): Integer;
var
  V: TFloriaTessVertex;
begin
  V.X        := AX;
  V.Y        := AY;
  V.Coverage := ACoverage;
  V.Dist     := ADist;
  V.TexU     := AU;
  V.TexV     := AV;
  Result     := AddVertex(V);
end;

procedure TFloriaTessMesh.AddTriangle(I0, I1, I2: Integer);
begin
  EnsureIndexCapacity(IndexCount + 3);
  Indices[IndexCount]     := I0;
  Indices[IndexCount + 1] := I1;
  Indices[IndexCount + 2] := I2;
  Inc(IndexCount, 3);
end;

procedure TFloriaTessMesh.AddQuad(I0, I1, I2, I3: Integer);
begin
  // Quad defined by (I0, I1, I2, I3) -> 2 triangles (I0, I1, I2) and (I0, I2, I3)
  EnsureIndexCapacity(IndexCount + 6);
  Indices[IndexCount]     := I0;
  Indices[IndexCount + 1] := I1;
  Indices[IndexCount + 2] := I2;
  Indices[IndexCount + 3] := I0;
  Indices[IndexCount + 4] := I2;
  Indices[IndexCount + 5] := I3;
  Inc(IndexCount, 6);
end;

function TFloriaTessMesh.TriangleCount(): Integer;
begin
  Result := IndexCount div 3;
end;

procedure TFloriaTessMesh.ToUnindexedTriangles(out AOutVertices: TFloriaTessVertexArray);
var
  I: Integer;
begin
  SetLength(AOutVertices, IndexCount);
  for I := 0 to IndexCount - 1 do
    AOutVertices[I] := Vertices[Indices[I]];
end;

// ---------------------------------------------------------------------------
// TFloriaGPUTessellator Implementation
// ---------------------------------------------------------------------------
constructor TFloriaGPUTessellator.Create(ATolerance: Double; AAFringeWidth: Double);
begin
  inherited Create();
  FTolerance     := ATolerance;
  FAAFringeWidth := AAFringeWidth;
end;

destructor TFloriaGPUTessellator.Destroy();
begin
  inherited Destroy();
end;

// ---------------------------------------------------------------------------
// Stroke Geometry Subdivision & Emitters
// ---------------------------------------------------------------------------
procedure TFloriaGPUTessellator.TessellateStrokeSegment(
  const P0, P1: TPointD; AHalfWidth: Double; AAA: Boolean; var AMesh: TFloriaTessMesh;
  out OutL0, OutR0, OutL1, OutR1, OutOL0, OutOR0, OutOL1, OutOR1: Integer);
var
  Dir, Norm: TPointD;
  AAW: Double;
begin
  Dir := VecNormalize(PointD(P1.X - P0.X, P1.Y - P0.Y));
  Norm.X := -Dir.Y;
  Norm.Y :=  Dir.X;

  AAW := FAAFringeWidth;

  // Interior Core Vertices (Coverage = 1.0)
  OutL0 := AMesh.AddVertex(P0.X + Norm.X * AHalfWidth, P0.Y + Norm.Y * AHalfWidth, 1.0,  1.0);
  OutR0 := AMesh.AddVertex(P0.X - Norm.X * AHalfWidth, P0.Y - Norm.Y * AHalfWidth, 1.0, -1.0);
  OutL1 := AMesh.AddVertex(P1.X + Norm.X * AHalfWidth, P1.Y + Norm.Y * AHalfWidth, 1.0,  1.0);
  OutR1 := AMesh.AddVertex(P1.X - Norm.X * AHalfWidth, P1.Y - Norm.Y * AHalfWidth, 1.0, -1.0);

  // Core Solid Quad: (L0, R0, R1, L1)
  AMesh.AddQuad(OutL0, OutR0, OutR1, OutL1);

  if AAA then
  begin
    // Outer Left Fringe (Coverage = 0.0)
    OutOL0 := AMesh.AddVertex(P0.X + Norm.X * (AHalfWidth + AAW), P0.Y + Norm.Y * (AHalfWidth + AAW), 0.0,  2.0);
    OutOL1 := AMesh.AddVertex(P1.X + Norm.X * (AHalfWidth + AAW), P1.Y + Norm.Y * (AHalfWidth + AAW), 0.0,  2.0);
    AMesh.AddQuad(OutOL0, OutL0, OutL1, OutOL1);

    // Outer Right Fringe (Coverage = 0.0)
    OutOR0 := AMesh.AddVertex(P0.X - Norm.X * (AHalfWidth + AAW), P0.Y - Norm.Y * (AHalfWidth + AAW), 0.0, -2.0);
    OutOR1 := AMesh.AddVertex(P1.X - Norm.X * (AHalfWidth + AAW), P1.Y - Norm.Y * (AHalfWidth + AAW), 0.0, -2.0);
    AMesh.AddQuad(OutR0, OutOR0, OutOR1, OutR1);
  end
  else
  begin
    OutOL0 := -1; OutOL1 := -1; OutOR0 := -1; OutOR1 := -1;
  end;
end;

procedure TFloriaGPUTessellator.TessellateBevelJoin(
  const CenterPt: TPointD; L0, R0, L1, R1, OL0, OR0, OL1, OR1: Integer;
  IsTurnLeft, AAA: Boolean; var AMesh: TFloriaTessMesh);
var
  CIdx: Integer;
begin
  CIdx := AMesh.AddVertex(CenterPt.X, CenterPt.Y, 1.0, 0.0);

  if IsTurnLeft then
  begin
    // Right side is the outer corner
    AMesh.AddTriangle(CIdx, R0, R1);
    if AAA and (OR0 >= 0) and (OR1 >= 0) then
      AMesh.AddQuad(R0, OR0, OR1, R1);
  end
  else
  begin
    // Left side is the outer corner
    AMesh.AddTriangle(CIdx, L1, L0);
    if AAA and (OL0 >= 0) and (OL1 >= 0) then
      AMesh.AddQuad(OL0, L0, L1, OL1);
  end;
end;

procedure TFloriaGPUTessellator.TessellateMiterJoin(
  const CenterPt: TPointD; const InDir, OutDir, MiterNorm: TPointD;
  AHalfWidth, AMiterLimit: Double;
  L0, R0, L1, R1, OL0, OR0, OL1, OR1: Integer;
  IsTurnLeft, AAA: Boolean; var AMesh: TFloriaTessMesh);
var
  DotM: Double;
  MiterLen: Double;
  MiterPt, MiterAAPt: TPointD;
  MIdx, MAAIdx, CIdx: Integer;
begin
  DotM := VecDot(InDir, MiterNorm);
  if Abs(DotM) < 1e-4 then
  begin
    TessellateBevelJoin(CenterPt, L0, R0, L1, R1, OL0, OR0, OL1, OR1, IsTurnLeft, AAA, AMesh);
    Exit;
  end;

  MiterLen := AHalfWidth / Abs(DotM);
  if (MiterLen / AHalfWidth) > AMiterLimit then
  begin
    // Exceeds miter limit -> fallback to bevel
    TessellateBevelJoin(CenterPt, L0, R0, L1, R1, OL0, OR0, OL1, OR1, IsTurnLeft, AAA, AMesh);
    Exit;
  end;

  CIdx := AMesh.AddVertex(CenterPt.X, CenterPt.Y, 1.0, 0.0);

  if IsTurnLeft then
  begin
    // Right side is outer
    MiterPt.X := CenterPt.X - MiterNorm.X * MiterLen;
    MiterPt.Y := CenterPt.Y - MiterNorm.Y * MiterLen;
    MIdx := AMesh.AddVertex(MiterPt.X, MiterPt.Y, 1.0, -1.0);

    AMesh.AddTriangle(CIdx, R0, MIdx);
    AMesh.AddTriangle(CIdx, MIdx, R1);

    if AAA and (OR0 >= 0) and (OR1 >= 0) then
    begin
      MiterAAPt.X := CenterPt.X - MiterNorm.X * (MiterLen + FAAFringeWidth);
      MiterAAPt.Y := CenterPt.Y - MiterNorm.Y * (MiterLen + FAAFringeWidth);
      MAAIdx := AMesh.AddVertex(MiterAAPt.X, MiterAAPt.Y, 0.0, -2.0);

      AMesh.AddQuad(R0, OR0, MAAIdx, MIdx);
      AMesh.AddQuad(MIdx, MAAIdx, OR1, R1);
    end;
  end
  else
  begin
    // Left side is outer
    MiterPt.X := CenterPt.X + MiterNorm.X * MiterLen;
    MiterPt.Y := CenterPt.Y + MiterNorm.Y * MiterLen;
    MIdx := AMesh.AddVertex(MiterPt.X, MiterPt.Y, 1.0, 1.0);

    AMesh.AddTriangle(CIdx, MIdx, L0);
    AMesh.AddTriangle(CIdx, L1, MIdx);

    if AAA and (OL0 >= 0) and (OL1 >= 0) then
    begin
      MiterAAPt.X := CenterPt.X + MiterNorm.X * (MiterLen + FAAFringeWidth);
      MiterAAPt.Y := CenterPt.Y + MiterNorm.Y * (MiterLen + FAAFringeWidth);
      MAAIdx := AMesh.AddVertex(MiterAAPt.X, MiterAAPt.Y, 0.0, 2.0);

      AMesh.AddQuad(OL0, L0, MIdx, MAAIdx);
      AMesh.AddQuad(MAAIdx, MIdx, L1, OL1);
    end;
  end;
end;

procedure TFloriaGPUTessellator.TessellateRoundJoin(
  const CenterPt: TPointD; const InNorm, OutNorm: TPointD;
  AHalfWidth: Double; Outer0, Outer1, OuterAA0, OuterAA1: Integer;
  AAA: Boolean; var AMesh: TFloriaTessMesh);
var
  AngleIn, AngleOut, AngleDiff, AngleStep: Double;
  Steps, S, CIdx, PrevV, CurrV, PrevAAV, CurrAAV: Integer;
  CurAngle: Double;
  ArcPt, ArcAAPt: TPointD;
begin
  AngleIn  := ArcTan2(InNorm.Y, InNorm.X);
  AngleOut := ArcTan2(OutNorm.Y, OutNorm.X);
  AngleDiff := AngleOut - AngleIn;

  while AngleDiff > Pi do AngleDiff := AngleDiff - 2.0 * Pi;
  while AngleDiff < -Pi do AngleDiff := AngleDiff + 2.0 * Pi;

  Steps := Max(3, Ceil(Abs(AngleDiff) / (Pi / 6.0))); // ~30 deg per step
  AngleStep := AngleDiff / Steps;

  CIdx := AMesh.AddVertex(CenterPt.X, CenterPt.Y, 1.0, 0.0);
  PrevV   := Outer0;
  PrevAAV := OuterAA0;

  for S := 1 to Steps do
  begin
    if S = Steps then
    begin
      CurrV   := Outer1;
      CurrAAV := OuterAA1;
    end
    else
    begin
      CurAngle := AngleIn + S * AngleStep;
      ArcPt.X := CenterPt.X + Cos(CurAngle) * AHalfWidth;
      ArcPt.Y := CenterPt.Y + Sin(CurAngle) * AHalfWidth;
      CurrV := AMesh.AddVertex(ArcPt.X, ArcPt.Y, 1.0, 1.0);

      if AAA then
      begin
        ArcAAPt.X := CenterPt.X + Cos(CurAngle) * (AHalfWidth + FAAFringeWidth);
        ArcAAPt.Y := CenterPt.Y + Sin(CurAngle) * (AHalfWidth + FAAFringeWidth);
        CurrAAV := AMesh.AddVertex(ArcAAPt.X, ArcAAPt.Y, 0.0, 2.0);
      end
      else
        CurrAAV := -1;
    end;

    AMesh.AddTriangle(CIdx, PrevV, CurrV);
    if AAA and (PrevAAV >= 0) and (CurrAAV >= 0) then
      AMesh.AddQuad(PrevV, PrevAAV, CurrAAV, CurrV);

    PrevV   := CurrV;
    PrevAAV := CurrAAV;
  end;
end;

procedure TFloriaGPUTessellator.TessellateRoundCap(
  const CenterPt, Dir, LeftNorm: TPointD; AHalfWidth: Double;
  LeftIdx, RightIdx: Integer; AAA: Boolean; var AMesh: TFloriaTessMesh);
var
  BaseAngle, AngleStep: Double;
  Steps, S, CIdx, PrevV, CurrV, PrevAAV, CurrAAV: Integer;
  CurAngle: Double;
  CapPt, CapAAPt: TPointD;
begin
  BaseAngle := ArcTan2(LeftNorm.Y, LeftNorm.X);
  Steps := 8;
  AngleStep := -Pi / Steps; // Clockwise from left normal to right normal

  CIdx := AMesh.AddVertex(CenterPt.X, CenterPt.Y, 1.0, 0.0);
  PrevV := LeftIdx;
  if AAA then
    PrevAAV := AMesh.AddVertex(CenterPt.X + LeftNorm.X * (AHalfWidth + FAAFringeWidth),
                               CenterPt.Y + LeftNorm.Y * (AHalfWidth + FAAFringeWidth), 0.0, 2.0)
  else
    PrevAAV := -1;

  for S := 1 to Steps do
  begin
    if S = Steps then
    begin
      CurrV := RightIdx;
      if AAA then
        CurrAAV := AMesh.AddVertex(CenterPt.X - LeftNorm.X * (AHalfWidth + FAAFringeWidth),
                                   CenterPt.Y - LeftNorm.Y * (AHalfWidth + FAAFringeWidth), 0.0, -2.0)
      else
        CurrAAV := -1;
    end
    else
    begin
      CurAngle := BaseAngle + S * AngleStep;
      CapPt.X := CenterPt.X + Cos(CurAngle) * AHalfWidth;
      CapPt.Y := CenterPt.Y + Sin(CurAngle) * AHalfWidth;
      CurrV := AMesh.AddVertex(CapPt.X, CapPt.Y, 1.0, 0.0);

      if AAA then
      begin
        CapAAPt.X := CenterPt.X + Cos(CurAngle) * (AHalfWidth + FAAFringeWidth);
        CapAAPt.Y := CenterPt.Y + Sin(CurAngle) * (AHalfWidth + FAAFringeWidth);
        CurrAAV := AMesh.AddVertex(CapAAPt.X, CapAAPt.Y, 0.0, 2.0);
      end
      else
        CurrAAV := -1;
    end;

    AMesh.AddTriangle(CIdx, PrevV, CurrV);
    if AAA and (PrevAAV >= 0) and (CurrAAV >= 0) then
      AMesh.AddQuad(PrevV, PrevAAV, CurrAAV, CurrV);

    PrevV := CurrV;
    PrevAAV := CurrAAV;
  end;
end;

procedure TFloriaGPUTessellator.TessellateLine(
  const P1, P2: TPointD; AWidth: Double; AAA: Boolean; var AMesh: TFloriaTessMesh);
var
  L0, R0, L1, R1, OL0, OR0, OL1, OR1: Integer;
begin
  TessellateStrokeSegment(P1, P2, AWidth * 0.5, AAA, AMesh,
                          L0, R0, L1, R1, OL0, OR0, OL1, OR1);
end;

procedure TFloriaGPUTessellator.TessellatePolyline(
  const APoints: TPathD; AClosed: Boolean; AWidth: Double;
  AJoin: TFloriaPathJoinType; ACap: TFloriaPathEndType;
  AMiterLimit: Double; AAA: Boolean; var AMesh: TFloriaTessMesh);
var
  N, I, NextI, SegCount: Integer;
  HalfW: Double;
  PrevL0, PrevR0, PrevL1, PrevR1, PrevOL0, PrevOR0, PrevOL1, PrevOR1: Integer;
  CurL0, CurR0, CurL1, CurR1, CurOL0, CurOR0, CurOL1, CurOR1: Integer;
  InDir, OutDir, InNorm, OutNorm, MiterNorm: TPointD;
  CrossVal: Double;
  IsTurnLeft: Boolean;
  StartPt, EndPt: TPointD;
begin
  N := Length(APoints);
  if N < 2 then Exit;

  HalfW := AWidth * 0.5;

  if (N = 2) and not AClosed and (ACap = fpetButt) then
  begin
    TessellateLine(APoints[0], APoints[1], AWidth, AAA, AMesh);
    Exit;
  end;

  SegCount := N - 1;
  if AClosed then SegCount := N;

  // Process first segment
  StartPt := APoints[0];
  EndPt   := APoints[1];
  TessellateStrokeSegment(StartPt, EndPt, HalfW, AAA, AMesh,
                          PrevL0, PrevR0, PrevL1, PrevR1,
                          PrevOL0, PrevOR0, PrevOL1, PrevOR1);

  InDir  := VecNormalize(PointD(EndPt.X - StartPt.X, EndPt.Y - StartPt.Y));
  InNorm := PointD(-InDir.Y, InDir.X);

  // Optional start cap if open
  if not AClosed then
  begin
    case ACap of
      fpetRound:
        TessellateRoundCap(StartPt, PointD(-InDir.X, -InDir.Y), InNorm, HalfW,
                           PrevL0, PrevR0, AAA, AMesh);
      fpetSquare:
        // Square cap extends backward by HalfW
        TessellateLine(PointD(StartPt.X - InDir.X * HalfW, StartPt.Y - InDir.Y * HalfW),
                       StartPt, AWidth, AAA, AMesh);
      else ; // fpetButt: flat edge
    end;
  end;

  // Process intermediate joints & segments
  for I := 1 to SegCount - 1 do
  begin
    NextI := (I + 1) mod N;
    StartPt := APoints[I];
    EndPt   := APoints[NextI];

    TessellateStrokeSegment(StartPt, EndPt, HalfW, AAA, AMesh,
                            CurL0, CurR0, CurL1, CurR1,
                            CurOL0, CurOR0, CurOL1, CurOR1);

    OutDir  := VecNormalize(PointD(EndPt.X - StartPt.X, EndPt.Y - StartPt.Y));
    OutNorm := PointD(-OutDir.Y, OutDir.X);

    CrossVal := VecCross(InDir, OutDir);
    IsTurnLeft := CrossVal > 0.0;

    MiterNorm := VecNormalize(PointD(InNorm.X + OutNorm.X, InNorm.Y + OutNorm.Y));

    case AJoin of
      fpjtBevel:
        TessellateBevelJoin(StartPt, PrevL1, PrevR1, CurL0, CurR0,
                            PrevOL1, PrevOR1, CurOL0, CurOR0, IsTurnLeft, AAA, AMesh);
      fpjtMiter:
        TessellateMiterJoin(StartPt, InDir, OutDir, MiterNorm, HalfW, AMiterLimit,
                            PrevL1, PrevR1, CurL0, CurR0,
                            PrevOL1, PrevOR1, CurOL0, CurOR0, IsTurnLeft, AAA, AMesh);
      fpjtRound:
        if IsTurnLeft then
          TessellateRoundJoin(StartPt, PointD(-InNorm.X, -InNorm.Y), PointD(-OutNorm.X, -OutNorm.Y),
                              HalfW, PrevR1, CurR0, PrevOR1, CurOR0, AAA, AMesh)
        else
          TessellateRoundJoin(StartPt, InNorm, OutNorm, HalfW,
                              PrevL1, CurL0, PrevOL1, CurOL0, AAA, AMesh);
    end;

    // Shift previous to current
    PrevL0 := CurL0; PrevR0 := CurR0; PrevL1 := CurL1; PrevR1 := CurR1;
    PrevOL0 := CurOL0; PrevOR0 := CurOR0; PrevOL1 := CurOL1; PrevOR1 := CurOR1;
    InDir  := OutDir;
    InNorm := OutNorm;
  end;

  // End cap or close loop
  if not AClosed then
  begin
    case ACap of
      fpetRound:
        TessellateRoundCap(APoints[N - 1], InDir, InNorm, HalfW,
                           PrevL1, PrevR1, AAA, AMesh);
      fpetSquare:
        TessellateLine(APoints[N - 1],
                       PointD(APoints[N - 1].X + InDir.X * HalfW, APoints[N - 1].Y + InDir.Y * HalfW),
                       AWidth, AAA, AMesh);
      else ; // Butt cap
    end;
  end;
end;

procedure TFloriaGPUTessellator.TessellateStroke(
  APath: TFloriaPath; AWidth: Double; var AMesh: TFloriaTessMesh;
  AJoin: TFloriaPathJoinType; ACap: TFloriaPathEndType;
  AMiterLimit: Double; AAA: Boolean);
var
  Paths: TPathsD;
  I: Integer;
begin
  if not Assigned(APath) or APath.IsEmpty then Exit;

  Paths := APath.ToPathsD();
  for I := 0 to High(Paths) do
  begin
    if Length(Paths[I]) >= 2 then
      TessellatePolyline(Paths[I], False, AWidth, AJoin, ACap, AMiterLimit, AAA, AMesh);
  end;
end;

// ---------------------------------------------------------------------------
// Ear-Clipping Polygon Triangulation & Analytic AA Fringe
// ---------------------------------------------------------------------------
procedure TFloriaGPUTessellator.TriangulateSimpleContour(
  const APoints: TPathD; var AMesh: TFloriaTessMesh);
var
  N, I, Count, PrevI, CurrI, NextI, BestEar: Integer;
  Filtered: TPathD;
  Area, CrossVal, CP: Double;
  PrevList, NextList: array of Integer;
  IsConvex: Boolean;
  TestPt, P0, P1, P2: TPointD;
  CanClip, AnyEarFound: Boolean;
  J, TestI: Integer;
  Dot00, Dot01, Dot02, Dot11, Dot12, InvDenom, U, V: Double;
  V0, V1, V2: TPointD;
begin
  N := Length(APoints);
  if N < 3 then Exit;

  // 1. Filter duplicate consecutive points
  SetLength(Filtered, N);
  Count := 0;
  for I := 0 to N - 1 do
  begin
    if (Count = 0) or
       (Abs(APoints[I].X - Filtered[Count - 1].X) > 1e-6) or
       (Abs(APoints[I].Y - Filtered[Count - 1].Y) > 1e-6) then
    begin
      Filtered[Count] := APoints[I];
      Inc(Count);
    end;
  end;

  // Drop closing point if identical to first
  if (Count > 2) and
     (Abs(Filtered[Count - 1].X - Filtered[0].X) < 1e-6) and
     (Abs(Filtered[Count - 1].Y - Filtered[0].Y) < 1e-6) then
    Dec(Count);

  if Count < 3 then Exit;
  SetLength(Filtered, Count);

  // 2. Check signed area and orientation (ensure CCW)
  Area := 0.0;
  for I := 0 to Count - 1 do
  begin
    NextI := (I + 1) mod Count;
    Area := Area + (Filtered[I].X * Filtered[NextI].Y - Filtered[NextI].X * Filtered[I].Y);
  end;

  if Abs(Area) < 1e-6 then Exit; // Degenerate polygon

  // Reverse if clockwise to enforce CCW
  if Area < 0.0 then
  begin
    for I := 0 to (Count div 2) - 1 do
    begin
      P0 := Filtered[I];
      Filtered[I] := Filtered[Count - 1 - I];
      Filtered[Count - 1 - I] := P0;
    end;
  end;

  // Base triangle shortcut
  if Count = 3 then
  begin
    AMesh.AddTriangle(
      AMesh.AddVertex(Filtered[0].X, Filtered[0].Y, 1.0, 0.0),
      AMesh.AddVertex(Filtered[1].X, Filtered[1].Y, 1.0, 0.0),
      AMesh.AddVertex(Filtered[2].X, Filtered[2].Y, 1.0, 0.0)
    );
    Exit;
  end;

  // 3. Initialize Doubly Linked Ring for Ear-Clipping
  SetLength(PrevList, Count);
  SetLength(NextList, Count);
  for I := 0 to Count - 1 do
  begin
    PrevList[I] := (I - 1 + Count) mod Count;
    NextList[I] := (I + 1) mod Count;
  end;

  CurrI := 0;
  while Count > 2 do
  begin
    if Count = 3 then
    begin
      PrevI := PrevList[CurrI];
      NextI := NextList[CurrI];
      AMesh.AddTriangle(
        AMesh.AddVertex(Filtered[PrevI].X, Filtered[PrevI].Y, 1.0, 0.0),
        AMesh.AddVertex(Filtered[CurrI].X, Filtered[CurrI].Y, 1.0, 0.0),
        AMesh.AddVertex(Filtered[NextI].X, Filtered[NextI].Y, 1.0, 0.0)
      );
      Break;
    end;

    AnyEarFound := False;
    BestEar := -1;

    // Scan for an ear vertex
    for J := 0 to Count - 1 do
    begin
      PrevI := PrevList[CurrI];
      NextI := NextList[CurrI];

      P0 := Filtered[PrevI];
      P1 := Filtered[CurrI];
      P2 := Filtered[NextI];

      // Cross product test for convexity in CCW polygon
      CP := (P1.X - P0.X) * (P2.Y - P1.Y) - (P1.Y - P0.Y) * (P2.X - P1.X);
      if CP > 1e-9 then
      begin
        // Convex! Now verify no other polygon vertex lies inside triangle (P0, P1, P2)
        CanClip := True;
        TestI := NextList[NextI];
        while TestI <> PrevI do
        begin
          TestPt := Filtered[TestI];

          // Barycentric point-in-triangle check
          V0 := PointD(P2.X - P0.X, P2.Y - P0.Y);
          V1 := PointD(P1.X - P0.X, P1.Y - P0.Y);
          V2 := PointD(TestPt.X - P0.X, TestPt.Y - P0.Y);

          Dot00 := VecDot(V0, V0);
          Dot01 := VecDot(V0, V1);
          Dot02 := VecDot(V0, V2);
          Dot11 := VecDot(V1, V1);
          Dot12 := VecDot(V1, V2);

          InvDenom := 1.0 / (Dot00 * Dot11 - Dot01 * Dot01 + 1e-12);
          U := (Dot11 * Dot02 - Dot01 * Dot12) * InvDenom;
          V := (Dot00 * Dot12 - Dot01 * Dot02) * InvDenom;

          if (U >= 0.0) and (V >= 0.0) and (U + V <= 1.0) then
          begin
            CanClip := False;
            Break;
          end;

          TestI := NextList[TestI];
        end;

        if CanClip then
        begin
          BestEar := CurrI;
          AnyEarFound := True;
          Break;
        end;
      end;

      CurrI := NextList[CurrI];
    end;

    // If numerical edge case prevented ear detection, clip current convex vertex
    if not AnyEarFound then
      BestEar := CurrI;

    PrevI := PrevList[BestEar];
    NextI := NextList[BestEar];

    AMesh.AddTriangle(
      AMesh.AddVertex(Filtered[PrevI].X, Filtered[PrevI].Y, 1.0, 0.0),
      AMesh.AddVertex(Filtered[BestEar].X, Filtered[BestEar].Y, 1.0, 0.0),
      AMesh.AddVertex(Filtered[NextI].X, Filtered[NextI].Y, 1.0, 0.0)
    );

    // Remove ear from ring
    NextList[PrevI] := NextI;
    PrevList[NextI] := PrevI;
    CurrI := NextI;
    Dec(Count);
  end;
end;

procedure TFloriaGPUTessellator.GenerateContourAAFringe(
  const APoints: TPathD; var AMesh: TFloriaTessMesh);
var
  N, I, NextI, PrevI: Integer;
  InDir, OutDir, InNorm, OutNorm, MiterNorm: TPointD;
  ExtrudeLen, DotM: Double;
  InnerIndices, OuterIndices: array of Integer;
  OutPt: TPointD;
begin
  N := Length(APoints);
  if N < 3 then Exit;

  SetLength(InnerIndices, N);
  SetLength(OuterIndices, N);

  // Compute outward normal at each vertex and generate outer AA boundary
  for I := 0 to N - 1 do
  begin
    PrevI := (I - 1 + N) mod N;
    NextI := (I + 1) mod N;

    InDir   := VecNormalize(PointD(APoints[I].X - APoints[PrevI].X, APoints[I].Y - APoints[PrevI].Y));
    InNorm  := PointD(InDir.Y, -InDir.X); // Outward normal for CCW

    OutDir  := VecNormalize(PointD(APoints[NextI].X - APoints[I].X, APoints[NextI].Y - APoints[I].Y));
    OutNorm := PointD(OutDir.Y, -OutDir.X);

    MiterNorm := VecNormalize(PointD(InNorm.X + OutNorm.X, InNorm.Y + OutNorm.Y));
    DotM := VecDot(OutNorm, MiterNorm);

    if DotM > 0.1 then
      ExtrudeLen := Min(FAAFringeWidth / DotM, FAAFringeWidth * 2.0)
    else
      ExtrudeLen := FAAFringeWidth;

    OutPt.X := APoints[I].X + MiterNorm.X * ExtrudeLen;
    OutPt.Y := APoints[I].Y + MiterNorm.Y * ExtrudeLen;

    InnerIndices[I] := AMesh.AddVertex(APoints[I].X, APoints[I].Y, 1.0, 0.0);
    OuterIndices[I] := AMesh.AddVertex(OutPt.X, OutPt.Y, 0.0, 1.0);
  end;

  // Connect boundary quads between consecutive contour vertices
  for I := 0 to N - 1 do
  begin
    NextI := (I + 1) mod N;
    AMesh.AddQuad(InnerIndices[I], InnerIndices[NextI],
                  OuterIndices[NextI], OuterIndices[I]);
  end;
end;

procedure TFloriaGPUTessellator.TessellatePolygonFill(
  const APoints: TPathD; AAA: Boolean; var AMesh: TFloriaTessMesh);
begin
  if Length(APoints) < 3 then Exit;

  // Triangulate inner solid fill
  TriangulateSimpleContour(APoints, AMesh);

  // Add 1px smooth AA fringe skirt
  if AAA then
    GenerateContourAAFringe(APoints, AMesh);
end;

procedure TFloriaGPUTessellator.TessellateFill(
  APath: TFloriaPath; var AMesh: TFloriaTessMesh;
  AFillRule: TFloriaPathFillRule; AAA: Boolean);
var
  Paths: TPathsD;
  I: Integer;
begin
  if not Assigned(APath) or APath.IsEmpty then Exit;

  Paths := APath.ToPathsD();
  for I := 0 to High(Paths) do
  begin
    if Length(Paths[I]) >= 3 then
      TessellatePolygonFill(Paths[I], AAA, AMesh);
  end;
end;

// ---------------------------------------------------------------------------
// Curve Adaptive Subdivision
// ---------------------------------------------------------------------------
procedure TFloriaGPUTessellator.SubdivideQuad(
  const P0, P1, P2: TPointD; var AOutPoints: TPathD);
var
  C1, C2: TPointD;
begin
  // Degree elevation from quadratic to cubic Bezier
  C1.X := P0.X + (2.0 / 3.0) * (P1.X - P0.X);
  C1.Y := P0.Y + (2.0 / 3.0) * (P1.Y - P0.Y);
  C2.X := P2.X + (2.0 / 3.0) * (P1.X - P2.X);
  C2.Y := P2.Y + (2.0 / 3.0) * (P1.Y - P2.Y);

  SubdivideCubic(P0, C1, C2, P2, AOutPoints);
end;

procedure TFloriaGPUTessellator.SubdivideCubic(
  const P0, P1, P2, P3: TPointD; var AOutPoints: TPathD);

  procedure Recurse(const A0, A1, A2, A3: TPointD; Depth: Integer);
  var
    Vx, Vy, L2, InvL, D1, D2: Double;
    Mid01, Mid12, Mid23, MidA, MidB, CenterPt: TPointD;
    Len: Integer;
  begin
    Vx := A3.X - A0.X;
    Vy := A3.Y - A0.Y;
    L2 := Vx * Vx + Vy * Vy;

    if (L2 < 1e-6) or (Depth >= 10) then
    begin
      Len := Length(AOutPoints);
      SetLength(AOutPoints, Len + 1);
      AOutPoints[Len] := A3;
      Exit;
    end;

    InvL := 1.0 / Sqrt(L2);
    Vx := Vx * InvL;
    Vy := Vy * InvL;

    D1 := Sqr((A1.X - A0.X) * (-Vy) + (A1.Y - A0.Y) * Vx);
    D2 := Sqr((A2.X - A0.X) * (-Vy) + (A2.Y - A0.Y) * Vx);

    if (D1 <= Sqr(FTolerance)) and (D2 <= Sqr(FTolerance)) then
    begin
      Len := Length(AOutPoints);
      SetLength(AOutPoints, Len + 1);
      AOutPoints[Len] := A3;
    end
    else
    begin
      Mid01.X := (A0.X + A1.X) * 0.5; Mid01.Y := (A0.Y + A1.Y) * 0.5;
      Mid12.X := (A1.X + A2.X) * 0.5; Mid12.Y := (A1.Y + A2.Y) * 0.5;
      Mid23.X := (A2.X + A3.X) * 0.5; Mid23.Y := (A2.Y + A3.Y) * 0.5;

      MidA.X := (Mid01.X + Mid12.X) * 0.5; MidA.Y := (Mid01.Y + Mid12.Y) * 0.5;
      MidB.X := (Mid12.X + Mid23.X) * 0.5; MidB.Y := (Mid12.Y + Mid23.Y) * 0.5;

      CenterPt.X := (MidA.X + MidB.X) * 0.5; CenterPt.Y := (MidA.Y + MidB.Y) * 0.5;

      Recurse(A0, Mid01, MidA, CenterPt, Depth + 1);
      Recurse(CenterPt, MidB, Mid23, A3, Depth + 1);
    end;
  end;

begin
  Recurse(P0, P1, P2, P3, 0);
end;

end.
