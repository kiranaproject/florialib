unit Floria.Path.Engine.Test;

// Floria.Path.Engine.Test
// =======================
// Covers the clipping backend facade: registration, selection, ownership, and
// the error path when no backend is available.
//
// The tests use a tiny in-memory stub backend so they never depend on the real
// clipping implementation and stay fast.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Floria.Geometry,
  Floria.Errors,
  Floria.Path.Engine;

type
  // Records the last call and returns a fixed marker path so the test can
  // confirm the facade forwarded correctly.
  TStubPathEngine = class(TFloriaPathEngine)
  public
    LastOp       : TPathBooleanOp;
    LastFillRule : TFillRule;
    LastPrecision: Integer;
    LastDelta    : Double;
    LastJoin     : TPathJoinType;
    LastEnd      : TPathEndType;
    LastTolerance: Double;
    CallCount    : Integer;
    Marker       : string;
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

  TFloriaPathEngineTest = class(TTestCase)
  private
    FSaved: TFloriaPathEngine;
  protected
    procedure SetUp(); override;
    procedure TearDown(); override;
  published
    procedure TestDefaultBackendIsAvailable();
    procedure TestDefaultBackendIsNative();
    procedure TestBooleanOpForwarding();
    procedure TestUnionSelfForwarding();
    procedure TestOffsetForwarding();
    procedure TestSimplifyForwarding();
    procedure TestUseUnknownBackendRaises();
    procedure TestSetEngineTakesEffect();
    procedure TestRegisteredBackendIsSelectable();
  end;

implementation

// ---------------------------------------------------------------------------
// TStubPathEngine
// ---------------------------------------------------------------------------

function TStubPathEngine.Name(): string;
begin
  Result := 'stub';
end;

function TStubPathEngine.BooleanOp(AOp: TPathBooleanOp;
  const ASubject, AClip: TPathsD; AFillRule: TFillRule;
  APrecision: Integer): TPathsD;
begin
  LastOp := AOp;
  LastFillRule := AFillRule;
  LastPrecision := APrecision;
  Inc(CallCount);
  SetLength(Result, 1);
  SetLength(Result[0], 1);
  Result[0][0] := PointD(1.0, 2.0);
end;

function TStubPathEngine.UnionSelf(const ASubject: TPathsD;
  AFillRule: TFillRule; APrecision: Integer): TPathsD;
begin
  LastFillRule := AFillRule;
  LastPrecision := APrecision;
  Inc(CallCount);
  SetLength(Result, 1);
  SetLength(Result[0], 1);
  Result[0][0] := PointD(3.0, 4.0);
end;

function TStubPathEngine.OffsetPaths(const APaths: TPathsD; ADelta: Double;
  AJoinType: TPathJoinType; AEndType: TPathEndType;
  AMiterLimit: Double; AArcTolerance: Double; APrecision: Integer): TPathsD;
begin
  LastDelta := ADelta;
  LastJoin := AJoinType;
  LastEnd := AEndType;
  LastPrecision := APrecision;
  Inc(CallCount);
  SetLength(Result, 0);
end;

function TStubPathEngine.SimplifyPaths(const APaths: TPathsD;
  ATolerance: Double; AClosed: Boolean; APrecision: Integer): TPathsD;
begin
  LastTolerance := ATolerance;
  LastPrecision := APrecision;
  Inc(CallCount);
  SetLength(Result, 0);
end;

// ---------------------------------------------------------------------------
// Fixture
// ---------------------------------------------------------------------------

procedure TFloriaPathEngineTest.SetUp();
begin
  FSaved := FloriaPathEngine();
end;

procedure TFloriaPathEngineTest.TearDown();
begin
  // Restore whatever the program was using so test order cannot leak state.
  if FSaved <> nil then
    SetFloriaPathEngine(FSaved, False);
end;

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

procedure TFloriaPathEngineTest.TestDefaultBackendIsAvailable();
begin
  AssertTrue('a backend is registered by default', FloriaPathEngineAvailable());
  AssertTrue('engine instance is not nil', FloriaPathEngine() <> nil);
end;

procedure TFloriaPathEngineTest.TestDefaultBackendIsNative();
begin
  AssertEquals('default backend name', 'native', FloriaPathEngine().Name());
end;

procedure TFloriaPathEngineTest.TestBooleanOpForwarding();
var
  Stub: TStubPathEngine;
  Subject, Clip, Res: TPathsD;
