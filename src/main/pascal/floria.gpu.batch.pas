unit Floria.GPU.Batch;

// Floria.GPU.Batch
// ================
// Instanced Quad & Vertex Batching Engine for High-Throughput 2D GPU Rendering.
//
// Capabilities:
// - Packs 95% regular UI geometry (rectangles, rounded boxes, drop shadows,
//   borders, linear gradients, textured quads) into GPU vertex arrays.
// - 6 vertices (2 triangles) per quad with analytical SDF parameters.
// - Automatic draw-call batching: coalesces consecutive quads with identical
//   pipeline state (Shader type, Texture ID, Blend mode, Clip index).
// - Direct VBO buffer streaming via glBufferData / glBufferSubData.

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  ctypes, Classes, SysUtils, Math,
  Floria.Image.Core,
  Floria.Canvas.Blend,
  Floria.Path.Clipper.Core,
  Floria.DisplayList,
  Floria.DisplayList.Clip,
  Floria.GL,
  Floria.GPU.Tessellator;

type
  // Batch Shader / Primitive Type
  TFloriaGPUBatchType = (
    gbtSolidQuad,
    gbtTexturedQuad,
    gbtRoundedRect,
    gbtBoxShadow,
    gbtLinearGradient,
    gbtPathMesh,
    gbtCapsuleLine
  );

  // ---------------------------------------------------------------------------
  // TFloriaGPUVertex (std140-friendly 32-byte / 64-byte aligned vertex structure)
  // ---------------------------------------------------------------------------
  TFloriaGPUVertex = packed record
    // Attrib 0: vec2 Position (X, Y)
    PosX, PosY: Single;
    // Attrib 1: vec2 TexCoord (U, V)
    TexU, TexV: Single;
    // Attrib 2: vec4 Primary Color (R, G, B, A in 0.0 .. 1.0)
    ColorR, ColorG, ColorB, ColorA: Single;
    // Attrib 3: vec4 Local Quad Geometry (X, Y, Width, Height)
    LocalX, LocalY, LocalW, LocalH: Single;
    // Attrib 4: vec4 Corner Radii (TopLeft X/Y, TopRight X/Y)
    RadiusTL_X, RadiusTL_Y, RadiusTR_X, RadiusTR_Y: Single;
    // Attrib 5: vec4 Corner Radii (BottomRight X/Y, BottomLeft X/Y)
    RadiusBR_X, RadiusBR_Y, RadiusBL_X, RadiusBL_Y: Single;
    // Attrib 6: vec4 Border Parameters (BorderWidth, BorderR, BorderG, BorderB)
    BorderWidth, BorderR, BorderG, BorderB: Single;
    // Attrib 7: vec4 Extra Parameters (Param0: ClipIndex, Param1: BlurRadius/Angle, Param2: Spread, Param3: Inset)
    ClipIndex, ExtraParam1, ExtraParam2, ExtraParam3: Single;
  end;
  PFloriaGPUVertex = ^TFloriaGPUVertex;

  TFloriaGPUVertexArray = array of TFloriaGPUVertex;

  // ---------------------------------------------------------------------------
  // TFloriaGPUDrawCall
  // ---------------------------------------------------------------------------
  TFloriaGPUDrawCall = record
    BatchType  : TFloriaGPUBatchType;
    TextureID  : Cardinal;
    BlendMode  : TFloriaBlendMode;
    ClipIndex  : Integer;
    StartIndex : Integer;
    VertexCount: Integer;
  end;
  TFloriaGPUDrawCallArray = array of TFloriaGPUDrawCall;

  // ---------------------------------------------------------------------------
  // TFloriaRenderBatch
  // ---------------------------------------------------------------------------
  TFloriaRenderBatch = class
  private
    FVertices      : TFloriaGPUVertexArray;
    FVertexCount   : Integer;
    FVertexCapacity: Integer;
    FDrawCalls     : TFloriaGPUDrawCallArray;
    FDrawCallCount : Integer;
    FVBO           : Cardinal;

    procedure EnsureVertexCapacity(ACount: Integer);
    procedure EnsureDrawCallCapacity();
    function CanMergeWithCurrent(ABatchType: TFloriaGPUBatchType; ATextureID: Cardinal;
                                ABlendMode: TFloriaBlendMode; AClipIndex: Integer): Boolean;
    procedure AppendQuadVertices(const AP1, AP2, AP3, AP4: TFloriaGPUVertex);
  public
    constructor Create();
    destructor Destroy(); override;

    procedure Clear();

    // Quad Primitive Emitters
    procedure EmitSolidRect(const ARect: TRectD; const AColor: TBgraPixel;
                            ABlendMode: TFloriaBlendMode = fbmSrcOver; AClipIndex: Integer = -1);

    procedure EmitTexturedRect(const ARect, ATexRect: TRectD; ATextureID: Cardinal;
                              AOpacity: Double = 1.0; ABlendMode: TFloriaBlendMode = fbmSrcOver;
                              AClipIndex: Integer = -1);

    procedure EmitGlyphRect(const ARect, ATexRect: TRectD; ATextureID: Cardinal;
                            const AColor: TBgraPixel; AOpacity: Double = 1.0;
                            ABlendMode: TFloriaBlendMode = fbmSrcOver; AClipIndex: Integer = -1);

    procedure EmitRoundedRect(const ARect: TRectD; const ARadii: TFloriaClipCornerRadii;
                             const AFillColor: TBgraPixel; const ABorderColor: TBgraPixel;
                             ABorderWidth: Double = 0.0; ABlendMode: TFloriaBlendMode = fbmSrcOver;
                             AClipIndex: Integer = -1);

    procedure EmitBoxShadow(const ARect: TRectD; ARadius: Double; const AShadowParams: TFloriaShadowParams;
                            ABlendMode: TFloriaBlendMode = fbmSrcOver; AClipIndex: Integer = -1);

    procedure EmitLinearGradient(const ARect: TRectD; const AColorStart, AColorEnd: TBgraPixel;
                                 AAngleDeg: Double; ABlendMode: TFloriaBlendMode = fbmSrcOver;
                                 AClipIndex: Integer = -1);

    procedure EmitPathMesh(const AMesh: TFloriaTessMesh; const AColor: TBgraPixel;
                           ABlendMode: TFloriaBlendMode = fbmSrcOver; AClipIndex: Integer = -1);

    procedure EmitCapsuleLine(const AP1, AP2: TPointD; AStrokeWidth: Double;
                             const AColor: TBgraPixel; ABlendMode: TFloriaBlendMode = fbmSrcOver;
                             AClipIndex: Integer = -1);

    // Buffer Synchronization
    procedure UploadToVBO(gl: TGLEngine);

    property Vertices     : TFloriaGPUVertexArray read FVertices;
    property VertexCount  : Integer read FVertexCount;
    property DrawCalls    : TFloriaGPUDrawCallArray read FDrawCalls;
    property DrawCallCount: Integer read FDrawCallCount;
    property VBO          : Cardinal read FVBO;
  end;

