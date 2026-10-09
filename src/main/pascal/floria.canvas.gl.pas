unit Floria.Canvas.GL;

// Floria.Canvas.GL
// ================
// Hardware-accelerated OpenGL / GLES 2D vector & UI canvas for Floria.
// Implements TFloriaCanvas on top of TFloriaGPURenderer, eliminating CPU blitting
// and rendering widgets directly via GPU vertex buffers, shaders, and dynamic atlasing.

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math,
  Floria.GL,
  Floria.Image.Core,
  Floria.Font,
  Floria.Canvas,
  Floria.Canvas.Blend,
  Floria.SVG.Types,
  Floria.SVG.DOM,
  Floria.Path.Clipper.Core,
  Floria.GPU.Atlas,
  Floria.GPU.Batch,
  Floria.GPU.Shaders,
  Floria.GPU.Tessellator,
  Floria.GPU.Context,
  Floria.DisplayList,
  Floria.DisplayList.Clip,
  Floria.Image.Blur,
  Floria.GPU.Renderer;

type
  TFloriaCanvasGL = class(TFloriaCanvas)
  private
    FGL: TGLEngine;
    FRenderer: TFloriaGPURenderer;
    FOwnsRenderer: Boolean;
    FAlphaStack: array[0..63] of Double;
    FAlphaStackCount: Integer;
    FClipStack: array[0..63] of TFtClipRect;
    FClipStackCount: Integer;
    FInFrame: Boolean;
    FBlurTexture: Cardinal;
    FBlurTextureW: Integer;
    FBlurTextureH: Integer;
  protected
    procedure SetBlendMode(AMode: TFloriaBlendMode); override;
  public
    constructor Create(W, H: Integer; gl: TGLEngine = nil); overload;
    constructor Create(ARenderer: TFloriaGPURenderer); overload;
    constructor Create(AContext: TFloriaGPUContext); overload;
    destructor Destroy(); override;

    procedure BeginFrame(AWidth, AHeight: Integer);
    procedure EndFrame();
    procedure Flush();

    procedure Resize(AWidth, AHeight: Integer); override;

    procedure Clear(R, G, B: Double); override;
    procedure DrawRect(X, Y, W, H: Integer; R, G, B: Double; A: Double = 1.0); override;
    procedure DrawRoundedRect(X, Y, W, H: Double; Radius: Double; R, G, B: Double; A: Double = 1.0); override;
    procedure DrawRoundedRectOutline(X, Y, W, H: Double; Radius: Double; BorderWidth: Double; R, G, B: Double; A: Double = 1.0); override;
    procedure DrawShadow(X, Y, W, H: Double; Radius: Double; OffsetX, OffsetY: Double; BlurRadius: Double; ShadowR, ShadowG, ShadowB, ShadowOpacity: Double); override;
    procedure BlurRoundedRect(X, Y, W, H: Double; Radius: Double; BlurRadius: Double); override;
    procedure BlurRect(X, Y, W, H: Double; BlurRadius: Double); override;

    procedure PushClipRect(X, Y, W, H: Integer); override;
    procedure PopClipRect(); override;
    procedure PushClipRoundedRect(X, Y, W, H: Double; Radius: Double); override; overload;
    procedure PushClipRoundedRect(X, Y, W, H: Double; TopRadius, BottomRadius: Double); override; overload;
    procedure PopClipRoundedRect(); override;
    procedure SetClipRect(X, Y, W, H: Integer); override;
    procedure ResetClipRect(); override;
    procedure ResetAllClipping(); override;
    function GetClipRect(out X, Y, W, H: Integer): Boolean; override;
    function IntersectsClip(X, Y, W, H: Integer): Boolean; override;

    procedure PushAlpha(AAlpha: Double); override;
    procedure PopAlpha(); override;
    procedure ResetAlpha(); override;

    procedure DrawText(X, Y: Double; const AText: string; AFont: TFloriaFont; R, G, B: Double); override; overload;
    procedure DrawTextCentered(X, Y, W, H: Integer; const AText: string; AFont: TFloriaFont; R, G, B: Double); override; overload;
    procedure DrawTextLeft(X, Y, W, H: Double; const AText: string; AFont: TFloriaFont; R, G, B: Double); override;

    procedure DrawCheckMark(CX, CY: Double; R, G, B: Double; A: Double = 1.0); override;
    procedure DrawSubMenuArrow(CX, CY: Double; R, G, B: Double; A: Double = 1.0); override;
    procedure DrawCircle(CX, CY, Radius: Double; R, G, B: Double; A: Double = 1.0); override;
    procedure DrawCircleOutline(CX, CY, Radius, BorderWidth: Double; R, G, B: Double; A: Double = 1.0); override;
    procedure DrawLine(X1, Y1, X2, Y2, LineWidth: Double; R, G, B: Double; A: Double = 1.0); override;

    // Image & Bitmap Drawing
    procedure DrawImage(X, Y: Double; AImage: TFloriaImage; AOpacity: Double = 1.0); override;
    procedure DrawImageScaled(X, Y, W, H: Double; AImage: TFloriaImage; AOpacity: Double = 1.0); override;
    procedure DrawImagePart(X, Y, W, H: Double; AImage: TFloriaImage; SrcX, SrcY, SrcW, SrcH: Integer; AOpacity: Double = 1.0); override;

    // SVG Drawing
    procedure DrawSVG(X, Y: Double; ADoc: TSVGDocument); override;
    procedure DrawSVGScaled(X, Y, W, H: Double; ADoc: TSVGDocument); override;
    procedure DrawSVGFile(X, Y, W, H: Double; const AFileName: string); override;
    procedure DrawSVGString(X, Y, W, H: Double; const ASVGContent: string); override;

    // Font size convenience overloads
    procedure DrawText(X, Y: Double; const AText: string; ASize: Double; R, G, B: Double); override; overload;
    procedure DrawTextCentered(X, Y, W, H: Integer; const AText: string; ASize: Double; R, G, B: Double); override; overload;

    property Renderer: TFloriaGPURenderer read FRenderer;
    property InFrame : Boolean            read FInFrame;
  end;

  // Backward-compatibility alias
  TFtCanvasGL = TFloriaCanvasGL;

