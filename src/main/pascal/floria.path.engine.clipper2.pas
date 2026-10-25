unit Floria.Path.Engine.Clipper2;

// Floria.Path.Engine.Clipper2
// ===========================
// Temporary adapter that implements TFloriaPathEngine on top of the vendored
// Clipper2 port. This is the only unit outside the vendored files themselves
// that imports Floria.Path.Clipper.*.
//
// It exists so Floria.Path.Ops can stop depending on a specific clipping
// library. When the first-party engine reaches parity this unit and the
// vendored units are deleted together.
//
// The adapter converts between Floria.Geometry types and the Clipper types by
// element-wise copy. They are layout-compatible today, but they are distinct
// Pascal types, so Move() across them would be relying on an implementation
// detail.

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  Floria.Geometry,
  Floria.Path.Engine;

type
  TFloriaClipper2Engine = class(TFloriaPathEngine)
  public
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
  end;

const
  CLIPPER2_ENGINE_NAME = 'clipper2';

implementation

uses
  Floria.Path.Clipper.Core,
  Floria.Path.Clipper.Engine,
  Floria.Path.Clipper.Offset,
  Floria.Path.Clipper;

var
  GInstance: TFloriaClipper2Engine = nil;

// ---------------------------------------------------------------------------
// Enum conversion
// ---------------------------------------------------------------------------

function ToClipperFillRule(ARule: TFillRule): TFillRule;
begin
  case ARule of
    frEvenOdd : Result := Floria.Geometry.frEvenOdd;
    frNonZero : Result := Floria.Geometry.frNonZero;
    frPositive: Result := Floria.Geometry.frPositive;
    frNegative: Result := Floria.Geometry.frNegative;
  else
    Result := Floria.Geometry.frNonZero;
  end;
end;

function ToClipperJoinType(AJoin: TPathJoinType): Floria.Path.Clipper.Offset.TJoinType;
begin
  case AJoin of
    pjtMiter : Result := Floria.Path.Clipper.Offset.jtMiter;
    pjtSquare: Result := Floria.Path.Clipper.Offset.jtSquare;
    pjtBevel : Result := Floria.Path.Clipper.Offset.jtBevel;
    pjtRound : Result := Floria.Path.Clipper.Offset.jtRound;
  else
    Result := Floria.Path.Clipper.Offset.jtRound;
  end;
end;

function ToClipperEndType(AEnd: TPathEndType): Floria.Path.Clipper.Offset.TEndType;
begin
  case AEnd of
    petPolygon: Result := Floria.Path.Clipper.Offset.etPolygon;
    petJoined : Result := Floria.Path.Clipper.Offset.etJoined;
    petButt   : Result := Floria.Path.Clipper.Offset.etButt;
    petSquare : Result := Floria.Path.Clipper.Offset.etSquare;
    petRound  : Result := Floria.Path.Clipper.Offset.etRound;
  else
    Result := Floria.Path.Clipper.Offset.etPolygon;
  end;
end;

// ---------------------------------------------------------------------------
// Path conversion
// ---------------------------------------------------------------------------

function ToClipperPaths(const APaths: TPathsD): TPathsD;
var
  I, J: Integer;
begin
  SetLength(Result, Length(APaths));
  for I := 0 to High(APaths) do
  begin
    SetLength(Result[I], Length(APaths[I]));
    for J := 0 to High(APaths[I]) do
    begin
      Result[I][J].X := APaths[I][J].X;
      Result[I][J].Y := APaths[I][J].Y;
    end;
  end;
end;

function FromClipperPaths(const APaths: TPathsD): TPathsD;
var
  I, J: Integer;
begin
  SetLength(Result, Length(APaths));
  for I := 0 to High(APaths) do
  begin
    SetLength(Result[I], Length(APaths[I]));
    for J := 0 to High(APaths[I]) do
    begin
      Result[I][J].X := APaths[I][J].X;
      Result[I][J].Y := APaths[I][J].Y;
    end;
  end;
end;

// ---------------------------------------------------------------------------
// TFloriaClipper2Engine
// ---------------------------------------------------------------------------

function TFloriaClipper2Engine.Name(): string;
begin
  Result := CLIPPER2_ENGINE_NAME;
end;

function TFloriaClipper2Engine.BooleanOp(AOp: TPathBooleanOp;
  const ASubject, AClip: TPathsD;
  AFillRule: TFillRule; APrecision: Integer): TPathsD;
var
  Subject, Clip: TPathsD;
  Rule: TFillRule;
  Solved: TPathsD;
begin
  Subject := ToClipperPaths(ASubject);
  Clip := ToClipperPaths(AClip);
  Rule := ToClipperFillRule(AFillRule);

  case AOp of
    pboUnion:
      Solved := Floria.Path.Clipper.Union(Subject, Clip, Rule, APrecision);
    pboDifference:
      Solved := Floria.Path.Clipper.Difference(Subject, Clip, Rule, APrecision);
    pboIntersect:
      Solved := Floria.Path.Clipper.Intersect(Subject, Clip, Rule, APrecision);
    pboXor:
      Solved := Floria.Path.Clipper.XOR_(Subject, Clip, Rule, APrecision);
  else
    raise EPathEngineError.Create('unsupported boolean operation');
  end;

  Result := FromClipperPaths(Solved);
end;

function TFloriaClipper2Engine.UnionSelf(const ASubject: TPathsD;
  AFillRule: TFillRule; APrecision: Integer): TPathsD;
var
  Subject: TPathsD;
  Solved: TPathsD;
begin
  Subject := ToClipperPaths(ASubject);
  Solved := Floria.Path.Clipper.Union(Subject, ToClipperFillRule(AFillRule), APrecision);
  Result := FromClipperPaths(Solved);
end;

function TFloriaClipper2Engine.OffsetPaths(const APaths: TPathsD; ADelta: Double;
  AJoinType: TPathJoinType; AEndType: TPathEndType;
  AMiterLimit: Double; AArcTolerance: Double; APrecision: Integer): TPathsD;
var
  Paths: TPathsD;
  Solved: TPathsD;
begin
  Paths := ToClipperPaths(APaths);
  Solved := Floria.Path.Clipper.InflatePaths(Paths, ADelta,
    ToClipperJoinType(AJoinType), ToClipperEndType(AEndType),
    AMiterLimit, APrecision, AArcTolerance);
  Result := FromClipperPaths(Solved);
end;

function TFloriaClipper2Engine.SimplifyPaths(const APaths: TPathsD;
  ATolerance: Double; AClosed: Boolean; APrecision: Integer): TPathsD;
var
  Paths: TPathsD;
  Solved: TPathsD;
begin
  Paths := ToClipperPaths(APaths);
  Solved := Floria.Path.Clipper.SimplifyPaths(Paths, ATolerance, AClosed, APrecision);
  Result := FromClipperPaths(Solved);
end;

initialization
  GInstance := TFloriaClipper2Engine.Create();
  RegisterFloriaPathEngine(CLIPPER2_ENGINE_NAME, GInstance);
  if not FloriaPathEngineAvailable() then
    SetFloriaPathEngine(GInstance, False);

finalization
  // Do not query the facade here; it raises when no backend is registered and
  // unit finalization order is not guaranteed.
  SetFloriaPathEngine(nil, False);
  FreeAndNil(GInstance);

end.