implementation

// -----------------------------------------------------------------------------
// TFloriaRenderBatch Implementation
// -----------------------------------------------------------------------------
constructor TFloriaRenderBatch.Create();
begin
  inherited Create();
  FVertexCount    := 0;
  FVertexCapacity := 0;
  SetLength(FVertices, 0);
  FDrawCallCount  := 0;
  SetLength(FDrawCalls, 0);
  FVBO            := 0;
end;

destructor TFloriaRenderBatch.Destroy();
var
  gl: TGLEngine;
begin
  if FVBO <> 0 then
  begin
    gl := FloriaGL();
    if gl.Available and Assigned(gl.DeleteBuffers) then
      gl.DeleteBuffers(1, @FVBO);
    FVBO := 0;
  end;
  SetLength(FVertices, 0);
  SetLength(FDrawCalls, 0);
  inherited Destroy();
end;

procedure TFloriaRenderBatch.Clear();
begin
  FVertexCount   := 0;
  FDrawCallCount := 0;
end;

procedure TFloriaRenderBatch.EnsureVertexCapacity(ACount: Integer);
begin
  if FVertexCount + ACount > FVertexCapacity then
  begin
    if FVertexCapacity = 0 then
      FVertexCapacity := 256
    else
      FVertexCapacity := FVertexCapacity * 2;
    if FVertexCapacity < FVertexCount + ACount then
      FVertexCapacity := FVertexCount + ACount;
    SetLength(FVertices, FVertexCapacity);
  end;
