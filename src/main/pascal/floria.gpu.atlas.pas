unit Floria.GPU.Atlas;

// Floria.GPU.Atlas
// ================
// Dynamic GPU Texture Atlas & Fallback Blob Rasterizer Engine.
//
// Features:
// - Skyline 2D bin packing algorithm in pure Object Pascal.
// - Multi-page dynamic texture atlas (default 2048x2048 per page).
// - CPU raster backing surfaces with minimal-rect GPU texture synchronization.
// - Fallback Blob Rasterizer: renders complex vector paths or SVGs using
//   Floria.Canvas.Agg into the atlas, returning cached GPU texture UV coordinates.
// - 1-pixel conservative padding to prevent bilinear texture bleed.

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Math,
  Floria.Image.Core,
  Floria.Font,
  Floria.Canvas.Agg,
  Floria.Path.Clipper.Core,
  Floria.Path.Ops,
  agg_path_storage,
  Floria.SVG.Types,
  Floria.SVG.DOM,
  Floria.GL;

const
  DEFAULT_ATLAS_PAGE_SIZE = 2048;
  DEFAULT_ATLAS_PADDING   = 1;

type
  // ---------------------------------------------------------------------------
  // TFloriaAtlasAlloc
  // ---------------------------------------------------------------------------
  // Represents an allocated sub-rectangle within a specific atlas page.
  // ---------------------------------------------------------------------------
  TFloriaAtlasAlloc = record
    PageIndex: Integer;
    Rect     : TRectD;  // Pixel coordinates in atlas (excluding padding)
    U1, V1   : Single;  // Normalized texture coordinates (0.0 .. 1.0)
    U2, V2   : Single;
    IsValid  : Boolean;

    class function Invalid(): TFloriaAtlasAlloc; static;
  end;

  // Skyline bin-packing node
  TFloriaSkylineNode = record
    X    : Integer;
    Y    : Integer;
    Width: Integer;
  end;
  TFloriaSkylineNodeArray = array of TFloriaSkylineNode;

  // ---------------------------------------------------------------------------
  // TFloriaAtlasPage
  // ---------------------------------------------------------------------------
  // A single 2D texture surface and its skyline spatial allocator.
  // ---------------------------------------------------------------------------
  TFloriaAtlasPage = class
  private
    FIndex       : Integer;
    FWidth       : Integer;
    FHeight      : Integer;
    FSurface     : TFloriaImage;
    FTextureID   : Cardinal;
    FSkyline     : TFloriaSkylineNodeArray;
    FSkylineCount: Integer;
    FDirty       : Boolean;
    FDirtyRect   : TRectD;

    function FitSkyline(NodeIdx, W, H: Integer; out BestY: Integer): Boolean;
    procedure AddSkylineLevel(NodeIdx, X, Y, W: Integer);
  public
    constructor Create(AIndex, AWidth, AHeight: Integer);
    destructor Destroy(); override;

    function Allocate(W, H: Integer; APadding: Integer; out AAllocRect: TRectD): Boolean;
    procedure MarkDirty(const ARect: TRectD);
    procedure SyncToGPU(gl: TGLEngine);

    property Index    : Integer read FIndex;
    property Width    : Integer read FWidth;
    property Height   : Integer read FHeight;
    property Surface  : TFloriaImage read FSurface;
    property TextureID: Cardinal read FTextureID;
    property Dirty    : Boolean read FDirty;
    property DirtyRect: TRectD read FDirtyRect;
  end;

  TFloriaTextCacheEntry = record
    Text: string;
    FontKey: string;
    Alloc: TFloriaAtlasAlloc;
  end;

  TFloriaAtlasPageArray = array of TFloriaAtlasPage;

  // ---------------------------------------------------------------------------
  // TFloriaGPUAtlas
  // ---------------------------------------------------------------------------
  TFloriaGPUAtlas = class
  private
    FPages         : TFloriaAtlasPageArray;
    FPageCount     : Integer;
    FPageSize      : Integer;
    FPadding       : Integer;
    FTextCache     : array of TFloriaTextCacheEntry;
    FTextCacheCount: Integer;

    function AddPage(APageWidth: Integer = 0; APageHeight: Integer = 0): TFloriaAtlasPage;
  public
    constructor Create(APageSize: Integer = DEFAULT_ATLAS_PAGE_SIZE; APadding: Integer = DEFAULT_ATLAS_PADDING);
    destructor Destroy(); override;

    procedure Clear();

    // Allocation
    function Allocate(W, H: Integer; out Alloc: TFloriaAtlasAlloc): Boolean;

    // Image Upload
    function AddImage(AImage: TFloriaImage; out Alloc: TFloriaAtlasAlloc): Boolean;
    function AddImagePart(AImage: TFloriaImage; const ASrcRect: TRectD; out Alloc: TFloriaAtlasAlloc): Boolean;

    // Fallback Blob Rasterizer: renders complex paths via AggPas into atlas
    function RasterizePath(APath: TFloriaPath; const AFillColor, AStrokeColor: TBgraPixel;
                           AStrokeWidth: Double; AFillRule: TFillRule;
                           out Alloc: TFloriaAtlasAlloc): Boolean;

    // High-performance Text/Glyph Rasterizer into Atlas with string reuse cache
    function RasterizeText(const AText: string; AFont: TFloriaFont;
                           out Alloc: TFloriaAtlasAlloc): Boolean; overload;
    function RasterizeText(const AText: string; AFont: TFloriaFont; const AColor: TBgraPixel;
                           out Alloc: TFloriaAtlasAlloc): Boolean; overload;

    // GPU Synchronization
    procedure SyncToGPU(gl: TGLEngine);

    property PageCount: Integer read FPageCount;
    property PageSize : Integer read FPageSize;
    property Padding  : Integer read FPadding;
    function GetPage(AIndex: Integer): TFloriaAtlasPage;
    property Pages[Index: Integer]: TFloriaAtlasPage read GetPage;
  end;

