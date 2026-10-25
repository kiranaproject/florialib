unit Floria.Path.Engine.Native;

// Floria.Path.Engine.Native
// =========================
// First-party path engine. Operations implemented here do not depend on any
// third-party clipping library.
//
// Native today:
//   - BooleanOp / UnionSelf  (planar-arrangement clipping)
//   - OffsetPaths            (inflate/deflate and open-path stroking)
//   - SimplifyPaths          (Douglas-Peucker style vertex reduction)
//
// Bounds, area, and point-in-polygon never reach the engine at all; they are
// first-party functions in Floria.Geometry.
//
// The fallback is injected at construction so this unit does not hard-code a
// dependency on a particular clipping library. When the remaining operations
// become native the fallback simply becomes optional.

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math,
  Floria.Geometry,
  Floria.Errors,
  Floria.Path.Engine;

type
  TFloriaNativeEngine = class(TFloriaPathEngine)
  private
    FFallback: TFloriaPathEngine;
  public
    // AFallback receives any operation the native engine does not implement.
    // The native engine does not own it.
    constructor Create(AFallback: TFloriaPathEngine = nil);

    function Name(): string; override;

    function BooleanOp(AOp: TPathBooleanOp;
      const ASubject, AClip: TPathsD;
      AFillRule: TFillRule = frNonZero;
      APrecision: Integer = 2): TPathsD; override;

    function UnionSelf(const ASubject: TPathsD;
      AFillRule: TFillRule = frNonZero;
      APrecision: Integer = 2): TPathsD; override;

    function OffsetPaths(const APaths: TPathsD; ADelta: Double;
      AJoinType: TPathJoinType = pjtRound;
      AEndType: TPathEndType = petPolygon;
      AMiterLimit: Double = 2.0;
      AArcTolerance: Double = 0.0;
      APrecision: Integer = 2): TPathsD; override;

    function SimplifyPaths(const APaths: TPathsD; ATolerance: Double;
      AClosed: Boolean = True;
      APrecision: Integer = 2): TPathsD; override;

    property Fallback: TFloriaPathEngine read FFallback;
  end;

const
  NATIVE_ENGINE_NAME = 'native';

implementation

uses
  Floria.Path.Engine.Boolean,
  Floria.Path.Engine.Offset,
  Floria.Path.Engine.Clipper2;

type
  // Integer grid point. Offsets, clipping, and simplification all work on a
  // scaled integer grid so results are reproducible across platforms.
  TGridPoint = record
    X, Y: Int64;
  end;

  TGridPath = array of TGridPoint;

  // Index-based doubly linked ring. Indices are used instead of pointers
  // because the backing array is allocated once, up front.
  TSimplifyNode = record
    Pt      : TGridPoint;
    DistSqrd: Double;
    Prev    : Integer;
    Next    : Integer;
  end;

var
  GInstance: TFloriaNativeEngine = nil;

// ---------------------------------------------------------------------------
// Scaling
// ---------------------------------------------------------------------------

function ScaleToGrid(const APath: TPathD; AScale: Double): TGridPath;
var
  I: Integer;
begin
  SetLength(Result, Length(APath));
  for I := 0 to High(APath) do
  begin
    Result[I].X := Round(APath[I].X * AScale);
    Result[I].Y := Round(APath[I].Y * AScale);
  end;
end;

function ScaleFromGrid(const APath: TGridPath; AInvScale: Double): TPathD;
var
  I: Integer;
begin
  SetLength(Result, Length(APath));
  for I := 0 to High(APath) do
  begin
    Result[I].X := APath[I].X * AInvScale;
    Result[I].Y := APath[I].Y * AInvScale;
  end;
end;

// Squared perpendicular distance from APt to the infinite line through
// ALine1..ALine2. A degenerate line reports 0.
function PerpendicDistSqrd(const APt, ALine1, ALine2: TGridPoint): Double;
var
  A, B, C, D: Double;
begin
  A := APt.X - ALine1.X;
  B := APt.Y - ALine1.Y;
  C := ALine2.X - ALine1.X;
  D := ALine2.Y - ALine1.Y;
  if (C = 0) and (D = 0) then
    Result := 0.0
  else
    Result := Sqr(A * D - C * B) / (C * C + D * D);
end;

// ---------------------------------------------------------------------------
// Simplify
// ---------------------------------------------------------------------------

function SimplifyGridPath(const APath: TGridPath;
  ATolerance: Double; AClosed: Boolean): TGridPath;
var
  Nodes: array of TSimplifyNode;
  I, HighIdx, MinHigh: Integer;
  First, Last: Integer;
  TolSqrd: Double;
