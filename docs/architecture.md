# florialib Architecture

This document describes how the subsystems fit together, which dependencies are
allowed between layers, and which files are generated or vendored.

---

## 1. Layering

The library is organized as a stack. A unit may depend on units below it and on
its own layer, but should not depend on a higher layer.

```
+---------------------------------------------------------------+
| Platform: XCB / X11 / Window Manager / Compositor             |
| Floria.XCB.*, Floria.X11.*                                    |
+---------------------------------------------------------------+
| Presentation: EGL / OpenGL / GPU renderer / GPU canvas        |
| Floria.EGL, Floria.GL, Floria.GPU.*, Floria.Canvas.GL         |
+---------------------------------------------------------------+
| Retained scene: display lists, clip chains, spatial index     |
| Floria.DisplayList.*                                          |
+---------------------------------------------------------------+
| Rendering: Canvas base, AggPas canvas, blend/filter, paths    |
| Floria.Canvas, Floria.Canvas.Agg, Floria.Canvas.Blend,        |
| Floria.Canvas.Filter, Floria.Path.*, Floria.SVG.Rasterizer    |
+---------------------------------------------------------------+
| Typography: fonts, shaping, bidi, paragraph layout            |
| Floria.Font, Floria.Text.*, Floria.Unicode.BiDi               |
+---------------------------------------------------------------+
| Document/style: CSS, XML, HTML, SVG DOM                       |
| Floria.CSS.*, Floria.XML.*, Floria.HTML.*, Floria.SVG.*       |
+---------------------------------------------------------------+
| Foundation: types, image core, color, compression, hashing    |
| Floria.Image.Core, Floria.ColorSpace, Floria.Hash.*,          |
| Floria.Compression.*, Floria.Unicode.BiDi (types)             |
+---------------------------------------------------------------+
```

The dashed boundary is intentional: `Floria.Canvas` currently references
`Floria.SVG.DOM` for its SVG helper methods, and `Floria.SVG.Rasterizer` accepts
`TFloriaCanvasAgg`. That is a known implementation cycle to remove in a later
phase by introducing a canvas-agnostic path/text painter interface.

---

## 2. Dependency rules

1. **Foundation units must stay small and portable.** `Floria.Image.Core` uses
   AggPas pixel formats, but the codecs (`Floria.Image.BMP/PNG/JPEG`) remain
   pure Pascal and must not depend on canvas or window-system units.
2. **Style and text units must not depend on a concrete canvas.** CSS, XML,
   HTML, SVG DOM, BiDi, HarfBuzz, and paragraph layout should be testable
   headless.
3. **Only presentation units may depend on EGL/GL.** The GPU renderer is the
   only place that should call OpenGL entry points.
4. **Only XCB/X11 units may depend on the X server bindings.** Canvas, image,
   CSS, and text code must not link XCB.
5. **Generated and vendored units are leaves.** Do not add hand-written logic
   to them; wrap them from first-party units instead.

The current package is monolithic: `florialib.lpk` publishes every unit. A later
phase will split it into `floria.core`, `floria.canvas`, `floria.svg`,
`floria.gpu`, and `floria.xcb`, with `florialib` remaining as a meta-package for
compatibility.

---

## 3. AggPas and fpGUI

AggPas is supplied by **fpGUI's `extras/aggpas` fork** (Lazarus package name
`aggpas`). Pasbuild gets it transitively from the `fpgui-framework` dependency.

- Do **not** add a standalone AggPas dependency.
- Do **not** maintain or port AggPas inside `florialib`.
- The Lazarus package requires fpGUI's `extras/aggpas/aggpas.lpk`; verify that
  Lazarus is not loading a discarded prototype package with the same name.

---

## 4. Generated units

The following units are generated from C headers with **blaise-bindgen** and are
marked `DO NOT EDIT` in their headers:

| Unit | Header / library |
|---|---|
| `Floria.XCB` | `xcb` |
| `Floria.XCB.ICCCM` | `xcb-icccm` |
| `Floria.XCB.EWMH` | `xcb-ewmh` |
| `Floria.XCB.RandR` | `xcb-randr` |
| `Floria.XCB.Render` | `xcb-render` |
| `Floria.XCB.SHM` | `xcb-shm` |
| `Floria.XCB.Shape` | `xcb-shape` |
| `Floria.XCB.XFixes` | `xcb-xfixes` |
| `Floria.XCB.Cursor` | `xcb-cursor` |
| `Floria.XCB.Keysyms` | `xcb-keysyms` |
| `Floria.X11.KeySym` | X11 keysymdef constants |

`Floria.XCB.Composite` and `Floria.XCB.Damage` are currently hand-written
bindings. They should be regenerated with the rest of the XCB family when the
generator supports the required requests. Xinerama queries used as a legacy
multi-head fallback are declared inline in `floria.xcb.wm.pas`.

See [tools/bindgen/README.md](../tools/bindgen/README.md) for regeneration
commands and known generator limitations.

---

## 5. Geometry and vendored code

### First-party geometry

`Floria.Geometry` owns the library's 2D value types: `TPointD`, `TRectD`,
`TPathD`, `TPathsD`, and `TFillRule`, plus `PointD`/`RectD` constructors and the
`GetBounds`, `Area`, and `PointInPolygon` helpers. Canvases, display lists, the
GPU pipeline, and text layout depend on this unit — never on a clipping engine —
for basic geometry.

Keep `TPointD` and `TRectD` field names and order stable: existing code relies
on positional construction and on `FillChar` zero-initialization of records that
embed them.

### Vendored clipping engine (transitional)

`floria.path.clipper.*` is a port of Angus Johnson's **Clipper2**, distributed
under the Boost Software License 1.0. It uses Delphi mode and its own
formatting; do not reformat it, and preserve its headers. See
[THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).

The vendored units now consume `Floria.Geometry` for the shared value types
instead of declaring their own copies, so exactly one `TPointD`/`TRectD` exists
in the program. The long-term plan replaces this engine with a first-party
implementation; `Floria.Path.Ops` is the intended seam for that work.

---

## 6. Memory ownership

- AST and DOM nodes own their children through `TObjectList` instances created
  with `OwnsObjects = True`. Freeing the root frees the tree.
- Never add one object instance to two owning lists.
- `ICSSTokenListener` and `IFloriaDisplayListReceiver` implementations manage
  their own lifetime; the library's base classes return `-1` from
  `_AddRef`/`_Release` to disable reference-count auto-free.
- `TFloriaImage` owns its pixel buffer; images passed to canvas methods remain
  owned by the caller.
- `TFloriaPicture` owns its operation array and any referenced objects it was
  constructed with; callers should follow the recorder's ownership rules.

---

## 7. Threading

The library does not currently provide internal locks for its global registries
(image codecs, font manager, GPU singletons, emoji cache). Treat those as
single-threaded and synchronize externally if a process uses them from multiple
threads.

XCB connections are asynchronous; sharing one connection between threads
requires external synchronization. Each thread should normally use its own
connection.

---

## 8. Build outputs

- `target/` contains Pasbuild output, including `target/units` and the test
  runner.
- `target/lazarus/` is the Lazarus package unit output directory.
- `src/main/pascal/lib/` is obsolete and must not be recreated; it was removed
  because Pasbuild added it to the unit search path and stale Lazarus `.ppu`
  files could shadow fresh units.
- Compile with the `pic` profile (`-Cg`) when the units will be linked into a
  shared library.

---

## 9. Error handling

First-party exceptions derive from `EFloriaError` in
[`floria.errors.pas`](../src/main/pascal/floria.errors.pas). Backends that
cannot perform an advertised operation should raise `EFloriaNotSupported`
rather than silently doing nothing. Current examples are GPU paragraph playback
and GPU layer compositing.