implementation

// -----------------------------------------------------------------------------
// TFloriaAtlasAlloc Implementation
// -----------------------------------------------------------------------------
class function TFloriaAtlasAlloc.Invalid(): TFloriaAtlasAlloc;
begin
  Result.PageIndex := -1;
  Result.Rect      := NullRectD;
  Result.U1        := 0.0;
  Result.V1        := 0.0;
  Result.U2        := 0.0;
  Result.V2        := 0.0;
  Result.IsValid   := False;
end;

// -----------------------------------------------------------------------------
// TFloriaAtlasPage Implementation
// -----------------------------------------------------------------------------
constructor TFloriaAtlasPage.Create(AIndex, AWidth, AHeight: Integer);
var
  gl: TGLEngine;
begin
  inherited Create();
  FIndex        := AIndex;
  FWidth        := AWidth;
  FHeight       := AHeight;
  FSurface      := TFloriaImage.Create(AWidth, AHeight);
  FSurface.Clear(0, 0, 0, 0);
  FTextureID    := 0;
  FSkylineCount := 1;
  SetLength(FSkyline, 16);
  FSkyline[0].X     := 0;
  FSkyline[0].Y     := 0;
  FSkyline[0].Width := AWidth;
  FDirty        := False;
  FDirtyRect    := NullRectD;

  gl := FloriaGL();
  if gl.Available and Assigned(gl.GenTextures) then
  begin
    gl.GenTextures(1, @FTextureID);
    gl.BindTexture(GL_TEXTURE_2D, FTextureID);
    gl.TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    gl.TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    gl.TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    gl.TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    gl.TexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, FWidth, FHeight, 0, GL_BGRA_EXT, GL_UNSIGNED_BYTE, FSurface.Data);
  end;
end;

destructor TFloriaAtlasPage.Destroy();
var
  gl: TGLEngine;
