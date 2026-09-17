unit Floria.SVG.Test;

// Floria.SVG.Test
// ===============
// Comprehensive test suite for Floria.SVG subsystems:
//   - TSVGTypesTest: Affine matrix math, transform parsing, units & viewBox calculations
//   - TSVGPathTest: Path command parsing, compact syntax, normalization, arc decomposition, bbox
//   - TSVGDOMTest: Scene graph hierarchy, style inheritance, opacity composition, <use> references
//   - TSVGParserTest: XML to SVG DOM building, presentation attributes, CSS stylesheet cascade

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Contnrs, fpcunit, testregistry, Math,
  Floria.CSS.Types, Floria.CSS.Values, Floria.CSS.Properties,
  Floria.SVG.Types, Floria.SVG.Path, Floria.SVG.DOM, Floria.SVG.Parser;

type
  { TSVGTypesTest }

  TSVGTypesTest = class(TTestCase)
  published
    procedure TestMatrixIdentity();
    procedure TestMatrixMultiply();
    procedure TestMatrixTransforms();
    procedure TestMatrixInvert();
    procedure TestTransformParser();
    procedure TestLengthParser();
    procedure TestViewBoxCalculation();
    procedure TestPaintParser();
  end;

  { TSVGPathTest }

  TSVGPathTest = class(TTestCase)
  published
    procedure TestPathBasicCommands();
    procedure TestPathCurves();
    procedure TestPathArcs();
    procedure TestPathRelative();
    procedure TestPathCompactSyntax();
    procedure TestPathNormalization();
    procedure TestArcDecomposition();
    procedure TestBoundingBox();
    procedure TestShapeToPath();
  end;

  { TSVGDOMTest }

  TSVGDOMTest = class(TTestCase)
  published
    procedure TestDOMHierarchy();
    procedure TestStyleInheritance();
    procedure TestStyleOverride();
    procedure TestOpacityComposition();
    procedure TestFindById();
    procedure TestUseElement();
  end;

  { TSVGParserTest }

  TSVGParserTest = class(TTestCase)
  published
    procedure TestParseSimpleSVG();
    procedure TestParseShapesAndGroups();
    procedure TestParseGradients();
    procedure TestCSSCascadeIntegration();
    procedure TestRealWorldSVGIcon();
  end;

implementation

// ── TSVGTypesTest ────────────────────────────────────────────────────────────

procedure TSVGTypesTest.TestMatrixIdentity();
var
  M: TSVGMatrix;
  P: TSVGPoint;
begin
  M := SVGMatrixIdentity();
  AssertTrue('Identity check', SVGMatrixIsIdentity(M));

  P := SVGMatrixTransformPoint(M, SVGPoint(12.5, 34.5));
  AssertEquals(12.5, P.X, 1e-6);
  AssertEquals(34.5, P.Y, 1e-6);
end;

procedure TSVGTypesTest.TestMatrixMultiply();
var
  M1, M2, M3: TSVGMatrix;
  P: TSVGPoint;
begin
  // Translate (10, 20) then scale (2, 3)
  M1 := SVGMatrixTranslate(10.0, 20.0);
  M2 := SVGMatrixScale(2.0, 3.0);
  M3 := SVGMatrixMultiply(M1, M2);

  // Point (5, 5): scaled to (10, 15) then translated by (10, 20) = (20, 35)
  P := SVGMatrixTransformPoint(M3, SVGPoint(5.0, 5.0));
  AssertEquals(20.0, P.X, 1e-6);
  AssertEquals(35.0, P.Y, 1e-6);
end;

procedure TSVGTypesTest.TestMatrixTransforms();
var
  M: TSVGMatrix;
  P: TSVGPoint;