implementation

constructor TFloriaCanvasGL.Create(W, H: Integer; gl: TGLEngine = nil);
begin
  inherited Create();
  if Assigned(gl) then
    FGL := gl
  else
    FGL := FloriaGL();

  FRenderer := TFloriaGPURenderer.Create(FGL);
  FRenderer.AutoSwapBuffers := False; // Window backend manages SwapBuffers
  FOwnsRenderer := True;
  FWidth := W;
  FHeight := H;
  FCurrentAlpha := 1.0;
  FAlphaStackCount := 0;
  FClipStackCount := 0;
  FInFrame := False;
end;

constructor TFloriaCanvasGL.Create(ARenderer: TFloriaGPURenderer);
begin
  inherited Create();
  FRenderer := ARenderer;
  FOwnsRenderer := False;
  FGL := FloriaGL();
  FWidth := 0;
  FHeight := 0;
  FCurrentAlpha := 1.0;
  FAlphaStackCount := 0;
  FClipStackCount := 0;
  FInFrame := False;
end;

constructor TFloriaCanvasGL.Create(AContext: TFloriaGPUContext);
begin
  inherited Create();
  FRenderer := TFloriaGPURenderer.Create(AContext);
  FRenderer.AutoSwapBuffers := False;
  FOwnsRenderer := True;
  if Assigned(AContext) then
    FGL := AContext.GL
  else
    FGL := FloriaGL();
  FWidth := 0;
  FHeight := 0;
  FCurrentAlpha := 1.0;
  FAlphaStackCount := 0;
  FClipStackCount := 0;
  FInFrame := False;
end;

destructor TFloriaCanvasGL.Destroy();
begin
  if (FBlurTexture <> 0) and Assigned(FGL) and FGL.Available then
  begin
    FGL.DeleteTextures(1, @FBlurTexture);
    FBlurTexture := 0;
  end;
  if FOwnsRenderer and Assigned(FRenderer) then
    FreeAndNil(FRenderer);
  inherited Destroy();
end;

