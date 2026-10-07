unit Floria.GPU.Test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fpcunit, testregistry,
  Floria.Image.Core,
  Floria.Canvas.Blend,
  Floria.Path.Clipper.Core,
  Floria.Path.Ops,
  Floria.DisplayList,
  Floria.DisplayList.Clip,
  Floria.EGL,
  Floria.GL,
  Floria.GPU.Atlas,
  Floria.GPU.Batch,
  Floria.GPU.Shaders,
  Floria.GPU.Renderer,
  Floria.GPU.Tessellator,
  Floria.GPU.Context;

type
  { TFloriaGPUTest }
  TFloriaGPUTest = class(TTestCase)
  published
    procedure TestGLConstantsAndErrorStrings;
    procedure TestGLAvailabilityAndLoader;
    procedure TestGPUAtlasPageAllocationAndSkyline;
    procedure TestGPUAtlasMultiPageAndImageBlit;
    procedure TestGPUAtlasFallbackBlobRasterizer;
    procedure TestRenderBatchEmitAndCoalescing;
    procedure TestRenderBatchBoxShadowAndGradients;
    procedure TestGPUPipelineManagerLifecycle;
    procedure TestGPURendererDisplayListPlayback;
    procedure TestTessellateStrokeLine;
    procedure TestTessellateStrokeJoins;
    procedure TestTessellateStrokeCaps;
    procedure TestTessellatePolygonFillConvex;
    procedure TestTessellatePolygonFillConcave;
    procedure TestTessellateCurvedPathSubdivision;
    procedure TestRenderBatchEmitPathMesh;
    procedure TestGPURendererDirectTessellationPlayback;
    procedure TestGPUBackendAvailability;
    procedure TestGPUOffscreenContextLifecycle;
    procedure TestGPURendererWithOffscreenContext;
  end;

implementation

{ TFloriaGPUTest }

procedure TFloriaGPUTest.TestGLConstantsAndErrorStrings;
begin
  AssertEquals('GL_FALSE', 0, GL_FALSE);
  AssertEquals('GL_TRUE', 1, GL_TRUE);
  AssertEquals('GL_TRIANGLES', $0004, GL_TRIANGLES);
  AssertEquals('GL_COLOR_BUFFER_BIT', $4000, GL_COLOR_BUFFER_BIT);
  AssertEquals('GL_RGBA', $1908, GL_RGBA);
  AssertEquals('GL_TEXTURE_2D', $0DE1, GL_TEXTURE_2D);

  AssertEquals('Error string NO_ERROR', 'GL_NO_ERROR', FloriaGLErrorString(GL_NO_ERROR));
  AssertEquals('Error string INVALID_ENUM', 'GL_INVALID_ENUM', FloriaGLErrorString(GL_INVALID_ENUM));
  AssertEquals('Error string INVALID_VALUE', 'GL_INVALID_VALUE', FloriaGLErrorString(GL_INVALID_VALUE));
  AssertEquals('Error string INVALID_OPERATION', 'GL_INVALID_OPERATION', FloriaGLErrorString(GL_INVALID_OPERATION));
  AssertEquals('Error string OUT_OF_MEMORY', 'GL_OUT_OF_MEMORY', FloriaGLErrorString(GL_OUT_OF_MEMORY));
end;

procedure TFloriaGPUTest.TestGLAvailabilityAndLoader;
var
  gl: TGLEngine;
begin
  gl := FloriaGL();
  AssertNotNull('FloriaGL singleton is assigned', gl);
  // On Linux systems with graphics drivers or Mesa, GL is available
  if gl.Available then
  begin
    AssertTrue('Library path not empty', Length(gl.LibraryPath) > 0);
    AssertNotNull('Viewport pointer assigned', Pointer(gl.Viewport));
    AssertNotNull('Clear pointer assigned', Pointer(gl.Clear));
    AssertNotNull('DrawArrays pointer assigned', Pointer(gl.DrawArrays));
  end;
end;

procedure TFloriaGPUTest.TestGPUAtlasPageAllocationAndSkyline;
var
  Page: TFloriaAtlasPage;
  R: TRectD;
  AllocOk: Boolean;
