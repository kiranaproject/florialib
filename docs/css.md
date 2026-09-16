# CSS Subsystem Guide

The `florialib` CSS subsystem is a modular, high-performance styling engine written in Free Pascal. It implements the W3C CSS specifications across four interconnected layers:

```
Floria.CSS.Types       (Tokens, token types, position tracking, listener interface)
      ↓
Floria.CSS.Tokenizer   (Streaming push tokenizer conforming to W3C CSS Syntax Level 3 §4)
      ↓
Floria.CSS.AST         (Abstract Syntax Tree nodes with cascaded memory ownership)
      ↓
Floria.CSS.Parser      (Grammar parser conforming to W3C CSS Syntax Level 3 §5)
      ↓
Floria.CSS.Values      (Typed values: TCSSColor, TCSSLength, TCSSBox, TCSSBorderSide, layout enums)
      ↓
Floria.CSS.Properties  (Canonical property IDs, metadata, TCSSStyleDeclaration, TCSSStyleBlock)
      ↓
Floria.CSS.Selectors   (Compound & complex selectors, specificity (A,B,C), combinators)
      ↓
Floria.CSS.Cascade     (ICSSElement abstraction, right-to-left matching, cascade resolver)
```

---

## 1. Tokenizer (`Floria.CSS.Types`, `Floria.CSS.Tokenizer`)

The tokenizer conforms to **W3C CSS Syntax Level 3 §4**. It accepts chunks of `AnsiString` (supporting streaming inputs) and emits tokens via `ICSSTokenListener`.

### Token Types (`TCSSTokenType`)

25 distinct token types are supported:
- **Values**: `cttIdent`, `cttFunction`, `cttAtKeyword`, `cttHash`, `cttString`, `cttBadString`, `cttUrl`, `cttBadUrl`, `cttDelim`, `cttNumber`, `cttPercentage`, `cttDimension`, `cttWhitespace`.
- **HTML Compatibility**: `cttCDO` (`<!--`), `cttCDC` (`-->`).
- **Punctuation**: `cttColon`, `cttSemicolon`, `cttComma`, `cttOpenSquare`, `cttCloseSquare`, `cttOpenParen`, `cttCloseParen`, `cttOpenCurly`, `cttCloseCurly`.
- **Stream Termination**: `cttEOF`.

### Example: Streaming Tokenization

```pascal
uses Floria.CSS.Types, Floria.CSS.Tokenizer;

type
  TMyTokenPrinter = class(TObject, ICSSTokenListener)
  private
    function QueryInterface(constref IID: TGUID; out Obj): HResult; cdecl;
    function _AddRef(): Integer; cdecl;
    function _Release(): Integer; cdecl;
  public
    procedure OnToken(const AToken: TCSSToken);
  end;

procedure TMyTokenPrinter.OnToken(const AToken: TCSSToken);
begin
  WriteLn('Token: type=', AToken.TokenType, ' val="', AToken.Value, '" line=', AToken.Pos.Line);
end;

var
  Printer: TMyTokenPrinter;
  Tok    : TCSSTokenizer;
begin
  Printer := TMyTokenPrinter.Create();
  Tok := TCSSTokenizer.Create(Printer);
  try
    Tok.Feed('button.primary { color: #fff; }');
    Tok.Finish();
  finally
    Tok.Free();
    Printer.Free();
  end;
end;
```

---

## 2. Parser & AST (`Floria.CSS.AST`, `Floria.CSS.Parser`)

The parser implements **W3C CSS Syntax Level 3 §5**. It consumes the token stream and constructs a strongly typed Abstract Syntax Tree.

### AST Node Hierarchy

- `TCSSNode`: Base node with `NodeType: TCSSNodeType`.
  - `TCSSPreservedToken`: Wraps a single literal `TCSSToken`.
  - `TCSSSimpleBlock`: Block enclosed by `{}`, `[]`, or `()`.
  - `TCSSFunctionBlock`: Named function value (`Name`, `Children: TObjectList`).
  - `TCSSDeclaration`: Single property declaration (`Name`, `Value: TObjectList`, `Important: Boolean`).
  - `TCSSQualifiedRule`: CSS rule block (`Prelude: TObjectList` for selectors, `Declarations: TObjectList`).
  - `TCSSAtRule`: CSS at-rule like `@media` or `@charset` (`Name`, `Prelude`, `Block`).
  - `TCSSStylesheet`: Root node owning all top-level rules (`Rules: TObjectList`).

### Ownership Model

Every `TObjectList` in the AST is created with `FreeObjects = True`. Freeing the root `TCSSStylesheet` automatically frees the entire AST branch without manual iteration.

### Example: One-Shot Parsing

