# florialib — Project Rules

## Build & Installation Workflow

Whenever any source file in `src/main/pascal/` is added, modified, or refactored:

1. **Run tests**: `pasbuild test` (all tests must pass with `E:0 F:0`).
2. **Install to local repository**: **Always** run `pasbuild install` immediately after successful testing. This step publishes the compiled units (`.ppu`, `.o`) to the local package repository (`~/.pasbuild/repository/florialib/`), enabling downstream consumer projects (such as `floria-toolkit`) to resolve and link against the updated `florialib`.

## Pasbuild Configuration File

- **`project.xml`** is the only project descriptor configuration file used by Pasbuild.
- **`pasbuild.json` does not exist**. Never look for, reference, create, or expect `pasbuild.json`. Always read, inspect, and configure `project.xml`.