begin
  if FTextureID <> 0 then
  begin
    gl := FloriaGL();
    if gl.Available and Assigned(gl.DeleteTextures) then
      gl.DeleteTextures(1, @FTextureID);
    FTextureID := 0;
  end;
  if Assigned(FSurface) then
    FreeAndNil(FSurface);
  SetLength(FSkyline, 0);
  inherited Destroy();
end;

function TFloriaAtlasPage.FitSkyline(NodeIdx, W, H: Integer; out BestY: Integer): Boolean;
var
  X, Y, WidthLeft, I: Integer;
begin
  X := FSkyline[NodeIdx].X;
  if X + W > FWidth then Exit(False);

  WidthLeft := W;
  I := NodeIdx;
  Y := FSkyline[NodeIdx].Y;

  while WidthLeft > 0 do
  begin
    if I >= FSkylineCount then Exit(False);
    if FSkyline[I].Y > Y then
      Y := FSkyline[I].Y;
    if Y + H > FHeight then Exit(False);
    WidthLeft := WidthLeft - FSkyline[I].Width;
    Inc(I);
  end;

  BestY := Y;
  Result := True;
end;

procedure TFloriaAtlasPage.AddSkylineLevel(NodeIdx, X, Y, W: Integer);
var
  NewNode: TFloriaSkylineNode;
  I, Shrink: Integer;
begin
  NewNode.X     := X;
  NewNode.Y     := Y;
  NewNode.Width := W;

  // Insert NewNode at NodeIdx
  if FSkylineCount >= Length(FSkyline) then
    SetLength(FSkyline, Length(FSkyline) * 2);

  for I := FSkylineCount downto NodeIdx + 1 do
    FSkyline[I] := FSkyline[I - 1];
  FSkyline[NodeIdx] := NewNode;
  Inc(FSkylineCount);

  // Shrink or remove subsequent nodes that are covered by NewNode
  I := NodeIdx + 1;
  while I < FSkylineCount do
  begin
    Shrink := (FSkyline[NodeIdx].X + FSkyline[NodeIdx].Width) - FSkyline[I].X;
    if Shrink <= 0 then Break;

    if Shrink < FSkyline[I].Width then
    begin
      FSkyline[I].X     := FSkyline[I].X + Shrink;
      FSkyline[I].Width := FSkyline[I].Width - Shrink;
      Break;
    end
    else
    begin
      // Delete node I
      Move(FSkyline[I + 1], FSkyline[I], (FSkylineCount - I - 1) * SizeOf(TFloriaSkylineNode));
      Dec(FSkylineCount);
    end;
  end;

  // Merge adjacent nodes with identical height
  I := 0;
  while I < FSkylineCount - 1 do
  begin
    if FSkyline[I].Y = FSkyline[I + 1].Y then
    begin
      FSkyline[I].Width := FSkyline[I].Width + FSkyline[I + 1].Width;
      Move(FSkyline[I + 2], FSkyline[I + 1], (FSkylineCount - I - 2) * SizeOf(TFloriaSkylineNode));
      Dec(FSkylineCount);
    end
    else
      Inc(I);
  end;
end;

function TFloriaAtlasPage.Allocate(W, H: Integer; APadding: Integer; out AAllocRect: TRectD): Boolean;
var
  AllocW, AllocH: Integer;
  BestHeight, BestWidth: Integer;
  BestIdx, BestX, BestY, CurY, I: Integer;