begin
  Page := TFloriaAtlasPage.Create(0, 512, 512);
  try
    AssertEquals('Page index 0', 0, Page.Index);
    AssertEquals('Page width 512', 512, Page.Width);
    AssertEquals('Page height 512', 512, Page.Height);

    // Allocate 64x64 item with 1px padding -> occupies 66x66
    AllocOk := Page.Allocate(64, 64, 1, R);
    AssertTrue('First allocation succeeds', AllocOk);
    AssertEquals('Alloc Left (padded by 1)', 1.0, R.Left);
    AssertEquals('Alloc Top (padded by 1)', 1.0, R.Top);
    AssertEquals('Alloc Right', 65.0, R.Right);
    AssertEquals('Alloc Bottom', 65.0, R.Bottom);

    // Second allocation fits right next to it on the skyline
    AllocOk := Page.Allocate(128, 64, 1, R);
    AssertTrue('Second allocation succeeds', AllocOk);
    AssertEquals('Second Alloc Left', 67.0, R.Left); // 66 + 1

    // Oversized allocation fails
    AllocOk := Page.Allocate(1000, 1000, 1, R);
    AssertFalse('Oversized allocation fails', AllocOk);
  finally
    Page.Free();
  end;
end;

procedure TFloriaGPUTest.TestGPUAtlasMultiPageAndImageBlit;
var
  Atlas: TFloriaGPUAtlas;
  Img1, Img2: TFloriaImage;
  Alloc1, Alloc2: TFloriaAtlasAlloc;
  P: TBgraPixel;
begin
  Atlas := TFloriaGPUAtlas.Create(128, 1);
  try
    Img1 := TFloriaImage.Create(50, 50);
    Img2 := TFloriaImage.Create(100, 100);
    try
      Img1.Clear(255, 0, 0, 255); // Red
      Img2.Clear(0, 255, 0, 255); // Green

      AssertTrue('Add first image succeeds', Atlas.AddImage(Img1, Alloc1));
      AssertEquals('First image on page 0', 0, Alloc1.PageIndex);
      AssertTrue('First alloc is valid', Alloc1.IsValid);
      AssertEquals('Alloc width 50', 50.0, Alloc1.Rect.Width);
      AssertEquals('Alloc height 50', 50.0, Alloc1.Rect.Height);

      // Verify pixel copied into atlas surface
      P := Atlas.Pages[0].Surface.Pixels[Round(Alloc1.Rect.Left), Round(Alloc1.Rect.Top)];
      AssertEquals('Atlas pixel Red', 255, P.R);
      AssertEquals('Atlas pixel Green', 0, P.G);

      // Img2 is 100x100 (+2px padding = 102x102). Remaining space on Page 0 is (128 - 52 = 76 < 102)
      // So Atlas must automatically allocate Page 1!
      AssertTrue('Add second image succeeds', Atlas.AddImage(Img2, Alloc2));
      AssertEquals('Second image assigned to page 1', 1, Alloc2.PageIndex);
      AssertEquals('Page count is 2', 2, Atlas.PageCount);
    finally
      Img2.Free();
      Img1.Free();
    end;
  finally
    Atlas.Free();
  end;
end;

procedure TFloriaGPUTest.TestGPUAtlasFallbackBlobRasterizer;
var
  Atlas: TFloriaGPUAtlas;
  Path: TFloriaPath;
  Alloc: TFloriaAtlasAlloc;
begin
  Atlas := TFloriaGPUAtlas.Create(512, 1);
  Path := TFloriaPath.Create();
  try
    Path.AddRoundedRect(10.0, 10.0, 100.0, 50.0, 8.0, 8.0);

    // Rasterize vector path via AggPas into atlas
    AssertTrue('Rasterize path succeeds',
      Atlas.RasterizePath(Path, BgraPixel(255, 128, 0, 255), BgraPixel(0, 0, 0, 255), 2.0, frNonZero, Alloc));

    AssertTrue('Alloc is valid', Alloc.IsValid);
    AssertEquals('Page 0', 0, Alloc.PageIndex);
    AssertTrue('Alloc Width > 90', Alloc.Rect.Width > 90.0);
    AssertTrue('Alloc Height > 40', Alloc.Rect.Height > 40.0);
    AssertTrue('U2 > U1', Alloc.U2 > Alloc.U1);
    AssertTrue('V2 > V1', Alloc.V2 > Alloc.V1);
  finally
    Path.Free();
    Atlas.Free();
  end;
