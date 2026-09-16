# Coding Standards & Contributor Guide

All units and test suites in `florialib` follow strict Object Pascal coding standards shared across the **Floria** project family.

---

## 1. Compiler Directives & Dialect

Every unit begins with:

```pascal
unit Floria.<Subsystem>.<Role>;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords} // When advanced record methods or static class functions are needed
```

- **Dialect**: `{$mode objfpc}` (Free Pascal object-oriented Pascal mode).
- **Strings**: `{$H+}` enables long `AnsiString` by default.
- **Advanced Records**: `{$modeswitch advancedrecords}` enables methods and constructors on `record` types.

---

## 2. Mandatory Empty Parentheses `()` on Zero-Parameter Routines

To unambiguously distinguish callable routines from fields and properties:

### 2.1 Routine Declarations
Every zero-parameter `procedure`, `function`, `constructor`, or `destructor` declaration **must** include empty parentheses `()`:

```pascal
// Correct
procedure Invalidate(); virtual;
function GetChildCount(): Integer;
constructor Create();
destructor Destroy(); override;

// Incorrect — do NOT omit parentheses
procedure Invalidate;
function GetChildCount: Integer;
constructor Create;
destructor Destroy; override;
```

### 2.2 Routine Call Sites
Every call to a zero-parameter routine **must** include empty parentheses `()`:

```pascal
// Correct
List := TObjectList.Create();
try
  Invalidate();
  inherited Destroy();
finally
  List.Free();
end;

// Incorrect — do NOT omit parentheses
List := TObjectList.Create;
Invalidate;
inherited Destroy;
List.Free;
```

*Note: Properties and record fields do not use parentheses: `Btn.Visible := True;`.*

---

## 3. Comment Conventions

Free Pascal does **not** support nested `{}` block comments. Any `{` or `}` inside a `{ ... }` comment confuses the parser and causes fatal errors.

- **Always use `//` line comments** for inline documentation, code comments, and section dividers.
- **Use `(* ... *)`** only when writing multi-line block comments that must contain `{}` characters in their text.
- **Never** write `{ }` comments that contain `{`, `}`, `[`, or `]`.

```pascal
// Correct:
// Section divider comment
// Simple block with contents: curly-brace or paren block.

// Correct multi-line:
(* Comment explaining { and } block tokens. *)

// Incorrect:
{ A block with { or } inside will corrupt the parser }
```

---

## 4. Identifier Casing & Naming Conventions

| Element | Format | Prefix / Rule | Example |
|---|---|---|---|
| **Unit Names** | PascalCase | Dotted namespaces | `Floria.CSS.Values` |
| **Classes / Records** | PascalCase | `T` prefix | `TCSSColor`, `TCSSStyleBlock` |
| **Interfaces** | PascalCase | `I` prefix | `ICSSElement`, `ICSSTokenListener` |
| **Private Fields** | PascalCase | `F` prefix | `FTagName`, `FParent` |
| **Arguments / Params** | PascalCase | `A` prefix | `const AName: AnsiString` |
| **Constants** | **ALL_CAPS** | Underscore separated | `MAX_ELEMENTS`, `DEFAULT_DPI` |
| **Enum Types** | PascalCase | `T` prefix | `TCSSDisplay`, `TCSSUnit` |
| **Enum Values** | Mixed | 2–3 letter lowercase prefix | `cdBlock`, `cdFlex`, `cuPx`, `cuAuto` |
| **Properties** | PascalCase | Maps to `F` field | `property Width: Double read FWidth;` |
| **Local Variables** | PascalCase | Clear descriptive names | `CurrentNode`, `ParsedColor` |

---

## 5. Memory Ownership & Collections

### `TObjectList` in `Contnrs`
`TObjectList` in Free Pascal lives in the **`Contnrs`** unit, not `Classes`:

```pascal
uses Classes, Contnrs, SysUtils, ...;
```

### Cascading Lifetime Hierarchy
Every composite node or list owns its items:

```pascal
FChildren := TObjectList.Create(True); // OwnsObjects = True
```

- When the parent container is freed via `Obj.Free()`, all contained children are freed recursively.
- Never add the same object instance to multiple owning lists. If an object reference is shared, store it in a non-owning list (`TObjectList.Create(False)`) or as an interface reference.

### Exception-Safe Destruction
Wrap allocations immediately in `try..finally`:

```pascal
List := TStringList.Create();
try
  PopulateList(List);
  ProcessList(List);
finally
  List.Free();
end;
```

---

## 6. Testing & Pasbuild Workflow

### Running Tests
Execute the entire test suite with plain text reporting:

```bash
pasbuild test
```

### Adding a New Unit
1. Create `src/main/pascal/Floria.<Subsystem>.<Role>.pas`.
2. Implement using `{$mode objfpc}{$H+}` and the conventions above.
3. Add the unit to `src/main/pascal/florialib.pas` and `florialib.lpk`.
4. Create the corresponding test unit in `src/test/pascal/Floria.<Subsystem>.<Role>.Test.pas`.
5. Register the test class in its `initialization` section:
   ```pascal
   initialization
     RegisterTest(TMyTestSuite);
   end.
   ```
6. Add the test unit to `src/test/pascal/TestRunner.pas` `uses` clause.
7. Run `pasbuild test` and ensure `E:0 F:0`.
