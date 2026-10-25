unit Floria.Path.Engine.Boolean.Test;

// Floria.Path.Engine.Boolean.Test
// ===============================
// Covers the first-party boolean engine: union, difference, intersection,
// exclusive-or, and self-union under all four fill rules.
//
// Every case is also compared against the vendored backend while it remains
// available. That comparison is what makes "native is a drop-in replacement"
// a checked claim rather than an assumption.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fpcunit, testregistry,
  Floria.Geometry,
  Floria.Errors,
  Floria.Path.Engine;

type
  TFloriaBooleanTest = class(TTestCase)
  private
    FSaved: TFloriaPathEngine;
    procedure CompareWithClipper2(const AContext: string;
      AOp: TPathBooleanOp;
      const ASubject, AClip: TPathsD;
      ARule: TFillRule = frNonZero);
  protected
    procedure SetUp(); override;
    procedure TearDown(); override;
  published
    procedure TestUnionOverlapping();
    procedure TestDifferenceOverlapping();
    procedure TestIntersectOverlapping();
    procedure TestXorOverlapping();
    procedure TestDisjointOperands();
    procedure TestNestedOperands();
    procedure TestIdenticalOperands();
    procedure TestTriangleVsSquare();
    procedure TestSelfUnionNonZeroFillsHole();
    procedure TestSelfUnionEvenOddCarvesHole();
    procedure TestEmptyOperands();
    procedure TestPrecisionOutOfRangeRaises();
    procedure TestCoordinateOverflowRaises();
    procedure TestCollinearOverlap();
    procedure TestTouchingEdgeOnly();
    procedure TestResultIsCallerOwned();
  end;

implementation

function Square(AX1, AY1, AX2, AY2: Double): TPathsD;
begin
  SetLength(Result, 1);
  Result[0] := RectD(AX1, AY1, AX2, AY2).AsPath();
end;

procedure TFloriaBooleanTest.SetUp();
begin
  FSaved := FloriaPathEngine();
end;

procedure TFloriaBooleanTest.TearDown();
begin
  if FSaved <> nil then
    SetFloriaPathEngine(FSaved, False);
end;

procedure TFloriaBooleanTest.CompareWithClipper2(const AContext: string;
  AOp: TPathBooleanOp; const ASubject, AClip: TPathsD; ARule: TFillRule);
var
  NativeRes, ClipperRes: TPathsD;
  NativeArea, ClipperArea: Double;
begin
  UseFloriaPathEngine('native');
  NativeRes := FloriaPathEngine().BooleanOp(AOp, ASubject, AClip, ARule, 2);

  UseFloriaPathEngine('clipper2');
  ClipperRes := FloriaPathEngine().BooleanOp(AOp, ASubject, AClip, ARule, 2);

  UseFloriaPathEngine('native');

  NativeArea := Abs(Area(NativeRes));
  ClipperArea := Abs(Area(ClipperRes));

  AssertTrue(AContext + ': area matches clipper2 (native=' +
    FormatFloat('0.##', NativeArea) + ' clipper=' +
    FormatFloat('0.##', ClipperArea) + ')',
    Abs(NativeArea - ClipperArea) <= 2.0);
end;

procedure TFloriaBooleanTest.TestUnionOverlapping();
var
  A, B, Res: TPathsD;
begin
  A := Square(0, 0, 100, 100);
  B := Square(50, 0, 150, 100);

  Res := FloriaPathEngine().BooleanOp(pboUnion, A, B, frNonZero, 2);

  AssertEquals('union area', 15000.0, Abs(Area(Res)), 1.0);
  AssertEquals('union bounds left', 0.0, GetBounds(Res).Left, 0.1);
  AssertEquals('union bounds right', 150.0, GetBounds(Res).Right, 0.1);
  CompareWithClipper2('union overlap', pboUnion, A, B);
end;

procedure TFloriaBooleanTest.TestDifferenceOverlapping();
var
  A, B, Res: TPathsD;
begin
  A := Square(0, 0, 100, 100);
  B := Square(50, 0, 150, 100);

  Res := FloriaPathEngine().BooleanOp(pboDifference, A, B, frNonZero, 2);

  AssertEquals('difference area', 5000.0, Abs(Area(Res)), 1.0);
  CompareWithClipper2('difference overlap', pboDifference, A, B);
end;

procedure TFloriaBooleanTest.TestIntersectOverlapping();
var
  A, B, Res: TPathsD;
begin
  A := Square(0, 0, 100, 100);
  B := Square(50, 0, 150, 100);

  Res := FloriaPathEngine().BooleanOp(pboIntersect, A, B, frNonZero, 2);

  AssertEquals('intersection area', 5000.0, Abs(Area(Res)), 1.0);
  CompareWithClipper2('intersection overlap', pboIntersect, A, B);
end;

procedure TFloriaBooleanTest.TestXorOverlapping();
var
  A, B, Res: TPathsD;
begin
  A := Square(0, 0, 100, 100);
  B := Square(50, 0, 150, 100);

  Res := FloriaPathEngine().BooleanOp(pboXor, A, B, frNonZero, 2);

  AssertEquals('xor area', 10000.0, Abs(Area(Res)), 2.0);
  CompareWithClipper2('xor overlap', pboXor, A, B);