begin
  Stub := TStubPathEngine.Create();
  try
    SetFloriaPathEngine(Stub, False);

    SetLength(Subject, 0);
    SetLength(Clip, 0);
    Res := FloriaPathEngine().BooleanOp(pboDifference, Subject, Clip, frEvenOdd, 3);

    AssertEquals('op forwarded', Ord(pboDifference), Ord(Stub.LastOp));
    AssertEquals('fill rule forwarded', Ord(frEvenOdd), Ord(Stub.LastFillRule));
    AssertEquals('precision forwarded', 3, Stub.LastPrecision);
    AssertEquals('call counted', 1, Stub.CallCount);
    AssertEquals('result returned', 1, Length(Res));
    AssertEquals('result point X', 1.0, Res[0][0].X, 1e-9);
  finally
    SetFloriaPathEngine(FSaved, False);
    Stub.Free();
  end;
end;

procedure TFloriaPathEngineTest.TestUnionSelfForwarding();
var
  Stub: TStubPathEngine;
  Subject, Res: TPathsD;
begin
  Stub := TStubPathEngine.Create();
  try
    SetFloriaPathEngine(Stub, False);
    SetLength(Subject, 0);
    Res := FloriaPathEngine().UnionSelf(Subject, frPositive, 4);

    AssertEquals('fill rule forwarded', Ord(frPositive), Ord(Stub.LastFillRule));
    AssertEquals('precision forwarded', 4, Stub.LastPrecision);
    AssertEquals('result point X', 3.0, Res[0][0].X, 1e-9);
  finally
    SetFloriaPathEngine(FSaved, False);
    Stub.Free();
  end;
end;

procedure TFloriaPathEngineTest.TestOffsetForwarding();
var
  Stub: TStubPathEngine;
  Paths: TPathsD;
begin
  Stub := TStubPathEngine.Create();
  try
    SetFloriaPathEngine(Stub, False);
    SetLength(Paths, 0);
    FloriaPathEngine().OffsetPaths(Paths, -2.5, pjtBevel, petRound, 3.0, 0.25, 5);

    AssertEquals('delta forwarded', -2.5, Stub.LastDelta, 1e-9);
    AssertEquals('join forwarded', Ord(pjtBevel), Ord(Stub.LastJoin));
    AssertEquals('end forwarded', Ord(petRound), Ord(Stub.LastEnd));
    AssertEquals('precision forwarded', 5, Stub.LastPrecision);
  finally
    SetFloriaPathEngine(FSaved, False);
    Stub.Free();
  end;
end;

procedure TFloriaPathEngineTest.TestSimplifyForwarding();
var
  Stub: TStubPathEngine;
  Paths: TPathsD;
begin
  Stub := TStubPathEngine.Create();
  try
    SetFloriaPathEngine(Stub, False);
    SetLength(Paths, 0);
    FloriaPathEngine().SimplifyPaths(Paths, 0.75, True, 6);

    AssertEquals('tolerance forwarded', 0.75, Stub.LastTolerance, 1e-9);
    AssertEquals('precision forwarded', 6, Stub.LastPrecision);
  finally
    SetFloriaPathEngine(FSaved, False);
    Stub.Free();
  end;
end;

procedure TFloriaPathEngineTest.TestUseUnknownBackendRaises();
var
  Raised: Boolean;
begin
  Raised := False;
  try
    UseFloriaPathEngine('does-not-exist');
  except
    on E: EPathEngineError do
      Raised := True;
  end;
  AssertTrue('unknown backend raises EPathEngineError', Raised);
end;

procedure TFloriaPathEngineTest.TestSetEngineTakesEffect();
var
  Stub: TStubPathEngine;
begin
  Stub := TStubPathEngine.Create();
  try
    SetFloriaPathEngine(Stub, False);
    AssertTrue('stub is active', FloriaPathEngine() = Stub);
  finally
    SetFloriaPathEngine(FSaved, False);
    Stub.Free();
  end;
  AssertTrue('restored backend', FloriaPathEngine() = FSaved);
end;

procedure TFloriaPathEngineTest.TestRegisteredBackendIsSelectable();
var
  Stub: TStubPathEngine;
begin
  Stub := TStubPathEngine.Create();
  try
    RegisterFloriaPathEngine('stub-selectable', Stub);
    UseFloriaPathEngine('stub-selectable');
    AssertTrue('registered backend became active', FloriaPathEngine() = Stub);
    AssertEquals('name reported', 'stub', FloriaPathEngine().Name());
  finally
    SetFloriaPathEngine(FSaved, False);
    Stub.Free();
  end;
end;

initialization
  RegisterTest(TFloriaPathEngineTest);

end.
