unit Floria.DisplayList.Spatial.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fpcunit, testregistry,
  Floria.Image.Core,
  Floria.Canvas.Agg,
  Floria.Path.Clipper.Core,
  Floria.DisplayList,
  Floria.DisplayList.Clip,
  Floria.DisplayList.Spatial;

type
  { TTestDisplayListSpatial }
  TTestDisplayListSpatial = class(TTestCase)
  published
    procedure TestClipCornerRadiiConstruction;
    procedure TestAnalyticalPointInRoundedRect;
    procedure TestAnalyticalRoundedRectSDF;
    procedure TestClipChainBasicOperations;
    procedure TestClipChainContainsAndTestRect;
    procedure TestClipChainGPUUniformPacking;
    procedure TestRTreeBasicInsertAndSearch;
    procedure TestRTreeSplittingAndHeightGrowth;
    procedure TestRTreeZOrderPreservation;
    procedure TestRTreeBuildFromPicture;
    procedure TestSpatialDisplayListLifecycleAndQuery;
    procedure TestSpatialDisplayListPlaybackViewport;
  end;

implementation

{ TTestDisplayListSpatial }

procedure TTestDisplayListSpatial.TestClipCornerRadiiConstruction;
var
  RUniform, RRounded, RZero, RCustom: TFloriaClipCornerRadii;
begin
  RUniform := TFloriaClipCornerRadii.Uniform(12.5);
  AssertTrue('Uniform radii should report IsUniform', RUniform.IsUniform());
  AssertTrue('Uniform radii should report HasRoundedCorners', RUniform.HasRoundedCorners());
  AssertEquals('TL_X', 12.5, RUniform.TopLeftX);
  AssertEquals('BR_Y', 12.5, RUniform.BottomRightY);

  RRounded := TFloriaClipCornerRadii.Rounded(8.0, 4.0);
  AssertFalse('Non-square radii is not uniform', RRounded.IsUniform());
  AssertTrue('Has rounded corners', RRounded.HasRoundedCorners());
  AssertEquals('TL_X', 8.0, RRounded.TopLeftX);
  AssertEquals('TL_Y', 4.0, RRounded.TopLeftY);

  RZero := TFloriaClipCornerRadii.Zero();
  AssertTrue('Zero radii is uniform', RZero.IsUniform());
  AssertFalse('Zero radii has no rounded corners', RZero.HasRoundedCorners());

  RCustom := ClipCornerRadii(1, 2, 3, 4, 5, 6, 7, 8);
  AssertEquals('Custom TL_X', 1.0, RCustom.TopLeftX);
  AssertEquals('Custom TL_Y', 2.0, RCustom.TopLeftY);
  AssertEquals('Custom TR_X', 3.0, RCustom.TopRightX);
  AssertEquals('Custom TR_Y', 4.0, RCustom.TopRightY);
  AssertEquals('Custom BR_X', 5.0, RCustom.BottomRightX);
  AssertEquals('Custom BR_Y', 6.0, RCustom.BottomRightY);
  AssertEquals('Custom BL_X', 7.0, RCustom.BottomLeftX);
  AssertEquals('Custom BL_Y', 8.0, RCustom.BottomLeftY);
end;

procedure TTestDisplayListSpatial.TestAnalyticalPointInRoundedRect;
var
  R: TRectD;
  Radii: TFloriaClipCornerRadii;
