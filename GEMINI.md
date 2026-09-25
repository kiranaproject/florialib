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

