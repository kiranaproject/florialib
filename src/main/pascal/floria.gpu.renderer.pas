unit Floria.GPU.Renderer;

// Floria.GPU.Renderer
// ===================
// Hardware-Accelerated 2D Display List Receiver & Vector Renderer.
//
// Capabilities:
// - Direct implementation of IFloriaDisplayListReceiver.
// - 95/5 Rule: Instanced SDF quad fast-path for 95% of UI primitives;
//   pure Pascal AggPas blob rasterizer into TFloriaGPUAtlas for 5% complex paths.
// - Analytical Clip Chain evaluation without temporary offscreen FBOs.
// - Single-pass batched draw calls with minimal state transitions.

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  ctypes, Classes, SysUtils, Math,
  Floria.Image.Core,
  Floria.Font,
  Floria.Canvas.Blend,
  Floria.Canvas.Filter,
  Floria.Path.Clipper.Core,
  Floria.Path.Ops,
  Floria.Text.Paragraph,
  Floria.DisplayList,
  Floria.DisplayList.Clip,
  Floria.GL,
  Floria.GPU.Atlas,
  Floria.GPU.Batch,
  Floria.GPU.Shaders,
  Floria.GPU.Tessellator,
  Floria.GPU.Context;

type
  // ---------------------------------------------------------------------------
  // TFloriaGPURenderer
  // ---------------------------------------------------------------------------
  TFloriaGPURenderer = class(TFloriaDisplayListReceiver)
  private
    FGL                       : TGLEngine;
    FContext                  : TFloriaGPUContext;
    FAutoSwapBuffers          : Boolean;
    FAtlas                    : TFloriaGPUAtlas;
    FBatch                    : TFloriaRenderBatch;
    FPipelines                : TFloriaGPUPipelineManager;
    FClipChain                : TFloriaClipChain;
    FTessellator              : TFloriaGPUTessellator;
    FDirectTessellationEnabled: Boolean;
    FCurrentAlpha             : Double;
    FBlendMode                : TFloriaBlendMode;
    FViewportW                : Integer;
    FViewportH                : Integer;
    FInFrame                  : Boolean;

    procedure ApplyBlendMode(AMode: TFloriaBlendMode);
  public
    constructor Create(gl: TGLEngine = nil); overload;
    constructor Create(AContext: TFloriaGPUContext); overload;
    destructor Destroy(); override;

    // Frame Lifecycle
    procedure BeginFrame(AWidth, AHeight: Integer);
    procedure EndFrame();
    procedure Flush();

    // IFloriaDisplayListReceiver Implementation
    procedure OnSave(); override;
    procedure OnRestore(); override;
    procedure OnTransform(const AMatrix: TFloriaMatrix2D); override;
    procedure OnPushClipRect(const ARect: TRectD; AAntiAlias: Boolean); override;
    procedure OnPushClipRoundedRect(const ARect: TRectD; ARadiusX, ARadiusY: Double; AAntiAlias: Boolean); override; overload;
    procedure OnPushClipRoundedRect(const ARect: TRectD; const ARadii: TFloriaClipCornerRadii; AAntiAlias: Boolean); overload;
    procedure OnPopClip(); override;
    procedure OnSetAlpha(AAlpha: Double); override;
    procedure OnSetBlendMode(AMode: TFloriaBlendMode); override;
    procedure OnClear(const AColor: TBgraPixel); override;
    procedure OnDrawRect(const ARect: TRectD; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double); override;
    procedure OnDrawRoundedRect(const ARect: TRectD; ARadiusX, ARadiusY: Double; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double); override;
    procedure OnDrawCircle(ACenterX, ACenterY, ARadius: Double; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double); override;
    procedure OnDrawLine(AX1, AY1, AX2, AY2: Double; const AColor: TBgraPixel; AStrokeWidth: Double); override;
    procedure OnDrawPath(APath: TFloriaPath; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double; AFillRule: TFillRule); override;
    procedure OnDrawShadow(const ARect: TRectD; ARadius: Double; const AParams: TFloriaShadowParams); override;
    procedure OnDrawBorder(const ARect: TRectD; const AParams: TFloriaBorderParams); override;
    procedure OnDrawLinearGradient(const ARect: TRectD; const AP1, AP2: TPointD; const AStops: TFloriaGradientStopArray); override;
    procedure OnDrawText(const AText: string; AX, AY: Double; AFont: TFloriaFont; AFontSize: Double; const AColor: TBgraPixel); override;
    procedure OnDrawParagraph(AParagraph: TFloriaParagraph; AX, AY: Double); override;
    procedure OnDrawImage(AImage: TFloriaImage; const ADstRect, ASrcRect: TRectD; AOpacity: Double); override;
    procedure OnDrawPicture(APicture: TFloriaPicture; AX, AY: Double); override;
    procedure OnSaveLayer(const ABounds: TRectD; AOpacity: Double; AFilter: TFloriaImageFilter; ABlendMode: TFloriaBlendMode); override;
    procedure OnRestoreLayer(); override;

    property Atlas                    : TFloriaGPUAtlas read FAtlas;
    property Batch                    : TFloriaRenderBatch read FBatch;
    property Pipelines                : TFloriaGPUPipelineManager read FPipelines;
    property ClipChain                : TFloriaClipChain read FClipChain;
    property Tessellator              : TFloriaGPUTessellator read FTessellator;
    property DirectTessellationEnabled: Boolean read FDirectTessellationEnabled write FDirectTessellationEnabled;
    property Context                  : TFloriaGPUContext read FContext;
    property AutoSwapBuffers          : Boolean read FAutoSwapBuffers write FAutoSwapBuffers;
    property InFrame                  : Boolean read FInFrame;
  end;