end;

procedure TFloriaGPUTest.TestRenderBatchEmitAndCoalescing;
var
  Batch: TFloriaRenderBatch;
begin
  Batch := TFloriaRenderBatch.Create();
  try
    AssertEquals('Initial vertex count 0', 0, Batch.VertexCount);
    AssertEquals('Initial draw calls 0', 0, Batch.DrawCallCount);

    // Emit 3 solid rects with same pipeline state
    Batch.EmitSolidRect(RectD(0.0, 0.0, 10.0, 10.0), BgraPixel(255, 0, 0, 255));
    Batch.EmitSolidRect(RectD(20.0, 0.0, 30.0, 10.0), BgraPixel(0, 255, 0, 255));
    Batch.EmitSolidRect(RectD(40.0, 0.0, 50.0, 10.0), BgraPixel(0, 0, 255, 255));

    AssertEquals('3 quads = 18 vertices', 18, Batch.VertexCount);
    AssertEquals('All 3 solid rects merged into 1 draw call', 1, Batch.DrawCallCount);
    AssertEquals('Draw call 0 vertex count 18', 18, Batch.DrawCalls[0].VertexCount);

    // Emit rounded rect (different shader type -> must break batch!)
    Batch.EmitRoundedRect(RectD(0.0, 50.0, 50.0, 100.0), TFloriaClipCornerRadii.Uniform(5.0),
                         BgraPixel(255, 255, 255, 255), BgraPixel(0, 0, 0, 255), 1.0);

    AssertEquals('Total vertices 24', 24, Batch.VertexCount);
    AssertEquals('Draw call count increased to 2', 2, Batch.DrawCallCount);
    AssertTrue('Batch 0 is solid quad', Batch.DrawCalls[0].BatchType = gbtSolidQuad);
    AssertTrue('Batch 1 is rounded rect', Batch.DrawCalls[1].BatchType = gbtRoundedRect);
  finally
    Batch.Free();
  end;
end;

procedure TFloriaGPUTest.TestRenderBatchBoxShadowAndGradients;
var
  Batch: TFloriaRenderBatch;
  ShadowParams: TFloriaShadowParams;
begin
  Batch := TFloriaRenderBatch.Create();
  try
    ShadowParams.Color        := BgraPixel(0, 0, 0, 128);
    ShadowParams.OffsetX      := 2.0;
    ShadowParams.OffsetY      := 4.0;
    ShadowParams.BlurRadius   := 8.0;
    ShadowParams.SpreadRadius := 1.0;

    Batch.EmitBoxShadow(RectD(50.0, 50.0, 150.0, 150.0), 10.0, ShadowParams);
    AssertEquals('Shadow emitted 6 vertices', 6, Batch.VertexCount);
    AssertEquals('1 draw call', 1, Batch.DrawCallCount);
    AssertTrue('Type is boxShadow', Batch.DrawCalls[0].BatchType = gbtBoxShadow);

    Batch.EmitLinearGradient(RectD(0.0, 0.0, 100.0, 100.0), BgraPixel(255, 0, 0, 255),
                             BgraPixel(0, 0, 255, 255), 45.0);
    AssertEquals('Gradient added 6 vertices', 12, Batch.VertexCount);
    AssertEquals('2 draw calls', 2, Batch.DrawCallCount);
    AssertTrue('Type is linearGradient', Batch.DrawCalls[1].BatchType = gbtLinearGradient);
  finally
    Batch.Free();
  end;
end;

procedure TFloriaGPUTest.TestGPUPipelineManagerLifecycle;
var
  egl: TEGLEngine;
  gl: TGLEngine;
  Pipelines: TFloriaGPUPipelineManager;
  BT: TFloriaGPUBatchType;
  Prog: TFloriaGPUShaderProgram;
  CfgAttribs: array[0..12] of EGLint;
  CtxAttribs: array[0..2] of EGLint;
  SurfAttribs: array[0..4] of EGLint;
  Cfg: EGLConfig;
  NumConfigs: EGLint;
  Ctx: EGLContext;
  Surf: EGLSurface;
  HasActiveContext: Boolean;