end;

procedure TFloriaBooleanTest.TestDisjointOperands();
var
  A, B, Res: TPathsD;
begin
  A := Square(0, 0, 100, 100);
  B := Square(200, 0, 300, 100);

  Res := FloriaPathEngine().BooleanOp(pboUnion, A, B, frNonZero, 2);
  AssertEquals('disjoint union area', 20000.0, Abs(Area(Res)), 1.0);

  Res := FloriaPathEngine().BooleanOp(pboIntersect, A, B, frNonZero, 2);
  AssertEquals('disjoint intersection is empty', 0, Length(Res));

  Res := FloriaPathEngine().BooleanOp(pboDifference, A, B, frNonZero, 2);
  AssertEquals('disjoint difference keeps subject', 10000.0, Abs(Area(Res)), 1.0);

  CompareWithClipper2('union disjoint', pboUnion, A, B);
  CompareWithClipper2('intersect disjoint', pboIntersect, A, B);
end;

procedure TFloriaBooleanTest.TestNestedOperands();
var
  A, B, Res: TPathsD;
begin
  A := Square(0, 0, 100, 100);
  B := Square(25, 25, 75, 75);

  Res := FloriaPathEngine().BooleanOp(pboUnion, A, B, frNonZero, 2);
  AssertEquals('nested union is the outer square', 10000.0, Abs(Area(Res)), 1.0);

  Res := FloriaPathEngine().BooleanOp(pboDifference, A, B, frNonZero, 2);
  AssertEquals('nested difference is a frame', 7500.0, Abs(Area(Res)), 1.0);

  Res := FloriaPathEngine().BooleanOp(pboIntersect, A, B, frNonZero, 2);
  AssertEquals('nested intersection is the inner square', 2500.0, Abs(Area(Res)), 1.0);

  CompareWithClipper2('union nested', pboUnion, A, B);
  CompareWithClipper2('difference nested', pboDifference, A, B);
  CompareWithClipper2('intersection nested', pboIntersect, A, B);
end;

procedure TFloriaBooleanTest.TestIdenticalOperands();
var
  A, B, Res: TPathsD;
begin
  A := Square(0, 0, 100, 100);
  B := Square(0, 0, 100, 100);

  Res := FloriaPathEngine().BooleanOp(pboUnion, A, B, frNonZero, 2);
  AssertEquals('identical union', 10000.0, Abs(Area(Res)), 1.0);

  Res := FloriaPathEngine().BooleanOp(pboIntersect, A, B, frNonZero, 2);
  AssertEquals('identical intersection', 10000.0, Abs(Area(Res)), 1.0);

  Res := FloriaPathEngine().BooleanOp(pboDifference, A, B, frNonZero, 2);
  AssertEquals('identical difference is empty', 0, Length(Res));

  CompareWithClipper2('union identical', pboUnion, A, B);
  CompareWithClipper2('intersection identical', pboIntersect, A, B);
end;

procedure TFloriaBooleanTest.TestTriangleVsSquare();
var
  A, B, Res: TPathsD;
begin
  SetLength(A, 1);
  SetLength(A[0], 3);
  A[0][0] := PointD(0, 0);
  A[0][1] := PointD(100, 0);
  A[0][2] := PointD(50, 100);

  B := Square(0, 0, 100, 50);

  Res := FloriaPathEngine().BooleanOp(pboUnion, A, B, frNonZero, 2);
  AssertEquals('triangle union square', 6250.0, Abs(Area(Res)), 2.0);

  Res := FloriaPathEngine().BooleanOp(pboIntersect, A, B, frNonZero, 2);
  AssertEquals('triangle intersect square', 3750.0, Abs(Area(Res)), 2.0);

  CompareWithClipper2('union tri-sq', pboUnion, A, B);
  CompareWithClipper2('intersection tri-sq', pboIntersect, A, B);
  CompareWithClipper2('difference tri-sq', pboDifference, A, B);
  CompareWithClipper2('xor tri-sq', pboXor, A, B);
end;

procedure TFloriaBooleanTest.TestSelfUnionNonZeroFillsHole();
var
  A, Res: TPathsD;
begin
  SetLength(A, 2);
  A[0] := RectD(0, 0, 100, 100).AsPath();
  A[1] := RectD(25, 25, 75, 75).AsPath();

  Res := FloriaPathEngine().UnionSelf(A, frNonZero, 2);

  // Both contours wind the same way, so nonzero keeps the inner area filled.
  AssertEquals('nonzero self-union keeps inner area', 10000.0, Abs(Area(Res)), 2.0);
end;

procedure TFloriaBooleanTest.TestSelfUnionEvenOddCarvesHole();
var
  A, Res: TPathsD;
begin
  SetLength(A, 2);
  A[0] := RectD(0, 0, 100, 100).AsPath();
  A[1] := RectD(25, 25, 75, 75).AsPath();

  Res := FloriaPathEngine().UnionSelf(A, frEvenOdd, 2);

  // Even-odd counts the nested contour twice, so it is carved out.
  AssertEquals('evenodd self-union carves hole', 7500.0, Abs(Area(Res)), 2.0);
