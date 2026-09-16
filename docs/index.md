# florialib

**florialib** is a Free Pascal library designed as a foundational toolkit for building modern user interfaces, graphical desktop applications, and X11 window managers on Unix-like operating systems.

Developed by **Dio Affriza**, licensed under the **Mozilla Public License 2.0 (MPL 2.0)**, and built with **Pasbuild**.

---

## Subsystems Overview

`florialib` provides two core subsystems:

```
                  ┌───────────────────────────────────────────────┐
                  │                   florialib                   │
                  └──────┬─────────────────────────────────┬──────┘
                         │                                 │
                         ▼                                 ▼
      ┌────────────────────────────────────┐    ┌────────────────────────────────────┐
      │           CSS Subsystem            │    │       XCB & X11 WM Subsystem       │
      ├────────────────────────────────────┤    ├────────────────────────────────────┤
      │ • W3C CSS Syntax Level 3 §4        │    │ • Pure XCB Pascal Bindings         │
      │   Streaming Push Tokenizer         │    │ • ICCCM 2.0 Protocol Helpers       │
      │ • W3C CSS Syntax Level 3 §5        │    │ • EWMH (Extended Window Manager)   │
      │   Streaming & One-shot Parser      │    │ • RandR Multi-Monitor Management   │
      │ • Complete AST Model (Ownership)   │    │ • XRender Hardware-Accelerated 2D  │
      │ • Typed Value Parsers (RGBA, Hex,  │    │ • SHM Shared Memory Framebuffers   │
      │   Units, Lengths, Box Model)       │    │ • Shape Extension (Non-rectangular)│
      │ • 70+ Style Property IDs           │    │ • XFixes Cursor Tracking & Damage  │
      │ • Automatic Shorthand Expansion    │    │ • XCB Cursor & KeySyms Management  │
      │ • W3C Selectors & Specificity      │    │ • Complete X11 KeySym Constants    │
      │ • Element Matching & Cascade Engine│    │                                    │
      └────────────────────────────────────┘    └────────────────────────────────────┘
```

---

## Documentation Directory

| Document | Description |
|---|---|
| [**CSS Subsystem Guide**](css.md) | Complete guide to the CSS pipeline: tokenizer, parser, AST, values, properties, selectors, and cascading engine. |
| [**XCB & Window Manager Guide**](xcb.md) | Documentation and code examples for XCB, ICCCM, EWMH, RandR, XRender, SHM, Shape, and KeySyms. |
| [**Coding Standards & Development**](coding-style.md) | Object Pascal conventions, mandatory `()` routine rules, memory ownership, and Pasbuild build workflow. |

---

## Quick Start & Building

### Prerequisites

- **Free Pascal Compiler** (FPC 3.2.0 or newer, recommended: FPC 3.2.3+).
- **Pasbuild** build tool (or Lazarus IDE via `florialib.lpk`).
- Standard Linux/Unix X11 development libraries (`libxcb`, `libxcb-render`, `libxcb-randr`, `libxcb-shape`, `libxcb-shm`, `libxcb-xfixes`, `libxcb-cursor`, `libxcb-keysyms`, `libxcb-icccm`, `libxcb-ewmh`).

### Compiling the Library

```bash
pasbuild compile
```

### Running the Test Suite

`florialib` features an extensive test suite (220+ unit tests) powered by FPCUnit:

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
