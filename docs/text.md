# Floria.Unicode.BiDi & Floria.Text.HarfBuzz — Text Layout & Shaping Subsystem

## 1. Overview & Architecture

The text subsystem in `florialib` provides internationalized text layout and OpenType glyph shaping:
- **`Floria.Unicode.BiDi`**: Pure Pascal implementation of the Unicode Bidirectional Algorithm (**UAX #9**).
- **`Floria.Text.HarfBuzz`**: Dynamic binding and shaper engine powered by **HarfBuzz** (`libharfbuzz.so.0`), with zero hard binary dependencies and automatic fallback.

```
                      UTF-8 Input String ("Hello مرحبا 123")
                                   │
                                   ▼
             ┌───────────────────────────────────────────┐
             │       Floria.Unicode.BiDi (Pure Pascal)   │
             │   - Unicode Bidi_Class lookup (ranges)    │
             │   - Paragraph direction detection (P1-P3) │
             │   - Weak & neutral resolution (W1-W7, N)  │
             │   - Bracket mirroring (Bidi_Mirrored)     │
             │   - Reorders into unidirectional visual   │
             │     runs: [Run0: LTR], [Run1: RTL], ...   │
             └───────────────────────────────────────────┘
                                   │
                                   ▼
             ┌───────────────────────────────────────────┐
             │            Floria.Text.HarfBuzz           │
             │   - Dynamic dlopen of libharfbuzz.so.0    │
             │   - Pure Pascal Fallback if not found     │
             │   - Shapes each run with font + direction │
             │     (HB_DIRECTION_LTR / HB_DIRECTION_RTL) │
             │   - Outputs: Glyph IDs, advances, offsets │
             └───────────────────────────────────────────┘
                                   │
                                   ▼
             ┌───────────────────────────────────────────┐
             │         Canvas Rendering & Metrics        │
             │   Blits shaped glyphs with font cache     │
             └───────────────────────────────────────────┘
```

---

## 2. Unicode Bidirectional Engine (`Floria.Unicode.BiDi`)

### 2.1 Capabilities
- Full classification for all 23 Unicode `Bidi_Class` types:
  - Strong: `fbcL` (LTR), `fbcR` (RTL / Hebrew), `fbcAL` (Arabic Letter)
  - Weak: `fbcEN`, `fbcES`, `fbcET`, `fbcAN`, `fbcCS`, `fbcNSM`, `fbcBN`
  - Neutral / Isolates: `fbcB`, `fbcS`, `fbcWS`, `fbcON`, `fbcLRE`, `fbcRLE`, `fbcPDF`, etc.
- Implements UAX #9 resolution rules:
  - **P1–P3**: Paragraph base embedding level (`fbbAuto`, `fbbLTR`, `fbbRTL`).
  - **W1–W7**: Weak type resolution (numbers, non-spacing marks, separators).
  - **N0–N2**: Neutral and bracket pairing resolution.
  - **I1–I2**: Implicit level resolution.
  - **L1–L2**: Visual run ordering.
- **RTL Character Mirroring**: Automatically mirrors glyphs in RTL contexts (e.g. `(` ↔ `)`, `[` ↔ `]`, `<` ↔ `>`).
- **RTL Fast Detection**: `TFloriaBiDi.HasRTL(text)` to avoid BiDi overhead for purely LTR strings.

### 2.2 Visual Runs vs. Visual String
The engine supports two distinct outputs depending on your rendering pipeline:

1. **`GetVisualRuns(text, baseDir)`**:
   Returns an array of `TFloriaBiDiRun` ordered from left to right on screen.
   **Crucial Invariant**: The characters *inside* each run remain in **logical reading order**. This allows OpenType shaping engines like HarfBuzz to compute contextual cursive joining (initial, medial, final, isolated forms) and ligatures correctly.
2. **`ReorderToVisualString(text, baseDir)`**:
   Reorders text visually and **reverses** code points in RTL runs with bracket mirroring. Used for plain fallback output (consoles, simple canvas without a shaping engine).

---

## 3. Dynamic HarfBuzz Text Shaping (`Floria.Text.HarfBuzz`)

### 3.1 Zero Hard Binary Dependencies
`Floria.Text.HarfBuzz` uses FPC's `dynlibs` to safely load `libharfbuzz.so.0` on Linux (or `.dylib` / `.dll` on other platforms) at runtime:
- If HarfBuzz is installed on the host system: full OpenType layout is enabled (`GSUB` ligatures, `GPOS` kerning, Arabic cursive joining, Indic conjuncts, Thai mark positioning).
- If HarfBuzz is absent: the unit seamlessly falls back to `FallbackSimpleShape` (1:1 character-to-advance mapping) without crashes or missing library errors.

### 3.2 High-Level API

```pascal
uses
  Floria.Font, Floria.Unicode.BiDi, Floria.Text.HarfBuzz;

var
  Fnt: TFloriaFont;
  Run: TFloriaShapedRun;
  TotalWidth: Double;
begin
  Fnt := FloriaFontManager().GetFont('Sans-12');

  // Shape mixed bidirectional text
  Run := FloriaShapeText(Fnt, 'Hello مرحبا 123');

  // Compute exact pixel width from shaped glyph advances
  TotalWidth := FloriaShapedRunWidth(Run);
  WriteLn('Text width: ', TotalWidth:0:2, ' px');
end;
```

---

## 4. Shaped Glyph Structure

Each shaped glyph contains device-pixel-ready positioning:

```pascal
type
  TFloriaShapedGlyph = record
    GlyphIndex : Cardinal; // Font glyph index for rendering
    Cluster    : Cardinal; // Source character byte index
    XAdvance   : Double;   // Horizontal advance (px)
    YAdvance   : Double;   // Vertical advance (px)
    XOffset    : Double;   // Horizontal placement offset (px)
    YOffset    : Double;   // Vertical placement offset (px)
  end;
  TFloriaShapedRun = array of TFloriaShapedGlyph;
```

---

## 5. File & Unit Conventions

| Unit | Filename | Description |
|---|---|---|
| `Floria.Unicode.BiDi` | `floria.unicode.bidi.pas` | UAX #9 Bidirectional algorithm |
| `Floria.Text.HarfBuzz` | `floria.text.harfbuzz.pas` | Dynamic HarfBuzz shaper |
| `Floria.Unicode.BiDi.Test` | `floria.unicode.bidi.test.pas` | 8 BiDi unit tests |
| `Floria.Text.HarfBuzz.Test` | `floria.text.harfbuzz.test.pas` | 6 HarfBuzz shaper unit tests |