end;

procedure TFloriaRenderBatch.EnsureDrawCallCapacity();
begin
  if FDrawCallCount >= Length(FDrawCalls) then
  begin
    if Length(FDrawCalls) = 0 then
      SetLength(FDrawCalls, 16)
    else
      SetLength(FDrawCalls, Length(FDrawCalls) * 2);
  end;
end;

function TFloriaRenderBatch.CanMergeWithCurrent(ABatchType: TFloriaGPUBatchType; ATextureID: Cardinal;
                                               ABlendMode: TFloriaBlendMode; AClipIndex: Integer): Boolean;
begin
  if FDrawCallCount = 0 then Exit(False);
  with FDrawCalls[FDrawCallCount - 1] do
  begin
    Result := (BatchType = ABatchType) and
              (TextureID = ATextureID) and
              (BlendMode = ABlendMode) and
              (ClipIndex = AClipIndex);
  end;
end;

procedure TFloriaRenderBatch.AppendQuadVertices(const AP1, AP2, AP3, AP4: TFloriaGPUVertex);
begin
  EnsureVertexCapacity(6);
  // Triangle 1: P1, P2, P3
  FVertices[FVertexCount + 0] := AP1;
  FVertices[FVertexCount + 1] := AP2;
  FVertices[FVertexCount + 2] := AP3;
  // Triangle 2: P3, AP4, P1
  FVertices[FVertexCount + 3] := AP3;
  FVertices[FVertexCount + 4] := AP4;
  FVertices[FVertexCount + 5] := AP1;
  Inc(FVertexCount, 6);
end;

procedure TFloriaRenderBatch.EmitSolidRect(const ARect: TRectD; const AColor: TBgraPixel;
                                          ABlendMode: TFloriaBlendMode = fbmSrcOver; AClipIndex: Integer = -1);
var
  V: array[0..3] of TFloriaGPUVertex;
  I: Integer;
begin
  if ARect.IsEmpty then Exit;

  // Prepare vertices
  FillChar(V, SizeOf(V), 0);
  for I := 0 to 3 do
  begin
    V[I].ColorR    := AColor.R / 255.0;
    V[I].ColorG    := AColor.G / 255.0;
    V[I].ColorB    := AColor.B / 255.0;
    V[I].ColorA    := AColor.A / 255.0;
    V[I].LocalX    := ARect.Left;
    V[I].LocalY    := ARect.Top;
    V[I].LocalW    := ARect.Width;
    V[I].LocalH    := ARect.Height;
    V[I].ClipIndex := AClipIndex;
  end;

  // Top-Left
  V[0].PosX := ARect.Left;  V[0].PosY := ARect.Top;
  // Top-Right
  V[1].PosX := ARect.Right; V[1].PosY := ARect.Top;
  // Bottom-Right
  V[2].PosX := ARect.Right; V[2].PosY := ARect.Bottom;
  // Bottom-Left
  V[3].PosX := ARect.Left;  V[3].PosY := ARect.Bottom;

  if CanMergeWithCurrent(gbtSolidQuad, 0, ABlendMode, AClipIndex) then
    Inc(FDrawCalls[FDrawCallCount - 1].VertexCount, 6)
  else
  begin
    EnsureDrawCallCapacity();
    with FDrawCalls[FDrawCallCount] do
    begin
      BatchType   := gbtSolidQuad;
      TextureID   := 0;
      BlendMode   := ABlendMode;
      ClipIndex   := AClipIndex;
      StartIndex  := FVertexCount;
      VertexCount := 6;
    end;
    Inc(FDrawCallCount);
  end;

  AppendQuadVertices(V[0], V[1], V[2], V[3]);
end;