procedure TFloriaCanvasGL.BeginFrame(AWidth, AHeight: Integer);
begin
  FWidth := AWidth;
  FHeight := AHeight;
  FInFrame := True;
  FCurrentAlpha := 1.0;
  FAlphaStackCount := 0;
  FClipStackCount := 0;
  if Assigned(FRenderer) then
    FRenderer.BeginFrame(AWidth, AHeight);
end;

procedure TFloriaCanvasGL.EndFrame();
begin
  if Assigned(FRenderer) then
    FRenderer.EndFrame();
  FInFrame := False;
end;

procedure TFloriaCanvasGL.Flush();
begin
  if Assigned(FRenderer) then
    FRenderer.Flush();
end;

procedure TFloriaCanvasGL.Resize(AWidth, AHeight: Integer);
begin
  FWidth := AWidth;
  FHeight := AHeight;
end;

procedure TFloriaCanvasGL.SetBlendMode(AMode: TFloriaBlendMode);
begin
  inherited SetBlendMode(AMode);
  if Assigned(FRenderer) then
    FRenderer.OnSetBlendMode(AMode);
end;

procedure TFloriaCanvasGL.Clear(R, G, B: Double);
var
  col: TBgraPixel;
begin
  col := BgraPixel(Round(EnsureRange(R, 0.0, 1.0) * 255.0),
                   Round(EnsureRange(G, 0.0, 1.0) * 255.0),
                   Round(EnsureRange(B, 0.0, 1.0) * 255.0),
                   255);
  if Assigned(FRenderer) then
    FRenderer.OnClear(col);
end;

procedure TFloriaCanvasGL.DrawRect(X, Y, W, H: Integer; R, G, B: Double; A: Double);
var
  fillCol: TBgraPixel;
  rect: TRectD;
begin
  if (W <= 0) or (H <= 0) or (A <= 0.0) or (FCurrentAlpha <= 0.0) then Exit;
  fillCol := BgraPixel(Round(EnsureRange(R, 0.0, 1.0) * 255.0),
                       Round(EnsureRange(G, 0.0, 1.0) * 255.0),
                       Round(EnsureRange(B, 0.0, 1.0) * 255.0),
                       Round(EnsureRange(A * FCurrentAlpha, 0.0, 1.0) * 255.0));
  rect := RectD(X, Y, X + W, Y + H);
  if Assigned(FRenderer) then
    FRenderer.OnDrawRect(rect, fillCol, BgraPixel(0, 0, 0, 0), 0.0);
end;

procedure TFloriaCanvasGL.DrawRoundedRect(X, Y, W, H: Double; Radius: Double; R, G, B: Double; A: Double);
var
  fillCol: TBgraPixel;
  rect: TRectD;
begin
  if (W <= 0.0) or (H <= 0.0) or (A <= 0.0) or (FCurrentAlpha <= 0.0) then Exit;
  fillCol := BgraPixel(Round(EnsureRange(R, 0.0, 1.0) * 255.0),
                       Round(EnsureRange(G, 0.0, 1.0) * 255.0),
                       Round(EnsureRange(B, 0.0, 1.0) * 255.0),
                       Round(EnsureRange(A * FCurrentAlpha, 0.0, 1.0) * 255.0));
  rect := RectD(X, Y, X + W, Y + H);
  if Assigned(FRenderer) then
    FRenderer.OnDrawRoundedRect(rect, Radius, Radius, fillCol, BgraPixel(0, 0, 0, 0), 0.0);
end;

procedure TFloriaCanvasGL.DrawRoundedRectOutline(X, Y, W, H: Double; Radius: Double; BorderWidth: Double; R, G, B: Double; A: Double);
var
  strokeCol: TBgraPixel;
  rect: TRectD;
begin
  if (W <= 0.0) or (H <= 0.0) or (BorderWidth <= 0.0) or (A <= 0.0) or (FCurrentAlpha <= 0.0) then Exit;
  strokeCol := BgraPixel(Round(EnsureRange(R, 0.0, 1.0) * 255.0),
                         Round(EnsureRange(G, 0.0, 1.0) * 255.0),
                         Round(EnsureRange(B, 0.0, 1.0) * 255.0),
                         Round(EnsureRange(A * FCurrentAlpha, 0.0, 1.0) * 255.0));
  rect := RectD(X, Y, X + W, Y + H);
  if Assigned(FRenderer) then
    FRenderer.OnDrawRoundedRect(rect, Radius, Radius, BgraPixel(0, 0, 0, 0), strokeCol, BorderWidth);
