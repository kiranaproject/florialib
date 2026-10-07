unit Floria.DisplayList.Cache;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Math,
  Floria.Image.Core,
  Floria.Canvas.Agg,
  Floria.Path.Clipper.Core,
  Floria.DisplayList;

const
  DEFAULT_TILE_SIZE = 256;
  DEFAULT_MAX_CACHED_TILES = 128; // e.g. 128 * 256 * 256 * 4 bytes = 32 MB budget

type
  // ---------------------------------------------------------------------------
  // TFloriaTileCoord
  // ---------------------------------------------------------------------------
  TFloriaTileCoord = record
    Col: Integer;
    Row: Integer;

    class function Create(ACol, ARow: Integer): TFloriaTileCoord; static;
    function Equals(const Other: TFloriaTileCoord): Boolean;
  end;

  // ---------------------------------------------------------------------------
  // TFloriaPictureTile
  // ---------------------------------------------------------------------------
  // Represents a single rasterized tile in the retained grid.
  // ---------------------------------------------------------------------------
  TFloriaPictureTile = class
  private
    FCoord          : TFloriaTileCoord;
    FWorldRect      : TRectD;
    FSurface        : TFloriaImage;
    FDirty          : Boolean;
    FLastAccessEpoch: Int64;
    FScaleFactor    : Double;
  public
    constructor Create(const ACoord: TFloriaTileCoord; const AWorldRect: TRectD; AScaleFactor: Double = 1.0);
    destructor Destroy(); override;

    procedure EnsureSurface(AWidth, AHeight: Integer);
    procedure ClearSurface();
    procedure MarkDirty();
    procedure MarkClean();

    property Coord          : TFloriaTileCoord read FCoord;
    property WorldRect      : TRectD read FWorldRect;
    property Surface        : TFloriaImage read FSurface;
    property Dirty          : Boolean read FDirty write FDirty;
    property LastAccessEpoch: Int64 read FLastAccessEpoch write FLastAccessEpoch;
    property ScaleFactor    : Double read FScaleFactor write FScaleFactor;
  end;

  TFloriaPictureTileArray = array of TFloriaPictureTile;

  // ---------------------------------------------------------------------------
  // TFloriaTileCacheStats
  // ---------------------------------------------------------------------------
  TFloriaTileCacheStats = record
    TotalTilesAllocated: Integer;
    ActiveTiles        : Integer;
    RasterizedCount    : Integer;  // Number of tile rasterizations performed
    CacheHits          : Integer;  // Number of times cached tile was reused without rasterization
    EvictedCount       : Integer;  // Tiles evicted due to LRU budget
    MemoryBytes        : Int64;    // Memory occupied by allocated tile surfaces
  end;

  // ---------------------------------------------------------------------------
  // TFloriaTileCache
  // ---------------------------------------------------------------------------
  // Retained 2D picture tile cache. Divides display list space into a regular
  // grid of tiles, rasterizing only dirty and visible regions. Enables 120 FPS
  // scrolling and viewport panning with zero redundant CPU vector redraws.
  // ---------------------------------------------------------------------------
  TFloriaTileCache = class
  private
    FPicture           : TFloriaPicture;
    FOwnsPicture       : Boolean;
    FTileSize          : Integer;
    FScaleFactor       : Double;
    FMaxCachedTiles    : Integer;
    FCurrentEpoch      : Int64;
    FTiles             : TFloriaPictureTileArray;
    FTileCount         : Integer;
    FTileCapacity      : Integer;
    FStats             : TFloriaTileCacheStats;
    FBackgroundColor   : TBgraPixel;
    FHasBackgroundColor: Boolean;

    procedure EnsureTileCapacity(AAdditional: Integer = 1);
    function FindTile(const ACoord: TFloriaTileCoord): TFloriaPictureTile;
    function GetOrCreateTile(const ACoord: TFloriaTileCoord): TFloriaPictureTile;
    procedure RemoveTileAtIndex(AIndex: Integer);
    procedure EnforceBudget();
    function WorldRectForCoord(const ACoord: TFloriaTileCoord): TRectD;
    function CoordForPoint(X, Y: Double): TFloriaTileCoord;
    procedure RasterizeTile(ATile: TFloriaPictureTile);
    function CalculateMemoryBytes(): Int64;
  public
    constructor Create(APicture: TFloriaPicture = nil; AOwnsPicture: Boolean = False;
                       ATileSize: Integer = DEFAULT_TILE_SIZE; AScaleFactor: Double = 1.0);
    destructor Destroy(); override;

    procedure SetPicture(APicture: TFloriaPicture; AOwnsPicture: Boolean = False);
    procedure Clear();

    // Damage & Invalidation
    procedure InvalidateAll();
    procedure InvalidateRect(const ARect: TRectD);

    // Rasterization
    procedure PrepareViewport(const AViewport: TRectD);

    // Blitting & Rendering
    procedure RenderViewport(ACanvas: TFloriaCanvasAgg; const AViewport: TRectD;
                             const ADestPoint: TPointD); overload;
    procedure RenderViewport(ACanvas: TFloriaCanvasAgg; const AViewport: TRectD); overload;
    procedure RenderScroll(ACanvas: TFloriaCanvasAgg; const AViewport: TRectD;
                           ADestX, ADestY: Double);

    // Tile Inspection
    function GetIntersectingTiles(const AViewport: TRectD): TFloriaPictureTileArray;
    function GetTileAt(const ACoord: TFloriaTileCoord): TFloriaPictureTile;

    procedure ResetStats();

    property Picture           : TFloriaPicture read FPicture;
    property TileSize          : Integer read FTileSize;
    property ScaleFactor       : Double read FScaleFactor write FScaleFactor;
    property MaxCachedTiles    : Integer read FMaxCachedTiles write FMaxCachedTiles;
    property TileCount         : Integer read FTileCount;
    property Stats             : TFloriaTileCacheStats read FStats;
    property BackgroundColor   : TBgraPixel read FBackgroundColor write FBackgroundColor;
    property HasBackgroundColor: Boolean read FHasBackgroundColor write FHasBackgroundColor;
  end;