procedure TFloriaRenderBatch.EmitTexturedRect(const ARect, ATexRect: TRectD; ATextureID: Cardinal;
                                             AOpacity: Double = 1.0; ABlendMode: TFloriaBlendMode = fbmSrcOver;
                                             AClipIndex: Integer = -1);
var
  V: array[0..3] of TFloriaGPUVertex;
  I: Integer;
begin
  if ARect.IsEmpty then Exit;

  FillChar(V, SizeOf(V), 0);
  for I := 0 to 3 do
  begin
    V[I].ColorR    := 1.0;
    V[I].ColorG    := 1.0;
    V[I].ColorB    := 1.0;
    V[I].ColorA    := AOpacity;
    V[I].LocalX    := ARect.Left;
    V[I].LocalY    := ARect.Top;
    V[I].LocalW    := ARect.Width;
    V[I].LocalH    := ARect.Height;
    V[I].ClipIndex := AClipIndex;
  end;

  // Top-Left
  V[0].PosX := ARect.Left;  V[0].PosY := ARect.Top;
  V[0].TexU := ATexRect.Left; V[0].TexV := ATexRect.Top;
  // Top-Right
  V[1].PosX := ARect.Right; V[1].PosY := ARect.Top;
  V[1].TexU := ATexRect.Right; V[1].TexV := ATexRect.Top;
  // Bottom-Right
  V[2].PosX := ARect.Right; V[2].PosY := ARect.Bottom;
  V[2].TexU := ATexRect.Right; V[2].TexV := ATexRect.Bottom;
  // Bottom-Left
  V[3].PosX := ARect.Left;  V[3].PosY := ARect.Bottom;
  V[3].TexU := ATexRect.Left; V[3].TexV := ATexRect.Bottom;

  if CanMergeWithCurrent(gbtTexturedQuad, ATextureID, ABlendMode, AClipIndex) then
    Inc(FDrawCalls[FDrawCallCount - 1].VertexCount, 6)
  else
  begin
    EnsureDrawCallCapacity();
    with FDrawCalls[FDrawCallCount] do
    begin
      BatchType   := gbtTexturedQuad;
      TextureID   := ATextureID;
      BlendMode   := ABlendMode;
      ClipIndex   := AClipIndex;
      StartIndex  := FVertexCount;
      VertexCount := 6;
    end;
    Inc(FDrawCallCount);
  end;

  AppendQuadVertices(V[0], V[1], V[2], V[3]);
end;

procedure TFloriaRenderBatch.EmitGlyphRect(const ARect, ATexRect: TRectD; ATextureID: Cardinal;
                                          const AColor: TBgraPixel; AOpacity: Double = 1.0;
                                          ABlendMode: TFloriaBlendMode = fbmSrcOver; AClipIndex: Integer = -1);
var
  V: array[0..3] of TFloriaGPUVertex;
  I: Integer;
begin
  if ARect.IsEmpty then Exit;

  FillChar(V, SizeOf(V), 0);
  for I := 0 to 3 do
  begin
    V[I].ColorR      := AColor.R / 255.0;
    V[I].ColorG      := AColor.G / 255.0;
    V[I].ColorB      := AColor.B / 255.0;
    V[I].ColorA      := (AColor.A / 255.0) * AOpacity;
    V[I].LocalX      := ARect.Left;
    V[I].LocalY      := ARect.Top;
    V[I].LocalW      := ARect.Width;
    V[I].LocalH      := ARect.Height;
    V[I].ClipIndex   := AClipIndex;
    V[I].ExtraParam1 := 1.0; // 1.0 = Glyph mask mode in shader
  end;

  // Top-Left
  V[0].PosX := ARect.Left;  V[0].PosY := ARect.Top;
  V[0].TexU := ATexRect.Left; V[0].TexV := ATexRect.Top;
  // Top-Right
  V[1].PosX := ARect.Right; V[1].PosY := ARect.Top;
  V[1].TexU := ATexRect.Right; V[1].TexV := ATexRect.Top;
  // Bottom-Right
  V[2].PosX := ARect.Right; V[2].PosY := ARect.Bottom;
  V[2].TexU := ATexRect.Right; V[2].TexV := ATexRect.Bottom;
  // Bottom-Left
  V[3].PosX := ARect.Left;  V[3].PosY := ARect.Bottom;
  V[3].TexU := ATexRect.Left; V[3].TexV := ATexRect.Bottom;

  if CanMergeWithCurrent(gbtTexturedQuad, ATextureID, ABlendMode, AClipIndex) then
    Inc(FDrawCalls[FDrawCallCount - 1].VertexCount, 6)
  else
  begin
    EnsureDrawCallCapacity();
    with FDrawCalls[FDrawCallCount] do
    begin
      BatchType   := gbtTexturedQuad;
      TextureID   := ATextureID;
      BlendMode   := ABlendMode;
      ClipIndex   := AClipIndex;
      StartIndex  := FVertexCount;
      VertexCount := 6;
    end;
    Inc(FDrawCallCount);
  end;

  AppendQuadVertices(V[0], V[1], V[2], V[3]);