end;

procedure TFloriaCanvasGL.DrawShadow(X, Y, W, H: Double; Radius: Double; OffsetX, OffsetY: Double;
                                    BlurRadius: Double; ShadowR, ShadowG, ShadowB, ShadowOpacity: Double);
var
  params: TFloriaShadowParams;
  rect: TRectD;
begin
  if (W <= 0.0) or (H <= 0.0) or (ShadowOpacity <= 0.0) or (FCurrentAlpha <= 0.0) then Exit;
  params.OffsetX := OffsetX;
  params.OffsetY := OffsetY;
  params.BlurRadius := BlurRadius;
  params.SpreadRadius := 0.0;
  params.Color := BgraPixel(Round(EnsureRange(ShadowR, 0.0, 1.0) * 255.0),
                            Round(EnsureRange(ShadowG, 0.0, 1.0) * 255.0),
                            Round(EnsureRange(ShadowB, 0.0, 1.0) * 255.0),
                            Round(EnsureRange(ShadowOpacity * FCurrentAlpha, 0.0, 1.0) * 255.0));
  params.Inset := False;
  rect := RectD(X, Y, X + W, Y + H);
  if Assigned(FRenderer) then
    FRenderer.OnDrawShadow(rect, Radius, params);
end;

procedure TFloriaCanvasGL.BlurRoundedRect(X, Y, W, H: Double; Radius: Double; BlurRadius: Double);
var
  rx, ry, rw, rh, glY: Integer;
  rawGL, flippedBuf: PByte;
  rowSize, rowIdx: Integer;
  srcRow, dstRow: PByte;
  texRect: TRectD;
begin
  if (W <= 0.0) or (H <= 0.0) or (BlurRadius <= 0.5) then Exit;
  if not Assigned(FGL) or not FGL.Available or not Assigned(FGL.ReadPixels) then Exit;

  // 1. Commit all queued drawing so current OpenGL framebuffer is complete
  Flush();

  // 2. Compute clamped bounds in screen coordinates
  rx := Max(0, Round(X));
  ry := Max(0, Round(Y));
  rw := Min(FWidth - rx, Round(W));
  rh := Min(FHeight - ry, Round(H));
  if (rw <= 0) or (rh <= 0) then Exit;

  // 3. Compute OpenGL Y coordinate (GL origin is bottom-left)
  glY := FHeight - (ry + rh);
  if glY < 0 then
  begin
    rh := rh + glY;
    glY := 0;
    if rh <= 0 then Exit;
  end;

  // 4. Read pixels from OpenGL framebuffer (format GL_RGBA)
  GetMem(rawGL, rw * rh * 4);
  try
    FGL.PixelStorei(GL_PACK_ALIGNMENT, 4);
    FGL.ReadPixels(rx, glY, rw, rh, GL_RGBA, GL_UNSIGNED_BYTE, rawGL);

    // 5. Flip rows vertically so row 0 is top
    GetMem(flippedBuf, rw * rh * 4);
    try
      rowSize := rw * 4;
      for rowIdx := 0 to rh - 1 do
      begin
        srcRow := rawGL + ((rh - 1 - rowIdx) * rowSize);
        dstRow := flippedBuf + (rowIdx * rowSize);
        Move(srcRow^, dstRow^, rowSize);
      end;

      // 6. Fast separable box blur
      FloriaFastBlurRect(flippedBuf, rw, rh, 0, 0, rw, rh, BlurRadius);

      // 7. Upload to dedicated blur texture
      FGL.PixelStorei(GL_UNPACK_ALIGNMENT, 4);
      if FBlurTexture = 0 then
      begin
        FGL.GenTextures(1, @FBlurTexture);
        FGL.BindTexture(GL_TEXTURE_2D, FBlurTexture);
        FGL.TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        FGL.TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        FGL.TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        FGL.TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        FGL.TexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, rw, rh, 0, GL_RGBA, GL_UNSIGNED_BYTE, flippedBuf);
        FBlurTextureW := rw;
        FBlurTextureH := rh;
      end
      else
      begin
        FGL.BindTexture(GL_TEXTURE_2D, FBlurTexture);
        if (rw > FBlurTextureW) or (rh > FBlurTextureH) then
        begin
          FGL.TexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, rw, rh, 0, GL_RGBA, GL_UNSIGNED_BYTE, flippedBuf);
          FBlurTextureW := rw;
          FBlurTextureH := rh;
        end
        else
        begin
          FGL.TexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, rw, rh, GL_RGBA, GL_UNSIGNED_BYTE, flippedBuf);
        end;
      end;

      // 8. Emit textured rect with GPU SDF rounded rect clipping
      texRect.Left := 0.0;
      texRect.Top := 0.0;
      texRect.Right := rw / FBlurTextureW;
      texRect.Bottom := rh / FBlurTextureH;

      if Radius > 0.5 then
        PushClipRoundedRect(X, Y, W, H, Radius);

      if Assigned(FRenderer) then
      begin
        FRenderer.Batch.EmitTexturedRect(
          RectD(rx, ry, rx + rw, ry + rh),
          texRect,
          FBlurTexture,
          FCurrentAlpha,
          fbmSrcOver,
          FRenderer.ClipChain.CurrentNode
        );
      end;

      // Commit the textured quad with its clipping before restoring clip state
      Flush();

      if Radius > 0.5 then
        PopClipRoundedRect();
    finally
      FreeMem(flippedBuf);
    end;
  finally
    FreeMem(rawGL);
  end;