begin
  egl := FloriaEGL();
  gl := FloriaGL();
  Pipelines := TFloriaGPUPipelineManager.Create();
  try
    AssertFalse('Initially not initialized', Pipelines.Initialized);
    if gl.Available and egl.Available and egl.InitializeDefaultDisplay() then
    begin
      eglBindAPI(EGL_OPENGL_ES_API);

      CfgAttribs[0] := EGL_SURFACE_TYPE;
      CfgAttribs[1] := EGL_PBUFFER_BIT;
      CfgAttribs[2] := EGL_RED_SIZE;
      CfgAttribs[3] := 8;
      CfgAttribs[4] := EGL_GREEN_SIZE;
      CfgAttribs[5] := 8;
      CfgAttribs[6] := EGL_BLUE_SIZE;
      CfgAttribs[7] := 8;
      CfgAttribs[8] := EGL_ALPHA_SIZE;
      CfgAttribs[9] := 8;
      CfgAttribs[10] := EGL_RENDERABLE_TYPE;
      CfgAttribs[11] := EGL_OPENGL_ES2_BIT;
      CfgAttribs[12] := EGL_NONE;

      Cfg := nil;
      NumConfigs := 0;
      HasActiveContext := False;
      Ctx := nil;
      Surf := nil;

      if (eglChooseConfig(egl.DefaultDisplay, @CfgAttribs[0], @Cfg, 1, @NumConfigs) = EGL_TRUE) and (NumConfigs > 0) then
      begin
        CtxAttribs[0] := EGL_CONTEXT_CLIENT_VERSION;
        CtxAttribs[1] := 2;
        CtxAttribs[2] := EGL_NONE;

        Ctx := eglCreateContext(egl.DefaultDisplay, Cfg, EGL_NO_CONTEXT, @CtxAttribs[0]);
        if Ctx <> nil then
        begin
          SurfAttribs[0] := EGL_WIDTH;
          SurfAttribs[1] := 16;
          SurfAttribs[2] := EGL_HEIGHT;
          SurfAttribs[3] := 16;
          SurfAttribs[4] := EGL_NONE;

          Surf := eglCreatePbufferSurface(egl.DefaultDisplay, Cfg, @SurfAttribs[0]);
          if Surf <> nil then
            HasActiveContext := (eglMakeCurrent(egl.DefaultDisplay, Surf, Surf, Ctx) = EGL_TRUE);
        end;
      end;

      try
        Pipelines.EnsureInitialized(gl);
        AssertTrue('Initialized after EnsureInitialized', Pipelines.Initialized);

        for BT := Low(TFloriaGPUBatchType) to High(TFloriaGPUBatchType) do
        begin
          Prog := Pipelines.GetProgram(BT);
          AssertNotNull('Program assigned for batch type', Prog);
          if HasActiveContext then
            AssertTrue('Program compiled and linked', Prog.Linked);
        end;
      finally
        if HasActiveContext then
          eglMakeCurrent(egl.DefaultDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        if Surf <> nil then
          eglDestroySurface(egl.DefaultDisplay, Surf);
        if Ctx <> nil then
          eglDestroyContext(egl.DefaultDisplay, Ctx);
      end;
    end;
  finally
    Pipelines.Free();
  end;
end;

procedure TFloriaGPUTest.TestGPURendererDisplayListPlayback;
var
  Recorder: TFloriaPictureRecorder;
  Pic: TFloriaPicture;
  Renderer: TFloriaGPURenderer;
  Path: TFloriaPath;
  ShadowParams: TFloriaShadowParams;
begin
  Recorder := TFloriaPictureRecorder.Create();
  try
    Recorder.BeginRecording(RectD(0.0, 0.0, 800.0, 600.0));
    Recorder.Clear(BgraPixel(245, 245, 245, 255));
    // 1. Solid Rect
    Recorder.DrawRect(RectD(10.0, 10.0, 100.0, 50.0), BgraPixel(255, 0, 0, 255));
    // 2. Rounded Rect
    Recorder.DrawRoundedRect(RectD(120.0, 10.0, 220.0, 50.0), 8.0, 8.0, BgraPixel(0, 255, 0, 255));
    // 3. Drop Shadow
    ShadowParams.Color := BgraPixel(0, 0, 0, 100);
    ShadowParams.OffsetX := 2.0; ShadowParams.OffsetY := 4.0;
    ShadowParams.BlurRadius := 6.0; ShadowParams.SpreadRadius := 0.0;
    Recorder.DrawShadow(RectD(240.0, 10.0, 340.0, 50.0), 6.0, ShadowParams);
    // 4. Circle
    Recorder.DrawCircle(400.0, 30.0, 20.0, BgraPixel(0, 0, 255, 255));
    // 5. Complex vector path (tested via blob rasterizer)
    Path := TFloriaPath.Create();
    try
      Path.AddRoundedRect(500.0, 10.0, 600.0, 50.0, 10.0, 10.0);
      Recorder.DrawPath(Path, BgraPixel(255, 128, 0, 255));
    finally
      Path.Free();
    end;
    Pic := Recorder.EndRecording();
  finally
    Recorder.Free();
  end;

  Renderer := TFloriaGPURenderer.Create();
  try
    Renderer.BeginFrame(800, 600);
    AssertTrue('In frame', Renderer.InFrame);

    // Playback retained picture to GPU receiver!
    Pic.Playback(Renderer);

    // Verify GPU batcher captured the geometry
    AssertTrue('Vertices accumulated in batch', Renderer.Batch.VertexCount >= 30);
    AssertTrue('Draw calls generated', Renderer.Batch.DrawCallCount >= 3);

    // End frame flushes to GPU
    Renderer.EndFrame();
    AssertFalse('Frame ended', Renderer.InFrame);
  finally
    Renderer.Free();
    Pic.Free();
  end;
end;

procedure TFloriaGPUTest.TestTessellateStrokeLine;
var
  Tess: TFloriaGPUTessellator;
  Mesh: TFloriaTessMesh;
begin
  Tess := TFloriaGPUTessellator.Create();
  try
    Mesh.Clear();
    // Non-AA horizontal line (10, 20) -> (100, 20) with width 4.0
    Tess.TessellateLine(PointD(10.0, 20.0), PointD(100.0, 20.0), 4.0, False, Mesh);
    AssertEquals('Non-AA line has 4 vertices', 4, Mesh.VertexCount);
    AssertEquals('Non-AA line has 6 indices (2 triangles)', 6, Mesh.IndexCount);
    AssertEquals('Left normal offset Y=22', 22.0, Mesh.Vertices[0].Y);
    AssertEquals('Right normal offset Y=18', 18.0, Mesh.Vertices[1].Y);
    AssertEquals('Vertex coverage is 1.0', 1.0, Mesh.Vertices[0].Coverage);

    // AA line horizontal (10, 20) -> (100, 20) with width 4.0
    Mesh.Clear();
    Tess.TessellateLine(PointD(10.0, 20.0), PointD(100.0, 20.0), 4.0, True, Mesh);
    AssertTrue('AA line has at least 8 vertices', Mesh.VertexCount >= 8);
    AssertTrue('AA line has at least 18 indices (6 triangles)', Mesh.IndexCount >= 18);
    AssertEquals('Core coverage 1.0', 1.0, Mesh.Vertices[0].Coverage);
    AssertEquals('Fringe coverage 0.0', 0.0, Mesh.Vertices[4].Coverage);
  finally
    Tess.Free();
  end;
end;

procedure TFloriaGPUTest.TestTessellateStrokeJoins;
var
  Tess: TFloriaGPUTessellator;
  Mesh: TFloriaTessMesh;
  Pts: TPathD;
begin
  Tess := TFloriaGPUTessellator.Create();
  try
    SetLength(Pts, 3);
    Pts[0] := PointD(0.0, 0.0);
    Pts[1] := PointD(50.0, 0.0);
    Pts[2] := PointD(50.0, 50.0);

    // Bevel join
    Mesh.Clear();
    Tess.TessellatePolyline(Pts, False, 10.0, fpjtBevel, fpetButt, 4.0, False, Mesh);
    AssertTrue('Bevel join generates triangles', Mesh.TriangleCount() >= 5);

    // Miter join
    Mesh.Clear();
    Tess.TessellatePolyline(Pts, False, 10.0, fpjtMiter, fpetButt, 4.0, False, Mesh);
    AssertTrue('Miter join generates triangles', Mesh.TriangleCount() >= 6);

    // Round join
    Mesh.Clear();
    Tess.TessellatePolyline(Pts, False, 10.0, fpjtRound, fpetButt, 4.0, False, Mesh);
    AssertTrue('Round join generates smooth fan', Mesh.TriangleCount() >= 7);
  finally
    Tess.Free();
  end;
end;

procedure TFloriaGPUTest.TestTessellateStrokeCaps;
var
  Tess: TFloriaGPUTessellator;
  MeshButt, MeshRound, MeshSquare: TFloriaTessMesh;
  Pts: TPathD;
begin
  Tess := TFloriaGPUTessellator.Create();
  try
    SetLength(Pts, 2);
    Pts[0] := PointD(10.0, 10.0);
    Pts[1] := PointD(90.0, 10.0);

    MeshButt.Clear();
    Tess.TessellatePolyline(Pts, False, 10.0, fpjtMiter, fpetButt, 4.0, False, MeshButt);
    AssertEquals('Butt cap has 2 triangles', 2, MeshButt.TriangleCount());

    MeshSquare.Clear();
    Tess.TessellatePolyline(Pts, False, 10.0, fpjtMiter, fpetSquare, 4.0, False, MeshSquare);
    AssertTrue('Square cap extends ends', MeshSquare.TriangleCount() > MeshButt.TriangleCount());

    MeshRound.Clear();
    Tess.TessellatePolyline(Pts, False, 10.0, fpjtMiter, fpetRound, 4.0, False, MeshRound);
    AssertTrue('Round cap adds semi-circle fans', MeshRound.TriangleCount() > MeshSquare.TriangleCount());
  finally
    Tess.Free();
  end;
end;

procedure TFloriaGPUTest.TestTessellatePolygonFillConvex;
var
  Tess: TFloriaGPUTessellator;
  Mesh: TFloriaTessMesh;
  Pts: TPathD;
begin
  Tess := TFloriaGPUTessellator.Create();
  try
    // CCW Rectangle (10, 10) to (50, 50)
    SetLength(Pts, 4);
    Pts[0] := PointD(10.0, 10.0);
    Pts[1] := PointD(50.0, 10.0);
    Pts[2] := PointD(50.0, 50.0);
    Pts[3] := PointD(10.0, 50.0);

    // Non-AA
    Mesh.Clear();
    Tess.TessellatePolygonFill(Pts, False, Mesh);
    AssertEquals('Quad decomposes into 2 triangles', 2, Mesh.TriangleCount());
    AssertEquals('Interior vertices have coverage 1.0', 1.0, Mesh.Vertices[0].Coverage);

    // AA
    Mesh.Clear();
    Tess.TessellatePolygonFill(Pts, True, Mesh);
    AssertEquals('AA quad has 10 triangles', 10, Mesh.TriangleCount());
    AssertTrue('Vertex count contains fringe', Mesh.VertexCount >= 10);
  finally
    Tess.Free();
  end;
end;

procedure TFloriaGPUTest.TestTessellatePolygonFillConcave;
var
  Tess: TFloriaGPUTessellator;
  Mesh: TFloriaTessMesh;
  Pts: TPathD;
begin
  Tess := TFloriaGPUTessellator.Create();
  try
    // L-shaped concave polygon with 6 vertices:
    // (0,0) -> (40,0) -> (40,20) -> (20,20) -> (20,40) -> (0,40)
    SetLength(Pts, 6);
    Pts[0] := PointD(0.0, 0.0);
    Pts[1] := PointD(40.0, 0.0);
    Pts[2] := PointD(40.0, 20.0);
    Pts[3] := PointD(20.0, 20.0);
    Pts[4] := PointD(20.0, 40.0);
    Pts[5] := PointD(0.0, 40.0);

    Mesh.Clear();
    Tess.TessellatePolygonFill(Pts, False, Mesh);
    AssertEquals('6-vertex L-shape decomposes into 4 triangles', 4, Mesh.TriangleCount());
  finally
    Tess.Free();
  end;
end;

procedure TFloriaGPUTest.TestTessellateCurvedPathSubdivision;
var
  Tess: TFloriaGPUTessellator;
  OutPts: TPathD;
  Mesh: TFloriaTessMesh;
  Path: TFloriaPath;
begin
  Tess := TFloriaGPUTessellator.Create(0.25);
  Path := TFloriaPath.Create();
  try
    // Quadratic subdivision
    SetLength(OutPts, 1);
    OutPts[0] := PointD(0.0, 0.0);
    Tess.SubdivideQuad(PointD(0.0, 0.0), PointD(50.0, 100.0), PointD(100.0, 0.0), OutPts);
    AssertTrue('Quad subdivided into multiple chord points', Length(OutPts) >= 8);

    // Cubic subdivision
    SetLength(OutPts, 1);
    OutPts[0] := PointD(0.0, 0.0);
    Tess.SubdivideCubic(PointD(0.0, 0.0), PointD(25.0, 100.0), PointD(75.0, -100.0), PointD(100.0, 0.0), OutPts);
    AssertTrue('Cubic subdivided into multiple chord points', Length(OutPts) >= 12);

    // Full path with curves
    Path.MoveTo(10.0, 10.0);
    Path.QuadTo(50.0, 80.0, 100.0, 10.0);
    Path.Close();

    Mesh.Clear();
    Tess.TessellateFill(Path, Mesh, fpfrNonZero, True);
    AssertTrue('Curved path fill generates triangles', Mesh.TriangleCount() >= 10);
  finally
    Path.Free();
    Tess.Free();
  end;
end;

procedure TFloriaGPUTest.TestRenderBatchEmitPathMesh;
var
  Batch: TFloriaRenderBatch;
  Tess: TFloriaGPUTessellator;
  Mesh: TFloriaTessMesh;
  Pts: TPathD;
begin
  Batch := TFloriaRenderBatch.Create();
  Tess := TFloriaGPUTessellator.Create();
  try
    SetLength(Pts, 3);
    Pts[0] := PointD(0.0, 0.0);
    Pts[1] := PointD(50.0, 0.0);
    Pts[2] := PointD(25.0, 40.0);

    Mesh.Clear();
    Tess.TessellatePolygonFill(Pts, False, Mesh);

    Batch.EmitPathMesh(Mesh, BgraPixel(255, 0, 0, 255));
    AssertEquals('1 draw call generated', 1, Batch.DrawCallCount);
    AssertEquals('Draw call batch type is gbtPathMesh', Integer(gbtPathMesh), Integer(Batch.DrawCalls[0].BatchType));
    AssertEquals('Vertices match mesh index count', 3, Batch.VertexCount);

    // Emitting another path mesh merges into the same draw call!
    Batch.EmitPathMesh(Mesh, BgraPixel(0, 255, 0, 255));
    AssertEquals('Draw calls coalesced into 1', 1, Batch.DrawCallCount);
    AssertEquals('Vertex count is 6', 6, Batch.VertexCount);
  finally
    Tess.Free();
    Batch.Free();
  end;
end;

procedure TFloriaGPUTest.TestGPURendererDirectTessellationPlayback;
var
  Recorder: TFloriaPictureRecorder;
  Pic: TFloriaPicture;
  Renderer: TFloriaGPURenderer;
  Path: TFloriaPath;
begin
  Recorder := TFloriaPictureRecorder.Create();
  try
    Recorder.BeginRecording(RectD(0.0, 0.0, 800.0, 600.0));
    // Solid rect (generates gbtSolidQuad draw call)
    Recorder.DrawRect(RectD(0.0, 0.0, 50.0, 50.0), BgraPixel(0, 0, 255, 255));

    // Angled line (generates gbtPathMesh draw call)
    Recorder.DrawLine(10.0, 10.0, 100.0, 80.0, BgraPixel(255, 0, 0, 255), 4.0);

    // Filled vector triangle
    Path := TFloriaPath.Create();
    try
      Path.MoveTo(200.0, 50.0);
      Path.LineTo(300.0, 50.0);
      Path.LineTo(250.0, 150.0);
      Path.Close();
      Recorder.DrawPath(Path, BgraPixel(0, 255, 0, 255));
    finally
      Path.Free();
    end;

    Pic := Recorder.EndRecording();
  finally
    Recorder.Free();
  end;

  Renderer := TFloriaGPURenderer.Create();
  try
    Renderer.BeginFrame(800, 600);
    AssertTrue('Direct tessellation enabled by default', Renderer.DirectTessellationEnabled);

    // Playback picture to GPU receiver!
    Pic.Playback(Renderer);

    // Verify GPU batcher captured geometry via direct tessellation
    AssertTrue('Batch accumulated path vertices', Renderer.Batch.VertexCount > 10);
    AssertTrue('Batch generated draw calls', Renderer.Batch.DrawCallCount >= 2);

    Renderer.EndFrame();
  finally
    Renderer.Free();
    Pic.Free();
  end;
end;

procedure TFloriaGPUTest.TestGPUBackendAvailability;
begin
  AssertTrue('EGL backend is available on Linux', FloriaGPUIsBackendAvailable(gbeEGL));
  AssertTrue('Software backend is always available', FloriaGPUIsBackendAvailable(gbeSoftware));
  AssertFalse('WGL backend is not available on Linux', FloriaGPUIsBackendAvailable(gbeWGL));
  AssertFalse('CGL backend is not available on Linux', FloriaGPUIsBackendAvailable(gbeCGL));
end;

procedure TFloriaGPUTest.TestGPUOffscreenContextLifecycle;
var
  Ctx: TFloriaGPUContext;
  W, H: Integer;
begin
  Ctx := FloriaCreateGPUOffscreenContext(256, 256);
  if Assigned(Ctx) then
  begin
    try
      AssertTrue('Context is initialized', Ctx.Initialized);
      AssertTrue('Context is offscreen', Ctx.IsOffscreen);
      AssertEquals('Backend is gbeEGL', Integer(gbeEGL), Integer(Ctx.BackendType));

      Ctx.GetSurfaceSize(W, H);
      AssertEquals('Surface width is 256', 256, W);
      AssertEquals('Surface height is 256', 256, H);

      AssertTrue('MakeCurrent succeeds', Ctx.MakeCurrent());
      AssertTrue('Context is current', Ctx.IsCurrent);

      Ctx.ReleaseCurrent();
      AssertFalse('Context is no longer current', Ctx.IsCurrent);
    finally
      Ctx.Free();
    end;
  end;
end;

procedure TFloriaGPUTest.TestGPURendererWithOffscreenContext;
var
  Ctx: TFloriaGPUContext;
  Renderer: TFloriaGPURenderer;
  Recorder: TFloriaPictureRecorder;
  Pic: TFloriaPicture;
begin
  Ctx := FloriaCreateGPUOffscreenContext(320, 240);
  if Assigned(Ctx) then
  begin
    try
      Renderer := TFloriaGPURenderer.Create(Ctx);
      try
        AssertNotNull('Renderer context assigned', Renderer.Context);

        Recorder := TFloriaPictureRecorder.Create();
        try
          Recorder.BeginRecording(RectD(0.0, 0.0, 320.0, 240.0));
          Recorder.DrawRect(RectD(10.0, 10.0, 100.0, 100.0), BgraPixel(255, 0, 0, 255));
          Pic := Recorder.EndRecording();
        finally
          Recorder.Free();
        end;

        try
          // Begin frame makes context current
          Renderer.BeginFrame(320, 240);
          AssertTrue('In frame', Renderer.InFrame);
          AssertTrue('Context is current during frame', Ctx.IsCurrent);

          // Playback to GPU receiver
          Pic.Playback(Renderer);
          AssertTrue('Batch has vertices', Renderer.Batch.VertexCount > 0);

          // End frame flushes to GPU
          Renderer.EndFrame();
          AssertFalse('Frame ended', Renderer.InFrame);
        finally
          Pic.Free();
        end;
      finally
        Renderer.Free();
      end;
    finally
      Ctx.Free();
    end;
  end;
end;

initialization
  RegisterTest(TFloriaGPUTest);

end.
