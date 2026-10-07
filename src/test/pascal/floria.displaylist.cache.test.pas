unit Floria.DisplayList.Cache.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fpcunit, testregistry,
  Floria.Image.Core,
  Floria.Canvas.Agg,
  Floria.Path.Clipper.Core,
  Floria.DisplayList,
  Floria.DisplayList.Cache;

type
  { TTestDisplayListCache }
  TTestDisplayListCache = class(TTestCase)
  published
    procedure TestTileCoordBasics;
    procedure TestTileCreationAndSurfaceLifecycle;
    procedure TestTileCacheGridPartitioning;
    procedure TestTileCacheRasterizationAndHitCounting;
    procedure TestTileCacheSelectiveDamageInvalidation;
    procedure TestTileCacheScrollingRetention;
    procedure TestTileCacheLRUBudgetEviction;
    procedure TestTileCacheRenderViewportAndRenderScroll;
    procedure TestTileCacheHiDPIScaleFactor;
  end;

implementation

{ TTestDisplayListCache }

procedure TTestDisplayListCache.TestTileCoordBasics;
var
  C1, C2, C3: TFloriaTileCoord;
begin
  C1 := TFloriaTileCoord.Create(2, 3);
  AssertEquals('Col 2', 2, C1.Col);
  AssertEquals('Row 3', 3, C1.Row);

  C2 := TFloriaTileCoord.Create(2, 3);
  C3 := TFloriaTileCoord.Create(3, 2);

  AssertTrue('C1 equals C2', C1.Equals(C2));
  AssertFalse('C1 not equals C3', C1.Equals(C3));
end;

procedure TTestDisplayListCache.TestTileCreationAndSurfaceLifecycle;
var
  Tile: TFloriaPictureTile;
begin
  Tile := TFloriaPictureTile.Create(TFloriaTileCoord.Create(1, 2), RectD(256.0, 512.0, 512.0, 768.0));
  try
    AssertTrue('Newly created tile is dirty', Tile.Dirty);
    AssertNull('Initial surface is nil', Tile.Surface);
    AssertEquals('Scale factor 1.0', 1.0, Tile.ScaleFactor);

    Tile.EnsureSurface(256, 256);
    AssertNotNull('Surface allocated', Tile.Surface);
    AssertEquals('Surface width 256', 256, Tile.Surface.Width);
    AssertEquals('Surface height 256', 256, Tile.Surface.Height);

    Tile.MarkClean();
    AssertFalse('Tile marked clean', Tile.Dirty);

    Tile.MarkDirty();
    AssertTrue('Tile marked dirty', Tile.Dirty);

    Tile.ClearSurface();
    AssertNull('Surface cleared to nil', Tile.Surface);
  finally
    Tile.Free();
  end;
end;

procedure TTestDisplayListCache.TestTileCacheGridPartitioning;
var
  Cache: TFloriaTileCache;
  Tiles: TFloriaPictureTileArray;
begin
  Cache := TFloriaTileCache.Create(nil, False, 256, 1.0);
  try
    // Exact single tile: (0, 0, 256, 256)
    Tiles := Cache.GetIntersectingTiles(RectD(0.0, 0.0, 256.0, 256.0));
    AssertEquals('Exact tile bounds returns 1 tile', 1, Length(Tiles));
    AssertEquals('Col 0', 0, Tiles[0].Coord.Col);
    AssertEquals('Row 0', 0, Tiles[0].Coord.Row);

    // 4 tiles: (100, 100, 300, 300) spans Col 0..1, Row 0..1
    Tiles := Cache.GetIntersectingTiles(RectD(100.0, 100.0, 300.0, 300.0));
    AssertEquals('Straddling 4 tiles returns length 4', 4, Length(Tiles));

    // Negative coordinates: (-100, -100, 50, 50) spans Col -1..0, Row -1..0
    Tiles := Cache.GetIntersectingTiles(RectD(-100.0, -100.0, 50.0, 50.0));
    AssertEquals('Negative coordinate span returns 4 tiles', 4, Length(Tiles));

    // Empty rectangle
    Tiles := Cache.GetIntersectingTiles(RectD(100.0, 100.0, 100.0, 100.0));
    AssertEquals('Empty rect returns 0 tiles', 0, Length(Tiles));
  finally
    Cache.Free();
  end;