begin
  // Rotate 90 degrees: (1, 0) -> (0, 1)
  M := SVGMatrixRotate(90.0);
  P := SVGMatrixTransformPoint(M, SVGPoint(1.0, 0.0));
  AssertEquals(0.0, P.X, 1e-6);
  AssertEquals(1.0, P.Y, 1e-6);

  // Rotate 90 degrees around center (10, 10): (11, 10) -> (10, 11)
  M := SVGMatrixRotateAt(90.0, 10.0, 10.0);
  P := SVGMatrixTransformPoint(M, SVGPoint(11.0, 10.0));
  AssertEquals(10.0, P.X, 1e-6);
  AssertEquals(11.0, P.Y, 1e-6);

  // SkewX 45 degrees: Tan(45 deg) = 1.0; (0, 10) -> (10, 10)
  M := SVGMatrixSkewX(45.0);
  P := SVGMatrixTransformPoint(M, SVGPoint(0.0, 10.0));
  AssertEquals(10.0, P.X, 1e-5);
  AssertEquals(10.0, P.Y, 1e-5);
end;

procedure TSVGTypesTest.TestMatrixInvert();
var
  M, Inv, Prod: TSVGMatrix;
  P, PTrans, PBack: TSVGPoint;
  Ok: Boolean;
begin
  M := SVGMatrixMultiply(SVGMatrixTranslate(50.0, 100.0), SVGMatrixRotate(30.0));
  Ok := SVGMatrixInvert(M, Inv);
  AssertTrue('Inversion succeeded', Ok);

  Prod := SVGMatrixMultiply(M, Inv);
  AssertTrue('Product is identity', SVGMatrixIsIdentity(Prod));

  P := SVGPoint(23.4, 67.8);
  PTrans := SVGMatrixTransformPoint(M, P);
  PBack := SVGMatrixTransformPoint(Inv, PTrans);
  AssertEquals(P.X, PBack.X, 1e-6);
  AssertEquals(P.Y, PBack.Y, 1e-6);
end;

procedure TSVGTypesTest.TestTransformParser();
var
  M: TSVGMatrix;
  P: TSVGPoint;
begin
  // Chained transform: translate(10, 20) scale(2)
  M := SVGParseTransform('translate(10, 20) scale(2)');
  // Point (5, 5) scaled by 2 -> (10, 10), translated by (10, 20) -> (20, 30)
  P := SVGMatrixTransformPoint(M, SVGPoint(5.0, 5.0));
  AssertEquals(20.0, P.X, 1e-6);
  AssertEquals(30.0, P.Y, 1e-6);
end;

procedure TSVGTypesTest.TestLengthParser();
var
  L: TSVGLength;
begin
  L := SVGParseLength('100px');
  AssertEquals(100.0, L.Value, 1e-6);
  AssertTrue('Unit is PX', L.UnitType = suPX);
  AssertEquals(100.0, SVGLengthToPixels(L), 1e-6);

  L := SVGParseLength('2in');
  AssertEquals(2.0, L.Value, 1e-6);
  AssertEquals(192.0, SVGLengthToPixels(L), 1e-6); // 2 * 96

  L := SVGParseLength('50%');
  AssertEquals(50.0, L.Value, 1e-6);
  AssertEquals(100.0, SVGLengthToPixels(L, 200.0), 1e-6); // 50% of 200 = 100

  L := SVGParseLength('2.5em');
  AssertEquals(2.5, L.Value, 1e-6);
  AssertEquals(40.0, SVGLengthToPixels(L, 0.0, 16.0), 1e-6); // 2.5 * 16 = 40
end;

procedure TSVGTypesTest.TestViewBoxCalculation();
var
  VB: TSVGViewBox;
  Align: TSVGPreserveAspectRatio;
  M: TSVGMatrix;
  P: TSVGPoint;
begin
  VB := SVGParseViewBox('0 0 100 100');
  AssertTrue('ViewBox has value', VB.HasValue);
  AssertEquals(100.0, VB.Width, 1e-6);
  AssertEquals(100.0, VB.Height, 1e-6);

  Align := SVGParsePreserveAspectRatio('xMidYMid meet');
  AssertTrue('Align is xMidYMid', Align.Align = paraXMidYMid);
  AssertTrue('MeetOrSlice is meet', Align.MeetOrSlice = mosMeet);

  // Target viewport 200x100: aspect fit (meet) scales by 1.0, centers horizontally:
  // OffsetX = (200 - 100 * 1.0) / 2 = 50.0
  M := SVGCalculateViewBoxTransform(VB, Align, 200.0, 100.0);
  P := SVGMatrixTransformPoint(M, SVGPoint(0.0, 0.0));
  AssertEquals(50.0, P.X, 1e-6);
  AssertEquals(0.0, P.Y, 1e-6);
