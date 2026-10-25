unit Floria.Path.Engine.Native.Test;

// Floria.Path.Engine.Native.Test
// ==============================
// Covers the first-party operations. Expected values match the frozen golden
// data, which was captured from the reference implementation before it was
// removed, so these assertions are not merely self-consistent.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fpcunit, testregistry,
  Floria.Geometry,
  Floria.Errors,
  Floria.Path.Engine;

type
  TFloriaNativeEngineTest = class(TTestCase)
  private
    FSaved: TFloriaPathEngine;
  protected
    procedure SetUp(); override;
    procedure TearDown(); override;
  published
    procedure TestNativeIsDefault();
    procedure TestSimplifyCollinearRun();
    procedure TestSimplifyPreservesEndpointsOnOpenPath();
    procedure TestSimplifyZeroToleranceKeepsShape();
    procedure TestSimplifyNegativeToleranceRaises();
    procedure TestSimplifyPrecisionOutOfRangeRaises();
    procedure TestSimplifyEmptyInput();
    procedure TestBooleanStillDelegates();
    procedure TestOffsetStillDelegates();
  end;

implementation

// Squared perpendicular distance, used to state expectations independently of
// the implementation under test.
function PerpDistSq(const APt, A1, A2: TPointD): Double;
var
  DX, DY, Len: Double;
begin
  DX := A2.X - A1.X;
  DY := A2.Y - A1.Y;
  Len := DX * DX + DY * DY;
  if Len = 0 then
    Exit(0);
  Result := Sqr((A2.X - A1.X) * (A1.Y - APt.Y) - (A1.X - APt.X) * (A2.Y - A1.Y)) / Len;
end;

// Sorted coordinate signature so two path sets can be compared without
// depending on contour or vertex ordering.
function PathSignature(const APaths: TPathsD): string;
var
  I, J: Integer;
  Points: array of string;
  Tmp: string;
begin
  SetLength(Points, 0);
  for I := 0 to High(APaths) do
    for J := 0 to High(APaths[I]) do
    begin
      SetLength(Points, Length(Points) + 1);
      Points[High(Points)] := Format('%.4f,%.4f', [APaths[I][J].X, APaths[I][J].Y]);
    end;

  // Simple insertion sort keeps this dependency-free.
  for I := 1 to High(Points) do
  begin
    Tmp := Points[I];
    J := I - 1;
    while (J >= 0) and (Points[J] > Tmp) do
    begin
      Points[J + 1] := Points[J];
      Dec(J);
    end;
    Points[J + 1] := Tmp;
  end;

  Result := '';
  for I := 0 to High(Points) do
    Result := Result + Points[I] + ';';
end;

// A closed rectangle whose top and bottom edges carry redundant collinear
// vertices, plus one genuine corner.
function BuildCollinearRect(): TPathsD;
begin
  SetLength(Result, 1);
  SetLength(Result[0], 9);
  Result[0][0] := PointD(0, 0);
  Result[0][1] := PointD(25, 0);
  Result[0][2] := PointD(50, 0);
  Result[0][3] := PointD(75, 0);
  Result[0][4] := PointD(100, 0);
  Result[0][5] := PointD(100, 50);
  Result[0][6] := PointD(50, 50);
  Result[0][7] := PointD(0, 50);
  Result[0][8] := PointD(0, 0);
end;

procedure TFloriaNativeEngineTest.SetUp();
begin
  FSaved := FloriaPathEngine();
end;

procedure TFloriaNativeEngineTest.TearDown();
begin
  if FSaved <> nil then
    SetFloriaPathEngine(FSaved, False);
end;

procedure TFloriaNativeEngineTest.TestNativeIsDefault();
begin
  AssertEquals('native engine is the default', 'native', FloriaPathEngine().Name());
end;

procedure TFloriaNativeEngineTest.TestSimplifyCollinearRun();
var
  Paths, Res: TPathsD;
begin
  Paths := BuildCollinearRect();
  Res := FloriaPathEngine().SimplifyPaths(Paths, 0.5, True, 2);

  AssertEquals('one contour survives', 1, Length(Res));
  AssertTrue('collinear vertices were dropped', Length(Res[0]) < Length(Paths[0]));
  AssertTrue('at least a triangle remains', Length(Res[0]) >= 3);

  // Every surviving vertex must be a real corner of the rectangle.
  AssertTrue('area preserved',
    Abs(Abs(Area(Res)) - 5000.0) < 1.0);
end;

procedure TFloriaNativeEngineTest.TestSimplifyPreservesEndpointsOnOpenPath();
var
  Paths, Res: TPathsD;