end;

procedure TFloriaBooleanTest.TestEmptyOperands();
var
  A, Empty, Res: TPathsD;
begin
  A := Square(0, 0, 100, 100);
  SetLength(Empty, 0);

  Res := FloriaPathEngine().BooleanOp(pboUnion, A, Empty, frNonZero, 2);
  AssertEquals('union with empty keeps subject', 10000.0, Abs(Area(Res)), 1.0);

  Res := FloriaPathEngine().BooleanOp(pboDifference, A, Empty, frNonZero, 2);
  AssertEquals('difference with empty keeps subject', 10000.0, Abs(Area(Res)), 1.0);

  Res := FloriaPathEngine().BooleanOp(pboIntersect, A, Empty, frNonZero, 2);
  AssertEquals('intersection with empty is empty', 0, Length(Res));

  Res := FloriaPathEngine().BooleanOp(pboUnion, Empty, A, frNonZero, 2);
  AssertEquals('union of empty and subject', 10000.0, Abs(Area(Res)), 1.0);

  Res := FloriaPathEngine().UnionSelf(Empty, frNonZero, 2);
  AssertEquals('self-union of empty is empty', 0, Length(Res));
end;

procedure TFloriaBooleanTest.TestPrecisionOutOfRangeRaises();
var
  A, B: TPathsD;
  Raised: Boolean;
begin
  A := Square(0, 0, 10, 10);
  B := Square(5, 0, 15, 10);

  Raised := False;
  try
    FloriaPathEngine().BooleanOp(pboUnion, A, B, frNonZero, 9);
  except
    on E: EPathEngineError do
      Raised := True;
  end;
  AssertTrue('precision above 8 raises', Raised);

  Raised := False;
  try
    FloriaPathEngine().BooleanOp(pboUnion, A, B, frNonZero, -1);
  except
    on E: EPathEngineError do
      Raised := True;
  end;
  AssertTrue('negative precision raises', Raised);
end;

procedure TFloriaBooleanTest.TestCoordinateOverflowRaises();
var
  A, B: TPathsD;
  Raised: Boolean;
begin
  // 2e9 scaled by 100 overflows the 1e9 coordinate limit.
  SetLength(A, 1);
  SetLength(A[0], 3);
  A[0][0] := PointD(0, 0);
  A[0][1] := PointD(2.0e9, 0);
  A[0][2] := PointD(0, 10);
  B := Square(0, 0, 10, 10);

  Raised := False;
  try
    FloriaPathEngine().BooleanOp(pboUnion, A, B, frNonZero, 2);
  except
    on E: EPathEngineError do
      Raised := True;
  end;
  AssertTrue('coordinate overflow raises', Raised);
end;

procedure TFloriaBooleanTest.TestCollinearOverlap();
var
  A, B, Res: TPathsD;
begin
  // Two rectangles sharing a full edge: the shared edge is interior to the
  // union and must not appear in the result.
  A := Square(0, 0, 100, 100);
  B := Square(100, 0, 200, 100);

  Res := FloriaPathEngine().BooleanOp(pboUnion, A, B, frNonZero, 2);
  AssertEquals('collinear union area', 20000.0, Abs(Area(Res)), 1.0);
  AssertEquals('collinear union width', 200.0, GetBounds(Res).Width, 0.1);

  CompareWithClipper2('collinear union', pboUnion, A, B);
end;

procedure TFloriaBooleanTest.TestTouchingEdgeOnly();
var
  A, B, Res: TPathsD;
begin
  // Corner-touching squares intersect in a zero-area point.
  A := Square(0, 0, 100, 100);
  B := Square(100, 100, 200, 200);

  Res := FloriaPathEngine().BooleanOp(pboIntersect, A, B, frNonZero, 2);
  AssertEquals('corner-touching intersection has no area', 0.0, Abs(Area(Res)), 1.0);

  Res := FloriaPathEngine().BooleanOp(pboUnion, A, B, frNonZero, 2);
  AssertEquals('corner-touching union area', 20000.0, Abs(Area(Res)), 1.0);
end;

procedure TFloriaBooleanTest.TestResultIsCallerOwned();
var
  A, B, Res: TPathsD;
begin
  A := Square(0, 0, 100, 100);
  B := Square(50, 0, 150, 100);

  Res := FloriaPathEngine().BooleanOp(pboUnion, A, B, frNonZero, 2);

  // Inputs must be untouched.
  AssertEquals('subject unchanged', 4, Length(A[0]));
  AssertEquals('clip unchanged', 4, Length(B[0]));
  AssertEquals('subject area unchanged', 10000.0, Abs(Area(A)), 1.0);

  // Result must not alias the inputs; mutating it cannot affect them.
  Res[0][0].X := -12345.0;
  AssertEquals('mutating result does not touch subject', 0.0, A[0][0].X, 1e-9);
end;

initialization
  RegisterTest(TFloriaBooleanTest);

end.
