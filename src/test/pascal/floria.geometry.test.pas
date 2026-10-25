unit Floria.Geometry.Test;

// Floria.Geometry.Test
// ====================
// Covers the first-party geometry value types: point/rect construction,
// rect predicates, bounds, area, and point-in-polygon under each fill rule.
//
// These tests intentionally pin the semantics that the display list, GPU
// pipeline, and path facade already rely on, so a future geometry change
// cannot silently alter them.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fpcunit, testregistry,
  Floria.Geometry;

type
  TFloriaGeometryTest = class(TTestCase)
  published
    procedure TestPointAndRectConstruction();
    procedure TestRectPredicates();
    procedure TestRectAsPath();
    procedure TestBoundsOfEmptyAndMultiplePaths();
    procedure TestAreaSignAndHoles();
    procedure TestPointInPolygonFillRules();
    procedure TestPointOnBoundary();
  end;

implementation

const
  EPS = 1e-9;

procedure TFloriaGeometryTest.TestPointAndRectConstruction();
var
  P: TPointD;
  R: TRectD;
begin
  P := PointD(3.5, -2.0);
  AssertEquals('Point X', 3.5, P.X, EPS);
  AssertEquals('Point Y', -2.0, P.Y, EPS);

  P := TPointD.Create(1.0, 2.0);
  AssertEquals('Create Point X', 1.0, P.X, EPS);
  AssertEquals('Create Point Y', 2.0, P.Y, EPS);

  R := RectD(10.0, 20.0, 40.0, 60.0);
  AssertEquals('Rect Left', 10.0, R.Left, EPS);
  AssertEquals('Rect Top', 20.0, R.Top, EPS);
  AssertEquals('Rect Right', 40.0, R.Right, EPS);
  AssertEquals('Rect Bottom', 60.0, R.Bottom, EPS);

  R := TRectD.Create(0.0, 1.0, 2.0, 3.0);
  AssertEquals('Create Rect Left', 0.0, R.Left, EPS);
  AssertEquals('Create Rect Bottom', 3.0, R.Bottom, EPS);
end;

procedure TFloriaGeometryTest.TestRectPredicates();
var
  R, Inner, Overlap, Disjoint: TRectD;
begin
  R := RectD(0.0, 0.0, 100.0, 50.0);

  AssertEquals('Width', 100.0, R.Width, EPS);
  AssertEquals('Height', 50.0, R.Height, EPS);
  AssertFalse('Non-empty rect', R.IsEmpty);
  AssertTrue('Valid rect', R.IsValid);

  AssertTrue('Contains interior point', R.Contains(PointD(10.0, 10.0)));
  AssertFalse('Excludes boundary point', R.Contains(PointD(0.0, 10.0)));
  AssertFalse('Excludes outside point', R.Contains(PointD(200.0, 10.0)));

  Inner := RectD(10.0, 10.0, 20.0, 20.0);
  AssertTrue('Contains inner rect', R.Contains(Inner));

  Overlap := RectD(90.0, 40.0, 200.0, 200.0);
  AssertTrue('Intersects overlapping rect', R.Intersects(Overlap));

  Disjoint := RectD(200.0, 200.0, 300.0, 300.0);
  AssertFalse('Does not intersect disjoint rect', R.Intersects(Disjoint));

  AssertTrue('Null rect is empty', NullRectD.IsEmpty);
  AssertFalse('Invalid rect is invalid', InvalidRectD.IsValid);
end;

procedure TFloriaGeometryTest.TestRectAsPath();
var
  P: TPathD;
begin
  P := RectD(1.0, 2.0, 3.0, 4.0).AsPath();
  AssertEquals('AsPath point count', 4, Length(P));
  AssertEquals('AsPath [0].X', 1.0, P[0].X, EPS);
  AssertEquals('AsPath [1].X', 3.0, P[1].X, EPS);
  AssertEquals('AsPath [2].Y', 4.0, P[2].Y, EPS);
  AssertEquals('AsPath [3].Y', 4.0, P[3].Y, EPS);
end;

procedure TFloriaGeometryTest.TestBoundsOfEmptyAndMultiplePaths();
var
  Paths: TPathsD;
  B: TRectD;
begin
  SetLength(Paths, 0);
  B := GetBounds(Paths);
  AssertTrue('Empty bounds is null rect', B.IsEmpty);

  SetLength(Paths, 2);
  SetLength(Paths[0], 3);
  Paths[0][0] := PointD(-5.0, 0.0);
  Paths[0][1] := PointD(10.0, 0.0);
  Paths[0][2] := PointD(10.0, 7.0);

  SetLength(Paths[1], 2);
  Paths[1][0] := PointD(0.0, -3.0);
  Paths[1][1] := PointD(2.0, 20.0);

  B := GetBounds(Paths);
  AssertEquals('Bounds Left', -5.0, B.Left, EPS);
  AssertEquals('Bounds Top', -3.0, B.Top, EPS);
  AssertEquals('Bounds Right', 10.0, B.Right, EPS);
  AssertEquals('Bounds Bottom', 20.0, B.Bottom, EPS);