end;

procedure TSVGTypesTest.TestPaintParser();
var
  P: TSVGPaint;
begin
  P := SVGParsePaint('none');
  AssertTrue('Paint is none', P.Kind = pkNone);

  P := SVGParsePaint('currentColor');
  AssertTrue('Paint is currentColor', P.Kind = pkCurrentColor);

  P := SVGParsePaint('#ff0000');
  AssertTrue('Paint is color', P.Kind = pkColor);
  AssertEquals(255, P.Color.R);
  AssertEquals(0, P.Color.G);
  AssertEquals(0, P.Color.B);

  P := SVGParsePaint('url(#linearGrad)');
  AssertTrue('Paint is URI', P.Kind = pkUri);
  AssertEquals('linearGrad', P.UriId);
end;

// ── TSVGPathTest ─────────────────────────────────────────────────────────────

procedure TSVGPathTest.TestPathBasicCommands();
var
  P: TSVGPathData;
begin
  P := TSVGPathData.CreateFromSVG('M 10 20 L 30 40 H 50 V 60 Z');
  try
    AssertEquals(5, P.SegmentCount);
    AssertTrue('First is MoveTo', P.Segments[0].Command = spcMoveTo);
    AssertEquals(10.0, P.Segments[0].Params[0], 1e-6);
    AssertEquals(20.0, P.Segments[0].Params[1], 1e-6);
    AssertTrue('Second is LineTo', P.Segments[1].Command = spcLineTo);
    AssertTrue('Third is HorizLineTo', P.Segments[2].Command = spcHorizLineTo);
    AssertTrue('Fourth is VertLineTo', P.Segments[3].Command = spcVertLineTo);
    AssertTrue('Fifth is ClosePath', P.Segments[4].Command = spcClosePath);
  finally
    P.Free();
  end;
end;

procedure TSVGPathTest.TestPathCurves();
var
  P: TSVGPathData;
begin
  P := TSVGPathData.CreateFromSVG('M 0 0 C 10 20 30 40 50 60 S 70 80 90 100 Q 110 120 130 140 T 150 160');
  try
    AssertEquals(5, P.SegmentCount);
    AssertTrue('Cubic', P.Segments[1].Command = spcCubicTo);
    AssertTrue('Smooth cubic', P.Segments[2].Command = spcSmoothCubicTo);
    AssertTrue('Quad', P.Segments[3].Command = spcQuadTo);
    AssertTrue('Smooth quad', P.Segments[4].Command = spcSmoothQuadTo);
  finally
    P.Free();
  end;
end;

procedure TSVGPathTest.TestPathArcs();
var
  P: TSVGPathData;
begin
  P := TSVGPathData.CreateFromSVG('M 10 10 A 25 25 0 0 1 60 10');
  try
    AssertEquals(2, P.SegmentCount);
    AssertTrue('Arc command', P.Segments[1].Command = spcArcTo);
    AssertEquals(25.0, P.Segments[1].Params[0], 1e-6);
    AssertEquals(25.0, P.Segments[1].Params[1], 1e-6);
    AssertEquals(60.0, P.Segments[1].Params[5], 1e-6);
  finally
    P.Free();
  end;
end;

procedure TSVGPathTest.TestPathRelative();
var
  P: TSVGPathData;
  Norms: TSVGNormalizedSegmentArray;
