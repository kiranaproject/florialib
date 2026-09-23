---
name: florialib
description: >-
  Use this skill when working on the florialib project — a Free Pascal library
  containing helper units for a UI toolkit. Covers project conventions, build
  and test workflow (Pasbuild + FPCUnit), the CSS parser pipeline architecture
  (tokenizer → parser → AST), FPC-specific gotchas discovered during
  development, W3C CSS Syntax Level 3 spec references, and the current phase
  roadmap. Activate whenever the user asks to add features, fix bugs, write
  tests, or understand the codebase in this project.
---

# florialib — Developer Skill

`florialib` is a Free Pascal library: a collection of helper units for
building a UI toolkit. It is developed by **Dio Affriza**, licensed under
**MPL 2.0**, and built with **Pasbuild**.

---

## 1. Project Identity

| Property | Value |
|---|---|
| Language | Free Pascal (FPC 3.2.3) |
| Pascal dialect | `{$mode objfpc}{$H+}` — always at the top of every unit |
| String type | `AnsiString` throughout |
| Unit naming | Namespace-style: `Floria.<Subsystem>.<Role>` |
| License | MPL 2.0 |
| Author | Dio Affriza |
| Build tool | Pasbuild |

---

## 2. Directory Layout

```
florialib/
├── src/
│   ├── main/pascal/     ← library units (auto-discovered by Pasbuild)
│   └── test/pascal/     ← test units + TestRunner.pas
├── target/              ← build output (generated, do not edit)
└── project.xml          ← Pasbuild project descriptor (XML format; pasbuild.json does not exist)
```

`project.xml` is the sole project descriptor used by Pasbuild (there is no
`pasbuild.json`). Key configurations: library type, output `target/`, test
entry-point `TestRunner.pas`, FPCUnit runner flags `--all --format=plain`.

---

## 3. Build & Test Workflow

### Running tests

```bash
pasbuild test
```

Success looks like:
```
Time:00.002  N:123  E:0  F:0  I:0
[INFO] All tests passed
```

`N` = tests run, `E` = errors, `F` = failures, `I` = ignored.

### Forced clean build

```bash
rm -rf target && pasbuild test
```

Use this when stale `.ppu` / `.o` files cause spurious compile errors.

### Registering new test suites

1. Add the new test unit to the `uses` clause of
   `src/test/pascal/TestRunner.pas`.
2. Each test unit must call `RegisterTest(TMyTestClass)` in its own
   `initialization` section — Pasbuild picks them up automatically.

### Installing to local repository

```bash
pasbuild install
```

Installs compiled units to `~/.pasbuild/repository/florialib/...` so dependent
projects (e.g. `floria-toolkit`) can link against the updated library. Always run
this command whenever units in `florialib` are added, modified, or refactored.

---

## 4. Test Framework (FPCUnit)

- Base class: `TTestCase` from `fpcunit`
- Import: `uses fpcunit, testregistry`
- Tests are `published` methods on `TTestCase` subclasses
- Assert methods: `AssertEquals`, `AssertNotNull`, `AssertNull`,
  `AssertTrue`, `AssertFalse`
- Registering: `RegisterTest(TMyClass)` in `initialization`

---

## 5. CSS Parser Pipeline Architecture

### Unit dependency graph

```
Floria.CSS.Types
      ↓
Floria.CSS.Tokenizer       (Phase 1 — DONE)
      ↓
Floria.CSS.AST             (Phase 2 — DONE)
      ↓
Floria.CSS.Parser          (Phase 2 — DONE)
      ↓
Floria.CSS.Values          (Phase 3 — DONE)
      ↓
Floria.CSS.Properties      (Phase 3 — DONE)
      ↓
Floria.CSS.Selectors       (Phase 4 — DONE)
      ↓
Floria.CSS.Cascade         (Phase 4 — DONE)
```

### Unit responsibilities