end;

procedure TFloriaRenderBatch.EmitRoundedRect(const ARect: TRectD; const ARadii: TFloriaClipCornerRadii;
                                            const AFillColor: TBgraPixel; const ABorderColor: TBgraPixel;
                                            ABorderWidth: Double = 0.0; ABlendMode: TFloriaBlendMode = fbmSrcOver;
                                            AClipIndex: Integer = -1);
var
  V: array[0..3] of TFloriaGPUVertex;
  I: Integer;
  MaxR: Double;
begin
  if ARect.IsEmpty then Exit;

  MaxR := Min(ARect.Width * 0.5, ARect.Height * 0.5);

  FillChar(V, SizeOf(V), 0);
  for I := 0 to 3 do
  begin
    V[I].ColorR     := AFillColor.R / 255.0;
    V[I].ColorG     := AFillColor.G / 255.0;
    V[I].ColorB     := AFillColor.B / 255.0;
    V[I].ColorA     := AFillColor.A / 255.0;
    V[I].LocalX     := ARect.Left;
    V[I].LocalY     := ARect.Top;
    V[I].LocalW     := ARect.Width;
    V[I].LocalH     := ARect.Height;
    V[I].RadiusTL_X := Min(ARadii.TopLeftX, MaxR);
    V[I].RadiusTL_Y := Min(ARadii.TopLeftY, MaxR);
    V[I].RadiusTR_X := Min(ARadii.TopRightX, MaxR);
    V[I].RadiusTR_Y := Min(ARadii.TopRightY, MaxR);
    V[I].RadiusBR_X := Min(ARadii.BottomRightX, MaxR);
    V[I].RadiusBR_Y := Min(ARadii.BottomRightY, MaxR);
    V[I].RadiusBL_X := Min(ARadii.BottomLeftX, MaxR);
    V[I].RadiusBL_Y := Min(ARadii.BottomLeftY, MaxR);
    V[I].BorderWidth:= ABorderWidth;
    V[I].BorderR    := ABorderColor.R / 255.0;
    V[I].BorderG    := ABorderColor.G / 255.0;
    V[I].BorderB    := ABorderColor.B / 255.0;
    V[I].ClipIndex  := AClipIndex;
    V[I].ExtraParam1:= ABorderColor.A / 255.0;
  end;

  // Expand quad geometry by 1.5px skirt margin to accommodate the full SDF antialiasing falloff
  V[0].PosX := ARect.Left - 1.5;  V[0].PosY := ARect.Top - 1.5;
  V[1].PosX := ARect.Right + 1.5; V[1].PosY := ARect.Top - 1.5;
  V[2].PosX := ARect.Right + 1.5; V[2].PosY := ARect.Bottom + 1.5;
  V[3].PosX := ARect.Left - 1.5;  V[3].PosY := ARect.Bottom + 1.5;

  if CanMergeWithCurrent(gbtRoundedRect, 0, ABlendMode, AClipIndex) then
    Inc(FDrawCalls[FDrawCallCount - 1].VertexCount, 6)
  else
  begin
    EnsureDrawCallCapacity();
    with FDrawCalls[FDrawCallCount] do
    begin
      BatchType   := gbtRoundedRect;
      TextureID   := 0;
      BlendMode   := ABlendMode;
      ClipIndex   := AClipIndex;
      StartIndex  := FVertexCount;
      VertexCount := 6;
    end;
    Inc(FDrawCallCount);
  end;

  AppendQuadVertices(V[0], V[1], V[2], V[3]);
