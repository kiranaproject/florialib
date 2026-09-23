# Floria.Image — Independent Image Subsystem Specification

## 1. Overview & Motivation

`Floria.Image` provides a lightweight, pure Object Pascal image model and format reader/writer subsystem designed to eliminate dependency on the Free Component Library's `fcl-image` (`FPImage`, `fpreadpng`, `fpwritepng`, `fpreadjpeg`, `fpreadbmp`). 

This architecture supports the migration toward **Blaise** and ensures that `florialib` and downstream toolkits (like `floria-toolkit`) can decode, encode, and manipulate raster images without heavyweight framework dependencies or external C shared libraries.

```
                    ┌───────────────────────────────────────────────┐
                    │               Floria.Image.Core               │
                    │  • TFloriaImage raster buffer (BGRA32)        │
                    │  • Pixel access, stride, scanlines, scaling   │
                    │  • Extensible Reader / Writer Codec Registry  │
                    └───────┬───────────────┬───────────────┬───────┘
                            │               │               │
             ┌──────────────┴───┐    ┌──────┴────────┐    ┌─┴────────────────┐
             ▼                  ▼    ▼               ▼    ▼                  ▼
    ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
    │ Floria.Image.BMP│ │ Floria.Image.PNG│ │Floria.Image.JPEG│ │ Future Codecs │
    │ • 24/32-bit BGR │ │ • IHDR, IDAT    │ │ • Baseline DCT  │ │ (QOI, TGA, etc.)│
    │ • Top/bottom-up │ │ • Zlib/Deflate  │ │ • Huffman, IDCT │ │                 │
    │ • Reader/Writer │ │ • 5 Scanline Fltrs│ • YCbCr->RGB    │ │                 │
    │                 │ │ • Reader/Writer │ │ • Reader        │ │                 │
    └─────────────────┘ └─────────────────┘ └─────────────────┘ └─────────────────┘
```

---

## 2. Unit Architecture

| Unit | Role | Key Classes / Types |
|---|---|---|
| [`Floria.Image.Core`](file:///home/afumi/Documents/projects/kirana/florialib/src/main/pascal/Floria.Image.Core.pas) | Core raster buffer, color types, scaling, and codec registry | `TFloriaImage`, `TBgraPixel`, `TRgbaPixel`, `TFloriaPixelFormat`, `TFloriaImageReader`, `TFloriaImageWriter` |
| [`Floria.Image.BMP`](file:///home/afumi/Documents/projects/kirana/florialib/src/main/pascal/Floria.Image.BMP.pas) | Pure Pascal BMP encoder and decoder | `TFloriaBMPReader`, `TFloriaBMPWriter` |
| [`Floria.Image.PNG`](file:///home/afumi/Documents/projects/kirana/florialib/src/main/pascal/Floria.Image.PNG.pas) | Pure Pascal PNG encoder and decoder (with pure Pascal Deflate/Inflate) | `TFloriaPNGReader`, `TFloriaPNGWriter` |
| [`Floria.Image.JPEG`](file:///home/afumi/Documents/projects/kirana/florialib/src/main/pascal/Floria.Image.JPEG.pas) | Pure Pascal baseline JPEG decoder | `TFloriaJPEGReader` |

---

## 3. Data Structures & Memory Layout

### AggPas & 2D Graphics Compatibility
`TFloriaImage` stores pixel data natively in **32-bit BGRA format** (little-endian: Blue at byte 0, Green at byte 1, Red at byte 2, Alpha at byte 3):
- Matches `XCB_RENDER_PICT_FORMAT_ARGB32` in little-endian order.
- Direct zero-copy compatibility with AggPas (`pixfmt_bgra32`, `rendering_buffer.attach(PixelBuffer, Width, Height, Stride)`).
- Direct zero-copy compatibility with Cairo (`CAIRO_FORMAT_ARGB32`).

### Color Records
```pascal
type
  TBgraPixel = packed record
    B, G, R, A: Byte;
  end;
  PBgraPixel = ^TBgraPixel;

  TRgbaPixel = packed record
    R, G, B, A: Byte;
  end;
  PRgbaPixel = ^TRgbaPixel;
```

---

## 4. `TFloriaImage` API

### Constructors & Destructor
- `constructor Create();`
- `constructor Create(const AWidth, AHeight: Integer; const AFormat: TFloriaPixelFormat = fpfBGRA32);`
- `constructor CreateFromFile(const AFileName: string);`
- `constructor CreateFromStream(AStream: TStream);`
- `constructor CreateFromMemory(const AData: Pointer; const ASize: Integer);`
- `destructor Destroy(); override;`

### Pixel Manipulation & Blitting
- `property Pixels[const X, Y: Integer]: TBgraPixel read GetPixel write SetPixel;`
- `property Scanline[const Y: Integer]: Pointer read GetScanline;`
- `procedure Clear(const R, G, B: Byte; const A: Byte = 255);`
- `function Clone(): TFloriaImage;`
- `function CreateScaled(const NewW, NewH: Integer): TFloriaImage;`
- `procedure CopyFrom(ASource: TFloriaImage; const SrcX, SrcY, DstX, DstY, W, H: Integer);`

### Input / Output
- `procedure LoadFromFile(const AFileName: string);`
- `procedure LoadFromStream(AStream: TStream);`
- `procedure LoadFromMemory(const AData: Pointer; const ASize: Integer);`
- `procedure SaveToFile(const AFileName: string; const AFormat: TFloriaImageFormat = fifUnknown);`
- `procedure SaveToStream(AStream: TStream; const AFormat: TFloriaImageFormat);`

---

## 5. Codec Registry & Auto-Detection

The registry identifies image formats automatically by inspecting initial magic bytes:
- **BMP**: Header starting with ASCII `'B'`, `'M'` (`$42, $4D`).
- **PNG**: 8-byte signature (`$89, $50, $4E, $47, $0D, $0A, $1A, $0A`).
- **JPEG**: Start-of-Image marker (`$FF, $D8, $FF`).

```pascal
type
  TFloriaImageReaderClass = class of TFloriaImageReader;
  TFloriaImageWriterClass = class of TFloriaImageWriter;

procedure RegisterImageReader(const AReaderClass: TFloriaImageReaderClass);
procedure RegisterImageWriter(const AFormat: TFloriaImageFormat; const AWriterClass: TFloriaImageWriterClass);
function DetectImageFormat(AStream: TStream): TFloriaImageFormat;
```

---

## 6. Testing & Quality Assurance

The test suite in `Floria.Image.Test.pas` verifies:
1. Raster buffer memory allocation, stride alignment, pixel getters and setters.
2. Bilinear/box scaling algorithm (`CreateScaled`).
3. Format auto-detection on synthetic header data.
4. End-to-end BMP round-trip encoding and decoding (RGB24, RGBA32, bottom-up and top-down).
5. End-to-end PNG round-trip encoding and decoding with alpha channel.
6. Baseline JPEG decoding of SOI, DQT, DHT, SOF0, SOS markers, IDCT, and YCbCr conversion.
7. Error recovery and graceful failure on truncated or malformed streams.
