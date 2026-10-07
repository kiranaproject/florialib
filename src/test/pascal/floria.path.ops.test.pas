unit Floria.Path.Ops.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fpcunit, testregistry,
  agg_path_storage,
  Floria.Path.Clipper.Core,
  Floria.Path.Ops;

type
  TFloriaPathOpsTest = class(TTestCase)
  published
    procedure TestPathCreationAndBasics();
    procedure TestAddRect();
    procedure TestAddCircleAndEllipse();
    procedure TestPathUnion();
    procedure TestPathDifference();
    procedure TestPathIntersect();
    procedure TestPathXor();
    procedure TestDisjointUnion();
    procedure TestPathInflateSquare();
    procedure TestPathDeflate();
    procedure TestQuadAndCubicFlattening();
    procedure TestWindingRulesEvenOddVsNonZero();
    procedure TestAggPathStorageInterop();
    procedure TestAggPathDirectBooleans();
    procedure TestSVGInterop();
    procedure TestPathSimplify();
  end;

implementation

procedure TFloriaPathOpsTest.TestPathCreationAndBasics();
var
  Path, Cloned: TFloriaPath;
begin
  Path := TFloriaPath.Create();
  try
    AssertTrue('Initially empty', Path.IsEmpty);
    AssertEquals('Subpath count 0', 0, Path.SubpathCount);

    Path.MoveTo(10, 10);
    Path.LineTo(50, 10);
    Path.LineTo(50, 50);
    Path.Close();

    AssertFalse('Not empty after drawing', Path.IsEmpty);
    AssertEquals('Subpath count 1', 1, Path.SubpathCount);

    Cloned := Path.Clone();
    try
      AssertEquals('Cloned subpath count', 1, Cloned.SubpathCount);
      AssertEquals('Cloned total points', Path.TotalPointCount, Cloned.TotalPointCount);
    finally
      Cloned.Free();
    end;

    Path.Clear();
    AssertTrue('Empty after Clear', Path.IsEmpty);
  finally
    Path.Free();
  end;
end;

procedure TFloriaPathOpsTest.TestAddRect();
var
  Path: TFloriaPath;
  B: TRectD;
begin
  Path := TFloriaPath.Create();
  try
    Path.AddRect(10, 20, 100, 50);
    B := Path.GetBounds();

    AssertTrue('Left near 10', Abs(B.Left - 10.0) < 0.1);
    AssertTrue('Top near 20', Abs(B.Top - 20.0) < 0.1);
    AssertTrue('Right near 110', Abs(B.Right - 110.0) < 0.1);
    AssertTrue('Bottom near 70', Abs(B.Bottom - 70.0) < 0.1);

    AssertTrue('Area is 5000', Abs(Abs(Path.GetArea()) - 5000.0) < 1.0);
  finally
    Path.Free();
  end;
end;

procedure TFloriaPathOpsTest.TestAddCircleAndEllipse();
var
  Path: TFloriaPath;
  B: TRectD;
  ExpectedArea: Double;
begin
  Path := TFloriaPath.Create();
  try
    Path.AddCircle(50, 50, 20, 36);
    B := Path.GetBounds();

    AssertTrue('Circle bounds Left near 30', Abs(B.Left - 30.0) <= 0.5);
    AssertTrue('Circle bounds Right near 70', Abs(B.Right - 70.0) <= 0.5);
    AssertTrue('Circle bounds Top near 30', Abs(B.Top - 30.0) <= 0.5);
    AssertTrue('Circle bounds Bottom near 70', Abs(B.Bottom - 70.0) <= 0.5);

    // Area of circle with radius 20 is pi * 400 approx 1256.64
    ExpectedArea := Pi * 400.0;
    AssertTrue('Circle area close to pi*r^2', Abs(Abs(Path.GetArea()) - ExpectedArea) < 30.0);
  finally
    Path.Free();
  end;
end;

procedure TFloriaPathOpsTest.TestPathUnion();
var
  SquareA, SquareB, Res: TFloriaPath;
  B: TRectD;
