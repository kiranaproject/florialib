unit Floria.CSS.Values.Test;

// Floria.CSS.Values.Test
// ======================
// Comprehensive unit tests for Floria.CSS.Values:
//   - TCSSColor (hex 3/4/6/8-digit, named colors, rgb/rgba function)
//   - TCSSLength & TCSSUnit (px, em, rem, %, pt, auto, inherit, unset)
//   - TCSSBox (1, 2, 3, 4 value shorthands)
//   - Border side composite parsing
//   - Layout & styling enums and converters
//   - AST node parser helpers

{$mode objfpc}{$H+}

interface

uses
  Classes, Contnrs, SysUtils, fpcunit, testregistry,
  Floria.CSS.Types, Floria.CSS.AST, Floria.CSS.Parser, Floria.CSS.Values;

type
  TCSSValuesColorTest = class(TTestCase)
  published
    procedure TestHex3Digits();
    procedure TestHex6Digits();
    procedure TestHex4DigitsWithAlpha();
    procedure TestHex8DigitsWithAlpha();
    procedure TestHexCaseInsensitive();
    procedure TestInvalidHex();
    procedure TestNamedColorsBasic();
    procedure TestNamedColorsExtended();
    procedure TestNamedColorsCaseInsensitive();
    procedure TestRgbFunctionCommaSeparated();
    procedure TestRgbFunctionPercentages();
    procedure TestRgbaFunction();
    procedure TestRgbModernSlashSyntax();
    procedure TestToHexAndRGBAString();
  end;

  TCSSValuesLengthTest = class(TTestCase)
  published
    procedure TestPixels();
    procedure TestEmAndRem();
    procedure TestPercentage();
    procedure TestPoints();
    procedure TestAuto();
    procedure TestInheritAndUnset();
    procedure TestUnitlessZero();
    procedure TestUnitlessNumber();
    procedure TestToPixels();
    procedure TestLengthToString();
  end;

  TCSSValuesBoxTest = class(TTestCase)
  published
    procedure TestBoxOneValue();
    procedure TestBoxTwoValues();
    procedure TestBoxThreeValues();
    procedure TestBoxFourValues();
    procedure TestBoxWithAuto();
  end;

  TCSSValuesBorderSideTest = class(TTestCase)
  published
    procedure TestBorderSideWidthStyleColor();
    procedure TestBorderSideStyleColorWidth();
    procedure TestBorderSideKeywords();
    procedure TestBorderSidePartial();
  end;

  TCSSValuesEnumTest = class(TTestCase)
  published
    procedure TestDisplayEnum();
    procedure TestPositionEnum();
    procedure TestVisibilityEnum();
    procedure TestOverflowEnum();
    procedure TestBorderStyleEnum();
    procedure TestBoxSizingEnum();
    procedure TestFlexEnums();
    procedure TestTypographyEnums();
  end;

implementation

// ── TCSSValuesColorTest ─────────────────────────────────────────────────────

procedure TCSSValuesColorTest.TestHex3Digits();
var
  C: TCSSColor;
begin
  AssertTrue('Parse #f00', TCSSColor.FromHex('#f00', C));
  AssertEquals(255, C.R);
  AssertEquals(0, C.G);
  AssertEquals(0, C.B);
  AssertEquals(255, C.A);

  AssertTrue('Parse #fff', TCSSColor.FromHex('#fff', C));
  AssertEquals(255, C.R);
  AssertEquals(255, C.G);
  AssertEquals(255, C.B);
  AssertEquals(255, C.A);

  AssertTrue('Parse #000', TCSSColor.FromHex('#000', C));
  AssertEquals(0, C.R);
  AssertEquals(0, C.G);
  AssertEquals(0, C.B);
  AssertEquals(255, C.A);
end;

procedure TCSSValuesColorTest.TestHex6Digits();
var
  C: TCSSColor;
begin
  AssertTrue('Parse #123456', TCSSColor.FromHex('#123456', C));
  AssertEquals($12, C.R);
  AssertEquals($34, C.G);
  AssertEquals($56, C.B);
  AssertEquals(255, C.A);
end;

procedure TCSSValuesColorTest.TestHex4DigitsWithAlpha();
var
  C: TCSSColor;