begin
  P := TSVGPathData.CreateFromSVG('m 10 20 l 30 40 h 10 v 10 z');
  try
    AssertEquals(5, P.SegmentCount);
    AssertTrue('Relative move', P.Segments[0].IsRelative);
    AssertTrue('Relative line', P.Segments[1].IsRelative);

    // After normalization, all coords become absolute
    Norms := P.ToNormalized(False);
    AssertEquals(5, Length(Norms));
    AssertEquals(10.0, Norms[0].Params[0], 1e-6); // M 10 20
    AssertEquals(20.0, Norms[0].Params[1], 1e-6);
    AssertEquals(40.0, Norms[1].Params[0], 1e-6); // L (10+30) (20+40) = 40 60
    AssertEquals(60.0, Norms[1].Params[1], 1e-6);
    AssertEquals(50.0, Norms[2].Params[0], 1e-6); // L (40+10) 60 = 50 60
    AssertEquals(60.0, Norms[2].Params[1], 1e-6);
    AssertEquals(50.0, Norms[3].Params[0], 1e-6); // L 50 (60+10) = 50 70
    AssertEquals(70.0, Norms[3].Params[1], 1e-6);
  finally
    P.Free();
  end;
end;

procedure TSVGPathTest.TestPathCompactSyntax();
var
  P: TSVGPathData;
begin
  // Compact numbers without spaces between signs or decimals
  P := TSVGPathData.CreateFromSVG('M10-20L.5.5A25 25 0 0150 25');
  try
    AssertEquals(3, P.SegmentCount);
    AssertEquals(10.0, P.Segments[0].Params[0], 1e-6);
    AssertEquals(-20.0, P.Segments[0].Params[1], 1e-6);
    AssertEquals(0.5, P.Segments[1].Params[0], 1e-6);
    AssertEquals(0.5, P.Segments[1].Params[1], 1e-6);
    AssertTrue('Arc parsed', P.Segments[2].Command = spcArcTo);
  finally
    P.Free();
  end;
end;

procedure TSVGPathTest.TestPathNormalization();
var
  P: TSVGPathData;
  Norms: TSVGNormalizedSegmentArray;
begin
  // Smooth cubic reflection: M 0 0 C 10 10 20 10 30 0 S 50 -10 60 0
  // Previous P2 was (20, 10), current point is (30, 0)
  // Reflected control point P1 should be 2*(30, 0) - (20, 10) = (40, -10)
  P := TSVGPathData.CreateFromSVG('M 0 0 C 10 10 20 10 30 0 S 50 -10 60 0');
  try
    Norms := P.ToNormalized(False);
    AssertEquals(3, Length(Norms));
    AssertTrue('Normalised to Cubic', Norms[2].Command = sncCubicTo);
    AssertEquals(40.0, Norms[2].Params[0], 1e-5);
    AssertEquals(-10.0, Norms[2].Params[1], 1e-5);
  finally
    P.Free();
  end;
end;

procedure TSVGPathTest.TestArcDecomposition();
var
  P: TSVGPathData;
  Norms: TSVGNormalizedSegmentArray;
  LastIdx: Integer;
begin
  // Arc from (0, 0) to (100, 0) with radius 50: semicircle
  P := TSVGPathData.CreateFromSVG('M 0 0 A 50 50 0 0 1 100 0');
  try
    Norms := P.ToNormalized(True);
    AssertTrue('Decomposed into cubics', Length(Norms) >= 2);
    AssertTrue('First is MoveTo', Norms[0].Command = sncMoveTo);
    AssertTrue('Subsequent are Cubics', Norms[1].Command = sncCubicTo);

    LastIdx := High(Norms);
    AssertEquals(100.0, Norms[LastIdx].Params[4], 1e-6);
    AssertEquals(0.0, Norms[LastIdx].Params[5], 1e-6);
  finally
    P.Free();
  end;
end;

procedure TSVGPathTest.TestBoundingBox();
var
  P: TSVGPathData;
  Box: TSVGRect;
begin
  P := TSVGPathData.CreateFromSVG('M 10 20 L 50 20 L 50 80 L 10 80 Z');
  try
    Box := P.GetBoundingBox();
    AssertEquals(10.0, Box.X, 1e-6);
    AssertEquals(20.0, Box.Y, 1e-6);
    AssertEquals(40.0, Box.Width, 1e-6);
    AssertEquals(60.0, Box.Height, 1e-6);
  finally
    P.Free();
  end;
