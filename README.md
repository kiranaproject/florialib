# florialib

A modern, high-performance Free Pascal library providing foundational subsystems for building GUI toolkits, desktop applications, and X11 window managers.

Developed by **Dio Affriza** &bull; Licensed under the **Mozilla Public License 2.0 (MPL 2.0)** &bull; Built with **Pasbuild**.

[![FPC](https://img.shields.io/badge/Language-Free%20Pascal%203.2%2B-blue.svg)](https://www.freepascal.org/)
[![License: MPL 2.0](https://img.shields.io/badge/License-MPL%202.0-brightgreen.svg)](https://opensource.org/licenses/MPL-2.0)
[![Tests](https://img.shields.io/badge/Tests-223%20passed%20%7C%200%20errors-success.svg)](src/test/pascal/)

---

## Key Subsystems

### 1. W3C CSS Styling & Cascading Engine (`Floria.CSS.*`)

A complete, end-to-end CSS implementation written in Object Pascal following W3C specifications:

```
Floria.CSS.Types       (Tokens, token types, position tracking, listener interface)
      ↓
Floria.CSS.Tokenizer   (Streaming push tokenizer conforming to W3C CSS Syntax Level 3 §4)
      ↓
Floria.CSS.AST         (AST nodes with automatic cascaded memory ownership)
      ↓
Floria.CSS.Parser      (W3C CSS Syntax Level 3 §5 parser)
      ↓
Floria.CSS.Values      (Typed values: TCSSColor, TCSSLength, TCSSBox, TCSSBorderSide, layout enums)
      ↓
Floria.CSS.Properties  (70+ canonical property IDs, metadata, style declarations, style blocks)
      ↓
Floria.CSS.Selectors   (Compound/complex selectors, specificity (A,B,C), combinators)
      ↓
Floria.CSS.Cascade     (ICSSElement abstraction, right-to-left matching, cascade resolver)
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

- **Core XCB (`Floria.XCB`)**: Asynchronous, thread-safe connections, window creation, graphics contexts, events, atoms, and errors.
- **ICCCM 2.0 Protocol (`Floria.XCB.ICCCM`)**: Window manager protocols (`WM_PROTOCOLS`, `WM_DELETE_WINDOW`), window hints, and normal size hints.
- **EWMH / NetWM (`Floria.XCB.EWMH`)**: Modern desktop integration (`_NET_SUPPORTED`, `_NET_CLIENT_LIST`, `_NET_ACTIVE_WINDOW`, window types, window states, and struts).
- **RandR Multi-Monitor (`Floria.XCB.RandR`)**: Dynamic screen resources, CRTCs, outputs, resolutions, and multi-display management.
- **XRender 2D Compositing (`Floria.XCB.Render`)**: Hardware-accelerated alpha blending, picture formats, geometric primitives, and glyph sets.
- **Shared Memory (`Floria.XCB.SHM`)**: Zero-copy XSHM framebuffers for blitting software-rendered pixel buffers directly to the X server.
- **Non-Rectangular Windows (`Floria.XCB.Shape`)**: Window shaping masks for rounded corners, shaped titlebars, and custom window borders.
- **XFixes (`Floria.XCB.XFixes`)**: Modern cursor visibility, pointer tracking, and server-side damage/region handling.
- **Cursor & Keysyms (`Floria.XCB.Cursor`, `Floria.XCB.Keysyms`, `Floria.X11.KeySym`)**: Themed cursor loading and comprehensive hardware keycode-to-keysym translation.

---

## Quick Example: CSS Styling & Resolution

```pascal
uses
  Floria.CSS.Values, Floria.CSS.Properties, Floria.CSS.Cascade;

var
  Resolver   : TCSSStyleResolver;
  WindowElem : TCSSMockElement;
  ButtonElem : TCSSMockElement;
  ParentStyle: TCSSStyleBlock;
  Style      : TCSSStyleBlock;
begin
  Resolver := TCSSStyleResolver.Create();
  WindowElem := TCSSMockElement.Create('window', 'main-window');
  ButtonElem := TCSSMockElement.Create('button', 'submit-btn');
  try
    ButtonElem.AddClass('btn');
    ButtonElem.AddClass('btn-primary');
    WindowElem.AppendChild(ButtonElem);

    // Add stylesheets
    Resolver.AddCSS('window { color: #333333; font-family: "Ubuntu", sans-serif; }');
    Resolver.AddCSS('button { width: 120px; height: 36px; padding: 6px 12px; }');
    Resolver.AddCSS('.btn-primary { background-color: #007acc; color: #ffffff !important; }');
    Resolver.AddCSS('#submit-btn:hover { background-color: #005999; }');

    // 1. Resolve parent window style
    ParentStyle := Resolver.ResolveStyle(WindowElem);
    try
      // 2. Resolve button style (cascading inherited properties from parent)
      Style := Resolver.ResolveStyle(ButtonElem, ParentStyle);
      try
        WriteLn('Button width: ', Style.GetDeclaration(cpiWidth).Value.Length.ToString());
        WriteLn('Button color: ', Style.GetDeclaration(cpiColor).Value.Color.ToHex());
        WriteLn('Button bg:    ', Style.GetDeclaration(cpiBackgroundColor).Value.Color.ToHex());
        // Shorthand padding is automatically expanded to 4 sides
        WriteLn('Padding-left: ', Style.GetDeclaration(cpiPaddingLeft).Value.Length.ToString());
      finally
        Style.Free();
      end;
    finally
      ParentStyle.Free();
    end;
  finally
    WindowElem.Free();
    Resolver.Free();
  end;
end;
```

---

## Directory Structure

```
florialib/
├── docs/                    # Detailed documentation and architecture guides
│   ├── index.md             # Documentation overview
│   ├── css.md               # CSS Subsystem Guide (Tokenizer, AST, Values, Cascade)
│   ├── xcb.md               # XCB & Window Manager Subsystem Guide
│   └── coding-style.md      # Object Pascal coding standards & conventions
├── src/
│   ├── main/pascal/         # Library units (Floria.CSS.*, Floria.XCB.*, Floria.X11.*)
│   └── test/pascal/         # FPCUnit test suites and TestRunner.pas
├── project.xml              # Pasbuild build descriptor
└── README.md                # This file
```

---

## Building and Testing

### Requirements

- **Free Pascal**: FPC 3.2.0+ (recommended: FPC 3.2.3+).
- **Pasbuild**: Free Pascal build tool.
- **System Libraries**: `libxcb`, `libxcb-render`, `libxcb-randr`, `libxcb-shape`, `libxcb-shm`, `libxcb-xfixes`, `libxcb-cursor`, `libxcb-keysyms`, `libxcb-icccm`, `libxcb-ewmh`.

### Build Commands

```bash
# Compile library
pasbuild compile

# Run complete test suite (223 tests)
pasbuild test

# Force clean build and run tests
rm -rf target && pasbuild test
```

### Lazarus Package

Open [`src/main/pascal/florialib.lpk`](src/main/pascal/florialib.lpk) in Lazarus to compile and use `florialib` as a runtime package within Lazarus projects.

---

## Detailed Documentation

Comprehensive guides and API references are available in the [`docs/`](docs/) directory:

- [**CSS Subsystem Documentation**](docs/css.md)
- [**XCB & Window Manager Guide**](docs/xcb.md)
- [**Coding Standards & Development Guide**](docs/coding-style.md)

---

## License

This project is licensed under the **Mozilla Public License 2.0 (MPL 2.0)** &bull; See the [LICENSE](LICENSE) file for details.