implementation

// -----------------------------------------------------------------------------
// TFloriaGPURenderer Implementation
// -----------------------------------------------------------------------------
constructor TFloriaGPURenderer.Create(gl: TGLEngine = nil);
begin
  inherited Create();
  if Assigned(gl) then
    FGL := gl
  else
    FGL := FloriaGL();

  FContext                   := nil;
  FAutoSwapBuffers           := True;
  FAtlas                     := TFloriaGPUAtlas.Create();
  FBatch                     := TFloriaRenderBatch.Create();
  FPipelines                 := TFloriaGPUPipelineManager.Create();
  FClipChain                 := TFloriaClipChain.Create();
  FTessellator               := TFloriaGPUTessellator.Create();
  FDirectTessellationEnabled := True;
  FCurrentAlpha              := 1.0;
  FBlendMode                 := fbmSrcOver;
  FViewportW                 := 0;
  FViewportH                 := 0;
  FInFrame                   := False;
end;

constructor TFloriaGPURenderer.Create(AContext: TFloriaGPUContext);
begin
  if Assigned(AContext) then
    Create(AContext.GL)
  else
    Create(TGLEngine(nil));

  FContext := AContext;
end;

destructor TFloriaGPURenderer.Destroy();
begin
  if Assigned(FTessellator) then FreeAndNil(FTessellator);
  if Assigned(FClipChain) then FreeAndNil(FClipChain);
  if Assigned(FPipelines) then FreeAndNil(FPipelines);
  if Assigned(FBatch) then FreeAndNil(FBatch);
  if Assigned(FAtlas) then FreeAndNil(FAtlas);
  inherited Destroy();
end;

procedure TFloriaGPURenderer.BeginFrame(AWidth, AHeight: Integer);
begin
  FViewportW := AWidth;
  FViewportH := AHeight;
  FInFrame   := True;
  FBatch.Clear();
  FClipChain.Clear();
  FCurrentAlpha := 1.0;
  FBlendMode    := fbmSrcOver;

  if Assigned(FContext) and not FContext.IsCurrent() then
    FContext.MakeCurrent();

  if FGL.Available then
  begin
    FGL.Disable(GL_SCISSOR_TEST);
    FGL.Viewport(0, 0, AWidth, AHeight);
    FPipelines.EnsureInitialized(FGL);
  end;