begin
  R := RectD(100.0, 100.0, 200.0, 200.0);
  Radii := TFloriaClipCornerRadii.Uniform(20.0);

  // Center point
  AssertTrue('Center should be inside', AnalyticalPointInRoundedRect(150.0, 150.0, R, Radii));

  // Far outside
  AssertFalse('Outside left should be false', AnalyticalPointInRoundedRect(50.0, 150.0, R, Radii));
  AssertFalse('Outside right should be false', AnalyticalPointInRoundedRect(250.0, 150.0, R, Radii));
  AssertFalse('Outside top should be false', AnalyticalPointInRoundedRect(150.0, 50.0, R, Radii));
  AssertFalse('Outside bottom should be false', AnalyticalPointInRoundedRect(150.0, 250.0, R, Radii));

  // Top-left corner quadrant: (100..120, 100..120)
  // Corner arc center is (120, 120) with radius 20.
  // The absolute tip (101, 101) distance to center is sqrt(19^2 + 19^2) = 26.87 > 20 -> Outside!
  AssertFalse('Corner tip outside arc should be false', AnalyticalPointInRoundedRect(101.0, 101.0, R, Radii));

  // Inside arc: point (110, 110) distance to center is sqrt(10^2 + 10^2) = 14.14 < 20 -> Inside!
  AssertTrue('Inside corner arc should be true', AnalyticalPointInRoundedRect(110.0, 110.0, R, Radii));

  // Corner with zero radii: tip (101, 101) must be inside
  AssertTrue('Zero radii corner tip is inside', AnalyticalPointInRoundedRect(101.0, 101.0, R, TFloriaClipCornerRadii.Zero()));
end;

procedure TTestDisplayListSpatial.TestAnalyticalRoundedRectSDF;
var
  R: TRectD;
  Radii: TFloriaClipCornerRadii;
  DistCenter, DistOutside: Double;
begin
  R := RectD(0.0, 0.0, 100.0, 100.0);
  Radii := TFloriaClipCornerRadii.Uniform(10.0);

  // Center is deeply inside -> negative distance
  DistCenter := AnalyticalRoundedRectSDF(50.0, 50.0, R, Radii);
  AssertTrue('Center distance must be negative', DistCenter < 0.0);

  // Point at (150, 50) is 50 units to the right -> positive distance ~ 50.0
  DistOutside := AnalyticalRoundedRectSDF(150.0, 50.0, R, Radii);
  AssertEquals('Outside right distance ~ 50.0', 50.0, Round(DistOutside * 10.0) / 10.0);
end;

procedure TTestDisplayListSpatial.TestClipChainBasicOperations;
var
  Chain: TFloriaClipChain;
  Bounds: TRectD;
begin
  Chain := TFloriaClipChain.Create();
  try
    AssertEquals('Initial count 0', 0, Chain.Count);
    AssertEquals('Initial current node -1', -1, Chain.CurrentNode);

    Chain.PushClipRect(RectD(0.0, 0.0, 200.0, 200.0));
    AssertEquals('Count after push 1', 1, Chain.Count);
    AssertEquals('Current node after push 0', 0, Chain.CurrentNode);

    Chain.PushClipRoundedRect(RectD(50.0, 50.0, 150.0, 150.0), 10.0);
    AssertEquals('Count after second push 2', 2, Chain.Count);
    AssertEquals('Current node after second push 1', 1, Chain.CurrentNode);

    Bounds := Chain.GetConservativeBounds();
    AssertEquals('Conservative bounds Left', 50.0, Bounds.Left);
    AssertEquals('Conservative bounds Top', 50.0, Bounds.Top);
    AssertEquals('Conservative bounds Right', 150.0, Bounds.Right);
    AssertEquals('Conservative bounds Bottom', 150.0, Bounds.Bottom);

    Chain.PopClip();
    AssertEquals('Current node after first pop 0', 0, Chain.CurrentNode);

    Chain.PopClip();
    AssertEquals('Current node after second pop -1', -1, Chain.CurrentNode);
  finally
    Chain.Free();
  end;
end;

procedure TTestDisplayListSpatial.TestClipChainContainsAndTestRect;
var
  Chain: TFloriaClipChain;
begin
  Chain := TFloriaClipChain.Create();
  try
    Chain.PushClipRect(RectD(10.0, 10.0, 100.0, 100.0));

    // Points
    AssertTrue('Point inside rect', Chain.ContainsPoint(50.0, 50.0));
    AssertFalse('Point outside rect', Chain.ContainsPoint(150.0, 50.0));

    // Conservative Rect tests
    AssertTrue('Inside rect should be ctrInside', Chain.TestRect(RectD(20.0, 20.0, 80.0, 80.0)) = ctrInside);
    AssertTrue('Disjoint rect should be ctrOutside', Chain.TestRect(RectD(150.0, 150.0, 200.0, 200.0)) = ctrOutside);
    AssertTrue('Straddling rect should be ctrIntersecting', Chain.TestRect(RectD(50.0, 50.0, 150.0, 150.0)) = ctrIntersecting);
  finally
    Chain.Free();
  end;