end;

procedure TSVGPathTest.TestShapeToPath();
var
  P: TSVGPathData;
  Box: TSVGRect;
begin
  P := TSVGPathData.CreateCirclePath(50.0, 50.0, 25.0);
  try
    Box := P.GetBoundingBox();
    AssertEquals(25.0, Box.X, 1e-2);
    AssertEquals(25.0, Box.Y, 1e-2);
    AssertEquals(50.0, Box.Width, 1e-2);
    AssertEquals(50.0, Box.Height, 1e-2);
  finally
    P.Free();
  end;

  P := TSVGPathData.CreateRectPath(10.0, 15.0, 80.0, 40.0, 5.0, 5.0);
  try
    Box := P.GetBoundingBox();
    AssertEquals(10.0, Box.X, 1e-2);
    AssertEquals(15.0, Box.Y, 1e-2);
    AssertEquals(80.0, Box.Width, 1e-2);
    AssertEquals(40.0, Box.Height, 1e-2);
  finally
    P.Free();
  end;
end;

// ── TSVGDOMTest ──────────────────────────────────────────────────────────────

procedure TSVGDOMTest.TestDOMHierarchy();
var
  Doc: TSVGDocument;
  Group: TSVGGroupElement;
  RectElem: TSVGRectElement;
begin
  Doc := TSVGDocument.Create();
  try
    Group := TSVGGroupElement.Create(Doc);
    Group.Id := 'grp1';
    Doc.RegisterElement('grp1', Group);

    RectElem := TSVGRectElement.Create(Doc);
    RectElem.Id := 'r1';
    RectElem.X := SVGLength(10.0);
    RectElem.Y := SVGLength(20.0);
    RectElem.Width := SVGLength(30.0);
    RectElem.Height := SVGLength(40.0);
    Doc.RegisterElement('r1', RectElem);

    Group.AddChild(RectElem);
    Doc.Root.AddChild(Group);

    AssertEquals(1, Doc.Root.ChildCount());
    AssertEquals(1, Group.ChildCount());
    AssertSame('Parent link', Group, RectElem.Parent);
    AssertSame('Root link', Doc.Root, Group.Parent);
  finally
    Doc.Free();
  end;
end;

procedure TSVGDOMTest.TestStyleInheritance();
var
  Doc: TSVGDocument;
  Group: TSVGGroupElement;
  RectElem: TSVGRectElement;
begin
  Doc := TSVGDocument.Create();
  try
    Group := TSVGGroupElement.Create(Doc);
    Group.Style.ApplyPresentationAttribute('fill', '#ff0000');
    Group.Style.ApplyPresentationAttribute('stroke-width', '4');

    RectElem := TSVGRectElement.Create(Doc);
    Group.AddChild(RectElem);
    Doc.Root.AddChild(Group);

    Doc.ComputeStyles(100.0, 100.0);

    AssertEquals(255, RectElem.ComputedStyle.Fill.Color.R);
    AssertEquals(0, RectElem.ComputedStyle.Fill.Color.G);
    AssertEquals(4.0, RectElem.ComputedStyle.StrokeWidth, 1e-6);
  finally
    Doc.Free();
  end;
end;

procedure TSVGDOMTest.TestStyleOverride();
var
  Doc: TSVGDocument;
  Group: TSVGGroupElement;
  RectElem: TSVGRectElement;
begin
  Doc := TSVGDocument.Create();
  try
    Group := TSVGGroupElement.Create(Doc);
    Group.Style.ApplyPresentationAttribute('fill', '#ff0000');

    RectElem := TSVGRectElement.Create(Doc);
    RectElem.Style.ApplyPresentationAttribute('fill', '#0000ff');
    Group.AddChild(RectElem);
    Doc.Root.AddChild(Group);

    Doc.ComputeStyles(100.0, 100.0);

    AssertEquals(0, RectElem.ComputedStyle.Fill.Color.R);
    AssertEquals(255, RectElem.ComputedStyle.Fill.Color.B);
  finally
    Doc.Free();
  end;