end;

procedure TTestDisplayListCache.TestTileCacheRasterizationAndHitCounting;
var
  Recorder: TFloriaPictureRecorder;
  Pic: TFloriaPicture;
  Cache: TFloriaTileCache;
  Tile0: TFloriaPictureTile;
begin
  Recorder := TFloriaPictureRecorder.Create();
  try
    Recorder.BeginRecording(RectD(0.0, 0.0, 512.0, 512.0));
    Recorder.Clear(BgraPixel(255, 255, 255, 255));
    // Red rect in tile (0, 0)
    Recorder.DrawRect(RectD(50.0, 50.0, 150.0, 150.0), BgraPixel(255, 0, 0, 255));
    // Blue rect in tile (1, 1)
    Recorder.DrawRect(RectD(300.0, 300.0, 400.0, 400.0), BgraPixel(0, 0, 255, 255));
    Pic := Recorder.EndRecording();
  finally
    Recorder.Free();
  end;

  Cache := TFloriaTileCache.Create(Pic, True, 256, 1.0);
  try
    // First prepare: viewport covering tile (0, 0) only
    Cache.PrepareViewport(RectD(0.0, 0.0, 256.0, 256.0));
    AssertEquals('First prepare rasterizes 1 tile', 1, Cache.Stats.RasterizedCount);
    AssertEquals('Cache hits 0 on first pass', 0, Cache.Stats.CacheHits);

    Tile0 := Cache.GetTileAt(TFloriaTileCoord.Create(0, 0));
    AssertNotNull('Tile (0, 0) exists', Tile0);
    AssertNotNull('Tile (0, 0) has surface', Tile0.Surface);
    AssertFalse('Tile (0, 0) is clean', Tile0.Dirty);

    // Pixel inside red rect at (100, 100) must be red
    AssertEquals('Pixel (100, 100) is red', 255, Tile0.Surface.Pixels[100, 100].R);
    AssertEquals('Pixel (100, 100) Green is 0', 0, Tile0.Surface.Pixels[100, 100].G);

    // Second prepare covering the same viewport
    Cache.PrepareViewport(RectD(0.0, 0.0, 256.0, 256.0));
    AssertEquals('Rasterized count unchanged', 1, Cache.Stats.RasterizedCount);
    AssertEquals('Cache hits incremented', 1, Cache.Stats.CacheHits);
  finally
    Cache.Free();
  end;
end;

procedure TTestDisplayListCache.TestTileCacheSelectiveDamageInvalidation;
var
  Recorder: TFloriaPictureRecorder;
  Pic: TFloriaPicture;
  Cache: TFloriaTileCache;
  Tile00, Tile11: TFloriaPictureTile;
begin
  Recorder := TFloriaPictureRecorder.Create();
  try
    Recorder.BeginRecording(RectD(0.0, 0.0, 512.0, 512.0));
    Recorder.Clear(BgraPixel(255, 255, 255, 255));
    Recorder.DrawRect(RectD(50.0, 50.0, 150.0, 150.0), BgraPixel(255, 0, 0, 255));
    Recorder.DrawRect(RectD(300.0, 300.0, 400.0, 400.0), BgraPixel(0, 0, 255, 255));
    Pic := Recorder.EndRecording();
  finally
    Recorder.Free();
  end;

  Cache := TFloriaTileCache.Create(Pic, True, 256, 1.0);
  try
    // Prepare entire 512x512 region -> 4 tiles rasterized
    Cache.PrepareViewport(RectD(0.0, 0.0, 512.0, 512.0));
    AssertEquals('Initial rasterized tiles 4', 4, Cache.Stats.RasterizedCount);

    Tile00 := Cache.GetTileAt(TFloriaTileCoord.Create(0, 0));
    Tile11 := Cache.GetTileAt(TFloriaTileCoord.Create(1, 1));
    AssertFalse('Tile (0, 0) initially clean', Tile00.Dirty);
    AssertFalse('Tile (1, 1) initially clean', Tile11.Dirty);

    // Invalidate rect strictly inside tile (0, 0): (10, 10, 50, 50)
    Cache.InvalidateRect(RectD(10.0, 10.0, 50.0, 50.0));
    AssertTrue('Tile (0, 0) marked dirty', Tile00.Dirty);
    AssertFalse('Tile (1, 1) remains clean', Tile11.Dirty);

    // Prepare viewport again
    Cache.PrepareViewport(RectD(0.0, 0.0, 512.0, 512.0));
    // Only tile (0, 0) was re-rasterized; other 3 tiles were cache hits!
    AssertEquals('Only 1 dirty tile re-rasterized (total 5)', 5, Cache.Stats.RasterizedCount);
    AssertEquals('Remaining 3 tiles were cache hits', 3, Cache.Stats.CacheHits);
  finally
    Cache.Free();
  end;
