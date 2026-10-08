# florialib

A modern, high-performance Free Pascal library providing foundational subsystems for building GUI toolkits, desktop applications, 2D vector graphics, and X11 window managers.

Developed by **Dio Affriza** &bull; Licensed under the **Mozilla Public License 2.0 (MPL 2.0)** &bull; Built with **Pasbuild**.

[![FPC](https://img.shields.io/badge/Language-Free%20Pascal%203.2%2B-blue.svg)](https://www.freepascal.org/)
[![License: MPL 2.0](https://img.shields.io/badge/License-MPL%202.0-brightgreen.svg)](https://opensource.org/licenses/MPL-2.0)
[![Tests](https://img.shields.io/badge/Tests-579%20passed%20%7C%200%20errors-success.svg)](src/test/pascal/)

---

## Key Subsystems

### 1. W3C CSS Styling & Cascading Engine (`Floria.CSS.*`)

A complete, end-to-end CSS implementation written in Object Pascal following W3C specifications:

```
floria.css.types       (Tokens, token types, position tracking, listener interface)
      ↓
floria.css.tokenizer   (Streaming push tokenizer conforming to W3C CSS Syntax Level 3 §4)
      ↓
floria.css.ast         (AST nodes with automatic cascaded memory ownership)
      ↓
floria.css.parser      (W3C CSS Syntax Level 3 §5 parser)
      ↓
floria.css.values      (Typed values: TCSSColor, TCSSLength, TCSSBox, TCSSBorderSide, layout enums)
      ↓
floria.css.properties  (70+ canonical property IDs, metadata, style declarations, style blocks)
      ↓
floria.css.selectors   (Compound/complex selectors, specificity (A,B,C), combinators)
      ↓
floria.css.cascade     (ICSSElement abstraction, right-to-left matching, cascade resolver)
```

- **Push Tokenizer**: Full W3C CSS Syntax Level 3 §4 compliance, supporting 25 token types, streaming chunks, unicode escape sequence decoding, and resilient error recovery.
- **AST & Memory Hierarchy**: Ownership cascades cleanly through the AST (`TObjectList` with `FreeObjects = True`). Freeing the root stylesheet frees all descendant rules and declarations safely.
- **Rich Typed Values**:
  - `TCSSColor`: 32-bit RGBA, hex `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`, `rgb(...)` / `rgba(...)` (including modern slash syntax `rgb(255 128 0 / 0.5)`), and named CSS colors.
  - `TCSSLength`: Pixel conversion (`ToPixels()`), units (`px`, `em`, `rem`, `%`, `pt`, `vw`, `vh`), `auto`, `inherit`, `initial`, `unset`.
  - `TCSSBox`: 4-sided box model handling 1, 2, 3, and 4-value CSS shorthands.
  - `TCSSBorderSide`: Width, style, and color composite parsing.
  - Enums for display (`block`, `inline`, `flex`, `grid`, etc.), position, overflow, visibility, flexbox, text alignment, and font styling.
- **Property Model & Shorthand Expansion**:
  - 70+ canonical property IDs mapped with inheritance and shorthand metadata.
  - Automatic expansion of shorthands (`margin`, `padding`, `border`, `border-radius`, `border-top`..`left`).
- **W3C Selectors & Specificity**:
  - Specificity calculation `(A, B, C)` where `A` = IDs, `B` = classes/attributes/pseudos, `C` = types/elements.
  - Combinators: descendant (` `), child (`>`), adjacent sibling (`+`), general sibling (`~`).
  - Attribute operators: `[attr]`, `[attr=val]`, `[attr~=val]`, `[attr|=val]`, `[attr^=val]`, `[attr$=val]`, `[attr*=val]`.
  - Pseudo-classes: `:hover`, `:active`, `:focus`, `:first-child`, `:last-child`, `:disabled`, etc.
- **Cascade & Style Resolver**:
  - Toolkit-agnostic element contract (`ICSSElement`) and reference tree node (`TCSSMockElement`).
  - Right-to-left matching engine.
  - Cascading resolution ordering: `!important` &gt; Specificity `(A, B, C)` &gt; Source order.
  - Automatic inheritance of styling properties (`color`, `font-family`, `font-size`, `visibility`, etc.) from parent elements.

---

### 2. Pure XCB & X11 Window Manager Suite (`Floria.XCB.*`, `Floria.X11.*`)

A complete Pascal binding suite for XCB with **zero dependencies on legacy Xlib**:

- **Core XCB (`floria.xcb.pas`)**: Asynchronous, thread-safe connections, window creation, graphics contexts, events, atoms, and errors.
- **ICCCM 2.0 Protocol (`floria.xcb.icccm.pas`)**: Window manager protocols (`WM_PROTOCOLS`, `WM_DELETE_WINDOW`), window hints, and normal size hints.
- **EWMH / NetWM (`floria.xcb.ewmh.pas`)**: Modern desktop integration (`_NET_SUPPORTED`, `_NET_CLIENT_LIST`, `_NET_ACTIVE_WINDOW`, window types, window states, and struts).
- **RandR Multi-Monitor (`floria.xcb.randr.pas`)**: Dynamic screen resources, CRTCs, outputs, resolutions, and multi-display management.
- **XRender 2D Compositing (`floria.xcb.render.pas`)**: Hardware-accelerated alpha blending, picture formats, geometric primitives, and glyph sets.
- **Shared Memory (`floria.xcb.shm.pas`)**: Zero-copy XSHM framebuffers for blitting software-rendered pixel buffers directly to the X server.
- **Non-Rectangular Windows (`floria.xcb.shape.pas`)**: Window shaping masks for rounded corners, shaped titlebars, and custom window borders.
- **XFixes (`floria.xcb.xfixes.pas`)**: Modern cursor visibility, pointer tracking, and server-side damage/region handling.
- **Cursor & Keysyms (`floria.xcb.cursor.pas`, `floria.xcb.keysyms.pas`, `floria.x11.keysym.pas`)**: Themed cursor loading and comprehensive hardware keycode-to-keysym translation.
- **WM Framework (`floria.xcb.wm.pas`)**: Reparenting frame geometry, virtual workspaces, titlebar drag interaction, and client window lifecycle.

---

### 3. XML & SVG 1.1 Vector Graphics Subsystem (`Floria.XML.*`, `Floria.SVG.*`)

- **Pure Pascal XML 1.0 Parser**: Streaming tokenizer, DOM tree, entity encoding/decoding, and `ICSSElement` bridge for CSS styling.
- **SVG Scene Graph**: Full SVG DOM with `<path>`, `<rect>`, `<circle>`, `<ellipse>`, `<line>`, `<polygon>`, `<g>`, `<defs>`, and `<use>`.
- **Affine Transforms & Path Math**: 2D transform matrices, SVG compact path tokenizer, Bézier curves, arc decomposition, and linear/radial gradients.
- **Vector Rasterizer (`floria.svg.rasterizer.pas`)**: Converts SVG DOM trees directly onto anti-aliased 32-bit pixel surfaces using AggPas.

---

### 4. Pure Pascal Image Codecs (`Floria.Image.*`)

- **Zero External C Image Libraries**: Built-in, high-speed pure Pascal readers and writers.
- **Supported Formats**:
  - **PNG** (`floria.image.png.pas`): Full 8-bit truecolor RGBA with deflate/zlib decompression and filter un-filtering.
  - **BMP** (`floria.image.bmp.pas`): 24-bit and 32-bit BMP round-trip decoding and encoding.
  - **JPEG** (`floria.image.jpeg.pas`): Baseline JPEG parsing and marker extraction.
- **Core Image Surface (`floria.image.core.pas`)**: 32-bit BGRA pixel buffers (`TFloriaImage`), bilinear scaling, and format auto-detection.

---

### 5. 2D Vector Canvas & Graphics Engine (`Floria.Canvas.Agg`, `Floria.Image.Blur`, `Floria.Font`)

- **Anti-Grain Geometry (AggPas) Canvas**: High-fidelity sub-pixel anti-aliased lines, circles, rounded rectangles, polygons, outlines, and clipping rectangles.
- **High-Performance Blur (`floria.image.blur.pas`)**: Multi-pass box blur with downsampling, bilinear upsampling, and rounded-corner boundary clipping.
- **FreeType Font Engine (`floria.font.pas`)**: High-quality font loading, persistent glyph caching, stem darkening / gamma correction, and fontconfig fallback chaining.

---

### 6. Extended Blend Modes & Physical Linear Color Pipeline (`Floria.Blend`, `Floria.ColorSpace`)

- **29 W3C & Skia Blend Modes**:
  - 14 Porter-Duff & Arithmetic: `Clear`, `Src`, `Dst`, `SrcOver`, `DstOver`, `SrcIn`, `DstIn`, `SrcOut`, `DstOut`, `SrcATop`, `DstATop`, `Xor`, `Plus`, `Modulate`.
  - 11 Separable Color: `Multiply`, `Screen`, `Overlay`, `Darken`, `Lighten`, `ColorDodge`, `ColorBurn`, `HardLight`, `SoftLight`, `Difference`, `Exclusion`.
  - 4 Non-Separable HSL: `Hue`, `Saturation`, `Color`, `Luminosity`.
- **Color Spaces & HDR Types (`floria.colorspace.pas`)**:
  - Standard spaces: sRGB, Linear sRGB, Display P3, Rec. 2020, Adobe RGB (1998).
  - Transfer functions: Linear, sRGB (IEC 61966-2-1), Gamma 2.2 / 2.8, SMPTE ST 2084 PQ (HDR10), ITU-R BT.2100 HLG.
  - High-precision pixels: `TRgbaF16` (64-bit half-precision IEEE 754) and `TRgbaF32` (128-bit single-precision float).
  - Physical linear-light compositing eliminates dark fringing around anti-aliased edges.

---

### 7. Composable Filter Graph (`Floria.Canvas.Filter`)

- **Non-Destructive Filter Tree (`floria.filter.*`)**:
  - `TBlurFilter`: Multi-algorithm blur supporting 3-pass Gaussian (Central Limit Theorem $O(1)$), fast Box blur, and Dual Kawase blur.
  - `TColorMatrixFilter`: $4 \times 5$ color matrix transforms with presets for Grayscale, Invert, Sepia, Saturation, Brightness, and Contrast.
  - `TDropShadowFilter`: Configurable offset, sigma blur, tint color, and composite mode.
  - `TMorphologyFilter`: Mathematical morphology operators (Dilate / Erode).
  - `TDisplacementMapFilter`: SVG `<feDisplacementMap>` sub-pixel bilinear sampling.
  - Fluent pipelining with `Compose` and `Composite`.

---

### 8. Boolean Path Operations & Vector Math (`Floria.Path.*`, Clipper2)

- **Pure Object Pascal Clipper2 Engine**: Angus Johnson's polygon clipping engine with native dotted namespaces (`Floria.Path.Clipper.*`).
- **High-Level `TFloriaPath`**:
  - Primitives: `MoveTo`, `LineTo`, `QuadTo`, `CubicTo` (adaptive de Casteljau subdivision), `ArcTo`, and `Close`.
  - Boolean operations: `Union`, `Difference`, `Intersect`, and `XorOp`.
  - Path offset / inflation: `Inflate` with Miter, Round, Bevel joins and Butt, Square, Round caps.
  - Simplification: Douglas-Peucker contour reduction.
  - Two-way interop with SVG path data strings (`d="..."`) and AggPas `path_storage`.

---

### 9. Rich Paragraph Layout Engine (`Floria.Text.Paragraph`)

- **Multi-Style Spans**: Fluent `TFloriaParagraphBuilder` (`PushStyle`, `PopStyle`, `AddText`, `AddPlaceholder`, `Build`) managing independent styles per span.
- **Unicode Line Breaking (UAX #14)**: Multilingual line breaking, whitespace wrapping, CJK ideographs/Kana/Hangul boundary breaks, Kinsoku Shori punctuation rules, and soft hyphens.
- **Paragraph Formatting & Alignment**: Left, Right, Center, Justify, LTR/RTL text direction, `TextIndent`, `MaxLines`, and ellipsis overflow (`ftoEllipsis`).
- **Inline Placeholders & Hit-Testing**: Support for embedded badges/chips, `GetPositionForOffset` for caret positioning, and `GetRectsForRange` for multi-line selection bounding boxes.

---

### 10. Retained Display Lists & Scene Graph Caching (`Floria.DisplayList.*`)

- **`TFloriaPicture` & `TFloriaPictureRecorder`**: Semantic command recording, affine 2D transform stack, viewport culling, and visitor playback.
- **Analytical Clip Chains (`Floria.DisplayList.Clip`)**: WebRender-style analytical SDF clip evaluation in uniforms/shaders, bypassing offscreen FBO allocation.
- **2D R-Tree Spatial Acceleration (`Floria.DisplayList.Spatial`)**: Logarithmic spatial indexing with quadratic split algorithm for damage-region queries and viewport culling.
- **Retained Picture Tile Caching (`Floria.DisplayList.Cache`)**: 2D grid tile cache with selective damage invalidation (`InvalidateRect`) and LRU memory management, enabling zero-CPU-redraw scrolling.

---

### 11. Hardware-Accelerated GPU Vector Core (`Floria.GL`, `Floria.GPU.*`, `Floria.Canvas.GPU`)

- **Dynamic OpenGL / GLES Loader (`Floria.GL`)**: Pure Pascal dynamic loader via `dynlibs` (`libGLESv2.so.2` / `libGL.so.1`) and `eglGetProcAddress`.
- **EGL Presentation Driver (`Floria.GPU.Context`)**: Native X11 EGL 1.4/1.5 context management, VSync synchronization (`eglSwapInterval`), and offscreen PBuffers.
- **Dynamic Texture Atlas & Fallback Blob Rasterizer (`Floria.GPU.Atlas`)**: Skyline bin-packing atlas with AggPas CPU rasterization for complex vector glyphs.
- **Instanced Quad & Vertex Batching (`Floria.GPU.Batch`)**: Draw-call coalescing streaming 64-byte std140-aligned vertices to GPU VBOs.
- **AOT Precompiled Mega-Shaders (`Floria.GPU.Shaders`)**: Zero runtime JIT stutter; SDF analytical rounded rectangles, borders, box shadows, linear gradients, and in-shader clip chains.
- **Native GPU Path Tessellation (`Floria.GPU.Tessellator`)**: Single-pass stroke extrusion with Miter/Round/Bevel joins, ear-clipping polygon triangulation, and 1px analytic AA boundary skirts.
- **Polymorphic GPU Canvas (`Floria.Canvas.GPU`)**: Implements standard canvas operations backed directly by hardware acceleration.

---

### 12. Compression & Hashing Utilities (`Floria.Compression`, `Floria.Hash`)

- **Pure Pascal Compression**: Streaming BitStream, Huffman trees, Deflate, Zlib, and Gzip codecs.
- **High-Performance Hashing**: CRC16, CRC32, CRC64, Adler32, FNV-1a, and MurmurHash3 algorithms.

---

### 13. Internationalized Text Layout & Shaping (`Floria.Unicode.BiDi`, `Floria.Text.HarfBuzz`)

- **Unicode Bidirectional Algorithm (UAX #9)**: Complete pure Pascal implementation handling mixed LTR and RTL scripts (Arabic, Hebrew, Persian, Latin), weak/neutral character resolution, bracket pairing, and glyph mirroring.
- **Dynamic HarfBuzz OpenType Shaper**: Dynamically loads `libharfbuzz.so.0` via `dynlibs` (zero hard binary dependency; automatic fallback if unavailable). Accurately shapes ligatures (`liga`, `calt`), cursive Arabic connections, and complex mark placement.

---

## Building and Testing

### Requirements

- **Free Pascal**: FPC 3.2.0+ (recommended: FPC 3.2.3+).
- **Pasbuild**: Free Pascal build tool.
- **System Libraries**: `libxcb`, `libxcb-render`, `libxcb-randr`, `libxcb-shape`, `libxcb-shm`, `libxcb-xfixes`, `libxcb-cursor`, `libxcb-keysyms`, `libxcb-icccm`, `libxcb-ewmh`, `libfreetype`, `libharfbuzz` (optional at runtime), `libEGL`, `libGLESv2` (optional at runtime for GPU acceleration).

### Build Commands

```bash
# Compile library
pasbuild compile

# Run complete test suite (579 tests)
pasbuild test

# Force clean build and run tests
rm -rf target && pasbuild test

# Install to local package repository (~/.pasbuild/repository/)
pasbuild install
```

### Lazarus Package

Open [`src/main/pascal/florialib.lpk`](src/main/pascal/florialib.lpk) in Lazarus to compile and use `florialib` as a runtime package within Lazarus projects.

---

## Detailed Documentation

Comprehensive guides and API references are available in the [`docs/`](docs/) directory:

- [**Documentation Overview**](docs/index.md)
- [**CSS Subsystem Documentation**](docs/css.md)
- [**XML Subsystem Guide**](docs/xml.md)
- [**SVG Subsystem Guide**](docs/svg.md)
- [**Image Subsystem Guide**](docs/image.md)
- [**Canvas & 2D Graphics Guide**](docs/canvas.md)
- [**Text Layout & Shaping Guide**](docs/text.md)
- [**XCB & Window Manager Guide**](docs/xcb.md)
- [**WM Framework Specification**](docs/wm.md)
- [**Coding Standards & Development Guide**](docs/coding-style.md)
- [**Skia-Parity Graphics Architecture Roadmap**](roadmap.md)

---

## License

This project is licensed under the **Mozilla Public License 2.0 (MPL 2.0)** &bull; See the [LICENSE](LICENSE) file for details.