begin
  AllocW := W + APadding * 2;
  AllocH := H + APadding * 2;

  BestHeight := MaxInt;
  BestWidth  := MaxInt;
  BestIdx    := -1;
  BestX      := 0;
  BestY      := 0;

  for I := 0 to FSkylineCount - 1 do
  begin
    if FitSkyline(I, AllocW, AllocH, CurY) then
    begin
      if (CurY + AllocH < BestHeight) or
         ((CurY + AllocH = BestHeight) and (FSkyline[I].Width < BestWidth)) then
      begin
        BestHeight := CurY + AllocH;
        BestWidth  := FSkyline[I].Width;
        BestIdx    := I;
        BestX      := FSkyline[I].X;
        BestY      := CurY;
      end;
    end;
  end;

  if BestIdx = -1 then Exit(False);

  AddSkylineLevel(BestIdx, BestX, BestY + AllocH, AllocW);

  // Return rectangle without padding
  AAllocRect.Left   := BestX + APadding;
  AAllocRect.Top    := BestY + APadding;
  AAllocRect.Right  := AAllocRect.Left + W;
  AAllocRect.Bottom := AAllocRect.Top + H;

  MarkDirty(RectD(BestX, BestY, BestX + AllocW, BestY + AllocH));
  Result := True;
end;

procedure TFloriaAtlasPage.MarkDirty(const ARect: TRectD);
begin
  if not FDirty then
  begin
    FDirtyRect := ARect;
    FDirty     := True;
  end
  else
  begin
    FDirtyRect.Left   := Min(FDirtyRect.Left, ARect.Left);
    FDirtyRect.Top    := Min(FDirtyRect.Top, ARect.Top);
    FDirtyRect.Right  := Max(FDirtyRect.Right, ARect.Right);
    FDirtyRect.Bottom := Max(FDirtyRect.Bottom, ARect.Bottom);
  end;
end;

procedure TFloriaAtlasPage.SyncToGPU(gl: TGLEngine);
var
  SubX, SubY, SubW, SubH: Integer;
  RowBytes, SubSize: Integer;
  SubBuffer: PByte;
  Y: Integer;
  SrcPtr, DstPtr: PByte;
begin
  if not Assigned(gl) or not gl.Available then Exit;

  // 1. Initial texture allocation
  if FTextureID = 0 then
  begin
    gl.GenTextures(1, @FTextureID);
    gl.BindTexture(GL_TEXTURE_2D, FTextureID);
    gl.TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    gl.TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    gl.TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    gl.TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    gl.TexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, FWidth, FHeight, 0, GL_BGRA_EXT, GL_UNSIGNED_BYTE, FSurface.Data);
    FDirty := False;
    FDirtyRect := NullRectD;
    Exit;
  end;

  // 2. Incremental sub-texture upload
  if FDirty and not FDirtyRect.IsEmpty then
  begin
    SubX := Max(0, Floor(FDirtyRect.Left));
    SubY := Max(0, Floor(FDirtyRect.Top));
    SubW := Min(FWidth - SubX, Ceil(FDirtyRect.Right) - SubX);
    SubH := Min(FHeight - SubY, Ceil(FDirtyRect.Bottom) - SubY);

    if (SubW > 0) and (SubH > 0) then
    begin
      gl.BindTexture(GL_TEXTURE_2D, FTextureID);

      RowBytes := SubW * 4;
      SubSize  := RowBytes * SubH;
      GetMem(SubBuffer, SubSize);
      try
        DstPtr := SubBuffer;
        for Y := SubY to SubY + SubH - 1 do
        begin
          SrcPtr := PByte(FSurface.Scanline[Y]) + (SubX * 4);
          Move(SrcPtr^, DstPtr^, RowBytes);
          Inc(DstPtr, RowBytes);
        end;
        gl.TexSubImage2D(GL_TEXTURE_2D, 0, SubX, SubY, SubW, SubH, GL_BGRA_EXT, GL_UNSIGNED_BYTE, SubBuffer);
      finally
        FreeMem(SubBuffer);
      end;
    end;

    FDirty     := False;
    FDirtyRect := NullRectD;
  end;
end;

// -----------------------------------------------------------------------------
// TFloriaGPUAtlas Implementation
// -----------------------------------------------------------------------------
constructor TFloriaGPUAtlas.Create(APageSize: Integer = DEFAULT_ATLAS_PAGE_SIZE; APadding: Integer = DEFAULT_ATLAS_PADDING);
begin
  inherited Create();
  if APageSize <= 0 then
    FPageSize := DEFAULT_ATLAS_PAGE_SIZE
  else
    FPageSize := APageSize;
  FPadding        := APadding;
  FPageCount      := 0;
  SetLength(FPages, 0);
  FTextCacheCount := 0;
  SetLength(FTextCache, 0);