implementation

// -----------------------------------------------------------------------------
// TFloriaTileCoord Implementation
// -----------------------------------------------------------------------------
class function TFloriaTileCoord.Create(ACol, ARow: Integer): TFloriaTileCoord;
begin
  Result.Col := ACol;
  Result.Row := ARow;
end;

function TFloriaTileCoord.Equals(const Other: TFloriaTileCoord): Boolean;
begin
  Result := (Col = Other.Col) and (Row = Other.Row);
end;

// -----------------------------------------------------------------------------
// TFloriaPictureTile Implementation
// -----------------------------------------------------------------------------
constructor TFloriaPictureTile.Create(const ACoord: TFloriaTileCoord; const AWorldRect: TRectD; AScaleFactor: Double = 1.0);
begin
  inherited Create();
  FCoord           := ACoord;
  FWorldRect       := AWorldRect;
  FSurface         := nil;
  FDirty           := True;
  FLastAccessEpoch := 0;
  FScaleFactor     := AScaleFactor;
end;

destructor TFloriaPictureTile.Destroy();
begin
  ClearSurface();
  inherited Destroy();
end;

procedure TFloriaPictureTile.EnsureSurface(AWidth, AHeight: Integer);
begin
  if (AWidth <= 0) or (AHeight <= 0) then Exit;

  if Assigned(FSurface) then
  begin
    if (FSurface.Width <> AWidth) or (FSurface.Height <> AHeight) then
    begin
      FreeAndNil(FSurface);
      FSurface := TFloriaImage.Create(AWidth, AHeight);
    end;
  end
  else
    FSurface := TFloriaImage.Create(AWidth, AHeight);
end;

procedure TFloriaPictureTile.ClearSurface();
begin
  if Assigned(FSurface) then
    FreeAndNil(FSurface);
end;

procedure TFloriaPictureTile.MarkDirty();
begin
  FDirty := True;
end;

procedure TFloriaPictureTile.MarkClean();
begin
  FDirty := False;
end;

// -----------------------------------------------------------------------------
// TFloriaTileCache Implementation
// -----------------------------------------------------------------------------
constructor TFloriaTileCache.Create(APicture: TFloriaPicture = nil; AOwnsPicture: Boolean = False;
                                   ATileSize: Integer = DEFAULT_TILE_SIZE; AScaleFactor: Double = 1.0);
