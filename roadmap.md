# Floria Graphics Architecture Roadmap: Evolution Toward Skia-Level Parity

## 1. Executive Summary & Vision

The objective of this roadmap is to establish a clear, phased engineering strategy to evolve **`florialib`**'s rendering and typography foundations (`Floria.Canvas.*`, `Floria.Font.*`, `Floria.SVG.*`) and **Floria Toolkit (`ft`)** into an industrial-grade 2D graphics engine comparable in capabilities and performance to **Google Skia** (the engine powering Chromium, Android, Flutter, Firefox, and Avalonia).

Today, `florialib` boasts a solid foundation:
- **`AggPas:2.4.0`**: A mathematically rigorous, sub-pixel accurate CPU 2D vector rasterizer decoupled from legacy frameworks.
- **Modern Typography Pipeline**: FreeType glyph caching, HarfBuzz text shaping (`Floria.Text.HarfBuzz`), and FriBidi bidirectional reordering (`Floria.Unicode.BiDi`).
- **W3C CSS & SVG Engines**: Complete push tokenizers, AST, selector matching, cascade solvers, and SVG path rasterization.
- **Hardware Presentation**: EGL 1.4/1.5 and OpenGL ES 2.0 streaming pipeline (`Ft.Backend.EGL`).

However, reaching "Skia level" requires overcoming architectural bottlenecks: transitioning from immediate-mode CPU rasterization to **retained display lists**, **native GPU path rendering**, **true color space pipelines (HDR/Linear sRGB)**, **arbitrary boolean path operations**, and **composable filter graphs**.

---

## 2. Architectural Comparison: Florialib vs. Google Skia

```mermaid
flowchart TD
    subgraph FloriaCurrent ["florialib Today"]
        A_CPU["CPU Rasterizer: AggPas (Scanline AA)"]
        A_Color["Color: 32-bit BGRA (8-bit sRGB assumption)"]
        A_Paint["Paint: Solid, Linear/Radial Gradient LUTs, Basic Blur"]
        A_Paths["Geometry: Curves, Strokes, Basic Clipping"]
        A_Text["Text: FreeType + HarfBuzz + FriBidi (Manual Widget Wrap)"]
        A_Pres["Compositing: Software Buffer Upload to EGL Texture Quad"]
    end

    subgraph SkiaTarget ["Skia-Level Parity Target"]
        S_GPU["Native GPU Rasterizer: Graphite / Ganesh (Path Shaders & Tessellation)"]
        S_Color["Color: SkColorSpace (sRGB, P3, Rec2020, FP16/10-bit HDR)"]
        S_Paint["Paint: 29 Blend Modes, SkSL Shaders, Composable Filter Graphs"]
        S_Paths["Geometry: SkPathOp (Boolean Union/Intersect/Diff, Contours)"]
        S_Text["Text: SkParagraph (Unicode Line Break UAX#14, Fallback Cascades)"]
        S_Pres["Compositing: SkPicture & DisplayLists (R-Tree Culling, Retained Layers)"]
    end

    FloriaCurrent -.->|Phased Evolution| SkiaTarget
```

### Detailed Domain Gap Matrix