begin
  SquareA := TFloriaPath.Create();
  SquareB := TFloriaPath.Create();
  try
    // Square A: [0, 0, 100, 100], area = 10000
    SquareA.AddRect(0, 0, 100, 100);
    // Square B: [50, 0, 100, 100], area = 10000, overlapping by [50..100, 0..100]
    SquareB.AddRect(50, 0, 100, 100);

    Res := PathUnion(SquareA, SquareB);
    try
      B := Res.GetBounds();
      AssertTrue('Union Left is 0', Abs(B.Left - 0.0) < 0.1);
      AssertTrue('Union Right is 150', Abs(B.Right - 150.0) < 0.1);
      AssertTrue('Union Top is 0', Abs(B.Top - 0.0) < 0.1);
      AssertTrue('Union Bottom is 100', Abs(B.Bottom - 100.0) < 0.1);

      // Expected combined area: 10000 + 10000 - 5000 = 15000
      AssertTrue('Union area is 15000', Abs(Abs(Res.GetArea()) - 15000.0) < 1.0);
    finally
      Res.Free();
    end;
  finally
    SquareA.Free();
    SquareB.Free();
  end;
end;

procedure TFloriaPathOpsTest.TestPathDifference();
var
  SquareA, SquareB, Res: TFloriaPath;
  B: TRectD;
begin
  SquareA := TFloriaPath.Create();
  SquareB := TFloriaPath.Create();
  try
    SquareA.AddRect(0, 0, 100, 100);
    SquareB.AddRect(50, 0, 100, 100);

    // A minus B: removes right half of Square A -> [0, 0, 50, 100]
    Res := PathDifference(SquareA, SquareB);
    try
      B := Res.GetBounds();
      AssertTrue('Diff Left is 0', Abs(B.Left - 0.0) < 0.1);
      AssertTrue('Diff Right is 50', Abs(B.Right - 50.0) < 0.1);
      AssertTrue('Diff Top is 0', Abs(B.Top - 0.0) < 0.1);
      AssertTrue('Diff Bottom is 100', Abs(B.Bottom - 100.0) < 0.1);

      AssertTrue('Diff area is 5000', Abs(Abs(Res.GetArea()) - 5000.0) < 1.0);
    finally
      Res.Free();
    end;
  finally
    SquareA.Free();
    SquareB.Free();
  end;
end;

procedure TFloriaPathOpsTest.TestPathIntersect();
var
  SquareA, SquareB, Res: TFloriaPath;
  B: TRectD;
begin
  SquareA := TFloriaPath.Create();
  SquareB := TFloriaPath.Create();
  try
    SquareA.AddRect(0, 0, 100, 100);
    SquareB.AddRect(50, 0, 100, 100);

    // Intersect of [0..100] and [50..150] is [50..100]
    Res := PathIntersect(SquareA, SquareB);
    try
      B := Res.GetBounds();
      AssertTrue('Intersect Left is 50', Abs(B.Left - 50.0) < 0.1);
      AssertTrue('Intersect Right is 100', Abs(B.Right - 100.0) < 0.1);
      AssertTrue('Intersect Top is 0', Abs(B.Top - 0.0) < 0.1);
      AssertTrue('Intersect Bottom is 100', Abs(B.Bottom - 100.0) < 0.1);

      AssertTrue('Intersect area is 5000', Abs(Abs(Res.GetArea()) - 5000.0) < 1.0);
    finally
      Res.Free();
    end;
  finally
    SquareA.Free();
    SquareB.Free();
  end;
end;

procedure TFloriaPathOpsTest.TestPathXor();
var
  SquareA, SquareB, Res: TFloriaPath;
begin
  SquareA := TFloriaPath.Create();
  SquareB := TFloriaPath.Create();
  try
    SquareA.AddRect(0, 0, 100, 100);
    SquareB.AddRect(50, 0, 100, 100);

    // XOR removes intersection [50..100], leaving [0..50] and [100..150]
    Res := PathXor(SquareA, SquareB);
    try
      AssertEquals('XOR produces 2 disjoint polygons', 2, Res.SubpathCount);
      AssertTrue('XOR area is 10000', Abs(Abs(Res.GetArea()) - 10000.0) < 2.0);
    finally
      Res.Free();
    end;
  finally
    SquareA.Free();
    SquareB.Free();
  end;
end;

procedure TFloriaPathOpsTest.TestDisjointUnion();
var
  SquareA, SquareB, Res: TFloriaPath;
begin
  SquareA := TFloriaPath.Create();
  SquareB := TFloriaPath.Create();
  try
    SquareA.AddRect(0, 0, 10, 10);
    SquareB.AddRect(100, 100, 10, 10);

    Res := PathUnion(SquareA, SquareB);
    try
      AssertEquals('Disjoint union keeps 2 subpaths', 2, Res.SubpathCount);
      AssertTrue('Disjoint total area is 200', Abs(Abs(Res.GetArea()) - 200.0) < 1.0);
    finally
      Res.Free();
    end;
  finally
    SquareA.Free();
    SquareB.Free();
  end;
end;