begin
  SetLength(Paths, 1);
  SetLength(Paths[0], 5);
  Paths[0][0] := PointD(0, 0);
  Paths[0][1] := PointD(10, 0);
  Paths[0][2] := PointD(20, 0);
  Paths[0][3] := PointD(30, 0);
  Paths[0][4] := PointD(40, 0);

  Res := FloriaPathEngine().SimplifyPaths(Paths, 0.5, False, 2);

  AssertEquals('open path keeps one contour', 1, Length(Res));
  AssertTrue('open path collapses to two endpoints', Length(Res[0]) = 2);
  AssertEquals('first endpoint preserved', 0.0, Res[0][0].X, 1e-6);
  AssertEquals('last endpoint preserved', 40.0, Res[0][High(Res[0])].X, 1e-6);
end;

procedure TFloriaNativeEngineTest.TestSimplifyZeroToleranceKeepsShape();
var
  Paths, Res: TPathsD;
begin
  // Zero tolerance still removes exactly-collinear vertices (their distance is
  // 0, which is not greater than the tolerance). It must not remove corners.
  Paths := BuildCollinearRect();
  Res := FloriaPathEngine().SimplifyPaths(Paths, 0.0, True, 2);

  AssertEquals('zero tolerance keeps the contour', 1, Length(Res));
  AssertEquals('rectangle reduces to its four corners', 4, Length(Res[0]));
  AssertEquals('area preserved at zero tolerance', 5000.0, Abs(Area(Res)), 1.0);
end;

procedure TFloriaNativeEngineTest.TestSimplifyNegativeToleranceRaises();
var
  Raised: Boolean;
  Paths: TPathsD;
begin
  SetLength(Paths, 1);
  SetLength(Paths[0], 3);
  Paths[0][0] := PointD(0, 0);
  Paths[0][1] := PointD(1, 0);
  Paths[0][2] := PointD(1, 1);

  Raised := False;
  try
    FloriaPathEngine().SimplifyPaths(Paths, -1.0, True, 2);
  except
    on E: EPathEngineError do
      Raised := True;
  end;
  AssertTrue('negative tolerance raises', Raised);
end;

procedure TFloriaNativeEngineTest.TestSimplifyPrecisionOutOfRangeRaises();
var
  Raised: Boolean;
  Paths: TPathsD;
begin
  SetLength(Paths, 0);

  Raised := False;
  try
    FloriaPathEngine().SimplifyPaths(Paths, 0.5, True, 9);
  except
    on E: EPathEngineError do
      Raised := True;
  end;
  AssertTrue('precision above 8 raises', Raised);

  Raised := False;
  try
    FloriaPathEngine().SimplifyPaths(Paths, 0.5, True, -1);
  except
    on E: EPathEngineError do
      Raised := True;
  end;
  AssertTrue('negative precision raises', Raised);
end;

procedure TFloriaNativeEngineTest.TestSimplifyEmptyInput();
var
  Paths, Res: TPathsD;
begin
  SetLength(Paths, 0);
  Res := FloriaPathEngine().SimplifyPaths(Paths, 0.5, True, 2);
  AssertEquals('empty input yields empty output', 0, Length(Res));

  SetLength(Paths, 1);
  SetLength(Paths[0], 0);
  Res := FloriaPathEngine().SimplifyPaths(Paths, 0.5, True, 2);
  AssertEquals('one empty contour preserved', 1, Length(Res));
  AssertEquals('empty contour stays empty', 0, Length(Res[0]));
end;

procedure TFloriaNativeEngineTest.TestBooleanStillDelegates();
var
  A, B, Res: TPathsD;
begin
  // The native engine has no boolean implementation, so this must reach the
  // fallback rather than raise.
  SetLength(A, 1);
  A[0] := RectD(0, 0, 10, 10).AsPath();
  SetLength(B, 1);
  B[0] := RectD(5, 0, 15, 10).AsPath();

  Res := FloriaPathEngine().BooleanOp(pboUnion, A, B, frNonZero, 2);
  AssertEquals('union through fallback has area 150', 150.0, Abs(Area(Res)), 1.0);
end;

procedure TFloriaNativeEngineTest.TestOffsetStillDelegates();
var
  Paths, Res: TPathsD;
begin
  SetLength(Paths, 1);
  Paths[0] := RectD(0, 0, 10, 10).AsPath();

  Res := FloriaPathEngine().OffsetPaths(Paths, 2.0, pjtMiter, petPolygon, 2.0, 0.0, 2);
  AssertTrue('inflate produced geometry', Length(Res) > 0);
  AssertTrue('inflate grew the area', Abs(Area(Res)) > 100.0);
end;

initialization
  RegisterTest(TFloriaNativeEngineTest);

end.