| Capability Domain | `florialib` Current State | Google Skia Benchmark | Gap Severity | Target Milestone |
| :--- | :--- | :--- | :--- | :--- |
| **Vector Rasterization** | CPU scanline rasterization via AggPas. | GPU path rasterization via compute shaders and tessellation (Ganesh/Graphite). | **Critical** | Phase 3 |
| **Color Spaces & HDR** | Fixed 32-bit BGRA (`TBgraPixel`, 8bpc), implicit gamma 2.2 approximation. | Arbitrary color spaces (`SkColorSpace`), ICC profiles, FP16 linear, 10-bit HDR, gamut mapping. | **High** | Phase 1 |
| **Blend Modes** | Porter-Duff `SrcOver`, alpha-blended strokes. | 29 Blend Modes (12 Porter-Duff + 17 Photoshop/W3C modes like Multiply, Screen, Overlay). | **Medium** | Phase 1 |
| **Shaders & Filter Graphs** | Linear and radial gradient LUTs, box blur, drop shadow generator. | Composable filter trees (blur, color matrix, lighting, morphology) + SkSL runtime shaders. | **High** | Phase 1 & 2 |
| **Path Geometry & Ops** | Path storage, cubic/quadratic beziers, stroke expansion, affine transforms. | Boolean path operations (`SkPathOp`: Union, Difference, Intersect, XOR), contour simplification. | **High** | Phase 1 |
| **Text & Typography** | FreeType + HarfBuzz + FriBidi glyph runs. Manual widget line wrap. | Multi-style rich text paragraph engine (`SkParagraph`), UAX #14 line breaking, font fallback chains, variable fonts, color emoji (COLR/CPAL). | **High** | Phase 1 |
| **Scene Graph & Caching** | Immediate mode rasterization into window buffer with dirty rectangles. | Retained command recording (`SkPicture`), spatial R-Tree indexing, thread-safe replay, layer tile caching. | **High** | Phase 2 |
| **Hardware Backends** | X11/XCB with EGL/OpenGL ES 2.0 texture streaming. | Vulkan, Metal, Direct3D 12, OpenGL ES, WebGPU. | **Medium** | Phase 3 |

### 2.2 The Modern Rendering Landscape: Google Skia vs. Flutter Impeller vs. Mozilla WebRender

To build a world-class 2D graphics and desktop UI stack in pure Object Pascal and GLSL/Vulkan, we synthesize the key architectural breakthroughs of three major modern graphics engines:

1. **Google Skia**: Our functional benchmark for **mathematical and colorimetric completeness** (29 blend modes, arbitrary color spaces, Clipper2 path ops, HarfBuzz typography, and high-precision software scanline ground truth).
2. **Flutter Impeller**: Our modern blueprint for **zero-jank GPU vector execution** (100% AOT precompiled shaders with static PSOs, eliminating runtime shader compilation pauses, and direct single-pass triangle strip tessellation).
3. **Mozilla WebRender**: Our blueprint for **high-throughput retained desktop UI compositing** (treating UI like 3D game geometry, instanced mega-batching, analytical clip chains in fragment shaders, picture tile caching, and delegating complex arbitrary vector paths to a fallback blob rasterizer).

#### The Triangle of Modern 2D Graphics Engines

```mermaid
flowchart TD
    subgraph SkiaEngine ["Google Skia (Ground Truth)"]
        SK1["Low-Level 2D Vector Primitives"]
        SK2["Arbitrary Bezier Curves & PathOps"]
        SK3["Full-Spectrum Color & Typography"]
    end

    subgraph ImpellerEngine ["Flutter Impeller (Zero-Jank Vector Pipeline)"]
        IM1["AOT Precompiled Shaders (No Runtime JIT)"]
        IM2["Single-Pass Direct Triangle Tessellation"]
        IM3["Modern Explicit APIs (Vulkan / Metal)"]
    end

    subgraph WebRenderEngine ["Mozilla WebRender (Game-Engine UI Compositor)"]
        WR1["Retained Display List (Semantic UI Items)"]
        WR2["Instanced Quad Mega-Batching"]
        WR3["Analytical Clip Chains in Shaders"]
        WR4["Retained Picture Tile Caching"]
    end

    WebRenderEngine -.->|"Delegates complex SVG paths to"| SkiaEngine
    ImpellerEngine -.->|"Modernizes GPU vector backend of"| SkiaEngine
```

#### Multi-Engine Architectural Matrix