end;

procedure TSVGDOMTest.TestOpacityComposition();
var
  Doc: TSVGDocument;
  Group: TSVGGroupElement;
  RectElem: TSVGRectElement;
begin
  Doc := TSVGDocument.Create();
  try
    Group := TSVGGroupElement.Create(Doc);
    Group.Style.ApplyPresentationAttribute('opacity', '0.5');

    RectElem := TSVGRectElement.Create(Doc);
    RectElem.Style.ApplyPresentationAttribute('opacity', '0.5');
    Group.AddChild(RectElem);
    Doc.Root.AddChild(Group);

    Doc.ComputeStyles(100.0, 100.0);

    AssertEquals(0.25, RectElem.ComputedStyle.Opacity, 1e-6);
  finally
    Doc.Free();
  end;
end;

procedure TSVGDOMTest.TestFindById();
var
  Doc: TSVGDocument;
  Group: TSVGGroupElement;
  CircleElem: TSVGCircleElement;
begin
  Doc := TSVGDocument.Create();
  try
    Group := TSVGGroupElement.Create(Doc);
    Group.Id := 'myGroup';
    Doc.RegisterElement('myGroup', Group);

    CircleElem := TSVGCircleElement.Create(Doc);
    CircleElem.Id := 'myCircle';
    Doc.RegisterElement('myCircle', CircleElem);

    Group.AddChild(CircleElem);
    Doc.Root.AddChild(Group);

    AssertSame('Found circle', CircleElem, Doc.FindElementById('myCircle'));
    AssertSame('Found group', Group, Doc.FindElementById('myGroup'));
    AssertNull('Not found', Doc.FindElementById('unknown'));
  finally
    Doc.Free();
  end;
end;

procedure TSVGDOMTest.TestUseElement();
var
  Doc: TSVGDocument;
  CircleElem: TSVGCircleElement;
  UseElem: TSVGUseElement;
begin
  Doc := TSVGDocument.Create();
  try
    CircleElem := TSVGCircleElement.Create(Doc);
    CircleElem.Id := 'symbol1';
    CircleElem.Cx := SVGLength(10.0);
    CircleElem.Cy := SVGLength(10.0);
    CircleElem.R := SVGLength(5.0);
    Doc.RegisterElement('symbol1', CircleElem);
    Doc.Root.AddChild(CircleElem);

    UseElem := TSVGUseElement.Create(Doc);
    UseElem.Href := '#symbol1';
    UseElem.X := SVGLength(50.0);
    UseElem.Y := SVGLength(50.0);
    Doc.Root.AddChild(UseElem);

    Doc.ResolveReferences();
    AssertSame('Referenced element linked', CircleElem, UseElem.ReferencedElement);
  finally
    Doc.Free();
  end;
end;

// ── TSVGParserTest ───────────────────────────────────────────────────────────

procedure TSVGParserTest.TestParseSimpleSVG();
var
  SvgXml: string;
  Doc: TSVGDocument;
  RectElem: TSVGRectElement;
begin
  SvgXml := '<svg width="200" height="150" viewBox="0 0 100 100">' +
            '  <rect x="10" y="20" width="80" height="60" fill="#00ff00"/>' +
            '</svg>';

  Doc := TSVGParser.ParseString(SvgXml);
  try
    AssertNotNull('Doc exists', Doc);
    AssertNotNull('Root exists', Doc.Root);
    AssertEquals(200.0, SVGLengthToPixels(Doc.Root.Width), 1e-6);
    AssertEquals(150.0, SVGLengthToPixels(Doc.Root.Height), 1e-6);
    AssertTrue('ViewBox set', Doc.Root.ViewBox.HasValue);
    AssertEquals(1, Doc.Root.ChildCount());

    AssertTrue('Child is Rect', Doc.Root.GetChild(0) is TSVGRectElement);
    RectElem := TSVGRectElement(Doc.Root.GetChild(0));
    AssertEquals(10.0, SVGLengthToPixels(RectElem.X), 1e-6);
    AssertEquals(20.0, SVGLengthToPixels(RectElem.Y), 1e-6);
    AssertEquals(80.0, SVGLengthToPixels(RectElem.Width), 1e-6);
    AssertEquals(60.0, SVGLengthToPixels(RectElem.Height), 1e-6);
    AssertEquals(255, RectElem.ComputedStyle.Fill.Color.G);
  finally
    Doc.Free();
  end;