end;

procedure TFloriaCanvasGL.BlurRect(X, Y, W, H: Double; BlurRadius: Double);
begin
  BlurRoundedRect(X, Y, W, H, 0.0, BlurRadius);
end;

procedure TFloriaCanvasGL.PushClipRect(X, Y, W, H: Integer);
var
  newR, topR: TFtClipRect;
begin
  if (W <= 0) or (H <= 0) then
  begin
    newR.X1 := 0; newR.Y1 := 0; newR.X2 := -1; newR.Y2 := -1;
  end
  else
  begin
    newR.X1 := X;
    newR.Y1 := Y;
    newR.X2 := X + W - 1;
    newR.Y2 := Y + H - 1;
  end;

  if FClipStackCount > 0 then
  begin
    topR := FClipStack[FClipStackCount - 1];
    if (topR.X2 < topR.X1) or (topR.Y2 < topR.Y1) then
      newR := topR
    else
    begin
      newR.X1 := Max(newR.X1, topR.X1);
      newR.Y1 := Max(newR.Y1, topR.Y1);
      newR.X2 := Min(newR.X2, topR.X2);
      newR.Y2 := Min(newR.Y2, topR.Y2);
    end;
  end;

  if FClipStackCount < High(FClipStack) then
  begin
    FClipStack[FClipStackCount] := newR;
    Inc(FClipStackCount);
  end;

  if Assigned(FRenderer) then
    FRenderer.OnPushClipRect(RectD(newR.X1, newR.Y1, newR.X2 + 1, newR.Y2 + 1), False);
end;

procedure TFloriaCanvasGL.PopClipRect();
begin
  if FClipStackCount > 0 then
    Dec(FClipStackCount);
  if Assigned(FRenderer) then
    FRenderer.OnPopClip();
end;

procedure TFloriaCanvasGL.PushClipRoundedRect(X, Y, W, H: Double; Radius: Double);
begin
  PushClipRoundedRect(X, Y, W, H, Radius, Radius);
end;

procedure TFloriaCanvasGL.PushClipRoundedRect(X, Y, W, H: Double; TopRadius, BottomRadius: Double);
var
  newR, topR: TFtClipRect;
  radii: TFloriaClipCornerRadii;
  topRVal, botRVal: Double;
  intX, intY, intW, intH: Integer;