begin
  inherited Create();
  FPicture            := APicture;
  FOwnsPicture        := AOwnsPicture;
  if ATileSize <= 0 then
    FTileSize := DEFAULT_TILE_SIZE
  else
    FTileSize := ATileSize;
  if AScaleFactor <= 0.0 then
    FScaleFactor := 1.0
  else
    FScaleFactor := AScaleFactor;
  FMaxCachedTiles     := DEFAULT_MAX_CACHED_TILES;
  FCurrentEpoch       := 0;
  FTileCount          := 0;
  FTileCapacity       := 0;
  SetLength(FTiles, 0);
  FillChar(FStats, SizeOf(FStats), 0);
  FBackgroundColor    := BgraPixel(0, 0, 0, 0);
  FHasBackgroundColor := False;
end;

destructor TFloriaTileCache.Destroy();
begin
  Clear();
  if FOwnsPicture and Assigned(FPicture) then
    FreeAndNil(FPicture);
  inherited Destroy();
end;

procedure TFloriaTileCache.SetPicture(APicture: TFloriaPicture; AOwnsPicture: Boolean = False);
begin
  if FOwnsPicture and Assigned(FPicture) and (FPicture <> APicture) then
    FreeAndNil(FPicture);

  FPicture     := APicture;
  FOwnsPicture := AOwnsPicture;
  InvalidateAll();
end;

procedure TFloriaTileCache.Clear();
var
  I: Integer;
begin
  for I := 0 to FTileCount - 1 do
    if Assigned(FTiles[I]) then
      FreeAndNil(FTiles[I]);
  FTileCount    := 0;
  FTileCapacity := 0;
  SetLength(FTiles, 0);
  FStats.ActiveTiles := 0;
  FStats.MemoryBytes := 0;
end;

procedure TFloriaTileCache.EnsureTileCapacity(AAdditional: Integer = 1);
begin
  if FTileCount + AAdditional > FTileCapacity then
  begin
    if FTileCapacity = 0 then
      FTileCapacity := 16
    else
      FTileCapacity := FTileCapacity * 2;
    if FTileCapacity < FTileCount + AAdditional then
      FTileCapacity := FTileCount + AAdditional;
    SetLength(FTiles, FTileCapacity);
  end;
end;

function TFloriaTileCache.FindTile(const ACoord: TFloriaTileCoord): TFloriaPictureTile;
var
  I: Integer;
begin
  for I := 0 to FTileCount - 1 do
    if FTiles[I].Coord.Equals(ACoord) then
      Exit(FTiles[I]);
  Result := nil;
end;

function TFloriaTileCache.GetOrCreateTile(const ACoord: TFloriaTileCoord): TFloriaPictureTile;
begin
  Result := FindTile(ACoord);
  if not Assigned(Result) then
  begin
    Result := TFloriaPictureTile.Create(ACoord, WorldRectForCoord(ACoord), FScaleFactor);
    EnsureTileCapacity(1);
    FTiles[FTileCount] := Result;
    Inc(FTileCount);
    Inc(FStats.TotalTilesAllocated);
    FStats.ActiveTiles := FTileCount;
  end;
end;

procedure TFloriaTileCache.RemoveTileAtIndex(AIndex: Integer);
var
  I: Integer;
begin
  if (AIndex < 0) or (AIndex >= FTileCount) then Exit;
  if Assigned(FTiles[AIndex]) then
    FreeAndNil(FTiles[AIndex]);
  for I := AIndex to FTileCount - 2 do
    FTiles[I] := FTiles[I + 1];
  Dec(FTileCount);
  FStats.ActiveTiles := FTileCount;
  Inc(FStats.EvictedCount);
end;

procedure TFloriaTileCache.EnforceBudget();
var
  OldestIdx, I: Integer;
  OldestEpoch: Int64;
begin
  while FTileCount > FMaxCachedTiles do
  begin
    OldestIdx := -1;
    OldestEpoch := High(Int64);
    for I := 0 to FTileCount - 1 do
    begin
      // Only evict tiles not accessed in the current frame/epoch
      if (FTiles[I].LastAccessEpoch < FCurrentEpoch) and
         (FTiles[I].LastAccessEpoch < OldestEpoch) then
      begin
        OldestEpoch := FTiles[I].LastAccessEpoch;
        OldestIdx   := I;
      end;
    end;

    if OldestIdx >= 0 then
      RemoveTileAtIndex(OldestIdx)
    else
      Break; // Cannot evict active frame tiles without thrashing
  end;
  FStats.MemoryBytes := CalculateMemoryBytes();
