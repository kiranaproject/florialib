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
  Floria.Errors,
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
    FCurrentMatrix            : TFloriaMatrix2D;
    FMatrixStack              : array of TFloriaMatrix2D;
    FMatrixDepth              : Integer;
    FAlphaStack               : array of Double;
    FAlphaDepth               : Integer;
    FBlendStack               : array of TFloriaBlendMode;
    FBlendDepth               : Integer;
    FViewportW                : Integer;
    FViewportH                : Integer;
    FInFrame                  : Boolean;

    procedure ApplyBlendMode(AMode: TFloriaBlendMode);
    function CurrentScale(): Double;
    function TransformRect(const ARect: TRectD): TRectD;
    function TransformPoint(const APt: TPointD): TPointD;
    function TransformPath(APath: TFloriaPath): TFloriaPath;
    function ApplyAlpha(const AColor: TBgraPixel): TBgraPixel;
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
    procedure OnDrawTextRotated(const AText: string; AX, AY: Double; AFont: TFloriaFont; AFontSize: Double; AAngleDeg: Double; const AColor: TBgraPixel);
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
  FCurrentMatrix             := TFloriaMatrix2D.Identity();
  FMatrixDepth               := 0;
  FAlphaDepth                := 0;
  FBlendDepth                := 0;
  SetLength(FMatrixStack, 16);
  SetLength(FAlphaStack, 16);
  SetLength(FBlendStack, 16);
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
  FCurrentMatrix := TFloriaMatrix2D.Identity();
  FMatrixDepth  := 0;
  FAlphaDepth   := 0;
  FBlendDepth   := 0;

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

function TFloriaGPURenderer.CurrentScale(): Double;
var
  Det: Double;
begin
  Det := FCurrentMatrix.Determinant();
  Result := Sqrt(Abs(Det));
  if Result < 1e-6 then
    Result := 1.0;
end;

function TFloriaGPURenderer.TransformRect(const ARect: TRectD): TRectD;
begin
  Result := FCurrentMatrix.TransformRect(ARect);
end;

function TFloriaGPURenderer.TransformPoint(const APt: TPointD): TPointD;
begin
  Result := FCurrentMatrix.TransformPoint(APt);
end;

function TFloriaGPURenderer.TransformPath(APath: TFloriaPath): TFloriaPath;
var
  Paths: TPathsD;
  I, J: Integer;
begin
  Result := nil;
  if not Assigned(APath) then Exit;

  Paths := APath.ToPathsD();
  for I := 0 to High(Paths) do
    for J := 0 to High(Paths[I]) do
      Paths[I][J] := FCurrentMatrix.TransformPoint(Paths[I][J]);

  Result := TFloriaPath.Create();
  try
    Result.FromPathsD(Paths);
  except
    Result.Free();
    raise;
  end;
end;

function TFloriaGPURenderer.ApplyAlpha(const AColor: TBgraPixel): TBgraPixel;
var
  A: Integer;
begin
  Result := AColor;
  A := Round(AColor.A * FCurrentAlpha);
  if A < 0 then A := 0;
  if A > 255 then A := 255;
  Result.A := Byte(A);
end;

procedure TFloriaGPURenderer.OnSave();
begin
  if FMatrixDepth >= Length(FMatrixStack) then
  begin
    if Length(FMatrixStack) = 0 then
      SetLength(FMatrixStack, 16)
    else
      SetLength(FMatrixStack, Length(FMatrixStack) * 2);
  end;
  FMatrixStack[FMatrixDepth] := FCurrentMatrix;
  Inc(FMatrixDepth);

  if FAlphaDepth >= Length(FAlphaStack) then
  begin
    if Length(FAlphaStack) = 0 then
      SetLength(FAlphaStack, 16)
    else
      SetLength(FAlphaStack, Length(FAlphaStack) * 2);
  end;
  FAlphaStack[FAlphaDepth] := FCurrentAlpha;
  Inc(FAlphaDepth);

  if FBlendDepth >= Length(FBlendStack) then
  begin
    if Length(FBlendStack) = 0 then
      SetLength(FBlendStack, 16)
    else
      SetLength(FBlendStack, Length(FBlendStack) * 2);
  end;
  FBlendStack[FBlendDepth] := FBlendMode;
  Inc(FBlendDepth);
end;

procedure TFloriaGPURenderer.OnRestore();
begin
  if FMatrixDepth > 0 then
  begin
    Dec(FMatrixDepth);
    FCurrentMatrix := FMatrixStack[FMatrixDepth];
  end;

  if FAlphaDepth > 0 then
  begin
    Dec(FAlphaDepth);
    FCurrentAlpha := FAlphaStack[FAlphaDepth];
  end;

  if FBlendDepth > 0 then
  begin
    Dec(FBlendDepth);
    FBlendMode := FBlendStack[FBlendDepth];
  end;