begin
  SetLength(Result, 0);
  HighIdx := High(APath);

  if AClosed then
    MinHigh := 2
  else
    MinHigh := 1;

  if HighIdx < MinHigh then
    Exit;

  SetLength(Nodes, HighIdx + 1);
  for I := 0 to HighIdx do
  begin
    Nodes[I].Pt := APath[I];
    Nodes[I].DistSqrd := 0.0;
  end;

  // Ring links: endpoints wrap when closed.
  for I := 0 to HighIdx do
  begin
    if I = 0 then
      Nodes[I].Prev := HighIdx
    else
      Nodes[I].Prev := I - 1;

    if I = HighIdx then
      Nodes[I].Next := 0
    else
      Nodes[I].Next := I + 1;
  end;

  // Endpoints of an open path are pinned with an infinite distance so the
  // reduction never drops them. Closed paths measure across the wrap instead.
  if AClosed then
  begin
    Nodes[0].DistSqrd := PerpendicDistSqrd(APath[0], APath[HighIdx], APath[1]);
    Nodes[HighIdx].DistSqrd := PerpendicDistSqrd(APath[HighIdx], APath[HighIdx - 1], APath[0]);
  end
  else
  begin
    Nodes[0].DistSqrd := Infinity;
    Nodes[HighIdx].DistSqrd := Infinity;
  end;

  for I := 1 to HighIdx - 1 do
    Nodes[I].DistSqrd := PerpendicDistSqrd(APath[I], APath[I - 1], APath[I + 1]);

  First := 0;
  Last := Nodes[First].Prev;
  TolSqrd := Sqr(ATolerance);

  // Remove a vertex when it sits within tolerance of the line joining its
  // neighbours, and no neighbour is even closer. Stop at two remaining nodes.
  while First <> Last do
  begin
    if (Nodes[First].DistSqrd > TolSqrd) or
       (Nodes[Nodes[First].Next].DistSqrd < Nodes[First].DistSqrd) then
    begin
      First := Nodes[First].Next;
      Continue;
    end;

    Dec(HighIdx);
    Nodes[Nodes[First].Prev].Next := Nodes[First].Next;
    Nodes[Nodes[First].Next].Prev := Nodes[First].Prev;
    Last := Nodes[First].Prev;
    First := Nodes[Last].Next;

    if Nodes[First].Next = Nodes[First].Prev then
      Break;

    Nodes[Last].DistSqrd := PerpendicDistSqrd(Nodes[Last].Pt,
      Nodes[Nodes[Last].Prev].Pt, Nodes[First].Pt);
    Nodes[First].DistSqrd := PerpendicDistSqrd(Nodes[First].Pt,
      Nodes[Last].Pt, Nodes[Nodes[First].Next].Pt);
  end;

  if HighIdx < MinHigh then
    Exit;

  if not AClosed then
    First := 0;

  SetLength(Result, HighIdx + 1);
  for I := 0 to HighIdx do
  begin
    Result[I] := Nodes[First].Pt;
    First := Nodes[First].Next;
  end;
end;

// ---------------------------------------------------------------------------
// TFloriaNativeEngine
// ---------------------------------------------------------------------------

constructor TFloriaNativeEngine.Create(AFallback: TFloriaPathEngine);
begin
  inherited Create();
  FFallback := AFallback;
end;

function TFloriaNativeEngine.Name(): string;
begin
  Result := NATIVE_ENGINE_NAME;
end;

function TFloriaNativeEngine.BooleanOp(AOp: TPathBooleanOp;
  const ASubject, AClip: TPathsD; AFillRule: TFillRule;
  APrecision: Integer): TPathsD;
begin
  Result := FloriaBooleanOp(AOp, ASubject, AClip, AFillRule, APrecision);
end;

function TFloriaNativeEngine.UnionSelf(const ASubject: TPathsD;
  AFillRule: TFillRule; APrecision: Integer): TPathsD;
begin
  Result := FloriaNormalizePaths(ASubject, AFillRule, APrecision);
end;

function TFloriaNativeEngine.OffsetPaths(const APaths: TPathsD; ADelta: Double;
  AJoinType: TPathJoinType; AEndType: TPathEndType;
  AMiterLimit: Double; AArcTolerance: Double; APrecision: Integer): TPathsD;
begin
  Result := FloriaOffsetPaths(APaths, ADelta, AJoinType, AEndType,
    AMiterLimit, AArcTolerance, APrecision);
end;

function TFloriaNativeEngine.SimplifyPaths(const APaths: TPathsD;
  ATolerance: Double; AClosed: Boolean; APrecision: Integer): TPathsD;
var
  I: Integer;
  Scale, InvScale: Double;
  GridPath, GridResult: TGridPath;
begin
  if (APrecision < 0) or (APrecision > 8) then
    raise EPathEngineError.CreateFmt('precision out of range: %d', [APrecision]);

  if ATolerance < 0 then
    raise EPathEngineError.CreateFmt(
      'simplify tolerance must not be negative: %f', [ATolerance]);

  Scale := Power(10, APrecision);
  InvScale := 1.0 / Scale;

  SetLength(Result, Length(APaths));
  for I := 0 to High(APaths) do
  begin
    GridPath := ScaleToGrid(APaths[I], Scale);
    GridResult := SimplifyGridPath(GridPath, ATolerance, AClosed);
    Result[I] := ScaleFromGrid(GridResult, InvScale);
  end;
end;

initialization
  // Clipper2 initializes first (implementation uses), so it is already the
  // active backend when this runs and can serve as the fallback.
  GInstance := TFloriaNativeEngine.Create(FloriaPathEngine());
  RegisterFloriaPathEngine(NATIVE_ENGINE_NAME, GInstance);
  SetFloriaPathEngine(GInstance, False);

finalization
  // Do not call FloriaPathEngine() here: the facade may already be torn down,
  // and it raises when no backend is registered. Compare the raw pointer.
  SetFloriaPathEngine(nil, False);
  FreeAndNil(GInstance);

end.