begin
  AssertTrue('Parse #f008', TCSSColor.FromHex('#f008', C));
  AssertEquals(255, C.R);
  AssertEquals(0, C.G);
  AssertEquals(0, C.B);
  AssertEquals($88, C.A);
end;

procedure TCSSValuesColorTest.TestHex8DigitsWithAlpha();
var
  C: TCSSColor;
begin
  AssertTrue('Parse #11223344', TCSSColor.FromHex('#11223344', C));
  AssertEquals($11, C.R);
  AssertEquals($22, C.G);
  AssertEquals($33, C.B);
  AssertEquals($44, C.A);
end;

procedure TCSSValuesColorTest.TestHexCaseInsensitive();
var
  C: TCSSColor;
begin
  AssertTrue('Parse #AABBCC', TCSSColor.FromHex('#AABBCC', C));
  AssertEquals($AA, C.R);
  AssertEquals($BB, C.G);
  AssertEquals($CC, C.B);
  AssertEquals(255, C.A);
end;

procedure TCSSValuesColorTest.TestInvalidHex();
var
  C: TCSSColor;
begin
  AssertFalse('Fail 2 digits', TCSSColor.FromHex('#12', C));
  AssertFalse('Fail 5 digits', TCSSColor.FromHex('#12345', C));
  AssertFalse('Fail non-hex chars', TCSSColor.FromHex('#ggg', C));
  AssertFalse('Fail empty', TCSSColor.FromHex('', C));
end;

procedure TCSSValuesColorTest.TestNamedColorsBasic();
var
  C: TCSSColor;
begin
  AssertTrue('Parse black', TCSSColor.FromName('black', C));
  AssertTrue('Black matches', C.Equals(TCSSColor.Black()));

  AssertTrue('Parse white', TCSSColor.FromName('white', C));
  AssertTrue('White matches', C.Equals(TCSSColor.White()));

  AssertTrue('Parse transparent', TCSSColor.FromName('transparent', C));
  AssertTrue('Transparent matches', C.Equals(TCSSColor.Transparent()));

  AssertTrue('Parse red', TCSSColor.FromName('red', C));
  AssertEquals(255, C.R);
  AssertEquals(0, C.G);
  AssertEquals(0, C.B);
end;

procedure TCSSValuesColorTest.TestNamedColorsExtended();
var
  C: TCSSColor;
begin
  AssertTrue('Parse blue', TCSSColor.FromName('blue', C));
  AssertEquals(255, C.B);

  AssertTrue('Parse green', TCSSColor.FromName('green', C));
  AssertEquals(128, C.G);

  AssertTrue('Parse orange', TCSSColor.FromName('orange', C));
  AssertEquals(255, C.R);
  AssertEquals(165, C.G);
  AssertEquals(0, C.B);

  AssertFalse('Fail non-existent color', TCSSColor.FromName('notacolor', C));
end;

procedure TCSSValuesColorTest.TestNamedColorsCaseInsensitive();
var
  C: TCSSColor;
begin
  AssertTrue('Parse Red in mixed case', TCSSColor.FromName('ReD', C));
  AssertEquals(255, C.R);
  AssertEquals(0, C.G);
  AssertEquals(0, C.B);
end;

procedure TCSSValuesColorTest.TestRgbFunctionCommaSeparated();
var
  C: TCSSColor;
begin
  AssertTrue('Parse rgb(10, 20, 30)', TCSSColor.TryParse('rgb(10, 20, 30)', C));
  AssertEquals(10, C.R);
  AssertEquals(20, C.G);
  AssertEquals(30, C.B);
  AssertEquals(255, C.A);
end;

procedure TCSSValuesColorTest.TestRgbFunctionPercentages();
var
  C: TCSSColor;
begin
  AssertTrue('Parse rgb(100%, 0%, 50%)', TCSSColor.TryParse('rgb(100%, 0%, 50%)', C));
  AssertEquals(255, C.R);
  AssertEquals(0, C.G);
  AssertEquals(128, C.B);
  AssertEquals(255, C.A);
end;

procedure TCSSValuesColorTest.TestRgbaFunction();
var
  C: TCSSColor;