end;

procedure TTestDisplayListCache.TestTileCacheScrollingRetention;
var
  Recorder: TFloriaPictureRecorder;
  Pic: TFloriaPicture;
  Cache: TFloriaTileCache;
begin
  Recorder := TFloriaPictureRecorder.Create();
  try
    Recorder.BeginRecording(RectD(0.0, 0.0, 256.0, 1000.0));
    Recorder.Clear(BgraPixel(240, 240, 240, 255));
    Recorder.DrawRect(RectD(10.0, 10.0, 100.0, 100.0), BgraPixel(255, 0, 0, 255));
    Pic := Recorder.EndRecording();
  finally
    Recorder.Free();
  end;

  Cache := TFloriaTileCache.Create(Pic, True, 256, 1.0);
  try
    // Frame 1: Scroll offset 0, viewport height 256 -> Tile (0, 0)
    Cache.PrepareViewport(RectD(0.0, 0.0, 256.0, 256.0));
    AssertEquals('Frame 1 rasterized 1 tile', 1, Cache.Stats.RasterizedCount);

    // Frame 2: Scrolled by 60px down -> Viewport (0, 60, 256, 316)
    // Intersects Tile (0, 0) and newly visible Tile (0, 1)
    Cache.PrepareViewport(RectD(0.0, 60.0, 256.0, 316.0));
    AssertEquals('Tile (0, 0) reused from cache', 1, Cache.Stats.CacheHits);
    AssertEquals('Only new Tile (0, 1) rasterized (total 2)', 2, Cache.Stats.RasterizedCount);

    // Frame 3: Scrolled back to top -> Viewport (0, 0, 256, 256)
    // Tile (0, 0) is already cached! Zero new rasterizations!
    Cache.PrepareViewport(RectD(0.0, 0.0, 256.0, 256.0));
    AssertEquals('Tile (0, 0) reused again with 0 rasterization', 2, Cache.Stats.RasterizedCount);
    AssertEquals('Cache hits incremented', 2, Cache.Stats.CacheHits);
  finally
    Cache.Free();
  end;
end;

procedure TTestDisplayListCache.TestTileCacheLRUBudgetEviction;
var
  Recorder: TFloriaPictureRecorder;
  Pic: TFloriaPicture;
  Cache: TFloriaTileCache;
begin
  Recorder := TFloriaPictureRecorder.Create();
  try
    Recorder.BeginRecording(RectD(0.0, 0.0, 2000.0, 256.0));
    Recorder.Clear(BgraPixel(255, 255, 255, 255));
    Pic := Recorder.EndRecording();
  finally
    Recorder.Free();
  end;

  Cache := TFloriaTileCache.Create(Pic, True, 256, 1.0);
  try
    // Restrict cache budget to at most 2 tiles
    Cache.MaxCachedTiles := 2;

    // Epoch 1: Viewport at (0, 0, 256, 256) -> Tile (0, 0)
    Cache.PrepareViewport(RectD(0.0, 0.0, 256.0, 256.0));
    AssertEquals('Tile count 1', 1, Cache.TileCount);

    // Epoch 2: Viewport at (256, 0, 512, 256) -> Tile (1, 0)
    Cache.PrepareViewport(RectD(256.0, 0.0, 512.0, 256.0));
    AssertEquals('Tile count 2', 2, Cache.TileCount);

    // Epoch 3: Viewport at (512, 0, 768, 256) -> Tile (2, 0)
    // Budget exceeded (count would be 3 > 2), oldest Tile (0, 0) is evicted
    Cache.PrepareViewport(RectD(512.0, 0.0, 768.0, 256.0));
    AssertTrue('Tile count respects budget limit <= 2', Cache.TileCount <= 2);
    AssertTrue('At least 1 tile evicted', Cache.Stats.EvictedCount >= 1);
  finally
    Cache.Free();
  end;