end;

procedure TTestDisplayListSpatial.TestClipChainGPUUniformPacking;
var
  Chain: TFloriaClipChain;
  Items: TFloriaGPUClipItemArray;
  PackedCount: Integer;
begin
  AssertEquals('GPU Clip Item struct size must be exactly 64 bytes for std140', 64, SizeOf(TFloriaGPUClipItem));

  Chain := TFloriaClipChain.Create();
  try
    Chain.PushClipRect(RectD(10.0, 20.0, 100.0, 200.0), False);
    Chain.PushClipRoundedRect(RectD(30.0, 40.0, 80.0, 90.0), 5.0, 6.0, True);

    PackedCount := Chain.PackGPUUniforms(Items);
    AssertEquals('Packed count 2', 2, PackedCount);
    AssertEquals('Array length 2', 2, Length(Items));

    // First item: Rect
    AssertEquals('Item 0 MinX', 10.0, Items[0].RectMinX);
    AssertEquals('Item 0 MinY', 20.0, Items[0].RectMinY);
    AssertEquals('Item 0 MaxX', 100.0, Items[0].RectMaxX);
    AssertEquals('Item 0 MaxY', 200.0, Items[0].RectMaxY);
    AssertEquals('Item 0 Kind (1.0 = Rect)', 1.0, Items[0].ClipKind);
    AssertEquals('Item 0 AntiAlias (0.0 = Non-AA)', 0.0, Items[0].AntiAlias);

    // Second item: Rounded Rect
    AssertEquals('Item 1 MinX', 30.0, Items[1].RectMinX);
    AssertEquals('Item 1 MinY', 40.0, Items[1].RectMinY);
    AssertEquals('Item 1 MaxX', 80.0, Items[1].RectMaxX);
    AssertEquals('Item 1 MaxY', 90.0, Items[1].RectMaxY);
    AssertEquals('Item 1 RadiiTL_X', 5.0, Items[1].RadiiTL_X);
    AssertEquals('Item 1 RadiiTL_Y', 6.0, Items[1].RadiiTL_Y);
    AssertEquals('Item 1 Kind (2.0 = RRect)', 2.0, Items[1].ClipKind);
    AssertEquals('Item 1 AntiAlias (1.0 = AA)', 1.0, Items[1].AntiAlias);
  finally
    Chain.Free();
  end;
end;

procedure TTestDisplayListSpatial.TestRTreeBasicInsertAndSearch;
var
  Tree: TFloriaRTree2D;
  Hits: TIntegerDynArray;
begin
  Tree := TFloriaRTree2D.Create();
  try
    Tree.Insert(RectD(0.0, 0.0, 50.0, 50.0), 100);
    Tree.Insert(RectD(100.0, 100.0, 150.0, 150.0), 200);

    AssertEquals('Item count 2', 2, Tree.Count);

    // Search hitting first item only
    Hits := Tree.Search(RectD(10.0, 10.0, 40.0, 40.0));
    AssertEquals('Hit count for item 1', 1, Length(Hits));
    AssertEquals('Payload for item 1', 100, Hits[0]);

    // Search hitting second item only
    Hits := Tree.Search(RectD(120.0, 120.0, 140.0, 140.0));
    AssertEquals('Hit count for item 2', 1, Length(Hits));
    AssertEquals('Payload for item 2', 200, Hits[0]);

    // Search hitting both items
    Hits := Tree.Search(RectD(0.0, 0.0, 200.0, 200.0));
    AssertEquals('Hit count for both', 2, Length(Hits));
    AssertEquals('Hits[0]', 100, Hits[0]);
    AssertEquals('Hits[1]', 200, Hits[1]);

    // Search hitting empty region between items
    Hits := Tree.Search(RectD(60.0, 60.0, 90.0, 90.0));
    AssertEquals('Disjoint search returns 0 hits', 0, Length(Hits));
  finally
    Tree.Free();
  end;
end;