end;

function TFloriaTileCache.WorldRectForCoord(const ACoord: TFloriaTileCoord): TRectD;
begin
  Result.Left   := ACoord.Col * FTileSize;
  Result.Top    := ACoord.Row * FTileSize;
  Result.Right  := (ACoord.Col + 1) * FTileSize;
  Result.Bottom := (ACoord.Row + 1) * FTileSize;
end;

function TFloriaTileCache.CoordForPoint(X, Y: Double): TFloriaTileCoord;
begin
  Result.Col := Floor(X / FTileSize);
  Result.Row := Floor(Y / FTileSize);
end;

function TFloriaTileCache.CalculateMemoryBytes(): Int64;
var
  I: Integer;
  Total: Int64;
begin
  Total := 0;
  for I := 0 to FTileCount - 1 do
    if Assigned(FTiles[I]) and Assigned(FTiles[I].Surface) then
      Total := Total + Int64(FTiles[I].Surface.Width) * Int64(FTiles[I].Surface.Height) * 4;
  Result := Total;
end;

procedure TFloriaTileCache.RasterizeTile(ATile: TFloriaPictureTile);
var
  PixelW, PixelH: Integer;
  TileCanvas: TFloriaCanvasAgg;
  TransMatrix: TFloriaMatrix2D;
  ClearCol: TBgraPixel;
begin
  if not Assigned(ATile) or not Assigned(FPicture) then Exit;

  PixelW := Round(FTileSize * FScaleFactor);
  PixelH := Round(FTileSize * FScaleFactor);
  if PixelW <= 0 then PixelW := 1;
  if PixelH <= 0 then PixelH := 1;

  ATile.EnsureSurface(PixelW, PixelH);

  if FHasBackgroundColor then
    ClearCol := FBackgroundColor
  else
    ClearCol := BgraPixel(0, 0, 0, 0);

  ATile.Surface.Clear(ClearCol.R, ClearCol.G, ClearCol.B, ClearCol.A);

  TileCanvas := TFloriaCanvasAgg.Create(ATile.Surface);
  try
    // World coordinates are shifted to tile local space: (-WorldRect.Left, -WorldRect.Top)
    // and scaled by FScaleFactor:
    if Abs(FScaleFactor - 1.0) < 1e-6 then
      TransMatrix := TFloriaMatrix2D.Translation(-ATile.WorldRect.Left, -ATile.WorldRect.Top)
    else
      TransMatrix := TFloriaMatrix2D.Scaling(FScaleFactor, FScaleFactor).Multiply(
                       TFloriaMatrix2D.Translation(-ATile.WorldRect.Left, -ATile.WorldRect.Top));

    // Playback picture clipped to local tile bounds
    FPicture.Playback(TileCanvas, RectD(0.0, 0.0, PixelW, PixelH), TransMatrix);
  finally
    TileCanvas.Free();
  end;

  ATile.MarkClean();
  Inc(FStats.RasterizedCount);
  FStats.MemoryBytes := CalculateMemoryBytes();
end;

procedure TFloriaTileCache.InvalidateAll();
var
  I: Integer;
begin
  for I := 0 to FTileCount - 1 do
    if Assigned(FTiles[I]) then
      FTiles[I].MarkDirty();
end;

procedure TFloriaTileCache.InvalidateRect(const ARect: TRectD);
var
  ColMin, ColMax, RowMin, RowMax: Integer;
  C, R: Integer;
  Tile: TFloriaPictureTile;
begin
  if ARect.IsEmpty then Exit;

  ColMin := Floor(ARect.Left / FTileSize);
  ColMax := Floor((ARect.Right - 1e-6) / FTileSize);
  RowMin := Floor(ARect.Top / FTileSize);
  RowMax := Floor((ARect.Bottom - 1e-6) / FTileSize);

  for C := ColMin to ColMax do
    for R := RowMin to RowMax do
    begin
      Tile := FindTile(TFloriaTileCoord.Create(C, R));
      if Assigned(Tile) then
        Tile.MarkDirty();
    end;