end;

procedure TFloriaRenderBatch.EmitBoxShadow(const ARect: TRectD; ARadius: Double; const AShadowParams: TFloriaShadowParams;
                                           ABlendMode: TFloriaBlendMode = fbmSrcOver; AClipIndex: Integer = -1);
var
  ExtRect: TRectD;
  V: array[0..3] of TFloriaGPUVertex;
  I: Integer;
  Pad: Double;
begin
  if ARect.IsEmpty then Exit;

  // Box shadow extends by BlurRadius * 3 + SpreadRadius
  Pad := AShadowParams.BlurRadius * 3.0 + Max(0.0, AShadowParams.SpreadRadius);
  ExtRect.Left   := ARect.Left + AShadowParams.OffsetX - Pad;
  ExtRect.Top    := ARect.Top + AShadowParams.OffsetY - Pad;
  ExtRect.Right  := ARect.Right + AShadowParams.OffsetX + Pad;
  ExtRect.Bottom := ARect.Bottom + AShadowParams.OffsetY + Pad;

  FillChar(V, SizeOf(V), 0);
  for I := 0 to 3 do
  begin
    V[I].ColorR      := AShadowParams.Color.R / 255.0;
    V[I].ColorG      := AShadowParams.Color.G / 255.0;
    V[I].ColorB      := AShadowParams.Color.B / 255.0;
    V[I].ColorA      := AShadowParams.Color.A / 255.0;
    V[I].LocalX      := ARect.Left + AShadowParams.OffsetX;
    V[I].LocalY      := ARect.Top + AShadowParams.OffsetY;
    V[I].LocalW      := ARect.Width;
    V[I].LocalH      := ARect.Height;
    V[I].RadiusTL_X  := ARadius;
    V[I].RadiusTL_Y  := ARadius;
    V[I].RadiusTR_X  := ARadius;
    V[I].RadiusTR_Y  := ARadius;
    V[I].RadiusBR_X  := ARadius;
    V[I].RadiusBR_Y  := ARadius;
    V[I].RadiusBL_X  := ARadius;
    V[I].RadiusBL_Y  := ARadius;
    V[I].ClipIndex   := AClipIndex;
    V[I].ExtraParam1 := AShadowParams.BlurRadius;
    V[I].ExtraParam2 := AShadowParams.SpreadRadius;
    V[I].ExtraParam3 := 0.0; // Outset
  end;

  V[0].PosX := ExtRect.Left;  V[0].PosY := ExtRect.Top;
  V[1].PosX := ExtRect.Right; V[1].PosY := ExtRect.Top;
  V[2].PosX := ExtRect.Right; V[2].PosY := ExtRect.Bottom;
  V[3].PosX := ExtRect.Left;  V[3].PosY := ExtRect.Bottom;

  if CanMergeWithCurrent(gbtBoxShadow, 0, ABlendMode, AClipIndex) then
    Inc(FDrawCalls[FDrawCallCount - 1].VertexCount, 6)
  else
  begin
    EnsureDrawCallCapacity();
    with FDrawCalls[FDrawCallCount] do
    begin
      BatchType   := gbtBoxShadow;
      TextureID   := 0;
      BlendMode   := ABlendMode;
      ClipIndex   := AClipIndex;
      StartIndex  := FVertexCount;
      VertexCount := 6;
    end;
    Inc(FDrawCallCount);
  end;

  AppendQuadVertices(V[0], V[1], V[2], V[3]);
end;

procedure TFloriaRenderBatch.EmitLinearGradient(const ARect: TRectD; const AColorStart, AColorEnd: TBgraPixel;
                                               AAngleDeg: Double; ABlendMode: TFloriaBlendMode = fbmSrcOver;
                                               AClipIndex: Integer = -1);
var
  V: array[0..3] of TFloriaGPUVertex;
  I: Integer;