| Architectural Dimension | Google Skia (Ganesh) | Flutter Impeller | Mozilla WebRender | Florialib Target Architecture |
| :--- | :--- | :--- | :--- | :--- |
| **Primary Domain** | Universal 2D (Browsers, OS compositors, PDF, print). | Reactive mobile/desktop UI (Flutter). | Web browser viewport rendering (Firefox Quantum/Servo). | Desktop desktop environment (`shellsama`) & widget toolkit (`ft`). |
| **Shader Lifecycle** | **Runtime JIT via SkSL**: Generates shaders on demand; causes 50–200ms frame drops on first draw. | **100% Ahead-Of-Time (AOT)**: All shaders compiled offline; static PSOs. Zero runtime shader compilation. | **AOT Mega-Shaders**: Fixed, bounded set of uber-shaders with uniform buffer parameters. | **100% AOT Precompiled Shaders**: Zero runtime JIT compilation jank on desktop GPUs. |
| **Path Rendering** | **Stencil-and-Cover**: Multi-pass stencil buffer or CPU mask atlas blits. | **Direct Tessellation**: Decomposes paths to triangle strips with analytic AA. | **Fallback Blob Rasterizer**: Skia rasterizes complex SVG paths to texture cache; WebRender composites. | **Impeller + WebRender Hybrid**: Direct tessellation for common paths; AggPas CPU blob cache for arbitrary complex SVGs. |
| **UI Primitive Handling** | Treats all drawing as low-level procedural canvas strokes/fills. | Retained `EntityPass` tree with vertex generation. | **The 95/5 Rule**: 95% of UI (rects, rounded corners, borders, shadows, text) are instanced GPU quads. | **95/5 Rule**: Instanced quads + SDF shaders for UI primitives; AggPas for 5% complex vector art. |
| **Clipping Strategy** | Allocates offscreen FBOs or GPU stencil masks. | Stencil or clip geometry bounding hulls. | **Analytical Clip Chains**: Passes stack of rounded clip boxes to shader; shader discards or computes AA coverage. | **Analytical Clip Chains**: Zero offscreen FBO allocation for nested rounded rect clipping. |
| **Pass Compositing** | Immediate mode stream; dynamic `saveLayer()` FBO switches. | Retained pass tree with pass reordering. | **Retained Picture Caching**: Breaks viewport into cached GPU tiles; scrolling only updates transform matrix. | **Retained `TFloriaTileCache`**: Zero-CPU-rasterization scrolling and window dragging in `shellsama`. |

#### 5 Architectural Tenets Adopted for Florialib:

1. **The "95 / 5 Rule" of Desktop UI (from WebRender)**:
   - 95% of desktop UI elements (window frames, buttons, taskbar panels, borders, text labels, drop shadows) are **regular analytical geometric shapes**, not arbitrary beziers.
   - We do not run CPU scanlines for simple rounded boxes or shadows: an instanced quad evaluated in a fragment shader with a Signed Distance Field (SDF) renders anti-aliased rounded boxes and blurs at 1,000+ FPS with zero CPU overhead.
2. **Analytical Clip Chains in Shaders (from WebRender)**:
   - Nested rounded clipping no longer requires allocating temporary offscreen textures or stencil buffers. Clip rectangles and radiuses are packed into uniform buffers, and the fragment shader analytically evaluates boundary distance (`distance_to_clip < 0.0 -> discard`).
3. **Zero-Jank AOT Shaders (from Impeller)**:
   - All shaders for color blending, gradient ramps, SDF rounded corners, box shadows, and frosted-glass blurs are precompiled ahead-of-time (offline GLSL/SPIR-V) with static Pipeline State Objects (PSOs).
4. **Direct Single-Pass Tessellation (from Impeller)**:
   - Vector paths and stroked outlines are triangulated into vertex strips and drawn directly into the color target in a single pass with analytic coverage, avoiding multi-pass stencil barriers.
5. **Retained Picture Tile Caching & Blob Rasterizer (from WebRender + AggPas)**:
   - Scrollable containers and desktop panels are cached as GPU texture tiles. Scrolling in `shellsama` simply updates quad transform coordinates with zero redraw overhead.
   - Pure Object Pascal AggPas acts as our reliable background "blob rasterizer" for high-precision SVG assets.

---

## 3. Phased Implementation Roadmap

