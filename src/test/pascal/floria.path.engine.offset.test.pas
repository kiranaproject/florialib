unit Floria.Path.Engine.Offset.Test;

// Floria.Path.Engine.Offset.Test
// ==============================
// Covers first-party polygon offsetting: inflate, deflate, every join type,
// every open-path cap, and collapse detection.
//
// Each case is also compared against the vendored backend while it remains
// available. Area is compared with a tolerance rather than for equality
// because arc tessellation step counts legitimately differ by a segment or two
// between implementations.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fpcunit, testregistry,
  Floria.Geometry,
  Floria.Errors,
  Floria.Path.Engine;

type
  TFloriaOffsetTest = class(TTestCase)
  private
    FSaved: TFloriaPathEngine;
    procedure CompareAreaWithClipper2(const AContext: string;
      const APaths: TPathsD; ADelta: Double;
      AJoin: TPathJoinType; AEnd: TPathEndType;
      ATolerance: Double);
  protected
    procedure SetUp(); override;
    procedure TearDown(); override;
  published
    procedure TestInflateSquareMiter();
    procedure TestInflateSquareBevel();
    procedure TestInflateSquareRound();
    procedure TestDeflateSquare();
    procedure TestDeflateBeyondInradiusCollapses();
    procedure TestZeroDeltaIsIdentity();
    procedure TestRoundJoinIsBetweenBevelAndMiter();
    procedure TestMiterLimitFallsBackToBevel();
    procedure TestOpenPathButtCap();
    procedure TestOpenPathSquareCap();
    procedure TestOpenPathRoundCap();
    procedure TestNegativeDeltaRejectedForNaN();
    procedure TestPrecisionOutOfRangeRaises();
    procedure TestEmptyInput();
    procedure TestBoundsGrowByDelta();
    procedure TestInputsNotModified();
  end;

implementation

function Square(AX1, AY1, AX2, AY2: Double): TPathsD;
begin
  SetLength(Result, 1);
  Result[0] := RectD(AX1, AY1, AX2, AY2).AsPath();
end;

function HorizontalLine(): TPathsD;
begin
  SetLength(Result, 1);
  SetLength(Result[0], 2);
  Result[0][0] := PointD(0, 0);
  Result[0][1] := PointD(100, 0);
end;

procedure TFloriaOffsetTest.SetUp();
begin
  FSaved := FloriaPathEngine();
end;

procedure TFloriaOffsetTest.TearDown();
begin
  if FSaved <> nil then
    SetFloriaPathEngine(FSaved, False);
end;

procedure TFloriaOffsetTest.CompareAreaWithClipper2(const AContext: string;
  const APaths: TPathsD; ADelta: Double;
  AJoin: TPathJoinType; AEnd: TPathEndType; ATolerance: Double);
var
  NativeRes, ClipperRes: TPathsD;
  NativeArea, ClipperArea: Double;
begin
  UseFloriaPathEngine('native');
  NativeRes := FloriaPathEngine().OffsetPaths(APaths, ADelta, AJoin, AEnd, 2.0, 0.0, 2);

  UseFloriaPathEngine('clipper2');
  ClipperRes := FloriaPathEngine().OffsetPaths(APaths, ADelta, AJoin, AEnd, 2.0, 0.0, 2);

  UseFloriaPathEngine('native');

  NativeArea := Abs(Area(NativeRes));
  ClipperArea := Abs(Area(ClipperRes));

  AssertTrue(AContext + ': area matches clipper2 (native=' +
    FormatFloat('0.##', NativeArea) + ' clipper=' +
    FormatFloat('0.##', ClipperArea) + ')',
    Abs(NativeArea - ClipperArea) <= ATolerance);
end;

procedure TFloriaOffsetTest.TestInflateSquareMiter();
var
  Paths, Res: TPathsD;
begin
  Paths := Square(0, 0, 100, 100);
  Res := FloriaPathEngine().OffsetPaths(Paths, 5.0, pjtMiter, petPolygon, 2.0, 0.0, 2);

  // A miter join keeps the sharp corner: 110x110.
  AssertEquals('miter inflate area', 12100.0, Abs(Area(Res)), 1.0);
  AssertEquals('miter inflate left', -5.0, GetBounds(Res).Left, 0.1);
  AssertEquals('miter inflate right', 105.0, GetBounds(Res).Right, 0.1);

  CompareAreaWithClipper2('miter inflate', Paths, 5.0, pjtMiter, petPolygon, 1.0);
end;

procedure TFloriaOffsetTest.TestInflateSquareBevel();
var
  Paths, Res: TPathsD;
begin
  Paths := Square(0, 0, 100, 100);
  Res := FloriaPathEngine().OffsetPaths(Paths, 5.0, pjtBevel, petPolygon, 2.0, 0.0, 2);

  // Bevel cuts each corner with a straight chord.
  AssertEquals('bevel inflate area', 12050.0, Abs(Area(Res)), 1.0);

  CompareAreaWithClipper2('bevel inflate', Paths, 5.0, pjtBevel, petPolygon, 1.0);