end;

procedure TTestDisplayListCache.TestTileCacheRenderViewportAndRenderScroll;
var
  Recorder: TFloriaPictureRecorder;
  Pic: TFloriaPicture;
  Cache: TFloriaTileCache;
  TargetImg: TFloriaImage;
  Canvas: TFloriaCanvasAgg;
begin
  Recorder := TFloriaPictureRecorder.Create();
  try
    Recorder.BeginRecording(RectD(0.0, 0.0, 200.0, 200.0));
    Recorder.Clear(BgraPixel(255, 255, 255, 255));
    Recorder.DrawRect(RectD(20.0, 20.0, 60.0, 60.0), BgraPixel(255, 0, 0, 255));
    Pic := Recorder.EndRecording();
  finally
    Recorder.Free();
  end;

  TargetImg := TFloriaImage.Create(200, 200);
  Canvas := TFloriaCanvasAgg.Create(TargetImg);
  Cache := TFloriaTileCache.Create(Pic, True, 256, 1.0);
  try
    // Render viewport onto target canvas
    Cache.RenderViewport(Canvas, RectD(0.0, 0.0, 100.0, 100.0), PointD(0.0, 0.0));

    // Pixel at (30, 30) should be red
    AssertEquals('Pixel (30, 30) is red', 255, TargetImg.Pixels[30, 30].R);
    AssertEquals('Pixel (30, 30) Green is 0', 0, TargetImg.Pixels[30, 30].G);

    // Test RenderScroll convenience method
    TargetImg.Clear(0, 0, 0, 0);
    Cache.RenderScroll(Canvas, RectD(0.0, 0.0, 100.0, 100.0), 10.0, 10.0);
    // Offset by 10, so red rect is now at (40, 40)
    AssertEquals('Scrolled pixel (40, 40) is red', 255, TargetImg.Pixels[40, 40].R);
  finally
    Cache.Free();
    Canvas.Free();
    TargetImg.Free();
  end;
end;

procedure TTestDisplayListCache.TestTileCacheHiDPIScaleFactor;
var
  Recorder: TFloriaPictureRecorder;
  Pic: TFloriaPicture;
  Cache: TFloriaTileCache;
  Tile: TFloriaPictureTile;
begin
  Recorder := TFloriaPictureRecorder.Create();
  try
    Recorder.BeginRecording(RectD(0.0, 0.0, 200.0, 200.0));
    Recorder.Clear(BgraPixel(255, 255, 255, 255));
    Pic := Recorder.EndRecording();
  finally
    Recorder.Free();
  end;

  // HiDPI scale factor 2.0 with tile size 128
  Cache := TFloriaTileCache.Create(Pic, True, 128, 2.0);
  try
    Cache.PrepareViewport(RectD(0.0, 0.0, 128.0, 128.0));
    Tile := Cache.GetTileAt(TFloriaTileCoord.Create(0, 0));
    AssertNotNull('Tile allocated', Tile);
    AssertNotNull('Tile surface allocated', Tile.Surface);
    // Physical raster surface is 128 * 2.0 = 256 pixels
    AssertEquals('Physical surface width is 256', 256, Tile.Surface.Width);
    AssertEquals('Physical surface height is 256', 256, Tile.Surface.Height);
  finally
    Cache.Free();
  end;
end;

initialization
  RegisterTest(TTestDisplayListCache);

end.
