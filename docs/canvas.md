# Floria.Canvas.Agg & 2D Graphics Subsystem

## 1. Overview & Architecture

`Floria.Canvas.Agg` is a high-performance, 2D vector and raster graphics canvas built on top of **AggPas** (Anti-Grain Geometry for Pascal) and integrated natively with `florialib`'s core units:
- **`Floria.Canvas.Agg`**: 2D anti-aliased canvas rendering to 32-bit BGRA raster buffers (`TFloriaImage`).
- **`Floria.Image.Blur`**: Multi-pass downsampled box blur with bilinear reconstruction and rounded corner masking.
- **`Floria.Font`**: FreeType font engine and cache manager with DPI scaling, stem darkening, and fallback chaining.
- **`Floria.SVG.Rasterizer`**: Vector rasterizer that maps `TSVGDocument` and `TSVGElement` scenes directly onto `Floria.Canvas.Agg`.

```
                        ┌─────────────────────────────────┐
                        │      TFloriaImage (BGRA32)      │
                        └───────────────┬─────────────────┘
                                        │ PixFormatPtr / Buffer
                                        ▼
                        ┌─────────────────────────────────┐
                        │        TFloriaCanvasAgg         │
                        └───────┬─────────────────┬───────┘
                                │                 │
            ┌───────────────────┴───┐         ┌───┴────────────────────┐
            ▼                       ▼         ▼                        ▼
  ┌───────────────────┐   ┌───────────────────┐ ┌───────────────────┐  ┌───────────────────┐
  │ Vector Primitives │   │ Floria.Image.Blur │ │    Floria.Font    │  │ Floria.SVG.Raster │
  ├───────────────────┤   ├───────────────────┤ ├───────────────────┤  ├───────────────────┤
  │ • Lines & Rects   │   │ • Fast box blur   │ │ • FreeType Cache  │  │ • SVG DOM render  │
  │ • Rounded corners │   │ • Rounded rect    │ │ • DPI scaling     │  │ • Linear / Radial │
  │ • Outlines & Join │   │ • Zero artifacts  │ │ • CJK Fallback    │  │   gradient LUTs   │
  │ • Drop shadows    │   │ • SIMD-friendly   │ │ • Gamma / dark    │  │ • Path curves     │
  └───────────────────┘   └───────────────────┘ └───────────────────┘  └───────────────────┘
```

---

## 2. Drawing on a Canvas

### Creating and Clearing

```pascal
uses
  Floria.Image.Core, Floria.Canvas.Agg;

var
  Img: TFloriaImage;
  Canvas: TFloriaCanvasAgg;
begin
  Img := TFloriaImage.Create(800, 600);
  try
    Canvas := TFloriaCanvasAgg.Create(Img);
    try
      // Clear with RGB [0..1]
      Canvas.Clear(0.15, 0.15, 0.18);

      // Draw anti-aliased shapes
      Canvas.DrawRoundedRect(50, 50, 200, 100, 12.0, 0.2, 0.5, 0.9, 1.0);
      Canvas.DrawRoundedRectOutline(50, 50, 200, 100, 12.0, 2.0, 1.0, 1.0, 1.0, 0.8);
    finally
      Canvas.Free();
    end;

    // Save directly to PNG using pure Pascal writer
    Img.SaveToFile('output.png', fifPNG);
  finally
    Img.Free();
  end;
end;
```

---

## 3. Advanced Features

### Drop Shadows & Rounded Rectangles
`DrawShadow` computes multiple feathered alpha steps:
```pascal
Canvas.DrawShadow(X, Y, W, H, Radius, OffsetX, OffsetY, BlurRadius, ShadowR, ShadowG, ShadowB, ShadowOpacity);
```

### Clipping Stacks
Supports both rectangular and rounded rectangle clipping:
```pascal
Canvas.PushClipRoundedRect(100, 100, 400, 300, 16.0);
try
  // Anything drawn here is clipped cleanly to the rounded card
finally
  Canvas.PopClipRoundedRect();
end;
```

### Image Blitting & Scaling
Draws `TFloriaImage` onto the canvas with alpha blending and high-performance bilinear scaling:
```pascal
Canvas.DrawImage(10, 10, MySubImage, 0.9);
Canvas.DrawImageScaled(100, 100, 300, 200, MySubImage, 1.0);
```

### SVG Rendering
Render vector SVGs directly onto the canvas:
```pascal
uses
  Floria.SVG.DOM, Floria.SVG.Parser, Floria.SVG.Rasterizer;

var
  Doc: TSVGDocument;
begin
  Doc := TSVGParser.ParseFile('icon.svg');
  try
    TFloriaSVGRenderer.Render(Canvas, Doc, 50, 50, 64, 64);
  finally
    Doc.Free();
  end;
end;
```

---

## 4. Extended 29 W3C & Skia Blend Modes