end;

destructor TFloriaGPUAtlas.Destroy();
begin
  Clear();
  inherited Destroy();
end;

procedure TFloriaGPUAtlas.Clear();
var
  I: Integer;
begin
  for I := 0 to FPageCount - 1 do
    if Assigned(FPages[I]) then
      FreeAndNil(FPages[I]);
  FPageCount := 0;
  SetLength(FPages, 0);
  FTextCacheCount := 0;
  SetLength(FTextCache, 0);
end;

function TFloriaGPUAtlas.AddPage(APageWidth: Integer = 0; APageHeight: Integer = 0): TFloriaAtlasPage;
var
  pw, ph: Integer;
begin
  if APageWidth <= 0 then pw := FPageSize else pw := APageWidth;
  if APageHeight <= 0 then ph := FPageSize else ph := APageHeight;
  Result := TFloriaAtlasPage.Create(FPageCount, pw, ph);
  SetLength(FPages, FPageCount + 1);
  FPages[FPageCount] := Result;
  Inc(FPageCount);
end;

function TFloriaGPUAtlas.GetPage(AIndex: Integer): TFloriaAtlasPage;
begin
  if (AIndex >= 0) and (AIndex < FPageCount) then
    Result := FPages[AIndex]
  else
    Result := nil;
end;

function TFloriaGPUAtlas.Allocate(W, H: Integer; out Alloc: TFloriaAtlasAlloc): Boolean;
var
  I, TargetW, TargetH: Integer;
  Page: TFloriaAtlasPage;
  AllocRect: TRectD;
begin
  if (W <= 0) or (H <= 0) then
  begin
    Alloc := TFloriaAtlasAlloc.Invalid();
    Exit(False);
  end;

  // 1. Try existing pages if W and H fit within page bounds
  for I := 0 to FPageCount - 1 do
  begin
    Page := FPages[I];
    if (W <= Page.Width) and (H <= Page.Height) and Page.Allocate(W, H, FPadding, AllocRect) then
    begin
      Alloc.PageIndex := Page.Index;
      Alloc.Rect      := AllocRect;
      Alloc.U1        := AllocRect.Left / Page.Width;
      Alloc.V1        := AllocRect.Top / Page.Height;
      Alloc.U2        := AllocRect.Right / Page.Width;
      Alloc.V2        := AllocRect.Bottom / Page.Height;
      Alloc.IsValid   := True;
      Exit(True);
    end;
  end;

  // 2. Allocate new page (at least FPageSize, or larger if W or H exceeds FPageSize)
  TargetW := FPageSize;
  while TargetW < W + FPadding * 2 do
    TargetW := TargetW * 2;
  TargetH := FPageSize;
  while TargetH < H + FPadding * 2 do
    TargetH := TargetH * 2;

  Page := AddPage(TargetW, TargetH);
  if Page.Allocate(W, H, FPadding, AllocRect) then
  begin
    Alloc.PageIndex := Page.Index;
    Alloc.Rect      := AllocRect;
    Alloc.U1        := AllocRect.Left / Page.Width;
    Alloc.V1        := AllocRect.Top / Page.Height;
    Alloc.U2        := AllocRect.Right / Page.Width;
    Alloc.V2        := AllocRect.Bottom / Page.Height;
    Alloc.IsValid   := True;
    Exit(True);
  end;

  Alloc := TFloriaAtlasAlloc.Invalid();
  Result := False;
end;

function TFloriaGPUAtlas.AddImage(AImage: TFloriaImage; out Alloc: TFloriaAtlasAlloc): Boolean;
begin
  if not Assigned(AImage) then
  begin
    Alloc := TFloriaAtlasAlloc.Invalid();
    Exit(False);
  end;
  Result := AddImagePart(AImage, RectD(0.0, 0.0, AImage.Width, AImage.Height), Alloc);