end;

function TFloriaTileCache.GetIntersectingTiles(const AViewport: TRectD): TFloriaPictureTileArray;
var
  ColMin, ColMax, RowMin, RowMax: Integer;
  C, R, Count: Integer;
begin
  if AViewport.IsEmpty then
  begin
    SetLength(Result, 0);
    Exit;
  end;

  ColMin := Floor(AViewport.Left / FTileSize);
  ColMax := Floor((AViewport.Right - 1e-6) / FTileSize);
  RowMin := Floor(AViewport.Top / FTileSize);
  RowMax := Floor((AViewport.Bottom - 1e-6) / FTileSize);

  SetLength(Result, (ColMax - ColMin + 1) * (RowMax - RowMin + 1));
  Count := 0;

  for C := ColMin to ColMax do
    for R := RowMin to RowMax do
    begin
      Result[Count] := GetOrCreateTile(TFloriaTileCoord.Create(C, R));
      Inc(Count);
    end;

  SetLength(Result, Count);
end;

function TFloriaTileCache.GetTileAt(const ACoord: TFloriaTileCoord): TFloriaPictureTile;
begin
  Result := FindTile(ACoord);
end;

procedure TFloriaTileCache.PrepareViewport(const AViewport: TRectD);
var
  VisibleTiles: TFloriaPictureTileArray;
  Tile: TFloriaPictureTile;
  I: Integer;
begin
  Inc(FCurrentEpoch);

  VisibleTiles := GetIntersectingTiles(AViewport);
  for I := 0 to High(VisibleTiles) do
  begin
    Tile := VisibleTiles[I];
    Tile.LastAccessEpoch := FCurrentEpoch;
    if Tile.Dirty or not Assigned(Tile.Surface) then
      RasterizeTile(Tile)
    else
      Inc(FStats.CacheHits);
  end;

  EnforceBudget();
end;

procedure TFloriaTileCache.RenderViewport(ACanvas: TFloriaCanvasAgg; const AViewport: TRectD;
                                         const ADestPoint: TPointD);
var
  VisibleTiles: TFloriaPictureTileArray;
  Tile: TFloriaPictureTile;
  I: Integer;
  OffsetX, OffsetY: Double;
  ClipX, ClipY, ClipW, ClipH: Integer;
begin
  if not Assigned(ACanvas) or not Assigned(FPicture) or AViewport.IsEmpty then Exit;

  PrepareViewport(AViewport);

  ClipX := Floor(ADestPoint.X);
  ClipY := Floor(ADestPoint.Y);
  ClipW := Ceil(AViewport.Right - AViewport.Left);
  ClipH := Ceil(AViewport.Bottom - AViewport.Top);

  ACanvas.PushClipRect(ClipX, ClipY, ClipW, ClipH);
  try
    VisibleTiles := GetIntersectingTiles(AViewport);
    for I := 0 to High(VisibleTiles) do
    begin
      Tile := VisibleTiles[I];
      if Assigned(Tile.Surface) then
      begin
        OffsetX := (Tile.WorldRect.Left - AViewport.Left) * FScaleFactor;
        OffsetY := (Tile.WorldRect.Top - AViewport.Top) * FScaleFactor;
        ACanvas.DrawImage(ADestPoint.X + OffsetX, ADestPoint.Y + OffsetY, Tile.Surface);
      end;
    end;
  finally
    ACanvas.PopClipRect();
  end;
end;

procedure TFloriaTileCache.RenderViewport(ACanvas: TFloriaCanvasAgg; const AViewport: TRectD);
begin
  RenderViewport(ACanvas, AViewport, PointD(AViewport.Left, AViewport.Top));
end;

procedure TFloriaTileCache.RenderScroll(ACanvas: TFloriaCanvasAgg; const AViewport: TRectD;
                                       ADestX, ADestY: Double);
begin
  RenderViewport(ACanvas, AViewport, PointD(ADestX, ADestY));
end;

procedure TFloriaTileCache.ResetStats();
begin
  FillChar(FStats, SizeOf(FStats), 0);
  FStats.ActiveTiles := FTileCount;
  FStats.MemoryBytes := CalculateMemoryBytes();
end;

end.