procedure TTestDisplayListSpatial.TestRTreeSplittingAndHeightGrowth;
var
  Tree: TFloriaRTree2D;
  I: Integer;
  Hits: TIntegerDynArray;
  TotalBox: TRectD;
begin
  Tree := TFloriaRTree2D.Create();
  try
    // Insert 24 non-overlapping items to force multiple node splits (RTREE_MAX_ENTRIES is 8)
    for I := 0 to 23 do
      Tree.Insert(RectD(I * 20.0, 0.0, I * 20.0 + 15.0, 20.0), I);

    AssertEquals('Count should be 24', 24, Tree.Count);
    AssertTrue('Tree height must grow after splits', Tree.Height >= 1);

    TotalBox := Tree.TotalBounds;
    AssertEquals('Total bounds Left', 0.0, TotalBox.Left);
    AssertEquals('Total bounds Right', 23 * 20.0 + 15.0, TotalBox.Right);

    // Query covering all items
    Hits := Tree.Search(RectD(-10.0, -10.0, 1000.0, 50.0));
    AssertEquals('Search covering all items returns 24 hits', 24, Length(Hits));

    // Verify all 24 indices are present
    for I := 0 to 23 do
      AssertEquals('Hits[' + IntToStr(I) + ']', I, Hits[I]);
  finally
    Tree.Free();
  end;
end;

procedure TTestDisplayListSpatial.TestRTreeZOrderPreservation;
var
  Tree: TFloriaRTree2D;
  Hits: TIntegerDynArray;
begin
  Tree := TFloriaRTree2D.Create();
  try
    // Insert items in reverse z-order with overlapping bounds
    Tree.Insert(RectD(10.0, 10.0, 50.0, 50.0), 42);
    Tree.Insert(RectD(10.0, 10.0, 50.0, 50.0), 7);
    Tree.Insert(RectD(10.0, 10.0, 50.0, 50.0), 99);
    Tree.Insert(RectD(10.0, 10.0, 50.0, 50.0), 1);

    Hits := Tree.Search(RectD(15.0, 15.0, 45.0, 45.0));
    AssertEquals('Hit count 4', 4, Length(Hits));

    // Must be sorted strictly in ascending z-order
    AssertEquals('Z-order 0', 1, Hits[0]);
    AssertEquals('Z-order 1', 7, Hits[1]);
    AssertEquals('Z-order 2', 42, Hits[2]);
    AssertEquals('Z-order 3', 99, Hits[3]);
  finally
    Tree.Free();
  end;
end;

procedure TTestDisplayListSpatial.TestRTreeBuildFromPicture;
var
  Recorder: TFloriaPictureRecorder;
  Pic: TFloriaPicture;
  Tree: TFloriaRTree2D;
  Hits: TIntegerDynArray;
begin
  Recorder := TFloriaPictureRecorder.Create();
  try
    Recorder.BeginRecording(RectD(0.0, 0.0, 400.0, 400.0));
    // Op 0: Rect at (10, 10, 50, 50)
    Recorder.DrawRect(RectD(10.0, 10.0, 50.0, 50.0), BgraPixel(255, 0, 0, 255), BgraPixel(0, 0, 0, 255), 1.0);
    // Op 1: Rect at (100, 100, 150, 150)
    Recorder.DrawRect(RectD(100.0, 100.0, 150.0, 150.0), BgraPixel(0, 255, 0, 255), BgraPixel(0, 0, 0, 255), 1.0);
    // Op 2: Circle at (300, 300) with radius 20 -> bounds (279, 279, 321, 321)
    Recorder.DrawCircle(300.0, 300.0, 20.0, BgraPixel(0, 0, 255, 255), BgraPixel(0, 0, 0, 255), 1.0);
    Pic := Recorder.EndRecording();
  finally
    Recorder.Free();
  end;

  try
    Tree := TFloriaRTree2D.BuildFromPicture(Pic);
    try
      AssertEquals('Indexed 3 draw operations', 3, Tree.Count);

      // Search matching only first rect
      Hits := Tree.Search(RectD(0.0, 0.0, 60.0, 60.0));
      AssertEquals('Only Op 0 returned', 1, Length(Hits));
      AssertEquals('Op index is 0', 0, Hits[0]);

      // Search matching Op 1 and Op 2
      Hits := Tree.Search(RectD(90.0, 90.0, 350.0, 350.0));
      AssertEquals('Ops 1 and 2 returned', 2, Length(Hits));
      AssertEquals('Hits[0]', 1, Hits[0]);
      AssertEquals('Hits[1]', 2, Hits[1]);
    finally
      Tree.Free();
    end;
  finally
    Pic.Free();
  end;