end;

procedure TFloriaGPURenderer.EndFrame();
begin
  Flush();
  if Assigned(FContext) and FAutoSwapBuffers and not FContext.IsOffscreen then
    FContext.SwapBuffers();
  FInFrame := False;
end;

procedure TFloriaGPURenderer.ApplyBlendMode(AMode: TFloriaBlendMode);
begin
  if not FGL.Available then Exit;
  case AMode of
    fbmSrc:
      FGL.BlendFuncSeparate(GL_ONE, GL_ZERO, GL_ONE, GL_ZERO);
    fbmSrcOver:
      FGL.BlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
    fbmDstOver:
      FGL.BlendFuncSeparate(GL_ONE_MINUS_DST_ALPHA, GL_ONE, GL_ONE_MINUS_DST_ALPHA, GL_ONE);
    fbmPlus:
      FGL.BlendFuncSeparate(GL_ONE, GL_ONE, GL_ONE, GL_ONE);
    fbmModulate, fbmMultiply:
      FGL.BlendFuncSeparate(GL_DST_COLOR, GL_ZERO, GL_DST_ALPHA, GL_ZERO);
    fbmScreen:
      FGL.BlendFuncSeparate(GL_ONE, GL_ONE_MINUS_SRC_COLOR, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
  else
    FGL.BlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
  end;
end;

procedure TFloriaGPURenderer.Flush();
var
  I: Integer;
  DC: TFloriaGPUDrawCall;
  Prog, LastProg: TFloriaGPUShaderProgram;
  ClipItems: TFloriaGPUClipItemArray;
  ClipCount: Integer;
  LastClipIndex: Integer;
  Stride: cint;
begin
  if not FGL.Available or (FBatch.VertexCount = 0) then Exit;

  // 1. Sync Texture Atlas to GPU
  FAtlas.SyncToGPU(FGL);

  // 2. Upload vertex data into VBO
  FBatch.UploadToVBO(FGL);

  // 3. Setup common GL state
  FGL.Enable(GL_BLEND);
  FGL.Disable(GL_DEPTH_TEST);
  FGL.Disable(GL_CULL_FACE);

  // 4. Bind VBO and configure attribute pointers
  FGL.BindBuffer(GL_ARRAY_BUFFER, FBatch.VBO);
  Stride := SizeOf(TFloriaGPUVertex);

  LastClipIndex := -999;
  LastProg := nil;

  // 5. Execute each batched draw call
  for I := 0 to FBatch.DrawCallCount - 1 do
  begin
    DC := FBatch.DrawCalls[I];
    Prog := FPipelines.GetProgram(DC.BatchType);
    if not Assigned(Prog) or not Prog.Linked then Continue;

    Prog.Bind(FGL);
    Prog.SetViewport(FGL, FViewportW, FViewportH);

    if (DC.ClipIndex <> LastClipIndex) or (Prog <> LastProg) then
    begin
      ClipCount := FClipChain.PackGPUUniformsForNode(DC.ClipIndex, ClipItems);
      Prog.UploadClipChain(FGL, ClipItems, ClipCount);
      LastClipIndex := DC.ClipIndex;
      LastProg := Prog;
    end;

    Prog.SetupVertexPointers(FGL);

    ApplyBlendMode(DC.BlendMode);

    if DC.TextureID <> 0 then
    begin
      FGL.ActiveTexture(GL_TEXTURE0);
      FGL.BindTexture(GL_TEXTURE_2D, DC.TextureID);
      Prog.SetTextureUnit(FGL, 0);
    end;

    FGL.DrawArrays(GL_TRIANGLES, DC.StartIndex, DC.VertexCount);
  end;

  FGL.BindBuffer(GL_ARRAY_BUFFER, 0);
  FGL.UseProgram(0);
  FBatch.Clear();
end;

procedure TFloriaGPURenderer.OnSave();
begin
  // Transforms and state managed via DisplayOp matrix flattening
end;

procedure TFloriaGPURenderer.OnRestore();
begin
end;

procedure TFloriaGPURenderer.OnTransform(const AMatrix: TFloriaMatrix2D);
begin
end;

procedure TFloriaGPURenderer.OnPushClipRect(const ARect: TRectD; AAntiAlias: Boolean);
begin
  FClipChain.PushClipRect(ARect, AAntiAlias);
end;

procedure TFloriaGPURenderer.OnPushClipRoundedRect(const ARect: TRectD; ARadiusX, ARadiusY: Double; AAntiAlias: Boolean);
begin
  FClipChain.PushClipRoundedRect(ARect, ARadiusX, ARadiusY, AAntiAlias);
end;

procedure TFloriaGPURenderer.OnPushClipRoundedRect(const ARect: TRectD; const ARadii: TFloriaClipCornerRadii; AAntiAlias: Boolean);
begin
  FClipChain.PushClipRoundedRect(ARect, ARadii, TFloriaMatrix2D.Identity(), AAntiAlias);
end;

procedure TFloriaGPURenderer.OnPopClip();
begin
  FClipChain.PopClip();
end;

procedure TFloriaGPURenderer.OnSetAlpha(AAlpha: Double);
begin
  FCurrentAlpha := Max(0.0, Min(1.0, AAlpha));
end;

procedure TFloriaGPURenderer.OnSetBlendMode(AMode: TFloriaBlendMode);
begin
  FBlendMode := AMode;
end;

procedure TFloriaGPURenderer.OnClear(const AColor: TBgraPixel);
begin
  if FGL.Available then
  begin
    FGL.ClearColor(AColor.R / 255.0, AColor.G / 255.0, AColor.B / 255.0, AColor.A / 255.0);
    FGL.Clear(GL_COLOR_BUFFER_BIT);
  end;
end;

procedure TFloriaGPURenderer.OnDrawRect(const ARect: TRectD; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double);
begin
  if (AStrokeWidth <= 0.0) or (AStrokeColor.A = 0) then
    FBatch.EmitSolidRect(ARect, AFillColor, FBlendMode, FClipChain.CurrentNode)
  else
    FBatch.EmitRoundedRect(ARect, TFloriaClipCornerRadii.Zero(), AFillColor, AStrokeColor, AStrokeWidth, FBlendMode, FClipChain.CurrentNode);
end;

procedure TFloriaGPURenderer.OnDrawRoundedRect(const ARect: TRectD; ARadiusX, ARadiusY: Double; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double);
begin
  FBatch.EmitRoundedRect(ARect, TFloriaClipCornerRadii.Rounded(ARadiusX, ARadiusY), AFillColor, AStrokeColor, AStrokeWidth, FBlendMode, FClipChain.CurrentNode);
end;

procedure TFloriaGPURenderer.OnDrawCircle(ACenterX, ACenterY, ARadius: Double; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double);
var
  R: TRectD;
begin
  R.Left   := ACenterX - ARadius;
  R.Top    := ACenterY - ARadius;
  R.Right  := ACenterX + ARadius;
  R.Bottom := ACenterY + ARadius;
  FBatch.EmitRoundedRect(R, TFloriaClipCornerRadii.Uniform(ARadius), AFillColor, AStrokeColor, AStrokeWidth, FBlendMode, FClipChain.CurrentNode);
end;

procedure TFloriaGPURenderer.OnDrawLine(AX1, AY1, AX2, AY2: Double; const AColor: TBgraPixel; AStrokeWidth: Double);
var
  R: TRectD;
  LineMesh: TFloriaTessMesh;
begin
  if AColor.A = 0 then Exit;

  // Axis-aligned lines as thin rects
  if Abs(AY1 - AY2) < 1e-4 then
  begin
    R := RectD(Min(AX1, AX2), AY1 - AStrokeWidth * 0.5, Max(AX1, AX2), AY1 + AStrokeWidth * 0.5);
    FBatch.EmitSolidRect(R, AColor, FBlendMode, FClipChain.CurrentNode);
  end
  else if Abs(AX1 - AX2) < 1e-4 then
  begin
    R := RectD(AX1 - AStrokeWidth * 0.5, Min(AY1, AY2), AX1 + AStrokeWidth * 0.5, Max(AY1, AY2));
    FBatch.EmitSolidRect(R, AColor, FBlendMode, FClipChain.CurrentNode);
  end
  else if FDirectTessellationEnabled then
  begin
    LineMesh.Clear();
    FTessellator.TessellateLine(PointD(AX1, AY1), PointD(AX2, AY2), AStrokeWidth, True, LineMesh);
    if LineMesh.IndexCount > 0 then
      FBatch.EmitPathMesh(LineMesh, AColor, FBlendMode, FClipChain.CurrentNode);
  end;
end;

procedure TFloriaGPURenderer.OnDrawPath(APath: TFloriaPath; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double; AFillRule: TFillRule);
var
  Alloc: TFloriaAtlasAlloc;
  TexRect: TRectD;
  FillMesh, StrokeMesh: TFloriaTessMesh;
  Handled: Boolean;
begin
  if not Assigned(APath) or APath.IsEmpty then Exit;

  Handled := False;

  if FDirectTessellationEnabled then
  begin
    // 1. Direct GPU Fill Tessellation
    if AFillColor.A > 0 then
    begin
      FillMesh.Clear();
      FTessellator.TessellateFill(APath, FillMesh, fpfrNonZero, True);
      if FillMesh.IndexCount > 0 then
      begin
        FBatch.EmitPathMesh(FillMesh, AFillColor, FBlendMode, FClipChain.CurrentNode);
        Handled := True;
      end;
    end;

    // 2. Direct GPU Stroke Tessellation
    if (AStrokeColor.A > 0) and (AStrokeWidth > 0.0) then
    begin
      StrokeMesh.Clear();
      FTessellator.TessellateStroke(APath, AStrokeWidth, StrokeMesh, fpjtRound, fpetRound, 4.0, True);
      if StrokeMesh.IndexCount > 0 then
      begin
        FBatch.EmitPathMesh(StrokeMesh, AStrokeColor, FBlendMode, FClipChain.CurrentNode);
        Handled := True;
      end;
    end;
  end;

  if not Handled then
  begin
    // Fallback Blob Rasterizer: renders path into GPU texture atlas via AggPas
    if FAtlas.RasterizePath(APath, AFillColor, AStrokeColor, AStrokeWidth, AFillRule, Alloc) then
    begin
      TexRect.Left   := Alloc.U1;
      TexRect.Top    := Alloc.V1;
      TexRect.Right  := Alloc.U2;
      TexRect.Bottom := Alloc.V2;
      FBatch.EmitTexturedRect(APath.Bounds, TexRect, FAtlas.Pages[Alloc.PageIndex].TextureID, FCurrentAlpha, FBlendMode, FClipChain.CurrentNode);
    end;
  end;
end;

procedure TFloriaGPURenderer.OnDrawShadow(const ARect: TRectD; ARadius: Double; const AParams: TFloriaShadowParams);
begin
  FBatch.EmitBoxShadow(ARect, ARadius, AParams, FBlendMode, FClipChain.CurrentNode);
end;

procedure TFloriaGPURenderer.OnDrawBorder(const ARect: TRectD; const AParams: TFloriaBorderParams);
begin
  FBatch.EmitRoundedRect(ARect, TFloriaClipCornerRadii.Rounded(AParams.RadiusX, AParams.RadiusY),
                         BgraPixel(0, 0, 0, 0), AParams.Top.Color, AParams.Top.Width,
                         FBlendMode, FClipChain.CurrentNode);
end;

procedure TFloriaGPURenderer.OnDrawLinearGradient(const ARect: TRectD; const AP1, AP2: TPointD; const AStops: TFloriaGradientStopArray);
var
  C1, C2: TBgraPixel;
  AngleDeg: Double;
  DX, DY: Double;
begin
  if Length(AStops) >= 2 then
  begin
    C1 := AStops[0].Color;
    C2 := AStops[High(AStops)].Color;
  end
  else
  begin
    C1 := BgraPixel(255, 255, 255, 255);
    C2 := BgraPixel(0, 0, 0, 255);
  end;

  DX := AP2.X - AP1.X;
  DY := AP2.Y - AP1.Y;
  AngleDeg := RadToDeg(ArcTan2(DY, DX));

  FBatch.EmitLinearGradient(ARect, C1, C2, AngleDeg, FBlendMode, FClipChain.CurrentNode);
end;

procedure TFloriaGPURenderer.OnDrawText(const AText: string; AX, AY: Double; AFont: TFloriaFont; AFontSize: Double; const AColor: TBgraPixel);
var
  Alloc: TFloriaAtlasAlloc;
  DstRect, TexRect: TRectD;
  Font: TFloriaFont;
  Page: TFloriaAtlasPage;
begin
  if (AText = '') or (AColor.A = 0) then Exit;
  Font := AFont;
  if not Assigned(Font) then Font := FloriaGetSystemFont();

  if FAtlas.RasterizeText(AText, Font, Alloc) then
  begin
    Page := FAtlas.Pages[Alloc.PageIndex];
    if (Page.TextureID = 0) and FGL.Available then
      Page.SyncToGPU(FGL);

    TexRect.Left   := Alloc.U1;
    TexRect.Top    := Alloc.V1;
    TexRect.Right  := Alloc.U2;
    TexRect.Bottom := Alloc.V2;

    DstRect.Left   := Round(AX - 2.0);
    DstRect.Top    := Round(AY) - Round(Font.Ascent) - 2.0;
    DstRect.Right  := DstRect.Left + Alloc.Rect.Width;
    DstRect.Bottom := DstRect.Top + Alloc.Rect.Height;

    FBatch.EmitGlyphRect(DstRect, TexRect, Page.TextureID,
                         AColor, FCurrentAlpha, FBlendMode, FClipChain.CurrentNode);
  end;
end;

procedure TFloriaGPURenderer.OnDrawParagraph(AParagraph: TFloriaParagraph; AX, AY: Double);
begin
end;

procedure TFloriaGPURenderer.OnDrawImage(AImage: TFloriaImage; const ADstRect, ASrcRect: TRectD; AOpacity: Double);
var
  Alloc: TFloriaAtlasAlloc;
  TexRect: TRectD;
  Page: TFloriaAtlasPage;
begin
  if not Assigned(AImage) then Exit;

  if FAtlas.AddImagePart(AImage, ASrcRect, Alloc) then
  begin
    Page := FAtlas.Pages[Alloc.PageIndex];
    if (Page.TextureID = 0) and FGL.Available then
      Page.SyncToGPU(FGL);

    TexRect.Left   := Alloc.U1;
    TexRect.Top    := Alloc.V1;
    TexRect.Right  := Alloc.U2;
    TexRect.Bottom := Alloc.V2;
    FBatch.EmitTexturedRect(ADstRect, TexRect, Page.TextureID,
                            AOpacity * FCurrentAlpha, FBlendMode, FClipChain.CurrentNode);
  end;
end;

procedure TFloriaGPURenderer.OnDrawPicture(APicture: TFloriaPicture; AX, AY: Double);
begin
  if Assigned(APicture) then
    APicture.Playback(Self);
end;

procedure TFloriaGPURenderer.OnSaveLayer(const ABounds: TRectD; AOpacity: Double; AFilter: TFloriaImageFilter; ABlendMode: TFloriaBlendMode);
begin
end;

procedure TFloriaGPURenderer.OnRestoreLayer();
begin
end;

end.