end;

procedure TFloriaGPURenderer.OnTransform(const AMatrix: TFloriaMatrix2D);
begin
  FCurrentMatrix := AMatrix;
end;

procedure TFloriaGPURenderer.OnPushClipRect(const ARect: TRectD; AAntiAlias: Boolean);
begin
  FClipChain.PushClipRect(ARect, FCurrentMatrix, AAntiAlias);
end;

procedure TFloriaGPURenderer.OnPushClipRoundedRect(const ARect: TRectD; ARadiusX, ARadiusY: Double; AAntiAlias: Boolean);
begin
  FClipChain.PushClipRoundedRect(ARect,
    TFloriaClipCornerRadii.Rounded(ARadiusX, ARadiusY),
    FCurrentMatrix, AAntiAlias);
end;

procedure TFloriaGPURenderer.OnPushClipRoundedRect(const ARect: TRectD; const ARadii: TFloriaClipCornerRadii; AAntiAlias: Boolean);
begin
  FClipChain.PushClipRoundedRect(ARect, ARadii, FCurrentMatrix, AAntiAlias);
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
var
  R: TRectD;
  FillColor, StrokeColor: TBgraPixel;
  Scale: Double;
begin
  R := TransformRect(ARect);
  FillColor := ApplyAlpha(AFillColor);
  StrokeColor := ApplyAlpha(AStrokeColor);
  Scale := CurrentScale();

  if (AStrokeWidth <= 0.0) or (StrokeColor.A = 0) then
    FBatch.EmitSolidRect(R, FillColor, FBlendMode, FClipChain.CurrentNode)
  else
    FBatch.EmitRoundedRect(R, TFloriaClipCornerRadii.Zero(),
      FillColor, StrokeColor, AStrokeWidth * Scale,
      FBlendMode, FClipChain.CurrentNode);
end;

procedure TFloriaGPURenderer.OnDrawRoundedRect(const ARect: TRectD; ARadiusX, ARadiusY: Double; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double);
var
  R: TRectD;
  Scale: Double;
begin
  R := TransformRect(ARect);
  Scale := CurrentScale();
  FBatch.EmitRoundedRect(R,
    TFloriaClipCornerRadii.Rounded(ARadiusX * Scale, ARadiusY * Scale),
    ApplyAlpha(AFillColor), ApplyAlpha(AStrokeColor), AStrokeWidth * Scale,
    FBlendMode, FClipChain.CurrentNode);
end;

procedure TFloriaGPURenderer.OnDrawCircle(ACenterX, ACenterY, ARadius: Double; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double);
var
  R: TRectD;
  Scale: Double;
begin
  R := TransformRect(RectD(ACenterX - ARadius, ACenterY - ARadius,
                           ACenterX + ARadius, ACenterY + ARadius));
  Scale := CurrentScale();
  FBatch.EmitRoundedRect(R,
    TFloriaClipCornerRadii.Uniform(ARadius * Scale),
    ApplyAlpha(AFillColor), ApplyAlpha(AStrokeColor), AStrokeWidth * Scale,
    FBlendMode, FClipChain.CurrentNode);
end;

procedure TFloriaGPURenderer.OnDrawLine(AX1, AY1, AX2, AY2: Double; const AColor: TBgraPixel; AStrokeWidth: Double);
var
  P1, P2: TPointD;
  Color: TBgraPixel;
  Scale: Double;
begin
  Color := ApplyAlpha(AColor);
  if (Color.A = 0) or (AStrokeWidth <= 0.0) then Exit;

  P1 := TransformPoint(PointD(AX1, AY1));
  P2 := TransformPoint(PointD(AX2, AY2));
  Scale := CurrentScale();

  // Analytical SDF capsule line with subpixel antialiasing and round caps.
  FBatch.EmitCapsuleLine(P1, P2, AStrokeWidth * Scale, Color,
    FBlendMode, FClipChain.CurrentNode);
end;

procedure TFloriaGPURenderer.OnDrawPath(APath: TFloriaPath; const AFillColor, AStrokeColor: TBgraPixel; AStrokeWidth: Double; AFillRule: TFillRule);
var
  Alloc: TFloriaAtlasAlloc;
  TexRect: TRectD;
  FillMesh, StrokeMesh: TFloriaTessMesh;
  Handled, OwnsPath: Boolean;
  DrawPath: TFloriaPath;
  FillColor, StrokeColor: TBgraPixel;
  Scale: Double;