end;

procedure TTestDisplayListSpatial.TestSpatialDisplayListLifecycleAndQuery;
var
  Recorder: TFloriaPictureRecorder;
  Pic: TFloriaPicture;
  SpatialList: TFloriaSpatialDisplayList;
  VisibleOps: TIntegerDynArray;
begin
  Recorder := TFloriaPictureRecorder.Create();
  try
    Recorder.BeginRecording(RectD(0.0, 0.0, 500.0, 500.0));
    Recorder.DrawRect(RectD(10.0, 10.0, 60.0, 60.0), BgraPixel(255, 0, 0, 255));
    Recorder.DrawRect(RectD(200.0, 200.0, 260.0, 260.0), BgraPixel(0, 255, 0, 255));
    Pic := Recorder.EndRecording();
  finally
    Recorder.Free();
  end;

  // Spatial list takes ownership of Pic
  SpatialList := TFloriaSpatialDisplayList.Create(Pic, True);
  try
    AssertTrue('Picture assigned', Assigned(SpatialList.Picture));
    AssertTrue('Index assigned', Assigned(SpatialList.Index));
    AssertEquals('Index count 2', 2, SpatialList.Index.Count);

    VisibleOps := SpatialList.QueryVisibleOps(RectD(0.0, 0.0, 100.0, 100.0));
    AssertEquals('Visible ops count 1', 1, Length(VisibleOps));
    AssertEquals('Visible op 0', 0, VisibleOps[0]);

    VisibleOps := SpatialList.QueryVisibleOps(RectD(150.0, 150.0, 300.0, 300.0));
    AssertEquals('Visible ops count 1', 1, Length(VisibleOps));
    AssertEquals('Visible op 1', 1, VisibleOps[0]);

    VisibleOps := SpatialList.QueryVisibleOps(RectD(400.0, 400.0, 500.0, 500.0));
    AssertEquals('Empty viewport has 0 visible ops', 0, Length(VisibleOps));
  finally
    SpatialList.Free();
  end;
end;

procedure TTestDisplayListSpatial.TestSpatialDisplayListPlaybackViewport;
var
  Recorder: TFloriaPictureRecorder;
  Pic: TFloriaPicture;
  SpatialList: TFloriaSpatialDisplayList;
  Canvas: TFloriaCanvasAgg;
  TargetImg: TFloriaImage;
begin
  Recorder := TFloriaPictureRecorder.Create();
  try
    Recorder.BeginRecording(RectD(0.0, 0.0, 100.0, 100.0));
    Recorder.Clear(BgraPixel(255, 255, 255, 255));
    Recorder.DrawRect(RectD(10.0, 10.0, 40.0, 40.0), BgraPixel(255, 0, 0, 255));
    Recorder.DrawRect(RectD(60.0, 60.0, 90.0, 90.0), BgraPixel(0, 0, 255, 255));
    Pic := Recorder.EndRecording();
  finally
    Recorder.Free();
  end;

  TargetImg := TFloriaImage.Create(100, 100);
  Canvas := TFloriaCanvasAgg.Create(TargetImg);
  SpatialList := TFloriaSpatialDisplayList.Create(Pic, True);
  try
    // Playback with viewport covering only the top-left region
    SpatialList.PlaybackViewport(Canvas, RectD(0.0, 0.0, 50.0, 50.0));

    // The rect at (10, 10, 40, 40) is drawn red
    AssertEquals('Pixel (20, 20) is red', 255, TargetImg.Pixels[20, 20].R);
  finally
    SpatialList.Free();
    Canvas.Free();
    TargetImg.Free();
  end;
end;

initialization
  RegisterTest(TTestDisplayListSpatial);

end.