begin
  AssertTrue('Parse rgba(255, 128, 0, 0.5)', TCSSColor.TryParse('rgba(255, 128, 0, 0.5)', C));
  AssertEquals(255, C.R);
  AssertEquals(128, C.G);
  AssertEquals(0, C.B);
  AssertEquals(128, C.A);
end;

procedure TCSSValuesColorTest.TestRgbModernSlashSyntax();
var
  C: TCSSColor;
begin
  AssertTrue('Parse rgb(255 128 64 / 0.5)', TCSSColor.TryParse('rgb(255 128 64 / 0.5)', C));
  AssertEquals(255, C.R);
  AssertEquals(128, C.G);
  AssertEquals(64, C.B);
  AssertEquals(128, C.A);
end;

procedure TCSSValuesColorTest.TestToHexAndRGBAString();
var
  C: TCSSColor;
begin
  C := TCSSColor.FromRGBA(255, 0, 128, 255);
  AssertEquals('#ff0080', C.ToHex());
  AssertEquals('rgb(255, 0, 128)', C.ToRGBAString());

  C := TCSSColor.FromRGBA(255, 0, 128, 128);
  AssertEquals('#ff008080', C.ToHex(True));
end;

// ── TCSSValuesLengthTest ────────────────────────────────────────────────────

procedure TCSSValuesLengthTest.TestPixels();
var
  L: TCSSLength;
begin
  AssertTrue('Parse 100px', TCSSLength.TryParse('100px', L));
  AssertEquals(100.0, L.Value);
  AssertTrue('Is cuPx', L.Unit_ = cuPx);
  AssertFalse('Not auto', L.IsAuto());
  AssertFalse('Not zero', L.IsZero());
end;

procedure TCSSValuesLengthTest.TestEmAndRem();
var
  L: TCSSLength;
begin
  AssertTrue('Parse 1.5em', TCSSLength.TryParse('1.5em', L));
  AssertEquals(1.5, L.Value);
  AssertTrue('Is cuEm', L.Unit_ = cuEm);

  AssertTrue('Parse 2rem', TCSSLength.TryParse('2rem', L));
  AssertEquals(2.0, L.Value);
  AssertTrue('Is cuRem', L.Unit_ = cuRem);
end;

procedure TCSSValuesLengthTest.TestPercentage();
var
  L: TCSSLength;
begin
  AssertTrue('Parse 50%', TCSSLength.TryParse('50%', L));
  AssertEquals(50.0, L.Value);
  AssertTrue('Is cuPercent', L.Unit_ = cuPercent);
end;

procedure TCSSValuesLengthTest.TestPoints();
var
  L: TCSSLength;
begin
  AssertTrue('Parse 12pt', TCSSLength.TryParse('12pt', L));
  AssertEquals(12.0, L.Value);
  AssertTrue('Is cuPt', L.Unit_ = cuPt);
end;

procedure TCSSValuesLengthTest.TestAuto();
var
  L: TCSSLength;
begin
  AssertTrue('Parse auto', TCSSLength.TryParse('auto', L));
  AssertTrue('Is auto', L.IsAuto());
  AssertTrue('Unit is cuAuto', L.Unit_ = cuAuto);
end;

procedure TCSSValuesLengthTest.TestInheritAndUnset();
var
  L: TCSSLength;
begin
  AssertTrue('Parse inherit', TCSSLength.TryParse('inherit', L));
  AssertTrue('Unit is cuInherit', L.Unit_ = cuInherit);

  AssertTrue('Parse unset', TCSSLength.TryParse('unset', L));
  AssertTrue('Unit is cuUnset', L.Unit_ = cuUnset);
end;

procedure TCSSValuesLengthTest.TestUnitlessZero();
var
  L: TCSSLength;
begin
  AssertTrue('Parse 0', TCSSLength.TryParse('0', L));
  AssertEquals(0.0, L.Value);
  AssertTrue('Is zero', L.IsZero());
end;

procedure TCSSValuesLengthTest.TestUnitlessNumber();
var
  L: TCSSLength;