end;

procedure TFloriaOffsetTest.TestInflateSquareRound();
var
  Paths, Res: TPathsD;
begin
  Paths := Square(0, 0, 100, 100);
  Res := FloriaPathEngine().OffsetPaths(Paths, 5.0, pjtRound, petPolygon, 2.0, 0.0, 2);

  // Rounded corners approximate a quarter circle at each corner.
  AssertEquals('round inflate area', 12078.0, Abs(Area(Res)), 5.0);

  CompareAreaWithClipper2('round inflate', Paths, 5.0, pjtRound, petPolygon, 5.0);
end;

procedure TFloriaOffsetTest.TestDeflateSquare();
var
  Paths, Res: TPathsD;
begin
  Paths := Square(0, 0, 100, 100);
  Res := FloriaPathEngine().OffsetPaths(Paths, -10.0, pjtMiter, petPolygon, 2.0, 0.0, 2);

  AssertEquals('deflate area', 6400.0, Abs(Area(Res)), 1.0);
  AssertEquals('deflate left', 10.0, GetBounds(Res).Left, 0.1);
  AssertEquals('deflate right', 90.0, GetBounds(Res).Right, 0.1);

  CompareAreaWithClipper2('deflate', Paths, -10.0, pjtMiter, petPolygon, 1.0);
end;

procedure TFloriaOffsetTest.TestDeflateBeyondInradiusCollapses();
var
  Paths, Res: TPathsD;
begin
  Paths := Square(0, 0, 100, 100);

  // The inradius is 50; deflating by 60 must erase the contour rather than
  // leave a small inverted island behind.
  Res := FloriaPathEngine().OffsetPaths(Paths, -60.0, pjtMiter, petPolygon, 2.0, 0.0, 2);

  AssertEquals('over-deflate produces no contours', 0, Length(Res));
  AssertEquals('over-deflate has zero area', 0.0, Abs(Area(Res)), 1e-9);
end;

procedure TFloriaOffsetTest.TestZeroDeltaIsIdentity();
var
  Paths, Res: TPathsD;
begin
  Paths := Square(0, 0, 100, 100);
  Res := FloriaPathEngine().OffsetPaths(Paths, 0.0, pjtRound, petPolygon, 2.0, 0.0, 2);

  AssertEquals('zero delta keeps area', 10000.0, Abs(Area(Res)), 1e-6);
  AssertEquals('zero delta keeps contour count', 1, Length(Res));
end;

procedure TFloriaOffsetTest.TestRoundJoinIsBetweenBevelAndMiter();
var
  Paths, Bevel, Round, Miter: TPathsD;
begin
  Paths := Square(0, 0, 100, 100);

  Bevel := FloriaPathEngine().OffsetPaths(Paths, 5.0, pjtBevel, petPolygon, 2.0, 0.0, 2);
  Round := FloriaPathEngine().OffsetPaths(Paths, 5.0, pjtRound, petPolygon, 2.0, 0.0, 2);
  Miter := FloriaPathEngine().OffsetPaths(Paths, 5.0, pjtMiter, petPolygon, 2.0, 0.0, 2);

  // A round join fills the corner arc, so it sits between the two extremes.
  AssertTrue('bevel <= round', Abs(Area(Bevel)) <= Abs(Area(Round)) + 1e-6);
  AssertTrue('round <= miter', Abs(Area(Round)) <= Abs(Area(Miter)) + 1e-6);
end;

procedure TFloriaOffsetTest.TestMiterLimitFallsBackToBevel();
var
  Paths, Tight, Loose: TPathsD;
begin
  // A thin spike: the miter would be very long, so a small limit must clip it.
  SetLength(Paths, 1);
  SetLength(Paths[0], 3);
  Paths[0][0] := PointD(0, 0);
  Paths[0][1] := PointD(100, 0);
  Paths[0][2] := PointD(100, 1);

  Tight := FloriaPathEngine().OffsetPaths(Paths, 5.0, pjtMiter, petPolygon, 1.01, 0.0, 2);
  Loose := FloriaPathEngine().OffsetPaths(Paths, 5.0, pjtMiter, petPolygon, 100.0, 0.0, 2);

  AssertTrue('tight miter limit clips the spike',
    Abs(Area(Tight)) < Abs(Area(Loose)) + 1e-6);
end;

procedure TFloriaOffsetTest.TestOpenPathButtCap();
var
  Paths, Res: TPathsD;
begin
  Paths := HorizontalLine();
  Res := FloriaPathEngine().OffsetPaths(Paths, 5.0, pjtMiter, petButt, 2.0, 0.0, 2);

  // 100 long by 10 wide, no extension.
  AssertEquals('butt cap area', 1000.0, Abs(Area(Res)), 1.0);
  AssertEquals('butt cap left', 0.0, GetBounds(Res).Left, 0.1);
  AssertEquals('butt cap right', 100.0, GetBounds(Res).Right, 0.1);

  CompareAreaWithClipper2('butt stroke', Paths, 5.0, pjtMiter, petButt, 1.0);