procedure TFloriaPathOpsTest.TestPathInflateSquare();
var
  Path, Inflated: TFloriaPath;
  B: TRectD;
begin
  Path := TFloriaPath.Create();
  try
    // 10x10 square at (10, 10)
    Path.AddRect(10, 10, 10, 10);

    // Inflate by +5 with square corners
    Inflated := PathInflate(Path, 5.0, fpjtSquare, fpetPolygon);
    try
      B := Inflated.GetBounds();
      AssertTrue('Inflated Left is 5, but was ' + FloatToStr(B.Left), Abs(B.Left - 5.0) < 0.5);
      AssertTrue('Inflated Top is 5', Abs(B.Top - 5.0) < 0.5);
      AssertTrue('Inflated Right is 25', Abs(B.Right - 25.0) < 0.5);
      AssertTrue('Inflated Bottom is 25', Abs(B.Bottom - 25.0) < 0.5);
      // Size becomes 20x20 = 400 area
      AssertTrue('Inflated area is approx 400', Abs(Abs(Inflated.GetArea()) - 400.0) < 50.0);
    finally
      Inflated.Free();
    end;
  finally
    Path.Free();
  end;
end;

procedure TFloriaPathOpsTest.TestPathDeflate();
var
  Path, Deflated: TFloriaPath;
  B: TRectD;
begin
  Path := TFloriaPath.Create();
  try
    // 100x100 square at (0, 0)
    Path.AddRect(0, 0, 100, 100);

    // Deflate by -10 with square corners
    Deflated := PathInflate(Path, -10.0, fpjtSquare, fpetPolygon);
    try
      B := Deflated.GetBounds();
      AssertTrue('Deflated Left is 10', Abs(B.Left - 10.0) < 0.5);
      AssertTrue('Deflated Top is 10', Abs(B.Top - 10.0) < 0.5);
      AssertTrue('Deflated Right is 90', Abs(B.Right - 90.0) < 0.5);
      AssertTrue('Deflated Bottom is 90', Abs(B.Bottom - 90.0) < 0.5);
      // 80x80 = 6400 area
      AssertTrue('Deflated area is 6400', Abs(Abs(Deflated.GetArea()) - 6400.0) < 5.0);
    finally
      Deflated.Free();
    end;
  finally
    Path.Free();
  end;
end;

procedure TFloriaPathOpsTest.TestQuadAndCubicFlattening();
var
  Path: TFloriaPath;
  B: TRectD;
begin
  Path := TFloriaPath.Create();
  try
    Path.MoveTo(0, 0);
    Path.CubicTo(0, 50, 50, 100, 100, 100);
    Path.Close();

    // Verify curve generated more than just 2 endpoints
    AssertTrue('Cubic flattened into multiple segments', Path.TotalPointCount > 5);

    B := Path.GetBounds();
    AssertTrue('Curve Left is 0', Abs(B.Left - 0.0) < 0.1);
    AssertTrue('Curve Right is 100', Abs(B.Right - 100.0) < 0.1);
    AssertTrue('Curve Top is 0', Abs(B.Top - 0.0) < 0.1);
    AssertTrue('Curve Bottom is 100', Abs(B.Bottom - 100.0) < 0.1);
  finally
    Path.Free();
  end;
end;

procedure TFloriaPathOpsTest.TestWindingRulesEvenOddVsNonZero();
var
  DonutEO, DonutNZ: TFloriaPath;
  OuterSq, InnerSq: TFloriaPath;
  Merged: TFloriaPath;
begin
  // Two nested squares with same clockwise winding
  OuterSq := TFloriaPath.Create();
  InnerSq := TFloriaPath.Create();
  Merged := TFloriaPath.Create();
  try
    OuterSq.AddRect(0, 0, 100, 100); // 10000
    InnerSq.AddRect(25, 25, 50, 50); // 2500

    Merged.AddPath(OuterSq);
    Merged.AddPath(InnerSq);

    // Self-union with EvenOdd: inner square is counted twice (mod 2 = 0) -> carved out hole!
    DonutEO := Merged.Union(nil, fpfrEvenOdd);
    try
      AssertTrue('EvenOdd carves out inner hole: area 7500',
        Abs(Abs(DonutEO.GetArea()) - 7500.0) < 5.0);
    finally
      DonutEO.Free();
    end;

    // Self-union with NonZero: inner square winding count >= 1 -> remains filled!
    DonutNZ := Merged.Union(nil, fpfrNonZero);
    try
      AssertTrue('NonZero fills inner hole: area 10000',
        Abs(Abs(DonutNZ.GetArea()) - 10000.0) < 5.0);
    finally
      DonutNZ.Free();
    end;
  finally
    OuterSq.Free();
    InnerSq.Free();
    Merged.Free();
  end;