begin
  if not Assigned(APath) or APath.IsEmpty then Exit;

  DrawPath := APath;
  OwnsPath := False;
  if not FCurrentMatrix.IsIdentity() then
  begin
    DrawPath := TransformPath(APath);
    OwnsPath := True;
  end;

  try
    FillColor := ApplyAlpha(AFillColor);
    StrokeColor := ApplyAlpha(AStrokeColor);
    Scale := CurrentScale();
    Handled := False;

    if FDirectTessellationEnabled then
    begin
      // 1. Direct GPU Fill Tessellation
      if FillColor.A > 0 then
      begin
        FillMesh.Clear();
        FTessellator.TessellateFill(DrawPath, FillMesh, fpfrNonZero, True);
        if FillMesh.IndexCount > 0 then
        begin
          FBatch.EmitPathMesh(FillMesh, FillColor, FBlendMode, FClipChain.CurrentNode);
          Handled := True;
        end;
      end;

      // 2. Direct GPU Stroke Tessellation
      if (StrokeColor.A > 0) and (AStrokeWidth > 0.0) then
      begin
        StrokeMesh.Clear();
        FTessellator.TessellateStroke(DrawPath, AStrokeWidth * Scale, StrokeMesh, fpjtRound, fpetRound, 4.0, True);
        if StrokeMesh.IndexCount > 0 then
        begin
          FBatch.EmitPathMesh(StrokeMesh, StrokeColor, FBlendMode, FClipChain.CurrentNode);
          Handled := True;
        end;
      end;
    end;

    if not Handled then
    begin
      // Fallback Blob Rasterizer: renders path into GPU texture atlas via AggPas
      if FAtlas.RasterizePath(DrawPath, FillColor, StrokeColor, AStrokeWidth * Scale, AFillRule, Alloc) then
      begin
        TexRect.Left   := Alloc.U1;
        TexRect.Top    := Alloc.V1;
        TexRect.Right  := Alloc.U2;
        TexRect.Bottom := Alloc.V2;
        FBatch.EmitTexturedRect(DrawPath.Bounds, TexRect, FAtlas.Pages[Alloc.PageIndex].TextureID,
          1.0, FBlendMode, FClipChain.CurrentNode);
      end;
    end;
  finally
    if OwnsPath then
      DrawPath.Free();
  end;
end;

procedure TFloriaGPURenderer.OnDrawShadow(const ARect: TRectD; ARadius: Double; const AParams: TFloriaShadowParams);
var
  R: TRectD;
  Params: TFloriaShadowParams;
  Scale: Double;
begin
  R := TransformRect(ARect);
  Scale := CurrentScale();
  Params := AParams;
  Params.OffsetX := Params.OffsetX * Scale;
  Params.OffsetY := Params.OffsetY * Scale;
  Params.BlurRadius := Params.BlurRadius * Scale;
  Params.SpreadRadius := Params.SpreadRadius * Scale;
  Params.Color := ApplyAlpha(Params.Color);
  FBatch.EmitBoxShadow(R, ARadius * Scale, Params, FBlendMode, FClipChain.CurrentNode);
end;

procedure TFloriaGPURenderer.OnDrawBorder(const ARect: TRectD; const AParams: TFloriaBorderParams);
var
  R: TRectD;
  Params: TFloriaBorderParams;
  Scale: Double;
begin
  R := TransformRect(ARect);
  Scale := CurrentScale();
  Params := AParams;
  Params.RadiusX := Params.RadiusX * Scale;
  Params.RadiusY := Params.RadiusY * Scale;
  Params.Top.Width := Params.Top.Width * Scale;
  Params.Right.Width := Params.Right.Width * Scale;
  Params.Bottom.Width := Params.Bottom.Width * Scale;
  Params.Left.Width := Params.Left.Width * Scale;
  Params.Top.Color := ApplyAlpha(Params.Top.Color);
  Params.Right.Color := ApplyAlpha(Params.Right.Color);
  Params.Bottom.Color := ApplyAlpha(Params.Bottom.Color);
  Params.Left.Color := ApplyAlpha(Params.Left.Color);
  FBatch.EmitRoundedRect(R, TFloriaClipCornerRadii.Rounded(Params.RadiusX, Params.RadiusY),
    BgraPixel(0, 0, 0, 0), Params.Top.Color, Params.Top.Width,
    FBlendMode, FClipChain.CurrentNode);
end;

procedure TFloriaGPURenderer.OnDrawLinearGradient(const ARect: TRectD; const AP1, AP2: TPointD; const AStops: TFloriaGradientStopArray);
var
  C1, C2: TBgraPixel;
  AngleDeg: Double;
  DX, DY: Double;
  R: TRectD;
  P1, P2: TPointD;
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

  R := TransformRect(ARect);
  P1 := TransformPoint(AP1);
  P2 := TransformPoint(AP2);
  C1 := ApplyAlpha(C1);
  C2 := ApplyAlpha(C2);

  DX := P2.X - P1.X;
  DY := P2.Y - P1.Y;
  AngleDeg := RadToDeg(ArcTan2(DY, DX));

  FBatch.EmitLinearGradient(R, C1, C2, AngleDeg, FBlendMode, FClipChain.CurrentNode);
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
    DstRect := TransformRect(DstRect);

    FBatch.EmitGlyphRect(DstRect, TexRect, Page.TextureID,
                         AColor, FCurrentAlpha, FBlendMode, FClipChain.CurrentNode);
  end;