begin
  if ARect.IsEmpty then Exit;

  FillChar(V, SizeOf(V), 0);
  for I := 0 to 3 do
  begin
    V[I].ColorR      := AColorStart.R / 255.0;
    V[I].ColorG      := AColorStart.G / 255.0;
    V[I].ColorB      := AColorStart.B / 255.0;
    V[I].ColorA      := AColorStart.A / 255.0;
    V[I].BorderR     := AColorEnd.R / 255.0;
    V[I].BorderG     := AColorEnd.G / 255.0;
    V[I].BorderB     := AColorEnd.B / 255.0;
    V[I].BorderWidth := AColorEnd.A / 255.0;
    V[I].LocalX      := ARect.Left;
    V[I].LocalY      := ARect.Top;
    V[I].LocalW      := ARect.Width;
    V[I].LocalH      := ARect.Height;
    V[I].ClipIndex   := AClipIndex;
    V[I].ExtraParam1 := AAngleDeg;
  end;

  V[0].PosX := ARect.Left;  V[0].PosY := ARect.Top;
  V[1].PosX := ARect.Right; V[1].PosY := ARect.Top;
  V[2].PosX := ARect.Right; V[2].PosY := ARect.Bottom;
  V[3].PosX := ARect.Left;  V[3].PosY := ARect.Bottom;

  if CanMergeWithCurrent(gbtLinearGradient, 0, ABlendMode, AClipIndex) then
    Inc(FDrawCalls[FDrawCallCount - 1].VertexCount, 6)
  else
  begin
    EnsureDrawCallCapacity();
    with FDrawCalls[FDrawCallCount] do
    begin
      BatchType   := gbtLinearGradient;
      TextureID   := 0;
      BlendMode   := ABlendMode;
      ClipIndex   := AClipIndex;
      StartIndex  := FVertexCount;
      VertexCount := 6;
    end;
    Inc(FDrawCallCount);
  end;

  AppendQuadVertices(V[0], V[1], V[2], V[3]);
end;

procedure TFloriaRenderBatch.EmitPathMesh(const AMesh: TFloriaTessMesh; const AColor: TBgraPixel;
                                         ABlendMode: TFloriaBlendMode = fbmSrcOver; AClipIndex: Integer = -1);
var
  I, AddedCount: Integer;
  V: TFloriaGPUVertex;
  SrcV: TFloriaTessVertex;
  Inv255, ColR, ColG, ColB, BaseA: Single;
begin
  if AMesh.IndexCount = 0 then Exit;
  AddedCount := AMesh.IndexCount;

  if CanMergeWithCurrent(gbtPathMesh, 0, ABlendMode, AClipIndex) then
    Inc(FDrawCalls[FDrawCallCount - 1].VertexCount, AddedCount)
  else
  begin
    EnsureDrawCallCapacity();
    with FDrawCalls[FDrawCallCount] do
    begin
      BatchType   := gbtPathMesh;
      TextureID   := 0;
      BlendMode   := ABlendMode;
      ClipIndex   := AClipIndex;
      StartIndex  := FVertexCount;
      VertexCount := AddedCount;
    end;
    Inc(FDrawCallCount);
  end;

  EnsureVertexCapacity(FVertexCount + AddedCount);

  Inv255 := 1.0 / 255.0;
  ColR  := AColor.R * Inv255;
  ColG  := AColor.G * Inv255;
  ColB  := AColor.B * Inv255;
  BaseA := AColor.A * Inv255;

  FillChar(V, SizeOf(V), 0);
  V.ColorR    := ColR;
  V.ColorG    := ColG;
  V.ColorB    := ColB;
  V.ClipIndex := AClipIndex;

  for I := 0 to AddedCount - 1 do
  begin
    SrcV := AMesh.Vertices[AMesh.Indices[I]];
    V.PosX        := SrcV.X;
    V.PosY        := SrcV.Y;
    V.TexU        := SrcV.TexU;
    V.TexV        := SrcV.TexV;
    V.ColorA      := BaseA * SrcV.Coverage;
    V.ExtraParam1 := SrcV.Dist;

    FVertices[FVertexCount] := V;
    Inc(FVertexCount);
  end;