| Unit | Role |
|---|---|
| `Floria.CSS.Types` | Shared enums, records, interfaces: `TCSSTokenType` (25 values), `TCSSToken`, `TCSSSourcePos`, `ICSSTokenListener` |
| `Floria.CSS.Tokenizer` | Streaming push tokenizer — W3C CSS Syntax §4. `Feed(chunk)` + `Finish()` |
| `Floria.CSS.AST` | AST node classes: `TCSSStylesheet`, `TCSSQualifiedRule`, `TCSSAtRule`, `TCSSDeclaration`, `TCSSSimpleBlock`, `TCSSFunctionBlock`, `TCSSPreservedToken` |
| `Floria.CSS.Parser` | W3C CSS Syntax §5 parser. Entry: `TCSSParser.FromCSS(css)` → `TCSSStylesheet`. Also exports `TokenizeCSS()` helper |
| `Floria.CSS.Values` | Typed CSS values: `TCSSColor` (RGBA, hex, rgb(), named), `TCSSLength`, `TCSSBox`, `TCSSBorderSide`, layout/style enums |
| `Floria.CSS.Properties` | Typed property model: `TCSSPropertyId`, metadata (inherited, shorthand), `TCSSStyleDeclaration`, `TCSSStyleBlock` with shorthand expander |
| `Floria.CSS.Selectors` | W3C Selectors: compound, complex, specificity tuple (A,B,C), combinators (child, descendant, siblings), attribute ops |
| `Floria.CSS.Cascade` | Style resolution engine: `ICSSElement` contract, `TCSSMockElement`, right-to-left matching, cascade sorting, inheritance |

### Key API

```pascal
// Tokenizer (streaming)
tok := TCSSTokenizer.Create(myListener); // myListener: ICSSTokenListener
tok.Feed(cssChunk);
tok.Finish;
tok.Free;

// Parser (one-shot convenience)
sheet := TCSSParser.FromCSS('p { color: red }');
try
  // sheet.Rules[0] is a TCSSQualifiedRule
  rule  := TCSSQualifiedRule(sheet.Rules[0]);
  decl  := TCSSDeclaration(rule.Declarations[0]);
  // decl.Name = 'color', decl.Important = false
finally
  sheet.Free;  // owns the entire tree
end;
```

### Memory ownership

Every `TObjectList` in an AST node is created with `FreeObjects = True`.
Freeing `TCSSStylesheet` cascades through the entire tree. Never add the
same node instance to two lists.

---

## 6. ICSSTokenListener — Implementation Pattern

FPC on Linux uses **`cdecl`** calling convention for interface methods
(not `stdcall`). Use the following pattern when implementing
`ICSSTokenListener` on a plain `TObject` (NOT `TInterfacedObject`):

```pascal
type
  TMyListener = class(TObject, ICSSTokenListener)
  private
    function QueryInterface(constref IID: TGUID; out Obj): HResult; cdecl;
    function _AddRef : Integer; cdecl;
    function _Release: Integer; cdecl;
  public
    procedure OnToken(const AToken: TCSSToken);
  end;

function TMyListener.QueryInterface(constref IID: TGUID; out Obj): HResult; cdecl;
begin
  if GetInterface(IID, Obj) then Result := S_OK else Result := E_NOINTERFACE;
end;
function TMyListener._AddRef : Integer; cdecl; begin Result := -1; end;
function TMyListener._Release: Integer; cdecl; begin Result := -1; end;
```

`_AddRef` / `_Release` return `-1` to disable reference-count auto-free.
Manage the object's lifetime manually with `try/finally obj.Free`.

**Do NOT** use `TInterfacedObject` as base — `_AddRef`/`_Release` are not
virtual in FPC's `TInterfacedObject` and cannot be overridden.

---

## 7. FPC-Specific Gotchas

### `TObjectList` lives in `Contnrs`, not `Classes`

```pascal
uses Classes, Contnrs, SysUtils, ...;  // Contnrs required for TObjectList
```

Omitting `Contnrs` gives `Error: Identifier not found "TObjectList"`.

### No nested `{ }` block comments

FPC does **not** support nested `{ }` comments. Any `{` or `}` character
inside a `{ ... }` block comment will confuse the parser, causing silent
truncation of the rest of the file and a misleading
`Fatal: Unexpected end of file` at the last line.

**Rules:**
- Use `//` for all doc comments and section dividers inside `.pas` files.
- Use `(* ... *)` only when you must write a multi-line block comment that
  contains `{` or `}` in its text.
- Never use `{ }` comments that contain `{`, `}`, `[`, or `]` in their body.

```pascal
// WRONG — the inner } closes the outer comment prematurely:
{ A simple block: { }, [ ], or ( ) with contents. }

// CORRECT — use // comments:
// A simple block: curly-brace, square-bracket, or paren blocks with contents.

// CORRECT — or (* *) when multiline is needed:
(* A simple block: { }, [ ], or ( ) with contents.
   This is the associated token. *)
```

### `{$mode objfpc}{$H+}` at the top of every unit

These are compiler directives inside `{ }` — they work because they start
with `$`. This is fine and must always be present.

### Image Codec Auto-Registration & Initialization Order

