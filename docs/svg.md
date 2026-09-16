# SVG Subsystem Guide

The `florialib` SVG subsystem is a zero-dependency, high-performance SVG 1.1 DOM and parsing library written in Free Pascal (`{$mode objfpc}`). It builds directly upon `Floria.XML` and `Floria.CSS` to provide a complete scene graph, affine 2D transform pipeline, precision path mathematics, and CSS style cascading.

```
Floria.XML (XML 1.0 Tokenizer & DOM)  +  Floria.CSS (Cascade Engine)
                   │                                │
                   ▼                                ▼
       Floria.SVG.Types    (Matrices, Transforms, Units, Lengths, Paints)
                   │
                   ▼
       Floria.SVG.Path     (SVG Path Parser, Arc Decomposition, Bounding Box)
                   │
                   ▼
       Floria.SVG.DOM      (Typed Scene Graph, Presentation Attributes, <use>)
                   │
                   ▼
       Floria.SVG.Parser   (TSVGDocument Builder, Embedded <style> Cascade)
```

---

## 1. Architecture Overview

| Unit | Role | Key Types & Functions |
|---|---|---|
| `Floria.SVG.Types` | 2D affine transforms, length units, colors/paints, viewBox mapping | `TSVGMatrix`, `TSVGPoint`, `TSVGRect`, `TSVGLength`, `TSVGPaint`, `SVGParseTransform`, `SVGParseLength`, `SVGParsePaint` |
| `Floria.SVG.Path` | SVG 1.1 path parser, command normalizer, W3C F.6 arc decomposition, bounding boxes | `TSVGPathData`, `TSVGPathSegment`, `TSVGCommandType`, basic shape path factories |
| `Floria.SVG.DOM` | Typed scene graph nodes, presentation attributes, style inheritance, `<use>` resolving | `TSVGElement`, `TSVGSvgElement`, `TSVGPathElement`, `TSVGRectElement`, `TSVGCircleElement`, `TSVGUseElement`, `TSVGLinearGradientElement` |
| `Floria.SVG.Parser` | XML-to-SVG document builder, `<style>` CSS stylesheet extraction and cascade | `TSVGParser`, `TSVGDocument` |

---

## 2. Parsing SVG Documents

### Parse from String

```pascal
uses Floria.SVG.DOM, Floria.SVG.Parser;

var
  Doc: TSVGDocument;
  SvgRoot: TSVGSvgElement;
begin
  Doc := TSVGParser.ParseString(
    '<svg width="200" height="200" viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">' +
    '  <rect x="10" y="10" width="80" height="80" fill="navy" stroke="orange" stroke-width="2" />' +
    '  <circle cx="50" cy="50" r="30" fill="gold" />' +
    '</svg>');
  try
    SvgRoot := Doc.Root;
    WriteLn('Width: ', SvgRoot.Width.Value);
    WriteLn('Children: ', SvgRoot.Children.Count);
  finally
    Doc.Free();
  end;
end;
```

### Parse from File

```pascal
Doc := TSVGParser.ParseFile('/path/to/icon.svg');
try
  // Traverse scene graph or rasterize...
finally
  Doc.Free();
end;
```

---

## 3. 2D Transforms and Coordinates

`TSVGMatrix` represents a 3x3 affine transformation matrix:

$$\begin{bmatrix} a & c & e \\ b & d & f \\ 0 & 0 & 1 \end{bmatrix}$$

### Matrix Operations

```pascal
var
  M: TSVGMatrix;
  Pt: TSVGPoint;
begin
  M := TSVGMatrix.Identity();
  M := M.Translate(50, 100);
  M := M.Rotate(45 * Pi / 180.0);
  M := M.Scale(2.0, 2.0);

  Pt := M.TransformPoint(SVGPoint(10, 20));
end;
```

### Transform Attribute Parsing

SVG `transform="..."` attributes are parsed with chained operation support:

```pascal
M := SVGParseTransform('translate(30, 20) rotate(45) scale(1.5)');
```

### ViewBox Calculation

The `CalculateViewBoxTransform` method determines the scaling and alignment matrix according to SVG `preserveAspectRatio` rules (`meet`, `slice`, `none`, `xMidYMid`, etc.):

```pascal
M := SvgRoot.GetViewBoxTransform(ActualPixelWidth, ActualPixelHeight);
```

---

## 4. Path Mathematics and Arc Decomposition

The `TSVGPathData` engine parses and processes SVG path mini-languages according to SVG 1.1 specifications.

### Parsing and Compact Notation

Supports both spaced and compact coordinate formatting:

```pascal
var
  Path: TSVGPathData;
begin
  Path := TSVGPathData.Create();
  try
    Path.Parse('M10 20L30 40C50 60 70 80 90 100Z');
  finally
    Path.Free();
  end;
end;
```

### Normalization

The `Normalize()` method transforms relative commands (`m, l, h, v, c, s, q, t, a, z`) into absolute cubic Bézier curves, line-to, and close-path commands:
- Relative moves and lines become absolute `sctMoveTo` and `sctLineTo`.
- Horizontal (`H/h`) and vertical (`V/v`) commands expand to 2D coordinates.
- Smooth cubics (`S/s`) and smooth quadratics (`T/t`) synthesize their reflected control points.
- Elliptical arcs (`A/a`) are decomposed into sequences of 4-point cubic Béziers using standard W3C Appendix F.6 parameter conversion.

```pascal
NormPath := Path.Normalize();
try
  // NormPath contains only sctMoveTo, sctLineTo, sctCubicTo, and sctClose
finally
  NormPath.Free();
end;
```

### Exact Bounding Box

Path bounding boxes are computed using exact derivative roots for cubic and quadratic Bézier curve extrema:

```pascal
Box := Path.GetBoundingBox();
WriteLn('BBox: (', Box.X:0:2, ', ', Box.Y:0:2, ') - ', Box.Width:0:2, 'x', Box.Height:0:2);
```

---

## 5. CSS Cascade Integration

`TSVGElement` implements `ICSSElement`, allowing CSS stylesheets in embedded `<style>` blocks or external stylesheets to style SVG elements via standard CSS selectors:

```xml
<svg xmlns="http://www.w3.org/2000/svg">
  <style>
    .highlight { fill: #ff0000; stroke: #000; stroke-width: 2px; }
    #badge { fill: gold; }
  </style>
  <rect id="badge" class="highlight" width="100" height="50" />
</svg>
```

When parsed by `TSVGParser`, styles are automatically resolved:
1. Presentation attributes (`fill`, `stroke`, `opacity`, `transform`) set baseline styles.
2. `<style>` selectors are evaluated with W3C specificity.
3. Inheritable properties cascade down from parent containers (`<svg>`, `<g>`) to children.
