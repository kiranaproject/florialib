# florialib — Project Rules

## Build & Installation Workflow

Whenever any source file in `src/main/pascal/` is added, modified, or refactored:

1. **Run tests**: `pasbuild test` (all tests must pass with `E:0 F:0`).
2. **Install to local repository**: **Always** run `pasbuild install` immediately after successful testing. This step publishes the compiled units (`.ppu`, `.o`) to the local package repository (`~/.pasbuild/repository/florialib/`), enabling downstream consumer projects (such as `floria-toolkit` and `wmsama`) to resolve and link against the updated `florialib`.

## Dependencies

- **`aggpas:2.4.0-SNAPSHOT`**: Independent 2D vector graphics rendering engine (decoupled from fpGUI).
- **`fpgui-framework` is not used**. Do not add `fpgui-framework` as a dependency.

## Pasbuild Configuration File

- **`project.xml`** is the only project descriptor configuration file used by Pasbuild.
- **`pasbuild.json` does not exist**. Never look for, reference, create, or expect `pasbuild.json`. Always read, inspect, and configure `project.xml`.

## Tool Call Schema Invariants

- **`find_by_name` Requires `Pattern`**: In `find_by_name`, the `Pattern` property is strictly required by the tool validator schema (`required: ["SearchDirectory", "Pattern", "toolSummary", "toolAction"]`). Never omit `Pattern`, even when specifying `Extensions` or `Type`. When searching by extension or listing directory contents, always explicitly set `Pattern: "*"`.
- **Required Metadata**: Every tool call must include both `toolSummary` (2–5 word noun phrase) and `toolAction` (2–5 word verb phrase).

## Canvas & Compositor Geometry Invariants

- **Symmetric AggPas Shadow Expansion**:
  - In `TFloriaCanvasAgg.DrawShadow`, expansion must remain mathematically symmetric on all 4 boundaries:
    `RR.Construct(X + OffsetX - expand * 0.5, Y + OffsetY - expand * 0.5, X + OffsetX + W + expand * 0.5, Y + OffsetY + H + expand * 0.5, curR)`
    with concentric corner radius `curR := Radius + (expand * 0.5)`. Never apply hardcoded vertical expansion biases.
- **X11 Input-Only Window Stacking**:
  - In `floria.xcb.wm.pas`, outer resize margins over background windows are managed via an `InputOnly` window (`ResizeWindow`) parented to root and stacked immediately below `FrameWindow` (`XCB_STACK_MODE_BELOW`).

## Linux Windowing & Display Server Policy

- **Strictly X11/XCB Only (No Wayland)**:
  - All Linux windowing, window management protocols (`floria.xcb.wm`), compositor integration (`floria.xcb.wm.compositor`), and EGL presentation target native **X11/XCB** (`libxcb`).
  - **Never reference, propose, design for, or insert Wayland** into code, configuration, architectural documentation, roadmaps, or README files.
  - All display and imaging engineering effort is dedicated to vector graphics fidelity (`AggPas`, `Floria.Canvas.*`), color pipelines, typography, and EGL/GL presentation on X11.