begin
  intX := Round(X);
  intY := Round(Y);
  intW := Round(W);
  intH := Round(H);

  if (intW <= 0) or (intH <= 0) then
  begin
    newR.X1 := 0; newR.Y1 := 0; newR.X2 := -1; newR.Y2 := -1;
  end
  else
  begin
    newR.X1 := intX;
    newR.Y1 := intY;
    newR.X2 := intX + intW - 1;
    newR.Y2 := intY + intH - 1;
  end;

  if FClipStackCount > 0 then
  begin
    topR := FClipStack[FClipStackCount - 1];
    if (topR.X2 < topR.X1) or (topR.Y2 < topR.Y1) then
      newR := topR
    else
    begin
      newR.X1 := Max(newR.X1, topR.X1);
      newR.Y1 := Max(newR.Y1, topR.Y1);
      newR.X2 := Min(newR.X2, topR.X2);
      newR.Y2 := Min(newR.Y2, topR.Y2);
    end;
  end;

  if FClipStackCount < High(FClipStack) then
  begin
    FClipStack[FClipStackCount] := newR;
    Inc(FClipStackCount);
  end;

  topRVal := Max(0.0, TopRadius);
  botRVal := Max(0.0, BottomRadius);
  if (W > 0.0) and (topRVal * 2.0 > W) then topRVal := W * 0.5;
  if (H > 0.0) and (topRVal * 2.0 > H) then topRVal := H * 0.5;
  if (W > 0.0) and (botRVal * 2.0 > W) then botRVal := W * 0.5;
  if (H > 0.0) and (botRVal * 2.0 > H) then botRVal := H * 0.5;

  radii := TFloriaClipCornerRadii.TopBottom(topRVal, botRVal);

  if Assigned(FRenderer) then
    FRenderer.OnPushClipRoundedRect(RectD(X, Y, X + W, Y + H), radii, True);
end;

procedure TFloriaCanvasGL.PopClipRoundedRect();
begin
  if FClipStackCount > 0 then
    Dec(FClipStackCount);
  if Assigned(FRenderer) then
    FRenderer.OnPopClip();
end;

procedure TFloriaCanvasGL.SetClipRect(X, Y, W, H: Integer);
begin
  ResetAllClipping();
  PushClipRect(X, Y, W, H);
end;

procedure TFloriaCanvasGL.ResetClipRect();
begin
  ResetAllClipping();
end;

procedure TFloriaCanvasGL.ResetAllClipping();
begin
  while FClipStackCount > 0 do
    PopClipRect();
end;

function TFloriaCanvasGL.GetClipRect(out X, Y, W, H: Integer): Boolean;
var
  cur: TFtClipRect;
begin
  if FClipStackCount > 0 then
  begin
    cur := FClipStack[FClipStackCount - 1];
    X := cur.X1;
    Y := cur.Y1;
    W := cur.X2 - cur.X1 + 1;
    H := cur.Y2 - cur.Y1 + 1;
    Result := (W > 0) and (H > 0);
  end
  else
  begin
    X := 0; Y := 0; W := FWidth; H := FHeight;
    Result := True;
  end;
end;

function TFloriaCanvasGL.IntersectsClip(X, Y, W, H: Integer): Boolean;
var
  cX, cY, cW, cH: Integer;
begin
  if not GetClipRect(cX, cY, cW, cH) then Exit(False);
  Result := (X < cX + cW) and (X + W > cX) and (Y < cY + cH) and (Y + H > cY);
end;

procedure TFloriaCanvasGL.PushAlpha(AAlpha: Double);
begin
  if FAlphaStackCount < High(FAlphaStack) then
  begin
    FAlphaStack[FAlphaStackCount] := FCurrentAlpha;
    Inc(FAlphaStackCount);
  end;
  FCurrentAlpha := FCurrentAlpha * Max(0.0, Min(1.0, AAlpha));
  if Assigned(FRenderer) then
    FRenderer.OnSetAlpha(FCurrentAlpha);
end;

procedure TFloriaCanvasGL.PopAlpha();
begin
  if FAlphaStackCount > 0 then
  begin
    Dec(FAlphaStackCount);
    FCurrentAlpha := FAlphaStack[FAlphaStackCount];
  end
  else
    FCurrentAlpha := 1.0;
  if Assigned(FRenderer) then
    FRenderer.OnSetAlpha(FCurrentAlpha);