```mermaid
gantt
    title Florialib Skia-Parity Roadmap
    dateFormat  YYYY-MM
    section Phase 1: High-End CPU Parity
    Extended Blend Modes (29 Modes)          :p1_1, 2026-10, 2026-11
    Color Spaces & Linear FP16 Pipeline       :p1_2, 2026-11, 2026-12
    Composable Filter Graph Architecture      :p1_3, 2026-12, 2027-01
    Boolean Path Operations (Clipper2)        :p1_4, 2027-01, 2027-02
    Rich Paragraph Layout Engine              :p1_5, 2027-02, 2027-03
    section Phase 2: Display Lists & Caching
    TFloriaPicture & Command Serialization    :p2_1, 2027-03, 2027-04
    Spatial R-Tree Viewport Culling           :p2_2, 2027-04, 2027-05
    Retained Layer Compositing & Tile Cache   :p2_3, 2027-05, 2027-06
    section Phase 3: GPU Vector Core
    Hybrid GPU Pipeline (Atlas + Shaders)     :p3_1, 2027-06, 2027-09
    Native GPU Path Renderer (Compute/Tess)   :p3_2, 2027-09, 2028-02
```

---

## 4. Phase Breakdown & Engineering Specifications

### Phase 1: High-End 2D CPU Parity (Months 1–6)
*Goal: Elevate the mathematical, colorimetric, and layout capabilities of `florialib` so that its CPU rasterizer matches Skia's feature set.*

#### 1.1 Extended Blend Modes (`Floria.Canvas.Blend`) — [COMPLETED]
- Implemented the full set of 29 standard blend modes:
  - **Porter-Duff & Arithmetic (14)**: `Clear`, `Src`, `Dst`, `SrcOver`, `DstOver`, `SrcIn`, `DstIn`, `SrcOut`, `DstOut`, `SrcATop`, `DstATop`, `Xor`, `Plus`, `Modulate`.
  - **Separable Color (11)**: `Multiply`, `Screen`, `Overlay`, `Darken`, `Lighten`, `ColorDodge`, `ColorBurn`, `HardLight`, `SoftLight`, `Difference`, `Exclusion`.
  - **Non-Separable HSL (4)**: `Hue`, `Saturation`, `Color`, `Luminosity` (W3C standard color transforms).
- Integrated directly with `Floria.Canvas.Agg` via `FloriaAggBlendAdaptor` (`pixfmt_custom_blend_rgba`) and updated `DrawImage` / `DrawImagePart`.
- Verified with 39 dedicated unit tests and full canvas integration tests (404/404 passing in `florialib`, 48/48 in `ft`).

#### 1.2 Color Management & Linear Float Pipeline (`Floria.ColorSpace`) — [COMPLETED]
- Implemented `TFloriaColorSpace` with chromaticities and 3x3 conversion matrices:
  - CIE 1931 D65 white point: sRGB, Linear sRGB, Display P3, Rec. 2020, Adobe RGB (1998).
  - Transfer functions: Linear, sRGB (IEC 61966-2-1 piecewise), Gamma 2.2, Gamma 2.8, SMPTE ST 2084 PQ (HDR10), and ITU-R BT.2100 HLG.
  - Precomputed fast lookup table `GSRGBToLinearLUT[0..255]` for zero-overhead 8-bit conversions.
- Implemented high-precision pixel formats alongside `TBgraPixel`:
  - `TRgbaF16`: 64-bit IEEE 754 half-precision float (`FloatToHalf`, `HalfToFloat` bitwise algorithms handling subnormals and infinity).
  - `TRgbaF32`: 128-bit single-precision float with premultiply/demultiply and clamp operations.
- Linear light alpha compositing & anti-aliased edge blending:
  - `FloriaBlendPixelLinear` and `FloriaBlendScanlineLinear` evaluate all 29 blend modes in physical linear light.
  - Mathematically eliminates dark fringing (muddy brown/olive halo) on semi-transparent and anti-aliased boundaries.
- Verified with 25 dedicated unit tests (429/429 passing in `florialib`, 48/48 in `ft`).