`Floria.Blend` implements the full complement of 29 standard 2D blend modes:
- **Porter-Duff & Arithmetic (14)**: `fbmClear`, `fbmSrc`, `fbmDst`, `fbmSrcOver`, `fbmDstOver`, `fbmSrcIn`, `fbmDstIn`, `fbmSrcOut`, `fbmDstOut`, `fbmSrcATop`, `fbmDstATop`, `fbmXor`, `fbmPlus`, `fbmModulate`.
- **Separable Color (11)**: `fbmMultiply`, `fbmScreen`, `fbmOverlay`, `fbmDarken`, `fbmLighten`, `fbmColorDodge`, `fbmColorBurn`, `fbmHardLight`, `fbmSoftLight`, `fbmDifference`, `fbmExclusion`.
- **Non-Separable HSL (4)**: `fbmHue`, `fbmSaturation`, `fbmColor`, `fbmLuminosity`.

```pascal
Canvas.SetBlendMode(fbmOverlay);
Canvas.DrawImage(0, 0, OverlayTexture, 0.75);
Canvas.SetBlendMode(fbmSrcOver); // Reset to default
```

---

## 5. Color Spaces & Linear-Light Pipeline

`Floria.ColorSpace` provides high-precision color management and HDR pixel formats:
- **Supported Gamuts**: sRGB, Linear sRGB, Display P3, Rec. 2020, Adobe RGB.
- **Transfer Functions**: IEC 61966-2-1 piecewise sRGB, Pure Gamma (2.2, 2.8), SMPTE ST 2084 PQ (HDR10), ITU-R BT.2100 HLG.
- **High-Precision Formats**:
  - `TRgbaF16`: 64-bit IEEE 754 half-precision float per pixel.
  - `TRgbaF32`: 128-bit single-precision float per pixel.
- **Physical Linear Blending**: `FloriaBlendPixelLinear` evaluates blend operations in physical linear light, completely eliminating dark muddy halos around anti-aliased boundaries.

---

## 6. Composable Filter Graph

`Floria.Filter` allows non-destructive image filter pipelining:
- **`TBlurFilter`**: Gaussian blur (3-pass Central Limit Theorem $O(1)$), fast box blur, or Dual Kawase blur.
- **`TColorMatrixFilter`**: $4 \times 5$ color transformation matrix with presets (`fcmGrayscale`, `fcmInvert`, `fcmSepia`, `fcmSaturation`).
- **`TDropShadowFilter`**: Configurable offset $(DX, DY)$, blur sigma, and shadow color.
- **`TMorphologyFilter`**: Mathematical morphology operators (Dilate / Erode).
- **`TDisplacementMapFilter`**: SVG `<feDisplacementMap>` sub-pixel bilinear sampling.

```pascal
var
  Blur: TBlurFilter;
  Shadow: TDropShadowFilter;
  Pipeline: TFloriaImageFilter;
  ResultImg: TFloriaImage;
begin
  Blur := TBlurFilter.CreateGaussian(8.0);
  Shadow := TDropShadowFilter.Create(4.0, 4.0, 10.0, RGBA(0, 0, 0, 180));
  Pipeline := Shadow.Compose(Blur);
  try
    ResultImg := Pipeline.Apply(SourceImage);
  finally
    Pipeline.Free();
  end;
end;
```

---

## 7. Vector Path & Boolean Operations

`Floria.Path` provides Angus Johnson's Clipper2 engine and high-level `TFloriaPath`:
- **Path Operations**: `Union`, `Difference`, `Intersect`, `XorOp`.
- **Contour Offsetting**: `Inflate` with Miter, Round, Bevel joins and Butt, Square, Round caps.
- **Simplification**: Douglas-Peucker contour reduction.
- **Bézier Curves**: Adaptive de Casteljau quadratic and cubic curves with chord error tolerance.

---

## 8. Retained Display Lists & Tile Caching

- **`TFloriaPicture` & `TFloriaPictureRecorder`**: Record drawing commands into a retained serializable display list with 2D affine transforms and spatial culling.
- **Analytical Clip Chains (`Floria.DisplayList.Clip`)**: Rounded-rect clip stacks evaluated analytically via SDF in uniforms, bypassing offscreen FBO allocation.
- **2D R-Tree Spatial Index (`Floria.DisplayList.Spatial`)**: Logarithmic viewport culling and damage query times.
- **Tile Cache (`Floria.DisplayList.Cache`)**: 2D tile grid with dirty region invalidation for zero-redraw panning and scrolling.

---

## 9. Hardware-Accelerated GPU Canvas (`Floria.Canvas.GPU`)

`Floria.Canvas.GPU` provides polymorphic hardware acceleration matching the software canvas:
- Native X11 EGL 1.4/1.5 context management and VSync synchronization.
- High-throughput instanced quad batching (`TFloriaRenderBatch`) and dynamic skyline texture atlas (`TFloriaGPUAtlas`).
- AOT precompiled GLSL shaders with SDF rounded rectangles, borders, box shadows, and linear gradients.
- Native stroke tessellation with AA boundary skirts and ear-clipping triangulation.
- Automatic fallback to AggPas for arbitrary complex SVG vector paths.