end;

procedure TFloriaCanvasGL.ResetAlpha();
begin
  FAlphaStackCount := 0;
  FCurrentAlpha := 1.0;
  if Assigned(FRenderer) then
    FRenderer.OnSetAlpha(FCurrentAlpha);
end;

procedure TFloriaCanvasGL.DrawText(X, Y: Double; const AText: string; AFont: TFloriaFont; R, G, B: Double);
var
  col: TBgraPixel;
begin
  if (AText = '') or (FCurrentAlpha <= 0.0) then Exit;
  col := BgraPixel(Round(EnsureRange(R, 0.0, 1.0) * 255.0),
                   Round(EnsureRange(G, 0.0, 1.0) * 255.0),
                   Round(EnsureRange(B, 0.0, 1.0) * 255.0),
                   Round(EnsureRange(FCurrentAlpha, 0.0, 1.0) * 255.0));
  if Assigned(FRenderer) then
    FRenderer.OnDrawText(AText, X, Y, AFont, AFont.Size, col);
end;

procedure TFloriaCanvasGL.DrawTextCentered(X, Y, W, H: Integer; const AText: string; AFont: TFloriaFont; R, G, B: Double);
var
  tw: Double;
  font: TFloriaFont;
begin
  if (AText = '') or (W <= 0) or (H <= 0) then Exit;
  font := AFont;
  if not Assigned(font) then font := FloriaGetSystemFont();
  tw := font.GetTextWidth(AText);
  DrawText(Round(X + (W - tw) / 2.0), Round(Y + (H / 2.0) + (font.Ascent - font.Descent) / 2.0), AText, font, R, G, B);
end;

procedure TFloriaCanvasGL.DrawTextLeft(X, Y, W, H: Double; const AText: string; AFont: TFloriaFont; R, G, B: Double);
var
  font: TFloriaFont;
begin
  if (AText = '') then Exit;
  font := AFont;
  if not Assigned(font) then font := FloriaGetSystemFont();
  DrawText(Round(X), Round(Y + (H / 2.0) + (font.Ascent - font.Descent) / 2.0), AText, font, R, G, B);
end;

procedure TFloriaCanvasGL.DrawCheckMark(CX, CY: Double; R, G, B: Double; A: Double);
begin
  DrawLine(CX - 5.0, CY, CX - 1.5, CY + 4.5, 2.0, R, G, B, A);
  DrawLine(CX - 1.5, CY + 4.5, CX + 5.5, CY - 4.0, 2.0, R, G, B, A);
end;

procedure TFloriaCanvasGL.DrawSubMenuArrow(CX, CY: Double; R, G, B: Double; A: Double);
begin
  DrawLine(CX - 2.0, CY - 4.0, CX + 2.5, CY, 1.5, R, G, B, A);
  DrawLine(CX + 2.5, CY, CX - 2.0, CY + 4.0, 1.5, R, G, B, A);
end;

procedure TFloriaCanvasGL.DrawCircle(CX, CY, Radius: Double; R, G, B: Double; A: Double);
var
  fillCol: TBgraPixel;
begin
  if (Radius <= 0.0) or (A <= 0.0) or (FCurrentAlpha <= 0.0) then Exit;
  fillCol := BgraPixel(Round(EnsureRange(R, 0.0, 1.0) * 255.0),
                       Round(EnsureRange(G, 0.0, 1.0) * 255.0),
                       Round(EnsureRange(B, 0.0, 1.0) * 255.0),
                       Round(EnsureRange(A * FCurrentAlpha, 0.0, 1.0) * 255.0));
  if Assigned(FRenderer) then
    FRenderer.OnDrawCircle(CX, CY, Radius, fillCol, BgraPixel(0, 0, 0, 0), 0.0);
end;

procedure TFloriaCanvasGL.DrawCircleOutline(CX, CY, Radius, BorderWidth: Double; R, G, B: Double; A: Double);
var
  strokeCol: TBgraPixel;
