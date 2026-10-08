# florialib

**florialib** is a Free Pascal library designed as a foundational toolkit for building modern user interfaces, graphical desktop applications, and X11 window managers on Unix-like operating systems.

Developed by **Dio Affriza**, licensed under the **Mozilla Public License 2.0 (MPL 2.0)**, and built with **Pasbuild**.

---

## Subsystems Overview

`florialib` provides comprehensive foundations for modern desktop graphics and applications:

```
                  ┌─────────────────────────────────────────────────────────────┐
                  │                          florialib                          │
                  └──────┬───────────────────────┬───────────────────────┬──────┘
                         │                       │                       │
                         ▼                       ▼                       ▼
      ┌─────────────────────────┐ ┌─────────────────────────┐ ┌─────────────────────────┐
      │      CSS Subsystem      │ │    2D Graphics & GPU    │ │  XCB & X11 WM Subsystem │
      ├─────────────────────────┤ ├─────────────────────────┤ ├─────────────────────────┤
      │ • W3C CSS Syntax L3 §4  │ │ • AggPas Vector Canvas  │ │ • Pure XCB Bindings     │
      │   Streaming Push Parser │ │ • 29 W3C/Skia Blends    │ │ • ICCCM 2.0 & EWMH/NetWM│
      │ • Complete AST Model    │ │ • Linear Float16/32 HDR │ │ • RandR Multi-Monitor   │
      │ • Typed Value Parsers   │ │ • Composable Filter Tree│ │ • XRender 2D Compositing │
      │ • 70+ Style Properties  │ │ • Clipper2 Path Ops     │ │ • SHM Framebuffers      │
      │ • W3C Selectors & Spec  │ │ • Retained Display List │ │ • Shape & XFixes        │
      │ • Style Cascade Resolver│ │ • GPU EGL/GLES2 Batcher │ │ • Themed Cursors & Keys │
      │ • Rich Typography (BiDi)│ │ • Dynamic Texture Atlas │ │ • Window Reparenting WM │
      └─────────────────────────┘ └─────────────────────────┘ └─────────────────────────┘
```

---

## Documentation Directory

| Document | Description |
|---|---|
| [**CSS Subsystem Guide**](css.md) | Complete guide to the CSS pipeline: tokenizer, parser, AST, values, properties, selectors, and cascading engine. |
| [**XML Subsystem Guide**](xml.md) | Complete guide to the XML 1.0 tokenizer, DOM tree, entity handling, and ICSSElement bridge. |
| [**SVG Subsystem Guide**](svg.md) | High-performance SVG 1.1 scene graph, 2D transforms, path math, arc decomposition, and CSS styling. |
| [**XCB & Window Manager Guide**](xcb.md) | Documentation and code examples for XCB, ICCCM, EWMH, RandR, XRender, SHM, Shape, and KeySyms. |
| [**WM Framework Specification**](wm.md) | Architecture and specifications for Floria.XCB.WM (reparenting, EWMH, virtual desktops, client management). |
| [**Image Subsystem Guide**](image.md) | Pure Pascal image buffer, BMP/PNG/JPEG codecs, and AggPas-compatible 32-bit raster graphics. |
| [**Canvas & 2D Graphics Guide**](canvas.md) | 2D vector canvas (`Floria.Canvas.Agg`), 29 blend modes, color spaces, filter graph, display lists, and GPU hardware canvas. |
| [**Text Layout & Shaping Guide**](text.md) | Rich paragraph layout (`Floria.Text.Paragraph`, UAX #14), Unicode BiDi (UAX #9), and dynamic HarfBuzz text shaping. |
| [**Coding Standards & Development**](coding-style.md) | Object Pascal conventions, mandatory `()` routine rules, memory ownership, and Pasbuild build workflow. |
| [**Skia-Parity Graphics Architecture Roadmap**](../roadmap.md) | Architectural roadmap documenting the evolution toward Google Skia-parity graphics and GPU vector core. |

---

## Quick Start & Building

### Prerequisites

- **Free Pascal Compiler** (FPC 3.2.0 or newer, recommended: FPC 3.2.3+).
- **Pasbuild** build tool (or Lazarus IDE via `florialib.lpk`).
- Standard Linux/Unix X11 development libraries (`libxcb`, `libxcb-render`, `libxcb-randr`, `libxcb-shape`, `libxcb-shm`, `libxcb-xfixes`, `libxcb-cursor`, `libxcb-keysyms`, `libxcb-icccm`, `libxcb-ewmh`, `libfreetype`, `libharfbuzz`, `libEGL`, `libGLESv2`).

### Compiling the Library

```bash
pasbuild compile
```

### Running the Test Suite

`florialib` features an extensive test suite (579 unit tests) powered by FPCUnit:

```bash
pasbuild test
```

A clean build and test execution:

```bash
rm -rf target && pasbuild test
```

### Using in Lazarus IDE

Open `src/main/pascal/florialib.lpk` in Lazarus, click **Compile**, and add it as a required package in your project.

---

## Library Architecture Highlights

1. **Strict W3C Specification Compliance**:
   The CSS tokenizer and parser follow the official W3C CSS Syntax Level 3 specifications (§4 and §5), accurately supporting error recovery, escape sequence unquoting, and streaming inputs.

2. **Clean Memory Ownership Model**:
   All collection structures (`TObjectList` from `Contnrs`) maintain strict ownership semantics (`OwnsObjects = True`). Freeing a root stylesheet node or a style resolver automatically cascades and frees all descendants without memory leaks.

3. **Toolkit-Agnostic Element Contract**:
   The `ICSSElement` interface enables arbitrary GUI widget trees, window trees, or headless mock nodes to be styled via the CSS cascading engine.

4. **Zero Xlib Dependency**:
   The window manager and graphics subsystem relies exclusively on modern, asynchronous, thread-safe XCB C libraries rather than legacy Xlib.