end;

procedure TFloriaPathOpsTest.TestAggPathStorageInterop();
var
  PathA, PathB: TFloriaPath;
  Storage: path_storage;
  B_Orig, B_Imported: TRectD;
begin
  PathA := TFloriaPath.Create();
  try
    PathA.AddRoundedRect(10, 10, 80, 60, 10, 10, 8);
    B_Orig := PathA.GetBounds();

    Storage := PathA.ToAggPath();
    try
      PathB := TFloriaPath.FromAggPath(Storage);
      try
        B_Imported := PathB.GetBounds();
        AssertTrue('Bounds Left match', Abs(B_Orig.Left - B_Imported.Left) < 0.1);
        AssertTrue('Bounds Right match', Abs(B_Orig.Right - B_Imported.Right) < 0.1);
        AssertTrue('Bounds Top match', Abs(B_Orig.Top - B_Imported.Top) < 0.1);
        AssertTrue('Bounds Bottom match', Abs(B_Orig.Bottom - B_Imported.Bottom) < 0.1);
        AssertTrue('Area match', Abs(PathA.GetArea() - PathB.GetArea()) < 5.0);
      finally
        PathB.Free();
      end;
    finally
      Storage.Destruct();
    end;
  finally
    PathA.Free();
  end;
end;

procedure TFloriaPathOpsTest.TestAggPathDirectBooleans();
var
  StorageA, StorageB, ResStorage: path_storage;
  Imported: TFloriaPath;
begin
  StorageA.Construct();
  StorageB.Construct();
  try
    // StorageA: Rect [0, 0, 100, 100]
    StorageA.move_to(0, 0);
    StorageA.line_to(100, 0);
    StorageA.line_to(100, 100);
    StorageA.line_to(0, 100);
    StorageA.close_polygon();

    // StorageB: Rect [50, 0, 100, 100]
    StorageB.move_to(50, 0);
    StorageB.line_to(150, 0);
    StorageB.line_to(150, 100);
    StorageB.line_to(50, 100);
    StorageB.close_polygon();

    ResStorage := PathUnion(StorageA, StorageB, fpfrNonZero);
    try
      Imported := TFloriaPath.FromAggPath(ResStorage);
      try
        AssertTrue('Direct Agg union area is 15000',
          Abs(Abs(Imported.GetArea()) - 15000.0) < 1.0);
      finally
        Imported.Free();
      end;
    finally
      ResStorage.Destruct();
    end;
  finally
    StorageA.Destruct();
    StorageB.Destruct();
  end;
end;

procedure TFloriaPathOpsTest.TestSVGInterop();
var
  Path: TFloriaPath;
  SvgStr: string;
begin
  Path := TFloriaPath.Create();
  try
    // Parse SVG string
    Path.FromSVGString('M 10 10 L 50 10 L 50 50 L 10 50 Z');
    AssertEquals('Subpath parsed', 1, Path.SubpathCount);
    AssertTrue('Area 1600 (40x40)', Abs(Abs(Path.GetArea()) - 1600.0) < 1.0);

    SvgStr := Path.ToSVGString();
    AssertTrue('SVG string starts with M', Pos('M', SvgStr) = 1);
    AssertTrue('SVG string contains Z', Pos('Z', SvgStr) > 0);
  finally
    Path.Free();
  end;
end;

procedure TFloriaPathOpsTest.TestPathSimplify();
var
  Path, Simplified: TFloriaPath;
begin
  Path := TFloriaPath.Create();
  try
    // Rectangle with extra collinear points along top and bottom edges
    Path.MoveTo(0, 0);
    Path.LineTo(25, 0);
    Path.LineTo(50, 0);
    Path.LineTo(75, 0);
    Path.LineTo(100, 0);
    Path.LineTo(100, 50);
    Path.LineTo(50, 50);
    Path.LineTo(0, 50);
    Path.Close();

    AssertTrue('Path has collinear points', Path.TotalPointCount > 5);

    Simplified := Path.Simplify(0.5);
    try
      AssertTrue('Simplified reduces point count', Simplified.TotalPointCount < Path.TotalPointCount);
      AssertTrue('Simplified maintains area 5000', Abs(Abs(Simplified.GetArea()) - 5000.0) < 1.0);
    finally
      Simplified.Free();
    end;
  finally
    Path.Free();
  end;
end;

initialization
  RegisterTest(TFloriaPathOpsTest);

end.