end;

procedure TSVGParserTest.TestParseShapesAndGroups();
var
  SvgXml: string;
  Doc: TSVGDocument;
  Group: TSVGGroupElement;
  PathNode: TSVGPathElement;
  CircleNode: TSVGCircleElement;
begin
  SvgXml := '<svg width="300" height="300">' +
            '  <g id="main-group" transform="translate(10, 20)">' +
            '    <path id="arrow" d="M 0 0 L 10 10 L 0 20 Z" fill="red"/>' +
            '    <circle id="dot" cx="50" cy="50" r="10" stroke="blue" stroke-width="2"/>' +
            '  </g>' +
            '</svg>';

  Doc := TSVGParser.ParseString(SvgXml);
  try
    AssertNotNull('Doc exists', Doc);
    Group := TSVGGroupElement(Doc.FindElementById('main-group'));
    AssertNotNull('Group found', Group);
    AssertEquals(2, Group.ChildCount());

    PathNode := TSVGPathElement(Doc.FindElementById('arrow'));
    AssertNotNull('Path found', PathNode);
    AssertEquals(4, PathNode.PathData.SegmentCount);
    AssertEquals(255, PathNode.ComputedStyle.Fill.Color.R);

    CircleNode := TSVGCircleElement(Doc.FindElementById('dot'));
    AssertNotNull('Circle found', CircleNode);
    AssertEquals(255, CircleNode.ComputedStyle.Stroke.Color.B);
    AssertEquals(2.0, CircleNode.ComputedStyle.StrokeWidth, 1e-6);
  finally
    Doc.Free();
  end;
end;

procedure TSVGParserTest.TestParseGradients();
var
  SvgXml: string;
  Doc: TSVGDocument;
  Grad, Grad2: TSVGLinearGradientElement;
  EffStops: TObjectList;
begin
  SvgXml := '<svg width="200" height="200">' +
            '  <defs>' +
            '    <linearGradient id="baseGrad" gradientUnits="userSpaceOnUse" spreadMethod="reflect">' +
            '      <stop offset="0%" style="stop-color:rgb(255,0,0);stop-opacity:1"/>' +
            '      <stop offset="100%" style="stop-color:#0000ff;stop-opacity:0.5"/>' +
            '    </linearGradient>' +
            '    <linearGradient id="g1" x1="0%" y1="0%" x2="100%" y2="100%" xlink:href="#baseGrad"/>' +
            '  </defs>' +
            '  <rect x="0" y="0" width="200" height="200" fill="url(#g1)"/>' +
            '</svg>';

  Doc := TSVGParser.ParseString(SvgXml);
  try
    AssertNotNull('Doc exists', Doc);
    Grad := TSVGLinearGradientElement(Doc.FindElementById('baseGrad'));
    AssertNotNull('Base gradient found', Grad);
    AssertEquals(Ord(sguUserSpaceOnUse), Ord(Grad.GradientUnits));
    AssertEquals(Ord(sgsReflect), Ord(Grad.SpreadMethod));
    AssertEquals(2, Grad.StopCount());
    AssertEquals(0.0, Grad.GetStop(0).Offset, 1e-6);
    AssertEquals(255, Grad.GetStop(0).Color.R);
    AssertEquals(1.0, Grad.GetStop(1).Offset, 1e-6);
    AssertEquals(255, Grad.GetStop(1).Color.B);
    AssertEquals(128, Grad.GetStop(1).Color.A, 2); // 0.5 * 255 = 127.5

    Grad2 := TSVGLinearGradientElement(Doc.FindElementById('g1'));
    AssertNotNull('Referencing gradient found', Grad2);
    AssertEquals(0, Grad2.StopCount());
    EffStops := Grad2.GetEffectiveStops();
    AssertNotNull('Effective stops found', EffStops);
    AssertEquals(2, EffStops.Count);
    AssertEquals(255, TSVGStopElement(EffStops[0]).Color.R);
    AssertEquals(255, TSVGStopElement(EffStops[1]).Color.B);
  finally
    Doc.Free();
  end;