#### 1.3 Composable Filter Graph (`Floria.Canvas.Filter`) — [COMPLETED]
- Architected a clean, non-destructive composable filter tree:
  - `TFloriaImageFilter` base class with `Apply(Src, Bounds): TFloriaImage`, `ApplyInPlace`, fluent `Compose` (pipelining) and `Composite` (dual-tree blend).
  - `TColorMatrixFilter`: $4 \times 5$ color transformation matrix with presets for `Grayscale`, `Invert`, `Sepia`, `Saturation`, `Brightness`, `Contrast`, and `Tint`.
  - `TBlurFilter`: Multi-algorithm blur supporting `fbtGaussian` (3-pass separable $O(1)$ box Central Limit Theorem approximation), fast `fbtBox`, and `fbtDualKawase`.
  - `TDropShadowFilter`: Configurable offset $(DX, DY)$, blur sigma, shadow tint color, and shadow-only or composite mode.
  - `TMorphologyFilter`: Separable 2D mathematical morphology operators (`fmoDilate` / `fmoErode`) with configurable rectangular radii.
  - `TDisplacementMapFilter`: SVG `<feDisplacementMap>` pixel displacement with sub-pixel bilinear sampling across arbitrary RGBA channels.
  - `TComposeFilter` & `TCompositeFilter`: Fluent graph chaining and blend mode composition.
- Verified with 20 dedicated unit tests (483/483 passing in `florialib`, 48/48 in `ft`).

#### 1.4 Boolean Path Operations (`Floria.Path.Ops`) — [COMPLETED]
- Integrated Angus Johnson's Clipper2 polygon clipping engine as pure Object Pascal units under dotted namespaces:
  - `Floria.Path.Clipper.Core`: Coordinate types (`TPoint64`, `TPointD`, `TRect64`, `TRectD`), winding rules (`TFillRule`), and vector math.
  - `Floria.Path.Clipper.Engine`: Core sweep-line clipping engine, active edge table, intersection list, and PolyTree hierarchy.
  - `Floria.Path.Clipper.Offset`: High-performance polygon expansion, deflating, and stroke offset generation (`TClipperOffset`).
  - `Floria.Path.Clipper.RectClip`: Fast analytical rectangular window clipping (`TRectClip64`, `TRectClipLines64`).
  - `Floria.Path.Clipper.Minkowski`: 2D Minkowski sum algorithms.
  - `Floria.Path.Clipper`: High-level procedural API (`Union`, `Difference`, `Intersect`, `XOR_`, `InflatePaths`, `RectClip`).
- Implemented high-level `TFloriaPath` class:
  - Procedural construction: `MoveTo`, `LineTo`, `QuadTo`, `CubicTo` (adaptive de Casteljau recursive subdivision), `ArcTo`, and `Close`.
  - Shape generators: `AddRect`, `AddRoundedRect`, `AddCircle`, `AddEllipse`, and `AddPolygon`.
  - First-class boolean operations: `Union`, `Difference`, `Intersect`, and `XorOp`.
  - Contour offsetting / inflation: `Inflate` supporting join styles (`Round`, `Miter`, `Square`, `Bevel`) and end caps (`Polygon`, `Joined`, `Butt`, `Square`, `Round`).
  - Simplification: `Simplify` using Douglas-Peucker reduction.
  - Contour winding rule resolution: NonZero, EvenOdd, Positive, and Negative.
  - Seamless interop: Two-way conversion between `TFloriaPath`, AggPas `path_storage`, SVG `<path>` data strings (`d="..."`), and Clipper native `TPathsD`.
  - Direct AggPas `path_storage` boolean functions: `PathUnion`, `PathDifference`, `PathIntersect`, `PathXor`.
- Verified with 16 dedicated unit tests (499/499 passing in `florialib`, 48/48 in `ft`).