end;

procedure TFloriaGeometryTest.TestAreaSignAndHoles();
var
  Square, Reversed, WithHole: TPathsD;
  Outer: TPathD;
  Hole: TPathD;
begin
  SetLength(Square, 1);
  Square[0] := RectD(0.0, 0.0, 10.0, 10.0).AsPath();
  AssertEquals('Square area magnitude', 100.0, Abs(Area(Square)), 1e-6);

  // Reversing the winding flips the sign but not the magnitude.
  SetLength(Reversed, 1);
  SetLength(Reversed[0], 4);
  Reversed[0][0] := Square[0][3];
  Reversed[0][1] := Square[0][2];
  Reversed[0][2] := Square[0][1];
  Reversed[0][3] := Square[0][0];
  AssertEquals('Reversed area magnitude', 100.0, Abs(Area(Reversed)), 1e-6);
  AssertEquals('Winding sign flips', -Sign(Area(Square)), Sign(Area(Reversed)), EPS);

  // A hole wound opposite to the outer contour subtracts area.
  Outer := RectD(0.0, 0.0, 10.0, 10.0).AsPath();
  Hole := RectD(3.0, 3.0, 7.0, 7.0).AsPath();
  if Sign(Area(Outer)) = Sign(Area(Hole)) then
  begin
    SetLength(Hole, 4);
    Hole[0] := PointD(3.0, 3.0);
    Hole[1] := PointD(3.0, 7.0);
    Hole[2] := PointD(7.0, 7.0);
    Hole[3] := PointD(7.0, 3.0);
  end;

  SetLength(WithHole, 2);
  WithHole[0] := Outer;
  WithHole[1] := Hole;
  AssertEquals('Area with hole', 84.0, Abs(Area(WithHole)), 1e-6);
end;

procedure TFloriaGeometryTest.TestPointInPolygonFillRules();
var
  Square: TPathD;
  DoubleWound: TPathD;
begin
  // A simple square is inside under every rule.
  Square := RectD(0.0, 0.0, 10.0, 10.0).AsPath();
  AssertTrue('Nonzero in square', PointInPolygon(PointD(5.0, 5.0), Square, frNonZero));
  AssertTrue('EvenOdd in square', PointInPolygon(PointD(5.0, 5.0), Square, frEvenOdd));
  AssertFalse('Outside square', PointInPolygon(PointD(50.0, 50.0), Square, frNonZero));

  // The same square traced twice in the same direction: winding 2, crossings 2.
  SetLength(DoubleWound, 8);
  DoubleWound[0] := PointD(0.0, 0.0);
  DoubleWound[1] := PointD(10.0, 0.0);
  DoubleWound[2] := PointD(10.0, 10.0);
  DoubleWound[3] := PointD(0.0, 10.0);
  DoubleWound[4] := PointD(0.0, 0.0);
  DoubleWound[5] := PointD(10.0, 0.0);
  DoubleWound[6] := PointD(10.0, 10.0);
  DoubleWound[7] := PointD(0.0, 10.0);

  AssertTrue('Nonzero keeps double-wound interior',
    PointInPolygon(PointD(5.0, 5.0), DoubleWound, frNonZero));
  AssertFalse('EvenOdd cancels double-wound interior',
    PointInPolygon(PointD(5.0, 5.0), DoubleWound, frEvenOdd));

  // Reversing the winding flips which signed rule accepts the interior.
  AssertTrue('Positive accepts forward winding',
    PointInPolygon(PointD(5.0, 5.0), Square, frPositive)
    xor PointInPolygon(PointD(5.0, 5.0), Square, frNegative));
end;

procedure TFloriaGeometryTest.TestPointOnBoundary();
var
  Square: TPathD;
begin
  Square := RectD(0.0, 0.0, 10.0, 10.0).AsPath();
  AssertTrue('Point on left edge', PointInPolygon(PointD(0.0, 5.0), Square, frNonZero));
  AssertTrue('Point on corner', PointInPolygon(PointD(0.0, 0.0), Square, frNonZero));
  AssertTrue('Point on right edge', PointInPolygon(PointD(10.0, 5.0), Square, frNonZero));
end;

initialization
  RegisterTest(TFloriaGeometryTest);

end.