end;

procedure TFloriaRenderBatch.EmitCapsuleLine(const AP1, AP2: TPointD; AStrokeWidth: Double;
                                            const AColor: TBgraPixel; ABlendMode: TFloriaBlendMode = fbmSrcOver;
                                            AClipIndex: Integer = -1);
var
  V: array[0..3] of TFloriaGPUVertex;
  I: Integer;
  Dx, Dy, Len, InvLen, Nx, Ny, DirX, DirY, R, Margin: Double;
begin
  if (AColor.A = 0) or (AStrokeWidth <= 0.0) then Exit;

  Dx := AP2.X - AP1.X;
  Dy := AP2.Y - AP1.Y;
  Len := Sqrt(Dx * Dx + Dy * Dy);

  R := AStrokeWidth * 0.5;
  if R < 0.5 then
    Margin := 1.5
  else
    Margin := R + 1.5;

  if Len < 1e-4 then
  begin
    DirX := 1.0; DirY := 0.0;
    Nx := 0.0;   Ny := 1.0;
  end
  else
  begin
    InvLen := 1.0 / Len;
    DirX := Dx * InvLen;
    DirY := Dy * InvLen;
    Nx := -DirY;
    Ny :=  DirX;
  end;

  FillChar(V, SizeOf(V), 0);
  for I := 0 to 3 do
  begin
    V[I].ColorR     := AColor.R / 255.0;
    V[I].ColorG     := AColor.G / 255.0;
    V[I].ColorB     := AColor.B / 255.0;
    V[I].ColorA     := AColor.A / 255.0;
    V[I].LocalX     := AP1.X;
    V[I].LocalY     := AP1.Y;
    V[I].LocalW     := AP2.X;
    V[I].LocalH     := AP2.Y;
    V[I].RadiusTL_X := R;
    V[I].RadiusTL_Y := AStrokeWidth;
    V[I].ClipIndex  := AClipIndex;
  end;

  // Oriented quad vertices enclosing the capsule segment + AA margin
  V[0].PosX := AP1.X - DirX * Margin + Nx * Margin;
  V[0].PosY := AP1.Y - DirY * Margin + Ny * Margin;

  V[1].PosX := AP2.X + DirX * Margin + Nx * Margin;
  V[1].PosY := AP2.Y + DirY * Margin + Ny * Margin;

  V[2].PosX := AP2.X + DirX * Margin - Nx * Margin;
  V[2].PosY := AP2.Y + DirY * Margin - Ny * Margin;

  V[3].PosX := AP1.X - DirX * Margin - Nx * Margin;
  V[3].PosY := AP1.Y - DirY * Margin - Ny * Margin;

  if CanMergeWithCurrent(gbtCapsuleLine, 0, ABlendMode, AClipIndex) then
    Inc(FDrawCalls[FDrawCallCount - 1].VertexCount, 6)
  else
  begin
    EnsureDrawCallCapacity();
    with FDrawCalls[FDrawCallCount] do
    begin
      BatchType   := gbtCapsuleLine;
      TextureID   := 0;
      BlendMode   := ABlendMode;
      ClipIndex   := AClipIndex;
      StartIndex  := FVertexCount;
      VertexCount := 6;
    end;
    Inc(FDrawCallCount);
  end;

  AppendQuadVertices(V[0], V[1], V[2], V[3]);
end;

procedure TFloriaRenderBatch.UploadToVBO(gl: TGLEngine);
var
  DataSize: csize_t;
begin
  if not Assigned(gl) or not gl.Available or (FVertexCount = 0) then Exit;

  if FVBO = 0 then
    gl.GenBuffers(1, @FVBO);

  gl.BindBuffer(GL_ARRAY_BUFFER, FVBO);
  DataSize := FVertexCount * SizeOf(TFloriaGPUVertex);
  gl.BufferData(GL_ARRAY_BUFFER, DataSize, @FVertices[0], GL_DYNAMIC_DRAW);
  gl.BindBuffer(GL_ARRAY_BUFFER, 0);
end;

end.