end;

function TFloriaGPUAtlas.AddImagePart(AImage: TFloriaImage; const ASrcRect: TRectD; out Alloc: TFloriaAtlasAlloc): Boolean;
var
  W, H: Integer;
  Page: TFloriaAtlasPage;
begin
  if not Assigned(AImage) or ASrcRect.IsEmpty then
  begin
    Alloc := TFloriaAtlasAlloc.Invalid();
    Exit(False);
  end;

  W := Round(ASrcRect.Width);
  H := Round(ASrcRect.Height);

  if not Allocate(W, H, Alloc) then Exit(False);

  Page := FPages[Alloc.PageIndex];
  Page.Surface.CopyFrom(AImage, Round(ASrcRect.Left), Round(ASrcRect.Top),
                        Round(Alloc.Rect.Left), Round(Alloc.Rect.Top), W, H);
  Page.MarkDirty(Alloc.Rect);
  Result := True;
end;

function TFloriaGPUAtlas.RasterizePath(APath: TFloriaPath; const AFillColor, AStrokeColor: TBgraPixel;
                                      AStrokeWidth: Double; AFillRule: TFillRule;
                                      out Alloc: TFloriaAtlasAlloc): Boolean;
var
  Bounds: TRectD;
  W, H: Integer;
  Page: TFloriaAtlasPage;
  Canvas: TFloriaCanvasAgg;
  TransPath: TFloriaPath;
  AggPath: path_storage;
  AggStyle: TSVGStyleRecord;
begin
  if not Assigned(APath) or APath.IsEmpty then
  begin
    Alloc := TFloriaAtlasAlloc.Invalid();
    Exit(False);
  end;

  Bounds := APath.Bounds;
  if (AStrokeWidth > 0.0) and (AStrokeColor.A > 0) then
    Bounds := RectD(Bounds.Left - AStrokeWidth, Bounds.Top - AStrokeWidth,
                    Bounds.Right + AStrokeWidth, Bounds.Bottom + AStrokeWidth);

  W := Ceil(Bounds.Width);
  H := Ceil(Bounds.Height);
  if (W <= 0) or (H <= 0) then
  begin
    Alloc := TFloriaAtlasAlloc.Invalid();
    Exit(False);
  end;

  if not Allocate(W, H, Alloc) then Exit(False);

  Page := FPages[Alloc.PageIndex];
  Canvas := TFloriaCanvasAgg.Create(Page.Surface);
  try
    // Translate path to target allocated rectangle
    TransPath := APath.Clone();
    try
      TransPath.Translate(Alloc.Rect.Left - Bounds.Left, Alloc.Rect.Top - Bounds.Top);
      AggPath.Construct();
      try
        TransPath.ExportToAggPath(AggPath);
        FillChar(AggStyle, SizeOf(AggStyle), 0);
        if AFillColor.A > 0 then
        begin
          AggStyle.Fill.Kind := pkColor;
          AggStyle.Fill.Color.R := AFillColor.R;
          AggStyle.Fill.Color.G := AFillColor.G;
          AggStyle.Fill.Color.B := AFillColor.B;
          AggStyle.Fill.Color.A := AFillColor.A;
          AggStyle.FillOpacity := AFillColor.A / 255.0;
          if AFillRule = frEvenOdd then
            AggStyle.FillRule := sfrEvenOdd
          else
            AggStyle.FillRule := sfrNonZero;
        end
        else
          AggStyle.Fill.Kind := pkNone;

        if (AStrokeWidth > 0.0) and (AStrokeColor.A > 0) then
        begin
          AggStyle.Stroke.Kind := pkColor;
          AggStyle.Stroke.Color.R := AStrokeColor.R;
          AggStyle.Stroke.Color.G := AStrokeColor.G;
          AggStyle.Stroke.Color.B := AStrokeColor.B;
          AggStyle.Stroke.Color.A := AStrokeColor.A;
          AggStyle.StrokeWidth := AStrokeWidth;
          AggStyle.StrokeOpacity := AStrokeColor.A / 255.0;
        end
        else
          AggStyle.Stroke.Kind := pkNone;

        Canvas.RenderPath(AggPath, AggStyle);
      finally
        AggPath.Destruct();
      end;
    finally
      TransPath.Free();
    end;
  finally
    Canvas.Free();
  end;

  Page.MarkDirty(Alloc.Rect);
  Result := True;