```pascal
uses Floria.CSS.AST, Floria.CSS.Parser;

var
  Sheet: TCSSStylesheet;
  Rule : TCSSQualifiedRule;
  Decl : TCSSDeclaration;
  I    : Integer;
begin
  Sheet := TCSSParser.FromCSS('window.active { border: 1px solid #336699; opacity: 0.95; }');
  try
    for I := 0 to Sheet.Rules.Count - 1 do
    begin
      if Sheet.Rules[I] is TCSSQualifiedRule then
      begin
        Rule := TCSSQualifiedRule(Sheet.Rules[I]);
        // Iterate declarations
        Decl := TCSSDeclaration(Rule.Declarations[0]);
        WriteLn('Found decl: ', Decl.Name, ' important=', Decl.Important);
      end;
    end;
  finally
    Sheet.Free(); // Automatically cascades through all nodes
  end;
end;
```

---

## 3. Typed Values (`Floria.CSS.Values`)

Raw AST declarations hold unparsed component tokens. `Floria.CSS.Values` transforms these into concrete Pascal records and enums:

### `TCSSColor`
- **Fields**: `R`, `G`, `B`, `A` (Byte, 0–255).
- **Parsers**:
  - `FromHex('#rgb')`, `FromHex('#rgba')`, `FromHex('#rrggbb')`, `FromHex('#rrggbbaa')`.
  - `FromName('red')`, `FromName('transparent')`, `FromName('white')` (supports all standard CSS named colors).
  - Functional syntax: `rgb(255, 0, 0)`, `rgba(0, 0, 255, 0.5)`, `rgb(100% 0% 0%)`, modern slash notation `rgb(255 128 0 / 0.5)`.
- **Formatters**: `ToHex(AIncludeAlpha)`, `ToRGBAString()`.

### `TCSSLength` & `TCSSUnit`
- **Units (`TCSSUnit`)**: `cuPx`, `cuEm`, `cuRem`, `cuPercent`, `cuPt`, `cuVw`, `cuVh`, `cuAuto`, `cuInherit`, `cuInitial`, `cuUnset`, `cuNone`.
- **Pixel Conversion**:
  ```pascal
  ActualPixels := Length.ToPixels(BaseFontSize, ParentSize);
  ```

### `TCSSBox`
Represents the 4-sided CSS box model (`Top`, `Right`, `Bottom`, `Left: TCSSLength`).
- Automatically handles 1, 2, 3, and 4-value shorthand forms:
  - 1 value: all 4 sides equal.
  - 2 values: top/bottom = val1, left/right = val2.
  - 3 values: top = val1, left/right = val2, bottom = val3.
  - 4 values: top, right, bottom, left.

### `TCSSBorderSide`
Composite representation for borders:
- `Width: TCSSLength`
- `Style: TCSSBorderStyle` (`cbsNone`, `cbsSolid`, `cbsDashed`, `cbsDotted`, `cbsDouble`, `cbsGroove`, etc.)
- `Color: TCSSColor`

### Layout & Appearance Enums
`TCSSDisplay`, `TCSSPosition`, `TCSSVisibility`, `TCSSOverflow`, `TCSSBoxSizing`, `TCSSFlexDirection`, `TCSSFlexWrap`, `TCSSJustifyContent`, `TCSSAlignItems`, `TCSSFontStyle`, `TCSSTextAlign`, `TCSSTextDecoration`.

---

## 4. Property Model (`Floria.CSS.Properties`)

Bridges component values and declarations into an indexed style container.

### `TCSSPropertyId`
Over 70 canonical property IDs:
- **Dimensions & Box Model**: `cpiWidth`, `cpiHeight`, `cpiMinWidth`, `cpiMaxWidth`, `cpiMargin`, `cpiMarginTop`..`Left`, `cpiPadding`, `cpiPaddingTop`..`Left`.
- **Borders**: `cpiBorder`, `cpiBorderTop`..`Left`, `cpiBorderWidth`, `cpiBorderStyle`, `cpiBorderColor`, `cpiBorderRadius`.
- **Layout & Flex**: `cpiDisplay`, `cpiPosition`, `cpiTop`, `cpiRight`, `cpiBottom`, `cpiLeft`, `cpiZIndex`, `cpiFlexDirection`, `cpiJustifyContent`, `cpiAlignItems`.
- **Appearance & Typography**: `cpiColor`, `cpiBackgroundColor`, `cpiOpacity`, `cpiFontFamily`, `cpiFontSize`, `cpiCursor`.
- **Custom Variables**: `cpiCustom` (`--theme-color`, etc.).

### Automatic Shorthand Expansion

When parsing declarations, `TCSSStyleBlock` automatically expands shorthand properties:
- `margin: 10px 20px` → expands to individual `cpiMarginTop`, `cpiMarginRight`, `cpiMarginBottom`, `cpiMarginLeft`.
- `padding: 8px` → expands to all four sides.
- `border: 1px solid #ff0000` → expands to top/right/bottom/left widths, styles, and colors.

### Example: Using `TCSSStyleBlock`