end;

procedure TFloriaGPURenderer.OnDrawTextRotated(const AText: string; AX, AY: Double; AFont: TFloriaFont; AFontSize: Double; AAngleDeg: Double; const AColor: TBgraPixel);
var
  Alloc: TFloriaAtlasAlloc;
  DstRect, TexRect: TRectD;
  Font: TFloriaFont;
  Page: TFloriaAtlasPage;
  PivX, PivY: Double;
  P: TPointD;
begin
  if (AText = '') or (AColor.A = 0) then Exit;
  Font := AFont;
  if not Assigned(Font) then Font := FloriaGetSystemFont();

  if Abs(AAngleDeg) < 0.001 then
  begin
    OnDrawText(AText, AX, AY, Font, AFontSize, AColor);
    Exit;
  end;

  if FAtlas.RasterizeText(AText, Font, Alloc) then
  begin
    Page := FAtlas.Pages[Alloc.PageIndex];
    if (Page.TextureID = 0) and FGL.Available then
      Page.SyncToGPU(FGL);

    TexRect.Left   := Alloc.U1;
    TexRect.Top    := Alloc.V1;
    TexRect.Right  := Alloc.U2;
    TexRect.Bottom := Alloc.V2;

    PivX := Round(AX);
    PivY := Round(AY);

    DstRect.Left   := PivX - 2.0;
    DstRect.Top    := PivY - Round(Font.Ascent) - 2.0;
    DstRect.Right  := DstRect.Left + Alloc.Rect.Width;
    DstRect.Bottom := DstRect.Top + Alloc.Rect.Height;
    DstRect := TransformRect(DstRect);
    P := TransformPoint(PointD(PivX, PivY));
    PivX := P.X;
    PivY := P.Y;

    FBatch.EmitGlyphRectRotated(DstRect, TexRect, PivX, PivY, AAngleDeg, Page.TextureID,
                                AColor, FCurrentAlpha, FBlendMode, FClipChain.CurrentNode);
  end;
end;

procedure TFloriaGPURenderer.OnDrawParagraph(AParagraph: TFloriaParagraph; AX, AY: Double);
begin
  if not Assigned(AParagraph) then Exit;
  raise EFloriaNotSupported.Create(
    'TFloriaGPURenderer does not support paragraph playback yet; ' +
    'use TFloriaCanvasAgg or draw the paragraph runs as text operations');
end;

procedure TFloriaGPURenderer.OnDrawImage(AImage: TFloriaImage; const ADstRect, ASrcRect: TRectD; AOpacity: Double);
var
  Alloc: TFloriaAtlasAlloc;
  TexRect, DstRect: TRectD;
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
    DstRect := TransformRect(ADstRect);
    FBatch.EmitTexturedRect(DstRect, TexRect, Page.TextureID,
                            AOpacity * FCurrentAlpha, FBlendMode, FClipChain.CurrentNode);
  end;
end;

procedure TFloriaGPURenderer.OnDrawPicture(APicture: TFloriaPicture; AX, AY: Double);
var
  SavedMatrix: TFloriaMatrix2D;
  SavedAlpha: Double;
  SavedBlend: TFloriaBlendMode;
  NestedMatrix: TFloriaMatrix2D;
begin
  if not Assigned(APicture) then Exit;

  SavedMatrix := FCurrentMatrix;
  SavedAlpha := FCurrentAlpha;
  SavedBlend := FBlendMode;
  NestedMatrix := FCurrentMatrix.Multiply(TFloriaMatrix2D.Translation(AX, AY));

  try
    APicture.Playback(Self, NestedMatrix, SavedAlpha);
  finally
    FCurrentMatrix := SavedMatrix;
    FCurrentAlpha := SavedAlpha;
    FBlendMode := SavedBlend;
  end;
end;

procedure TFloriaGPURenderer.OnSaveLayer(const ABounds: TRectD; AOpacity: Double; AFilter: TFloriaImageFilter; ABlendMode: TFloriaBlendMode);
begin
  raise EFloriaNotSupported.Create(
    'TFloriaGPURenderer does not support save/restore layers yet; ' +
    'render the layer through TFloriaCanvasAgg until the offscreen path is implemented');
end;

procedure TFloriaGPURenderer.OnRestoreLayer();
begin
  raise EFloriaNotSupported.Create(
    'TFloriaGPURenderer does not support save/restore layers yet');
end;

end.