end;

procedure TSVGParserTest.TestCSSCascadeIntegration();
var
  SvgXml: string;
  Doc: TSVGDocument;
  CircleElem: TSVGCircleElement;
  RectElem: TSVGRectElement;
begin
  SvgXml := '<svg width="200" height="200">' +
            '  <style type="text/css">' +
            '    .highlight { fill: #00ff00; stroke: #008800; stroke-width: 3px; }' +
            '    rect.box { fill: #ffff00; }' +
            '  </style>' +
            '  <circle id="c1" class="highlight" cx="50" cy="50" r="20"/>' +
            '  <rect id="r1" class="box" x="10" y="10" width="50" height="50" style="fill: #ff00ff;"/>' +
            '</svg>';

  Doc := TSVGParser.ParseString(SvgXml);
  try
    AssertNotNull('Doc exists', Doc);

    CircleElem := TSVGCircleElement(Doc.FindElementById('c1'));
    AssertNotNull('Circle found', CircleElem);
    // .highlight rule resolved
    AssertEquals(255, CircleElem.ComputedStyle.Fill.Color.G);
    AssertEquals(136, CircleElem.ComputedStyle.Stroke.Color.G);
    AssertEquals(3.0, CircleElem.ComputedStyle.StrokeWidth, 1e-6);

    RectElem := TSVGRectElement(Doc.FindElementById('r1'));
    AssertNotNull('Rect found', RectElem);
    // Inline style="fill: #ff00ff" overrides rect.box rule!
    AssertEquals(255, RectElem.ComputedStyle.Fill.Color.R);
    AssertEquals(0, RectElem.ComputedStyle.Fill.Color.G);
    AssertEquals(255, RectElem.ComputedStyle.Fill.Color.B);
  finally
    Doc.Free();
  end;
end;

procedure TSVGParserTest.TestRealWorldSVGIcon();
var
  SvgXml: string;
  Doc: TSVGDocument;
  CheckPath: TSVGPathElement;
begin
  // Real checkmark vector icon (e.g. from Feather icons / Lucide)
  SvgXml := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" ' +
            'fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' +
            '  <polyline id="check" points="20 6 9 17 4 12"/>' +
            '</svg>';

  Doc := TSVGParser.ParseString(SvgXml);
  try
    AssertNotNull('Doc parsed', Doc);
    AssertEquals(24.0, SVGLengthToPixels(Doc.Root.Width), 1e-6);
    AssertEquals(24.0, SVGLengthToPixels(Doc.Root.Height), 1e-6);
    AssertTrue('ViewBox set', Doc.Root.ViewBox.HasValue);
    AssertTrue('Root fill none', Doc.Root.ComputedStyle.Fill.Kind = pkNone);
    AssertTrue('Root stroke currentColor', Doc.Root.ComputedStyle.Stroke.Kind = pkCurrentColor);

    CheckPath := TSVGPathElement(Doc.FindElementById('check'));
    AssertNotNull('Polyline found', CheckPath);
    AssertTrue('LineCap round inherited', CheckPath.ComputedStyle.StrokeLineCap = slcRound);
    AssertTrue('LineJoin round inherited', CheckPath.ComputedStyle.StrokeLineJoin = sljRound);
    AssertEquals(2.0, CheckPath.ComputedStyle.StrokeWidth, 1e-6);
  finally
    Doc.Free();
  end;
end;

initialization
  RegisterTest(TSVGTypesTest);
  RegisterTest(TSVGPathTest);
  RegisterTest(TSVGDOMTest);
  RegisterTest(TSVGParserTest);

end.
