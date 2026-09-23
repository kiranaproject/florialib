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