begin
  if (Radius <= 0.0) or (BorderWidth <= 0.0) or (A <= 0.0) or (FCurrentAlpha <= 0.0) then Exit;
  strokeCol := BgraPixel(Round(EnsureRange(R, 0.0, 1.0) * 255.0),
                         Round(EnsureRange(G, 0.0, 1.0) * 255.0),
                         Round(EnsureRange(B, 0.0, 1.0) * 255.0),
                         Round(EnsureRange(A * FCurrentAlpha, 0.0, 1.0) * 255.0));
  if Assigned(FRenderer) then
    FRenderer.OnDrawCircle(CX, CY, Radius, BgraPixel(0, 0, 0, 0), strokeCol, BorderWidth);
end;

procedure TFloriaCanvasGL.DrawLine(X1, Y1, X2, Y2, LineWidth: Double; R, G, B: Double; A: Double);
var
  lineCol: TBgraPixel;
begin
  if (LineWidth <= 0.0) or (A <= 0.0) or (FCurrentAlpha <= 0.0) then Exit;
  lineCol := BgraPixel(Round(EnsureRange(R, 0.0, 1.0) * 255.0),
                       Round(EnsureRange(G, 0.0, 1.0) * 255.0),
                       Round(EnsureRange(B, 0.0, 1.0) * 255.0),
                       Round(EnsureRange(A * FCurrentAlpha, 0.0, 1.0) * 255.0));
  if Assigned(FRenderer) then
    FRenderer.OnDrawLine(X1, Y1, X2, Y2, lineCol, LineWidth);
end;

procedure TFloriaCanvasGL.DrawImage(X, Y: Double; AImage: TFloriaImage; AOpacity: Double);
begin
  if not Assigned(AImage) then Exit;
  DrawImagePart(X, Y, AImage.Width, AImage.Height, AImage, 0, 0, AImage.Width, AImage.Height, AOpacity);
end;

procedure TFloriaCanvasGL.DrawImageScaled(X, Y, W, H: Double; AImage: TFloriaImage; AOpacity: Double);
begin
  if not Assigned(AImage) then Exit;
  DrawImagePart(X, Y, W, H, AImage, 0, 0, AImage.Width, AImage.Height, AOpacity);
end;

procedure TFloriaCanvasGL.DrawImagePart(X, Y, W, H: Double; AImage: TFloriaImage; SrcX, SrcY, SrcW, SrcH: Integer; AOpacity: Double);
begin
  if not Assigned(AImage) or (W <= 0.0) or (H <= 0.0) or (AOpacity <= 0.0) or (FCurrentAlpha <= 0.0) then Exit;
  if Assigned(FRenderer) then
    FRenderer.OnDrawImage(AImage, RectD(X, Y, X + W, Y + H), RectD(SrcX, SrcY, SrcX + SrcW, SrcY + SrcH), AOpacity * FCurrentAlpha);
end;

procedure TFloriaCanvasGL.DrawSVG(X, Y: Double; ADoc: TSVGDocument);
begin
  // Fallback or render via display list
end;

procedure TFloriaCanvasGL.DrawSVGScaled(X, Y, W, H: Double; ADoc: TSVGDocument);
begin
end;

procedure TFloriaCanvasGL.DrawSVGFile(X, Y, W, H: Double; const AFileName: string);
begin
end;

procedure TFloriaCanvasGL.DrawSVGString(X, Y, W, H: Double; const ASVGContent: string);
begin
end;

procedure TFloriaCanvasGL.DrawText(X, Y: Double; const AText: string; ASize: Double; R, G, B: Double);
var
  f: TFloriaFont;
begin
  f := FloriaFontManager().GetFont('Sans-' + FloatToStr(ASize));
  DrawText(X, Y, AText, f, R, G, B);
end;

procedure TFloriaCanvasGL.DrawTextCentered(X, Y, W, H: Integer; const AText: string; ASize: Double; R, G, B: Double);
var
  f: TFloriaFont;
begin
  f := FloriaFontManager().GetFont('Sans-' + FloatToStr(ASize));
  DrawTextCentered(X, Y, W, H, AText, f, R, G, B);
end;

end.
