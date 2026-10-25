unit Floria.Path.Engine;

// Floria.Path.Engine
// ==================
// Clipping backend facade for Floria.Path.Ops.
//
// Path.Ops talks to this unit instead of a concrete clipping library. A backend
// registers itself during unit initialization and the facade forwards each
// operation to it. That keeps the public path API free of any specific
// clipping implementation, so the engine can be replaced (or compared against
// a second implementation) without touching callers.
//
// Contract:
//   - Inputs are const and never modified.
//   - Every result is a freshly allocated TPathsD owned by the caller.
//   - Backends must not return partially filled results on failure; raise.
//   - The registry is single-threaded. Swap backends before spawning workers.

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils,
  Floria.Geometry,
  Floria.Errors;

type
  TPathBooleanOp = (pboUnion, pboDifference, pboIntersect, pboXor);

  TPathJoinType = (pjtMiter, pjtSquare, pjtBevel, pjtRound);

  TPathEndType = (petPolygon, petJoined, petButt, petSquare, petRound);

  EPathEngineError = class(EFloriaError);

  TFloriaPathEngine = class
  public
    // Stable backend identifier, for diagnostics and tests.
    function Name(): string; virtual; abstract;

    // Boolean operations on two path sets.
    function BooleanOp(AOp: TPathBooleanOp;
      const ASubject, AClip: TPathsD;
      AFillRule: TFillRule = frNonZero;
      APrecision: Integer = 2): TPathsD; virtual; abstract;

    // Self-union used when only one path set is supplied.
    function UnionSelf(const ASubject: TPathsD;
      AFillRule: TFillRule = frNonZero;
      APrecision: Integer = 2): TPathsD; virtual; abstract;

    // Polygon offsetting / stroking.
    function OffsetPaths(const APaths: TPathsD; ADelta: Double;
      AJoinType: TPathJoinType = pjtRound;
      AEndType: TPathEndType = petPolygon;
      AMiterLimit: Double = 2.0;
      AArcTolerance: Double = 0.0;
      APrecision: Integer = 2): TPathsD; virtual; abstract;

    // Douglas-Peucker style simplification.
    function SimplifyPaths(const APaths: TPathsD; ATolerance: Double;
      AClosed: Boolean = True;
      APrecision: Integer = 2): TPathsD; virtual; abstract;
  end;

// Active backend. Raises EPathEngineError when none is registered, which means
// a program linked Path.Ops without linking a backend unit.
function FloriaPathEngine(): TFloriaPathEngine;

// Replace the active backend. The facade does not take ownership by default;
// pass AOwns = True for a backend the facade should free on replacement.
procedure SetFloriaPathEngine(AEngine: TFloriaPathEngine; AOwns: Boolean = False);

// Register a backend for later selection. Registration is idempotent per name;
// the last registration for a name wins.
procedure RegisterFloriaPathEngine(const AName: string; AEngine: TFloriaPathEngine);

// Select a previously registered backend by name. Raises EPathEngineError when
// the name is unknown.
procedure UseFloriaPathEngine(const AName: string);

// True when any backend is active.
function FloriaPathEngineAvailable(): Boolean;

implementation

type
  TEngineEntry = record
    Name  : string;
    Engine: TFloriaPathEngine;
  end;

var
  GEntries     : array of TEngineEntry;
  GActive      : TFloriaPathEngine = nil;
  GOwnsActive  : Boolean = False;

function FloriaPathEngine(): TFloriaPathEngine;
begin
  if GActive = nil then
    raise EPathEngineError.Create(
      'no path engine backend is registered; link Floria.Path.Engine.Native');
  Result := GActive;
end;

function FloriaPathEngineAvailable(): Boolean;
begin
  Result := GActive <> nil;
end;

procedure SetFloriaPathEngine(AEngine: TFloriaPathEngine; AOwns: Boolean);
begin
  if AEngine = GActive then
    Exit;

  if GOwnsActive and (GActive <> nil) then
    FreeAndNil(GActive);

  GActive := AEngine;
  GOwnsActive := AOwns;
end;

procedure RegisterFloriaPathEngine(const AName: string; AEngine: TFloriaPathEngine);
var
  I: Integer;
begin
  if (AName = '') or (AEngine = nil) then
    raise EPathEngineError.Create('a path engine registration needs a name and an instance');

  for I := 0 to High(GEntries) do
    if GEntries[I].Name = AName then
    begin
      GEntries[I].Engine := AEngine;
      Exit;
    end;

  SetLength(GEntries, Length(GEntries) + 1);
  GEntries[High(GEntries)].Name := AName;
  GEntries[High(GEntries)].Engine := AEngine;
end;

procedure UseFloriaPathEngine(const AName: string);
var
  I: Integer;
begin
  for I := 0 to High(GEntries) do
    if GEntries[I].Name = AName then
    begin
      SetFloriaPathEngine(GEntries[I].Engine, False);
      Exit;
    end;

  raise EPathEngineError.CreateFmt('unknown path engine backend: %s', [AName]);
end;

end.