```pascal
uses Floria.CSS.Properties, Floria.CSS.Values;

var
  Block: TCSSStyleBlock;
  Decl : TCSSStyleDeclaration;
begin
  Block := TCSSStyleBlock.FromCSS('color: #0088ff; margin: 10px 20px; display: flex;');
  try
    // Query color
    if Block.FindDeclaration(cpiColor, Decl) then
      WriteLn('Color: ', Decl.Value.Color.ToHex());

    // Query expanded margin
    if Block.FindDeclaration(cpiMarginRight, Decl) then
      WriteLn('Margin-Right: ', Decl.Value.Length.ToString()); // '20px'

    // Query enum
    if Block.FindDeclaration(cpiDisplay, Decl) then
      WriteLn('Display is flex: ', Decl.Value.AsDisplay() = cdFlex);
  finally
    Block.Free();
  end;
end;
```

---

## 5. Selectors & Specificity (`Floria.CSS.Selectors`)

Parses complex W3C selectors and computes their specificity tuple `(A, B, C)`.

### Specificity Scoring

Per W3C Selectors specification:
- **`A`**: Count of `#id` selectors.
- **`B`**: Count of class selectors (`.class`), attribute selectors (`[attr]`), and pseudo-classes (`:hover`).
- **`C`**: Count of type/tag selectors (`div`) and pseudo-elements.
- Universal selectors (`*`) contribute `(0, 0, 0)`.

```pascal
Spec := Selector.CalculateSpecificity(); // Returns TCSSSpecificity
if SpecA.CompareTo(SpecB) > 0 then
  WriteLn('SpecA has higher priority');
```

### Supported Combinators

- **Descendant** (` `): matches any descendant element.
- **Child** (`>`): matches direct child elements.
- **Adjacent Sibling** (`+`): matches immediately succeeding sibling.
- **General Sibling** (`~`): matches any subsequent sibling.

---

## 6. Cascade & Style Resolver (`Floria.CSS.Cascade`)

Applies matching rules across multiple stylesheets to an element hierarchy and computes the resulting styles.

### `ICSSElement` Interface

Any UI element or window node implements `ICSSElement` to receive styling:

```pascal
ICSSElement = interface(IInterface)
  function GetTagName(): AnsiString;
  function GetId(): AnsiString;
  function HasClass(const AClass: AnsiString): Boolean;
  function HasAttribute(const AName: AnsiString): Boolean;
  function GetAttribute(const AName: AnsiString): AnsiString;
  function GetParent(): ICSSElement;
  function GetPreviousSibling(): ICSSElement;
  function GetChildIndex(): Integer;
  function GetSiblingCount(): Integer;
  function IsHovered(): Boolean;
  function IsFocused(): Boolean;
  function IsActive(): Boolean;
  function IsDisabled(): Boolean;
end;
```

A concrete reference implementation is provided in `TCSSMockElement`.

### Cascade Precedence Rules

`TCSSStyleResolver.ResolveStyle()` applies matched rules in strict order:
1. **Importance**: `!important` declarations override normal declarations regardless of specificity.
2. **Specificity**: Higher `(A, B, C)` specificity overrides lower specificity.
3. **Source Order**: For equal specificity, declarations appearing later in stylesheets win.
4. **Inheritance**: Inherited properties (`color`, `font-family`, `font-size`, `visibility`, `line-height`, `text-align`) automatically cascade down from `AParentStyle` if not overridden on the target element.

### Example: Full Style Resolution

```pascal
uses Floria.CSS.Cascade, Floria.CSS.Properties, Floria.CSS.Values;

var
  Resolver   : TCSSStyleResolver;
  WindowElem : TCSSMockElement;
  ButtonElem : TCSSMockElement;
  ParentStyle: TCSSStyleBlock;
  ChildStyle : TCSSStyleBlock;
begin
  Resolver := TCSSStyleResolver.Create();
  WindowElem := TCSSMockElement.Create('window', 'main-win');
  ButtonElem := TCSSMockElement.Create('button');
  try
    ButtonElem.AddClass('btn');
    ButtonElem.AddClass('btn-primary');
    WindowElem.AppendChild(ButtonElem);

    // Add stylesheets
    Resolver.AddCSS('window { color: #ffffff; margin: 10px; }');
    Resolver.AddCSS('button { width: 100px; }');
    Resolver.AddCSS('.btn-primary { background-color: #007acc; }');

    // 1. Resolve parent window style
    ParentStyle := Resolver.ResolveStyle(WindowElem);
    try
      // 2. Resolve button style, inheriting from window
      ChildStyle := Resolver.ResolveStyle(ButtonElem, ParentStyle);
      try
        // Color is inherited from window
        WriteLn('Button color: ', ChildStyle.GetDeclaration(cpiColor).Value.Color.ToHex());
        // Background color is matched from .btn-primary
        WriteLn('Button bg: ', ChildStyle.GetDeclaration(cpiBackgroundColor).Value.Color.ToHex());
        // Width is matched from button
        WriteLn('Button width: ', ChildStyle.GetDeclaration(cpiWidth).Value.Length.ToString());
        // Margin was NOT inherited (margin is not an inherited property)
        WriteLn('Has margin: ', ChildStyle.HasProperty(cpiMarginTop)); // False
      finally
        ChildStyle.Free();
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