begin
  AssertTrue('Parse 1.5', TCSSLength.TryParse('1.5', L));
  AssertEquals(1.5, L.Value);
  AssertTrue('Unit is cuNone', L.Unit_ = cuNone);
end;

procedure TCSSValuesLengthTest.TestToPixels();
var
  L: TCSSLength;
begin
  L := TCSSLength.Px(32.0);
  AssertEquals(32.0, L.ToPixels(16.0));

  L := TCSSLength.Em(1.5);
  AssertEquals(24.0, L.ToPixels(16.0));

  L := TCSSLength.Percent(50.0);
  AssertEquals(200.0, L.ToPixels(16.0, 400.0));
end;

procedure TCSSValuesLengthTest.TestLengthToString();
var
  L: TCSSLength;
begin
  L := TCSSLength.Px(16.0);
  AssertEquals('16px', L.ToString());

  L := TCSSLength.Auto();
  AssertEquals('auto', L.ToString());

  L := TCSSLength.Percent(75.0);
  AssertEquals('75%', L.ToString());
end;

// ── TCSSValuesBoxTest ───────────────────────────────────────────────────────

procedure TCSSValuesBoxTest.TestBoxOneValue();
var
  Decls: TObjectList;
  Decl : TCSSDeclaration;
  Box  : TCSSBox;
begin
  Decls := TCSSParser.Create(TokenizeCSS('margin: 10px;')).ParseDeclarationList();
  try
    Decl := TCSSDeclaration(Decls[0]);
    AssertTrue('Parse box 1 value', ParseBoxFromNodes(Decl.Value, Box));
    AssertEquals(10.0, Box.Top.Value);
    AssertEquals(10.0, Box.Right.Value);
    AssertEquals(10.0, Box.Bottom.Value);
    AssertEquals(10.0, Box.Left.Value);
  finally
    Decls.Free();
  end;
end;

procedure TCSSValuesBoxTest.TestBoxTwoValues();
var
  Decls: TObjectList;
  Decl : TCSSDeclaration;
  Box  : TCSSBox;
begin
  Decls := TCSSParser.Create(TokenizeCSS('margin: 10px 20px;')).ParseDeclarationList();
  try
    Decl := TCSSDeclaration(Decls[0]);
    AssertTrue('Parse box 2 values', ParseBoxFromNodes(Decl.Value, Box));
    AssertEquals(10.0, Box.Top.Value);
    AssertEquals(20.0, Box.Right.Value);
    AssertEquals(10.0, Box.Bottom.Value);
    AssertEquals(20.0, Box.Left.Value);
  finally
    Decls.Free();
  end;
end;

procedure TCSSValuesBoxTest.TestBoxThreeValues();
var
  Decls: TObjectList;
  Decl : TCSSDeclaration;
  Box  : TCSSBox;
begin
  Decls := TCSSParser.Create(TokenizeCSS('margin: 10px 20px 30px;')).ParseDeclarationList();
  try
    Decl := TCSSDeclaration(Decls[0]);
    AssertTrue('Parse box 3 values', ParseBoxFromNodes(Decl.Value, Box));
    AssertEquals(10.0, Box.Top.Value);
    AssertEquals(20.0, Box.Right.Value);
    AssertEquals(30.0, Box.Bottom.Value);
    AssertEquals(20.0, Box.Left.Value);
  finally
    Decls.Free();
  end;
end;

procedure TCSSValuesBoxTest.TestBoxFourValues();
var
  Decls: TObjectList;
  Decl : TCSSDeclaration;
  Box  : TCSSBox;
begin
  Decls := TCSSParser.Create(TokenizeCSS('margin: 10px 20px 30px 40px;')).ParseDeclarationList();
  try
    Decl := TCSSDeclaration(Decls[0]);
    AssertTrue('Parse box 4 values', ParseBoxFromNodes(Decl.Value, Box));
    AssertEquals(10.0, Box.Top.Value);
    AssertEquals(20.0, Box.Right.Value);
    AssertEquals(30.0, Box.Bottom.Value);
    AssertEquals(40.0, Box.Left.Value);
  finally
    Decls.Free();
  end;
end;

procedure TCSSValuesBoxTest.TestBoxWithAuto();
var
  Decls: TObjectList;
  Decl : TCSSDeclaration;
  Box  : TCSSBox;