end;

function TFloriaGPUAtlas.RasterizeText(const AText: string; AFont: TFloriaFont;
                                      out Alloc: TFloriaAtlasAlloc): Boolean;
var
  W, H, Row, I: Integer;
  Page: TFloriaAtlasPage;
  Canvas: TFloriaCanvasAgg;
  TextW: Double;
  Font: TFloriaFont;
  FKey: string;
begin
  if AText = '' then
  begin
    Alloc := TFloriaAtlasAlloc.Invalid();
    Exit(False);
  end;

  Font := AFont;
  if not Assigned(Font) then Font := FloriaGetSystemFont();

  if Assigned(Font) then
    FKey := Font.FamilyName + '#' + IntToStr(Round(Font.Size * 10.0)) + '#' + BoolToStr(Font.Bold, True) + '#' + BoolToStr(Font.Italic, True)
  else
    FKey := 'default';

  // 1. Search text cache
  for I := 0 to FTextCacheCount - 1 do
  begin
    if (FTextCache[I].Text = AText) and (FTextCache[I].FontKey = FKey) then
    begin
      Alloc := FTextCache[I].Alloc;
      Exit(True);
    end;
  end;

  // 2. Measure & allocate in atlas
  TextW := Font.GetTextWidth(AText);
  W := Ceil(TextW) + 4;
  H := Ceil(Font.Height) + 4;
  if (W <= 0) or (H <= 0) then
  begin
    Alloc := TFloriaAtlasAlloc.Invalid();
    Exit(False);
  end;

  if not Allocate(W, H, Alloc) then
    Exit(False);

  // 3. Clear target slot
  Page := FPages[Alloc.PageIndex];
  for Row := Round(Alloc.Rect.Top) to Round(Alloc.Rect.Bottom) - 1 do
    FillChar(PByte(Page.Surface.PixelBuffer)[Row * Page.Surface.Stride + Round(Alloc.Rect.Left) * 4], W * 4, 0);

  // 4. Rasterize text in pure white so alpha channel holds font coverage
  Canvas := TFloriaCanvasAgg.Create(Page.Surface);
  try
    Canvas.DrawText(Alloc.Rect.Left + 2.0, Alloc.Rect.Top + Round(Font.Ascent) + 2.0, AText, Font,
                    1.0, 1.0, 1.0);
  finally
    Canvas.Free();
  end;

  Page.MarkDirty(Alloc.Rect);

  // 5. Cache result
  if FTextCacheCount >= Length(FTextCache) then
  begin
    if Length(FTextCache) = 0 then
      SetLength(FTextCache, 64)
    else
      SetLength(FTextCache, Length(FTextCache) * 2);
  end;
  FTextCache[FTextCacheCount].Text := AText;
  FTextCache[FTextCacheCount].FontKey := FKey;
  FTextCache[FTextCacheCount].Alloc := Alloc;
  Inc(FTextCacheCount);

  Result := True;
end;

function TFloriaGPUAtlas.RasterizeText(const AText: string; AFont: TFloriaFont; const AColor: TBgraPixel;
                                      out Alloc: TFloriaAtlasAlloc): Boolean;
begin
  Result := RasterizeText(AText, AFont, Alloc);
end;

procedure TFloriaGPUAtlas.SyncToGPU(gl: TGLEngine);
var
  I: Integer;
begin
  for I := 0 to FPageCount - 1 do
    if Assigned(FPages[I]) then
      FPages[I].SyncToGPU(gl);
end;

end.