#### 1.5 Rich Paragraph Layout Engine (`Floria.Text.Paragraph`) — [COMPLETED]
- Decoupled rich multi-style text layout and shaping from GUI widgets into a standalone typography engine:
  - **Multi-Style Spans**: Fluent `TFloriaParagraphBuilder` (`PushStyle`, `PopStyle`, `AddText`, `AddPlaceholder`, `Build`) managing nested character styles with independent font family, size, weights, italic slants, colors, background highlights, letter spacing, word spacing, height multipliers, and baseline offsets.
  - **Unicode Line Breaking (UAX #14)**: Multilingual line breaking supporting whitespace word breaks, mandatory newline sequences (`\n`, `\r\n`), CJK ideographs/Kana/Hangul boundary breaks, Kinsoku Shori punctuation rules (opening/closing punctuation constraints), soft hyphens (`&shy;`), and emergency break-all wrapping.
  - **Paragraph Formatting & Alignment**: `TFloriaParagraphStyle` supporting text alignments (`ftaLeft`, `ftaRight`, `ftaCenter`, `ftaJustify`, `ftaStart`, `ftaEnd`), text directions (`ftdLTR`, `ftdRTL`), first-line indentation (`TextIndent`), `MaxLines` constraints, and overflow behaviors (`ftoClip`, `ftoEllipsis` with custom ellipsis string).
  - **Vertical Baseline Alignment**: True typographic baseline alignment calculating ascents and descents across mixed font sizes and inline elements on identical lines.
  - **Inline Placeholders**: Support for inline chips, badges, icons, and embedded widgets (`AddPlaceholder`, `GetPlaceholderBounds`) with custom width, height, and alignment (`fpaBaseline`, `fpaTop`, `fpaBottom`, `fpaMiddle`).
  - **Hit-Testing & Selection**: `GetPositionForOffset(X, Y)` for accurate caret placement, `GetRectsForRange(Start, End)` generating contiguous multi-line selection bounding rectangles, and line metrics inspection (`GetLineMetrics`).
  - **Direct Canvas Painting**: `Paragraph.Paint(Canvas, X, Y)` rendering text decorations (underline, overline, strikethrough), background highlight fills, and text runs with sub-pixel precision.
- Verified with 18 dedicated unit tests (517/517 passing in `florialib`, 48/48 in `ft`).

---

### Phase 2: Retained Display Lists & Scene Graph Caching (Months 7–9)
*Goal: Prevent redundant CPU vector re-rasterization by introducing WebRender-inspired semantic display lists, analytical clip chains, and picture tile caching.*

#### 2.1 Semantic Retained Display List (`TFloriaDisplayList` / `TFloriaPicture`) — [COMPLETED]
- Implemented a high-performance semantic recording model and retained display list container:
  - **`TFloriaPictureRecorder` / `TFloriaDisplayListBuilder`**: Fluent, canvas-like recording interface:
    - Transform and state management: `Save`, `Restore`, `SetTransform`, `Translate`, `Scale`, `Rotate` (degrees about arbitrary center), `PushAlpha`, `PopAlpha`, `SetBlendMode`.
    - Clipping: `PushClipRect`, `PushClipRoundedRect`, `PopClip`.
    - Drawing primitives: `Clear`, `DrawRect`, `DrawRoundedRect`, `DrawRoundedRectOutline`, `DrawCircle`, `DrawLine`, `DrawPath` (integrating `TFloriaPath` with cloned resource ownership and winding rules).
    - Semantic high-level UI items: `DrawShadow` (with spread and blur dilation), `DrawBorder` (uniform and per-side widths/colors with corner radii), `DrawLinearGradient` (multi-stop color interpolation along arbitrary angles and vectors).
    - Typography: `DrawText` (with Font and Font-size overloads) and `DrawParagraph` (`Floria.Text.Paragraph` layout integration).
    - Images & Sub-Pictures: `DrawImage` (scaled and sub-rect blits) and `DrawPicture` (arbitrary recursive sub-picture nesting).
    - Layer compositing: `SaveLayer` (with opacity, blend mode, and filter graph integration) and `RestoreLayer`.
  - **Conservative Analytical Bounding Boxes & Viewport Culling**:
    - `TFloriaMatrix2D`: Complete 2D affine transformation record (Identity, Translation, Scaling, Rotation, Inversion, Determinant, Point/Rect transforms).
    - Every recorded operation calculates its conservative bounding box in root coordinate space.
    - `CullRect`: The picture computes the tight conservative axis-aligned bounding box of all visual items.
    - `Playback(Canvas, ClipBounds)`: Automatic spatial culling skips non-intersecting drawing primitives, eliminating redundant vertex math and rasterization.
  - **Visitor / Receiver Pattern**:
    - `IFloriaDisplayListReceiver` / `TFloriaDisplayListReceiver`: Extensible receiver interface enabling GPU compilation, custom analyzers, SVG export, and debugging.
    - Diagnostic `Dump()` method generating detailed human-readable logs of recorded operation streams.
- Verified with 18 dedicated unit tests (535/535 passing in `florialib`, 48/48 in `ft`).

#### 2.2 Analytical Clip Chains & Spatial Viewport Culling (`Floria.DisplayList.Clip` & `Floria.DisplayList.Spatial`) — [COMPLETED]
- Implemented WebRender-inspired analytical clip chains and 2D R-Tree spatial acceleration:
  - **Analytical Clip Chains (`Floria.DisplayList.Clip`)**:
    - Primitives: Rectangles (`fckRect`) and rounded rectangles (`fckRoundedRect`) with per-corner radii (`TopLeft`, `TopRight`, `BottomRight`, `BottomLeft`).
    - Hierarchical `TFloriaClipChain` managing nested clip stacks with affine matrix coordinate transformations and cumulative conservative bounding boxes.
    - Exact analytical point containment (`ContainsPoint`, `AnalyticalPointInRoundedRect`) and signed distance field evaluation (`SignedDistance`, `AnalyticalRoundedRectSDF`).
    - Three-way conservative intersection testing (`TestRect`: `ctrOutside`, `ctrInside`, `ctrIntersecting`) allowing non-intersecting geometry to be completely bypassed and fully enclosed geometry to avoid shader clip tests.
    - GPU uniform buffer packing: `PackGPUUniforms` generating 64-byte std140-aligned uniform structs (`TFloriaGPUClipItem`) ready for direct upload to uniform buffers / UBOs in shaders.
  - **2D R-Tree Spatial Acceleration Structure (`Floria.DisplayList.Spatial`)**:
    - Pure Pascal 2D R-Tree implementation (`TFloriaRTree2D`, `TFloriaRTreeNode`) with Guttman Quadratic split algorithm (`PickSeeds`, `Distribute`).
    - Bulk indexing from retained display lists: `TFloriaRTree2D.BuildFromPicture` automatically extracts bounding boxes of all visual draw commands.
    - Logarithmic spatial querying: `Search(QueryRect)` returning candidate draw operations with strict Z-order preservation.
    - Integrated `TFloriaSpatialDisplayList`: Combines retained pictures with the R-Tree index for $O(\log N)$ damage-region queries and viewport-culled playback.
- Verified with 12 dedicated unit tests (547/547 passing in `florialib`, 48/48 in `ft`).

#### 2.3 Retained Picture Tile Caching (`Floria.DisplayList.Cache`) — [COMPLETED]
- Implemented WebRender-style retained picture tile caching:
  - **Tile Grid Slicing & Storage**:
    - Uniform 2D tile coordinate grid (`TFloriaTileCoord`, `Col`, `Row`) dividing display list space into fixed-size square tiles (`DEFAULT_TILE_SIZE = 256` or custom).
    - Dedicated `TFloriaPictureTile` maintaining local world bounds, raster surface backing buffer (`TFloriaImage`), dirty damage state, scale factor, and LRU access epoch timestamp.
  - **Selective Damage Invalidation**:
    - `InvalidateRect(DirtyRect)` maps dirty region bounds to the minimal set of intersecting tile coordinates, ensuring unchanged tiles remain cached and never re-render.
    - Full cache invalidation via `InvalidateAll()`.
  - **High-Performance Viewport & Scroll Rendering**:
    - `PrepareViewport(Viewport)`: Pre-rasterizes only dirty visible tiles on demand using clipped picture playback, recording cache hits and rasterization statistics.
    - `RenderViewport(Canvas, Viewport, DestPoint)` and `RenderScroll(Canvas, Viewport, DestX, DestY)`: Directly composites cached tile bitmaps with automatic canvas boundary clipping. Panning or scrolling a document/window reuses 100% of existing tiles with zero CPU vector recalculation.
  - **LRU Memory Budget & HiDPI Awareness**:
    - Configurable cache budget (`MaxCachedTiles`, default 128 tiles / ~32MB). Automatic LRU eviction drops oldest off-screen tiles while safeguarding active frame tiles.
    - HiDPI sub-pixel scaling: `ScaleFactor` renders tile raster buffers at device pixel density for crisp vector display on Retina/4K screens.
- Verified with 9 dedicated unit tests (556/556 passing in `florialib`, 48/48 in `ft`).

---

### Phase 3: Hardware-Accelerated GPU Vector Core (Months 10–18)
*Goal: True hardware GPU vector acceleration for 60/120 FPS high-refresh-rate desktop applications using an Impeller + WebRender hybrid design.*

#### 3.1 The Hybrid Fast-Path & Blob Rasterizer Approach (Immediate High-Value Step)
- **Fast Path (95% of UI)**: Evaluate rounded boxes, borders, gradients, drop shadows, and backdrop frosted-glass blurs 100% in **AOT fragment shaders** on instanced quads.
- **Fallback Blob Rasterizer (5% of UI)**: Maintain pure Pascal `Floria.Canvas.Agg` on background threads for arbitrary complex SVG paths and vector artwork, uploading rasterized masks to a shared GPU texture atlas (`TFloriaGPUAtlas`).
- Zero memory blitting bottlenecks on the main presentation thread.

#### 3.2 Native GPU Vector Rasterizer (`Floria.Canvas.GPU`) — Impeller-Style Architecture
- Implement direct GPU path evaluation with guaranteed 60/120 FPS frame pacing:
  - **AOT Precompiled Shaders**: Precompile all fragment/vertex shaders ahead of time (offline SPIR-V/GLSL) into static Pipeline State Objects (PSOs), completely eliminating runtime shader compilation jank.
  - **Single-Pass Direct Tessellation**: Decompose curved paths into triangle strips with analytic coverage anti-aliasing directly in fragment shaders, avoiding multi-pass stencil buffers and CPU mask rasterization bottlenecks.
  - **Instanced Primitive Mega-Batching**: WebRender-style batching of rounded rectangles, outlines, gradients, and glyph quads into instanced vertex buffers (thousands of elements rendered in 2–5 draw calls).
  - **Compute Shader Tile Rasterizer**: Modern compute tile binning for arbitrary complex filled paths (inspired by Impeller & Vello).

#### 3.3 Multi-Platform Backend Abstraction
- Abstract GPU presentation across platforms:
  - Linux: X11/XCB via EGL + OpenGL ES 3.0 / Vulkan.
  - Windows: Direct3D 11/12 via ANGLE or native DXGI.
  - macOS: Metal / MoltenVK.

---

## 5. Summary of Recommended Next Steps

1. **Immediate (Sprint 1)**: Implement extended blend modes and gamma-correct linear color space blending in `Floria.Canvas.Agg`.
2. **Short-Term (Sprint 2–3)**: Port or bind **Clipper2** to deliver first-class boolean path operations (`Floria.Path.Ops`).
3. **Mid-Term (Sprint 4–6)**: Construct the standalone `TFloriaParagraph` engine with UAX #14 line-breaking and cascading font fallback.
4. **Long-Term**: Build the `TFloriaPicture` command recording pipeline and transition the EGL backend from a simple texture quad into a fragment-shader layer compositor.