begin
  Decls := TCSSParser.Create(TokenizeCSS('margin: 0 auto;')).ParseDeclarationList();
  try
    Decl := TCSSDeclaration(Decls[0]);
    AssertTrue('Parse box with auto', ParseBoxFromNodes(Decl.Value, Box));
    AssertEquals(0.0, Box.Top.Value);
    AssertTrue('Right is auto', Box.Right.IsAuto());
    AssertEquals(0.0, Box.Bottom.Value);
    AssertTrue('Left is auto', Box.Left.IsAuto());
  finally
    Decls.Free();
  end;
end;

// ── TCSSValuesBorderSideTest ────────────────────────────────────────────────

procedure TCSSValuesBorderSideTest.TestBorderSideWidthStyleColor();
var
  Decls: TObjectList;
  Decl : TCSSDeclaration;
  Side : TCSSBorderSide;
begin
  Decls := TCSSParser.Create(TokenizeCSS('border: 2px solid red;')).ParseDeclarationList();
  try
    Decl := TCSSDeclaration(Decls[0]);
    AssertTrue('Parse border', ParseBorderSideFromNodes(Decl.Value, Side));
    AssertEquals(2.0, Side.Width.Value);
    AssertTrue('Style is solid', Side.Style = cbsSolid);
    AssertEquals(255, Side.Color.R);
    AssertEquals(0, Side.Color.G);
    AssertEquals(0, Side.Color.B);
  finally
    Decls.Free();
  end;
end;

procedure TCSSValuesBorderSideTest.TestBorderSideStyleColorWidth();
var
  Decls: TObjectList;
  Decl : TCSSDeclaration;
  Side : TCSSBorderSide;
begin
  Decls := TCSSParser.Create(TokenizeCSS('border: dashed #0000ff 5px;')).ParseDeclarationList();
  try
    Decl := TCSSDeclaration(Decls[0]);
    AssertTrue('Parse border style-color-width', ParseBorderSideFromNodes(Decl.Value, Side));
    AssertEquals(5.0, Side.Width.Value);
    AssertTrue('Style is dashed', Side.Style = cbsDashed);
    AssertEquals(255, Side.Color.B);
  finally
    Decls.Free();
  end;
end;

procedure TCSSValuesBorderSideTest.TestBorderSideKeywords();
var
  Decls: TObjectList;
  Decl : TCSSDeclaration;
  Side : TCSSBorderSide;
begin
  Decls := TCSSParser.Create(TokenizeCSS('border: thin dotted black;')).ParseDeclarationList();
  try
    Decl := TCSSDeclaration(Decls[0]);
    AssertTrue('Parse border thin dotted', ParseBorderSideFromNodes(Decl.Value, Side));
    AssertEquals(1.0, Side.Width.Value);
    AssertTrue('Style is dotted', Side.Style = cbsDotted);
    AssertEquals(0, Side.Color.R);
  finally
    Decls.Free();
  end;
end;

procedure TCSSValuesBorderSideTest.TestBorderSidePartial();
var
  Decls: TObjectList;
  Decl : TCSSDeclaration;
  Side : TCSSBorderSide;
begin
  Decls := TCSSParser.Create(TokenizeCSS('border: none;')).ParseDeclarationList();
  try
    Decl := TCSSDeclaration(Decls[0]);
    AssertTrue('Parse border none', ParseBorderSideFromNodes(Decl.Value, Side));
    AssertTrue('Style is none', Side.Style = cbsNone);
  finally
    Decls.Free();
  end;
end;

// ── TCSSValuesEnumTest ──────────────────────────────────────────────────────

procedure TCSSValuesEnumTest.TestDisplayEnum();
var
  V: TCSSDisplay;
begin
  AssertTrue('Parse inline', TryParseDisplay('inline', V) and (V = cdInline));
  AssertTrue('Parse block', TryParseDisplay('block', V) and (V = cdBlock));
  AssertTrue('Parse flex', TryParseDisplay('flex', V) and (V = cdFlex));
  AssertTrue('Parse grid', TryParseDisplay('grid', V) and (V = cdGrid));
  AssertTrue('Parse none', TryParseDisplay('none', V) and (V = cdNone));
  AssertEquals('flex', DisplayToString(cdFlex));