end;

procedure TFloriaOffsetTest.TestOpenPathSquareCap();
var
  Paths, Res: TPathsD;
begin
  Paths := HorizontalLine();
  Res := FloriaPathEngine().OffsetPaths(Paths, 5.0, pjtMiter, petSquare, 2.0, 0.0, 2);

  // Each square cap adds delta to the length: 110 x 10.
  AssertEquals('square cap area', 1100.0, Abs(Area(Res)), 1.0);
  AssertEquals('square cap left', -5.0, GetBounds(Res).Left, 0.1);
  AssertEquals('square cap right', 105.0, GetBounds(Res).Right, 0.1);

  CompareAreaWithClipper2('square stroke', Paths, 5.0, pjtMiter, petSquare, 1.0);
end;

procedure TFloriaOffsetTest.TestOpenPathRoundCap();
var
  Paths, Res: TPathsD;
begin
  Paths := HorizontalLine();
  Res := FloriaPathEngine().OffsetPaths(Paths, 5.0, pjtRound, petRound, 2.0, 0.0, 2);

  // Two semicircles plus the rectangle: 1000 + pi*25.
  AssertEquals('round cap area', 1000.0 + Pi * 25.0, Abs(Area(Res)), 5.0);
  AssertEquals('round cap right', 105.0, GetBounds(Res).Right, 0.5);

  CompareAreaWithClipper2('round stroke', Paths, 5.0, pjtRound, petRound, 5.0);
end;

procedure TFloriaOffsetTest.TestNegativeDeltaRejectedForNaN();
var
  Paths: TPathsD;
  Raised: Boolean;
begin
  Paths := Square(0, 0, 100, 100);

  Raised := False;
  try
    FloriaPathEngine().OffsetPaths(Paths, NaN, pjtRound, petPolygon, 2.0, 0.0, 2);
  except
    on E: EPathEngineError do
      Raised := True;
  end;
  AssertTrue('NaN delta raises', Raised);

  Raised := False;
  try
    FloriaPathEngine().OffsetPaths(Paths, Infinity, pjtRound, petPolygon, 2.0, 0.0, 2);
  except
    on E: EPathEngineError do
      Raised := True;
  end;
  AssertTrue('infinite delta raises', Raised);
end;

procedure TFloriaOffsetTest.TestPrecisionOutOfRangeRaises();
var
  Paths: TPathsD;
  Raised: Boolean;
begin
  Paths := Square(0, 0, 10, 10);

  Raised := False;
  try
    FloriaPathEngine().OffsetPaths(Paths, 1.0, pjtRound, petPolygon, 2.0, 0.0, 9);
  except
    on E: EPathEngineError do
      Raised := True;
  end;
  AssertTrue('precision above 8 raises', Raised);
end;

procedure TFloriaOffsetTest.TestEmptyInput();
var
  Paths, Res: TPathsD;
begin
  SetLength(Paths, 0);
  Res := FloriaPathEngine().OffsetPaths(Paths, 5.0, pjtRound, petPolygon, 2.0, 0.0, 2);
  AssertEquals('empty input yields empty output', 0, Length(Res));

  // A degenerate contour cannot be offset.
  SetLength(Paths, 1);
  SetLength(Paths[0], 2);
  Paths[0][0] := PointD(0, 0);
  Paths[0][1] := PointD(10, 0);
  Res := FloriaPathEngine().OffsetPaths(Paths, 5.0, pjtRound, petPolygon, 2.0, 0.0, 2);
  AssertEquals('two-point closed contour is skipped', 0, Length(Res));
end;

procedure TFloriaOffsetTest.TestBoundsGrowByDelta();
var
  Paths, Res: TPathsD;
  B: TRectD;
begin
  Paths := Square(0, 0, 100, 100);
  Res := FloriaPathEngine().OffsetPaths(Paths, 10.0, pjtMiter, petPolygon, 2.0, 0.0, 2);

  B := GetBounds(Res);
  AssertEquals('bounds left grows by delta', -10.0, B.Left, 0.1);
  AssertEquals('bounds top grows by delta', -10.0, B.Top, 0.1);
  AssertEquals('bounds right grows by delta', 110.0, B.Right, 0.1);
  AssertEquals('bounds bottom grows by delta', 110.0, B.Bottom, 0.1);
end;

procedure TFloriaOffsetTest.TestInputsNotModified();
var
  Paths, Res: TPathsD;
  OriginalArea: Double;
begin
  Paths := Square(0, 0, 100, 100);
  OriginalArea := Area(Paths);

  Res := FloriaPathEngine().OffsetPaths(Paths, 5.0, pjtRound, petPolygon, 2.0, 0.0, 2);

  AssertEquals('input contour count unchanged', 1, Length(Paths));
  AssertEquals('input vertex count unchanged', 4, Length(Paths[0]));
  AssertEquals('input area unchanged', OriginalArea, Area(Paths), 1e-9);
end;

initialization
  RegisterTest(TFloriaOffsetTest);

end.