`Floria.Image.Core` maintains the global codec registry (`GReaders`, `GWriters`) and initializes them in its `initialization` block:
- Codec units (`Floria.Image.PNG`, `Floria.Image.BMP`, `Floria.Image.JPEG`) call `RegisterImageReader()` / `RegisterImageWriter()` in their own `initialization` sections.
- **Never** import codec units from the `implementation` section of `Floria.Image.Core`. Doing so causes FPC to execute the codec initializers *before* `Floria.Image.Core`'s initializer, which then executes and resets `GReaders` and `GWriters` with `SetLength(..., 0)`, erasing all registered codecs.
- `Floria.Image.Core` must remain pure and free of codec imports. Downstream consumers (executables, shared libraries, tests) must explicitly add `Floria.Image.PNG`, `Floria.Image.BMP`, `Floria.Image.JPEG` to their `uses` clause.

### Position-Independent Code (`-Cg` / `-fPIC`) for Shared Libraries

When `florialib` compiled units (`.o`, `.ppu`) are consumed by shared libraries (such as `libft.so` in `floria-toolkit`), the compiler must emit Position-Independent Code (`-Cg` flag).
- Without `-Cg`, the linker fails: `relocation R_X86_64_PC32 against symbol ... can not be used when making a shared object; recompile with -fPIC`.
- Ensure `-Cg` is enabled in `~/.fpc.cfg` or compiler options so units in the local Pasbuild repository are compatible with both executables and shared libraries.

---

## 8. Object Pascal Coding Style

These rules are **mandatory** for all code in this project. They are shared
with the wider Floria family of projects.

### 8.1 Mandatory Empty Parentheses `()` on Zero-Parameter Routines

To unambiguously distinguish callable routines from properties and fields:

- **Declarations** — every zero-parameter `procedure`, `function`,
  `constructor`, or `destructor` **must** include `()`:

  ```pascal
  // Correct
  procedure Invalidate(); virtual;
  function  GetFont(): TFtFont; virtual;
  destructor Destroy(); override;

  // Incorrect — do NOT write these
  procedure Invalidate; virtual;
  function  GetFont: TFtFont;
  destructor Destroy; override;
  ```

- **Call sites** — every call to a zero-parameter routine **must** include `()`:

  ```pascal
  // Correct
  Invalidate();
  inherited Destroy();
  Children.Free();

  // Incorrect
  Invalidate;
  inherited Destroy;
  ```

- **Properties and fields** do not use parentheses: `Btn.Visible := True;`

### 8.2 Dotted Namespaces

All units follow dotted Pascal namespaces: `Floria.<Subsystem>.<Role>`
(e.g. `Floria.CSS.Tokenizer`, `Floria.CSS.AST`).

### 8.3 Identifier Casing & Naming Conventions

| Identifier type | Case style | Prefix / rule | Example |
|:---|:---|:---|:---|
| Local variables | PascalCase | none | `UserCount`, `TotalAmount` |
| Private fields | PascalCase | `F` (Field) | `FUserName`, `FAge` |
| Constants | **ALL_CAPS** | underscore-separated | `MAX_USERS`, `DEFAULT_TIMEOUT` |
| Types (class/record) | PascalCase | `T` (Type) | `TUserAccount`, `TCSSToken` |
| Interfaces | PascalCase | `I` (Interface) | `ICSSTokenListener` |
| Properties | PascalCase | none; maps to `F` field | `property Name: string read FName;` |
| Method parameters | PascalCase | `A` (Argument) prefix | `procedure SetAge(const AValue: Integer);` |

Core rules:
- Constants **must** be `ALL_CAPS_WITH_UNDERSCORES` — no exceptions.
- **No** `snake_case` or `camelCase` for variables, types, or properties.
- Language keywords are always fully lowercase: `begin`, `end`, `var`, etc.

### 8.4 Enumerated Types

Type name uses `T` prefix; enum values use a **2–3 letter lowercase prefix**
derived from the type name to avoid global scope pollution:

```pascal
type
  TButtonKind = (bkOk, bkCancel, bkHelp, bkCustom);  // prefix: bk
  TUserType   = (utGuest, utStandard, utAdmin);        // prefix: ut
```

### 8.5 Block Formatting & Indentation

- **Indent**: 2 spaces per level. **Never use tab characters.**
- `begin` appears on a **new line**, aligned under its controlling keyword.
- `end` aligns vertically with its matching `begin`.

```pascal
// Correct
if UserCount > MAX_USERS then
begin
  ShowWarning();
  LogEvent('Capacity reached');
end;

// Incorrect
if UserCount > MAX_USERS then begin
    ShowWarning();
end;
```