end;

procedure TCSSValuesEnumTest.TestPositionEnum();
var
  V: TCSSPosition;
begin
  AssertTrue('Parse absolute', TryParsePosition('absolute', V) and (V = cpAbsolute));
  AssertTrue('Parse relative', TryParsePosition('relative', V) and (V = cpRelative));
  AssertTrue('Parse fixed', TryParsePosition('fixed', V) and (V = cpFixed));
  AssertTrue('Parse sticky', TryParsePosition('sticky', V) and (V = cpSticky));
  AssertEquals('absolute', PositionToString(cpAbsolute));
end;

procedure TCSSValuesEnumTest.TestVisibilityEnum();
var
  V: TCSSVisibility;
begin
  AssertTrue('Parse visible', TryParseVisibility('visible', V) and (V = cvVisible));
  AssertTrue('Parse hidden', TryParseVisibility('hidden', V) and (V = cvHidden));
  AssertEquals('hidden', VisibilityToString(cvHidden));
end;

procedure TCSSValuesEnumTest.TestOverflowEnum();
var
  V: TCSSOverflow;
begin
  AssertTrue('Parse hidden', TryParseOverflow('hidden', V) and (V = coHidden));
  AssertTrue('Parse scroll', TryParseOverflow('scroll', V) and (V = coScroll));
  AssertTrue('Parse auto', TryParseOverflow('auto', V) and (V = coAuto));
  AssertEquals('auto', OverflowToString(coAuto));
end;

procedure TCSSValuesEnumTest.TestBorderStyleEnum();
var
  V: TCSSBorderStyle;
begin
  AssertTrue('Parse solid', TryParseBorderStyle('solid', V) and (V = cbsSolid));
  AssertTrue('Parse dashed', TryParseBorderStyle('dashed', V) and (V = cbsDashed));
  AssertTrue('Parse double', TryParseBorderStyle('double', V) and (V = cbsDouble));
  AssertEquals('solid', BorderStyleToString(cbsSolid));
end;

procedure TCSSValuesEnumTest.TestBoxSizingEnum();
var
  V: TCSSBoxSizing;
begin
  AssertTrue('Parse border-box', TryParseBoxSizing('border-box', V) and (V = cbsBorderBox));
  AssertTrue('Parse content-box', TryParseBoxSizing('content-box', V) and (V = cbsContentBox));
  AssertEquals('border-box', BoxSizingToString(cbsBorderBox));
end;

procedure TCSSValuesEnumTest.TestFlexEnums();
var
  FD: TCSSFlexDirection;
  FW: TCSSFlexWrap;
  JC: TCSSJustifyContent;
  AI: TCSSAlignItems;
begin
  AssertTrue('Parse row', TryParseFlexDirection('row', FD) and (FD = cfdRow));
  AssertTrue('Parse column', TryParseFlexDirection('column', FD) and (FD = cfdColumn));
  AssertTrue('Parse wrap', TryParseFlexWrap('wrap', FW) and (FW = cfwWrap));
  AssertTrue('Parse space-between', TryParseJustifyContent('space-between', JC) and (JC = cjcSpaceBetween));
  AssertTrue('Parse center', TryParseAlignItems('center', AI) and (AI = caiCenter));
end;

procedure TCSSValuesEnumTest.TestTypographyEnums();
var
  FS: TCSSFontStyle;
  TA: TCSSTextAlign;
  TD: TCSSTextDecoration;
begin
  AssertTrue('Parse italic', TryParseFontStyle('italic', FS) and (FS = cfsItalic));
  AssertTrue('Parse center', TryParseTextAlign('center', TA) and (TA = ctaCenter));
  AssertTrue('Parse underline', TryParseTextDecoration('underline', TD) and (TD = ctdUnderline));
end;

initialization
  RegisterTest(TCSSValuesColorTest);
  RegisterTest(TCSSValuesLengthTest);
  RegisterTest(TCSSValuesBoxTest);
  RegisterTest(TCSSValuesBorderSideTest);
  RegisterTest(TCSSValuesEnumTest);

end.