**Single-statement branches** omit `begin`/`end`; indent by 2 spaces:

```pascal
if IsValidated then
  AllowAccess()
else
  DenyAccess();
```

### 8.6 Exception Handling (`try..finally` / `try..except`)

`try` cannot contain both `finally` and `except`. Use them as follows:

**Resource cleanup** — wrap immediately after creation:
```pascal
MyList := TStringList.Create();
try
  MyList.Add('item');
  SaveToLibrary(MyList);
finally
  MyList.Free();  // always runs, preventing leaks
end;
```

**Error trapping** — catch specific classes, never blank handlers:
```pascal
try
  Result := Compute(A, B);
except
  on E: EDivByZero do
  begin
    LogError('Division by zero.');
    Result := 0;
  end;
  on E: Exception do
  begin
    LogError('Unexpected: ' + E.Message);
    raise;
  end;
end;
```

**Combined cleanup + error handling** (the "double try" rule) — nest
`try..finally` _inside_ `try..except`:
```pascal
try
  Obj := TMyClass.Create();
  try
    Obj.DoWork();
  finally
    Obj.Free();  // fires first, guaranteed
  end;
except
  on E: Exception do
    HandleError(E.Message);
end;
```

Key rules:
- `try`, `finally`, `except`, and `end` must align to the **same column**.
- Always trap specific exception classes.

---

## 9. W3C CSS Syntax Level 3 Spec References

| Section | URL | Covers |
|---|---|---|
| §4 Tokenization | https://www.w3.org/TR/css-syntax-3/#tokenization | All 25 token types, tokenizer algorithms §4.3.1–§4.3.14 |
| §5 Parsing | https://www.w3.org/TR/css-syntax-3/#parsing | Parse entry points §5.3, consume algorithms §5.4 |
| §3 Preprocessing | https://www.w3.org/TR/css-syntax-3/#input-preprocessing | CRLF normalization, NUL replacement, BOM stripping |

Compliance level: **strict** — the implementation follows the spec algorithms
exactly, including error recovery (emit error tokens / skip bad declarations
and continue).

---

## 10. Phase Roadmap

| Phase | Unit(s) | Status |
|---|---|---|
| 1 — Tokenizer | `Floria.CSS.Types`, `Floria.CSS.Tokenizer` | ✅ Done — 80 tests |
| 2 — Parser | `Floria.CSS.AST`, `Floria.CSS.Parser` | ✅ Done — 43 tests |
| 3 — Typed property model | `Floria.CSS.Values`, `Floria.CSS.Properties` | ✅ Done — 60 tests |
| 4 — Selectors & Cascade | `Floria.CSS.Selectors`, `Floria.CSS.Cascade` | ✅ Done — 31 tests |
| 5 — Window Manager Framework | `Floria.XCB.WM` | ✅ Done — 12 tests |
| 6 — XML & SVG Subsystems | `Floria.XML.*`, `Floria.SVG.*` | ✅ Done — 49 tests |
| 7 — HTML Subsystem | `Floria.HTML.*` | ✅ Done — 23 tests |
| 8 — Image Codecs (Pure Pascal) | `Floria.Image.*` (Core, BMP, PNG, JPEG) | ✅ Done — 10 tests |
| 9 — Canvas & Graphics | `Floria.Image.Blur`, `Floria.Font`, `Floria.Canvas.Agg`, `Floria.SVG.Rasterizer` | ✅ Done — 13 tests |

The CSS engine, XCB Window Manager, XML/SVG DOM, HTML parser, pure Pascal Image codecs,
and AggPas 2D Canvas subsystems in `florialib` provide full foundations for GUI, window management, and vector/raster graphics.
Total test suite: 330 tests (all passing).

---

## 11. Adding a New Unit (Checklist)

1. Create `src/main/pascal/Floria.<Subsystem>.<Role>.pas`.
2. Start with `{$mode objfpc}{$H+}` and add `Contnrs` to `uses` if you need
   `TObjectList`.
3. Use `//` for all comments; avoid `{ }` block comments containing `{`/`}`.
4. Follow all coding style rules in §8 (casing, indentation, `()` on
   zero-parameter routines, exception handling).
5. Create a matching test unit `src/test/pascal/Floria.<Subsystem>.<Role>.Test.pas`.
6. Add the test unit to `src/test/pascal/TestRunner.pas` `uses` clause.
7. Run `pasbuild test` and confirm `E:0 F:0`.
8. Run `pasbuild install` to publish the updated units to the local repository
   for dependent projects.
