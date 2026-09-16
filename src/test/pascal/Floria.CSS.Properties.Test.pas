unit Floria.CSS.Properties.Test;

// Floria.CSS.Properties.Test
// ==========================
// Comprehensive unit tests for Floria.CSS.Properties:
//   - Canonical property name-to-id and id-to-name lookup
//   - Inheritance and shorthand metadata flags
//   - TCSSPropertyValue constructors and enum helpers
//   - TCSSStyleDeclaration importance handling and cloning
//   - TCSSStyleBlock storage, retrieval, and importance precedence
//   - Parsing CSS declaration lists and shorthand expansions (margin, padding, border)

{$mode objfpc}{$H+}

interface

uses
  Classes, Contnrs, SysUtils, fpcunit, testregistry,
  Floria.CSS.Types, Floria.CSS.AST, Floria.CSS.Values, Floria.CSS.Properties;

type
  TCSSPropertiesLookupTest = class(TTestCase)
  published
    procedure TestPropertyNameToId();
    procedure TestPropertyIdToName();
    procedure TestIsInherited();
    procedure TestIsShorthand();
    procedure TestCustomPropertyId();
  end;

  TCSSPropertyValueTest = class(TTestCase)
  published
    procedure TestConstructors();
    procedure TestEnumHelpers();
    procedure TestValueEquality();
  end;

  TCSSStyleBlockTest = class(TTestCase)
  published
    procedure TestSetAndGet();
    procedure TestImportancePrecedence();
    procedure TestRemoveAndClear();
    procedure TestCustomProperties();
    procedure TestFromCSSBasic();
    procedure TestFromCSSImportant();
    procedure TestFromCSSMarginShorthand();
    procedure TestFromCSSPaddingShorthand();
    procedure TestFromCSSBorderShorthand();
    procedure TestFromCSSBorderSideShorthand();
    procedure TestFromCSSWithoutShorthandExpansion();
  end;

implementation

// ── TCSSPropertiesLookupTest ────────────────────────────────────────────────

procedure TCSSPropertiesLookupTest.TestPropertyNameToId();
begin
  AssertTrue('margin -> cpiMargin', CSSPropertyNameToId('margin') = cpiMargin);
  AssertTrue('color -> cpiColor', CSSPropertyNameToId('color') = cpiColor);
  AssertTrue('background-color -> cpiBackgroundColor', CSSPropertyNameToId('background-color') = cpiBackgroundColor);
  AssertTrue('display -> cpiDisplay', CSSPropertyNameToId('display') = cpiDisplay);
  AssertTrue('width -> cpiWidth', CSSPropertyNameToId('width') = cpiWidth);
  AssertTrue('z-index -> cpiZIndex', CSSPropertyNameToId('z-index') = cpiZIndex);
  AssertTrue('flex-grow -> cpiFlexGrow', CSSPropertyNameToId('flex-grow') = cpiFlexGrow);
  AssertTrue('border-radius -> cpiBorderRadius', CSSPropertyNameToId('border-radius') = cpiBorderRadius);
  AssertTrue('unknown -> cpiUnknown', CSSPropertyNameToId('non-existent-prop') = cpiUnknown);
end;

procedure TCSSPropertiesLookupTest.TestPropertyIdToName();
begin
  AssertEquals('margin', CSSPropertyIdToName(cpiMargin));
  AssertEquals('color', CSSPropertyIdToName(cpiColor));
  AssertEquals('background-color', CSSPropertyIdToName(cpiBackgroundColor));
  AssertEquals('display', CSSPropertyIdToName(cpiDisplay));
end;

procedure TCSSPropertiesLookupTest.TestIsInherited();
begin
  AssertTrue('color is inherited', CSSIsInheritedProperty(cpiColor));
  AssertTrue('font-family is inherited', CSSIsInheritedProperty(cpiFontFamily));
  AssertTrue('font-size is inherited', CSSIsInheritedProperty(cpiFontSize));
  AssertTrue('visibility is inherited', CSSIsInheritedProperty(cpiVisibility));

  AssertFalse('margin is not inherited', CSSIsInheritedProperty(cpiMargin));
  AssertFalse('padding is not inherited', CSSIsInheritedProperty(cpiPadding));
  AssertFalse('width is not inherited', CSSIsInheritedProperty(cpiWidth));
  AssertFalse('display is not inherited', CSSIsInheritedProperty(cpiDisplay));
end;

procedure TCSSPropertiesLookupTest.TestIsShorthand();
begin
  AssertTrue('margin is shorthand', CSSIsShorthandProperty(cpiMargin));
  AssertTrue('padding is shorthand', CSSIsShorthandProperty(cpiPadding));
  AssertTrue('border is shorthand', CSSIsShorthandProperty(cpiBorder));
  AssertTrue('border-width is shorthand', CSSIsShorthandProperty(cpiBorderWidth));
  AssertTrue('border-radius is shorthand', CSSIsShorthandProperty(cpiBorderRadius));
  AssertTrue('overflow is shorthand', CSSIsShorthandProperty(cpiOverflow));

  AssertFalse('color is not shorthand', CSSIsShorthandProperty(cpiColor));
  AssertFalse('width is not shorthand', CSSIsShorthandProperty(cpiWidth));
  AssertFalse('margin-left is not shorthand', CSSIsShorthandProperty(cpiMarginLeft));
end;

procedure TCSSPropertiesLookupTest.TestCustomPropertyId();
begin
  AssertTrue('--theme-color -> cpiCustom', CSSPropertyNameToId('--theme-color') = cpiCustom);
  AssertTrue('--x -> cpiCustom', CSSPropertyNameToId('--x') = cpiCustom);
end;

// ── TCSSPropertyValueTest ───────────────────────────────────────────────────

procedure TCSSPropertyValueTest.TestConstructors();
var
  V: TCSSPropertyValue;
begin
  V := TCSSPropertyValue.FromColor(TCSSColor.FromRGBA(255, 0, 0, 255));
  AssertTrue('Kind is color', V.Kind = cvkColor);
  AssertEquals(255, V.Color.R);

  V := TCSSPropertyValue.FromLength(TCSSLength.Px(42.0));
  AssertTrue('Kind is length', V.Kind = cvkLength);
  AssertEquals(42.0, V.Length.Value);

  V := TCSSPropertyValue.FromNumber(100.0);
  AssertTrue('Kind is number', V.Kind = cvkNumber);
  AssertEquals(100.0, V.Number);

  V := TCSSPropertyValue.FromKeyword('block');
  AssertTrue('Kind is keyword', V.Kind = cvkKeyword);
  AssertEquals('block', V.Keyword);

  V := TCSSPropertyValue.FromString('Arial, sans-serif');
  AssertTrue('Kind is string', V.Kind = cvkString);
  AssertEquals('Arial, sans-serif', V.Str);

  V := TCSSPropertyValue.Initial();
  AssertTrue('Kind is initial', V.Kind = cvkInitial);

  V := TCSSPropertyValue.Inherit();
  AssertTrue('Kind is inherit', V.Kind = cvkInherit);

  V := TCSSPropertyValue.Unset();
  AssertTrue('Kind is unset', V.Kind = cvkUnset);
end;

procedure TCSSPropertyValueTest.TestEnumHelpers();
var
  V: TCSSPropertyValue;
begin
  V := TCSSPropertyValue.FromKeyword('flex');
  AssertTrue('AsDisplay flex', V.AsDisplay() = cdFlex);

  V := TCSSPropertyValue.FromKeyword('absolute');
  AssertTrue('AsPosition absolute', V.AsPosition() = cpAbsolute);

  V := TCSSPropertyValue.FromKeyword('hidden');
  AssertTrue('AsVisibility hidden', V.AsVisibility() = cvHidden);

  V := TCSSPropertyValue.FromKeyword('scroll');
  AssertTrue('AsOverflow scroll', V.AsOverflow() = coScroll);

  V := TCSSPropertyValue.FromKeyword('dashed');
  AssertTrue('AsBorderStyle dashed', V.AsBorderStyle() = cbsDashed);

  V := TCSSPropertyValue.FromKeyword('border-box');
  AssertTrue('AsBoxSizing border-box', V.AsBoxSizing() = cbsBorderBox);

  V := TCSSPropertyValue.FromKeyword('center');
  AssertTrue('AsTextAlign center', V.AsTextAlign() = ctaCenter);
end;

procedure TCSSPropertyValueTest.TestValueEquality();
var
  V1, V2: TCSSPropertyValue;
begin
  V1 := TCSSPropertyValue.FromLength(TCSSLength.Px(10.0));
  V2 := TCSSPropertyValue.FromLength(TCSSLength.Px(10.0));
  AssertTrue('Equal lengths', V1.Equals(V2));

  V2 := TCSSPropertyValue.FromLength(TCSSLength.Px(20.0));
  AssertFalse('Different lengths', V1.Equals(V2));

  V1 := TCSSPropertyValue.FromColor(TCSSColor.Black());
  V2 := TCSSPropertyValue.FromColor(TCSSColor.Black());
  AssertTrue('Equal colors', V1.Equals(V2));
end;

// ── TCSSStyleBlockTest ──────────────────────────────────────────────────────

procedure TCSSStyleBlockTest.TestSetAndGet();
var
  Block: TCSSStyleBlock;
  Decl : TCSSStyleDeclaration;
begin
  Block := TCSSStyleBlock.Create();
  try
    Block.SetProperty(cpiWidth, TCSSPropertyValue.FromLength(TCSSLength.Px(100.0)));
    Block.SetProperty(cpiHeight, TCSSPropertyValue.FromLength(TCSSLength.Px(50.0)));

    AssertEquals(2, Block.Count);
    AssertTrue('Has width', Block.HasProperty(cpiWidth));
    AssertTrue('Has height', Block.HasProperty(cpiHeight));
    AssertFalse('No margin', Block.HasProperty(cpiMargin));

    Decl := Block.GetDeclaration(cpiWidth);
    AssertNotNull('Width decl not nil', Decl);
    AssertEquals(100.0, Decl.Value.Length.Value);
  finally
    Block.Free();
  end;
end;

procedure TCSSStyleBlockTest.TestImportancePrecedence();
var
  Block: TCSSStyleBlock;
  Decl : TCSSStyleDeclaration;
begin
  Block := TCSSStyleBlock.Create();
  try
    // Set important property
    Block.SetProperty(cpiColor, TCSSPropertyValue.FromColor(TCSSColor.FromRGBA(255, 0, 0, 255)), True);
    // Attempt normal override
    Block.SetProperty(cpiColor, TCSSPropertyValue.FromColor(TCSSColor.FromRGBA(0, 255, 0, 255)), False);

    Decl := Block.GetDeclaration(cpiColor);
    AssertNotNull('Decl found', Decl);
    AssertTrue('Color remains red', Decl.Value.Color.R = 255);
    AssertTrue('Important remains true', Decl.Important);

    // Override with another important value
    Block.SetProperty(cpiColor, TCSSPropertyValue.FromColor(TCSSColor.FromRGBA(0, 0, 255, 255)), True);
    Decl := Block.GetDeclaration(cpiColor);
    AssertTrue('Color becomes blue', Decl.Value.Color.B = 255);
  finally
    Block.Free();
  end;
end;

procedure TCSSStyleBlockTest.TestRemoveAndClear();
var
  Block: TCSSStyleBlock;
begin
  Block := TCSSStyleBlock.Create();
  try
    Block.SetProperty(cpiTop, TCSSPropertyValue.FromLength(TCSSLength.Px(10.0)));
    Block.SetProperty(cpiLeft, TCSSPropertyValue.FromLength(TCSSLength.Px(20.0)));
    AssertEquals(2, Block.Count);

    Block.RemoveProperty(cpiTop);
    AssertEquals(1, Block.Count);
    AssertFalse('Top removed', Block.HasProperty(cpiTop));
    AssertTrue('Left retained', Block.HasProperty(cpiLeft));

    Block.Clear();
    AssertEquals(0, Block.Count);
  finally
    Block.Free();
  end;
end;

procedure TCSSStyleBlockTest.TestCustomProperties();
var
  Block: TCSSStyleBlock;
  Decl : TCSSStyleDeclaration;
begin
  Block := TCSSStyleBlock.Create();
  try
    Block.SetCustom('--primary-color', TCSSPropertyValue.FromString('#336699'));
    Decl := Block.GetCustom('--primary-color');
    AssertNotNull('Custom decl found', Decl);
    AssertEquals('--primary-color', Decl.CustomName);
    AssertEquals('#336699', Decl.Value.Str);
  finally
    Block.Free();
  end;
end;

procedure TCSSStyleBlockTest.TestFromCSSBasic();
var
  Block: TCSSStyleBlock;
  Decl : TCSSStyleDeclaration;
begin
  Block := TCSSStyleBlock.FromCSS('color: #ff0000; width: 200px; display: flex;');
  try
    AssertTrue('Has color', Block.HasProperty(cpiColor));
    Decl := Block.GetDeclaration(cpiColor);
    AssertEquals(255, Decl.Value.Color.R);

    AssertTrue('Has width', Block.HasProperty(cpiWidth));
    Decl := Block.GetDeclaration(cpiWidth);
    AssertEquals(200.0, Decl.Value.Length.Value);

    AssertTrue('Has display', Block.HasProperty(cpiDisplay));
    Decl := Block.GetDeclaration(cpiDisplay);
    AssertTrue('Display is flex', Decl.Value.AsDisplay() = cdFlex);
  finally
    Block.Free();
  end;
end;

procedure TCSSStyleBlockTest.TestFromCSSImportant();
var
  Block: TCSSStyleBlock;
  Decl : TCSSStyleDeclaration;
begin
  // First declaration is important, second is normal
  Block := TCSSStyleBlock.FromCSS('color: red !important; color: blue;');
  try
    Decl := Block.GetDeclaration(cpiColor);
    AssertNotNull('Decl found', Decl);
    AssertTrue('Important red preserved', Decl.Value.Color.R = 255);
    AssertTrue('Important flag is true', Decl.Important);
  finally
    Block.Free();
  end;
end;

procedure TCSSStyleBlockTest.TestFromCSSMarginShorthand();
var
  Block: TCSSStyleBlock;
begin
  Block := TCSSStyleBlock.FromCSS('margin: 10px 20px;');
  try
    AssertTrue('Has margin-top', Block.HasProperty(cpiMarginTop));
    AssertTrue('Has margin-right', Block.HasProperty(cpiMarginRight));
    AssertTrue('Has margin-bottom', Block.HasProperty(cpiMarginBottom));
    AssertTrue('Has margin-left', Block.HasProperty(cpiMarginLeft));

    AssertEquals(10.0, Block.GetDeclaration(cpiMarginTop).Value.Length.Value);
    AssertEquals(20.0, Block.GetDeclaration(cpiMarginRight).Value.Length.Value);
    AssertEquals(10.0, Block.GetDeclaration(cpiMarginBottom).Value.Length.Value);
    AssertEquals(20.0, Block.GetDeclaration(cpiMarginLeft).Value.Length.Value);
  finally
    Block.Free();
  end;
end;

procedure TCSSStyleBlockTest.TestFromCSSPaddingShorthand();
var
  Block: TCSSStyleBlock;
begin
  Block := TCSSStyleBlock.FromCSS('padding: 8px;');
  try
    AssertEquals(8.0, Block.GetDeclaration(cpiPaddingTop).Value.Length.Value);
    AssertEquals(8.0, Block.GetDeclaration(cpiPaddingRight).Value.Length.Value);
    AssertEquals(8.0, Block.GetDeclaration(cpiPaddingBottom).Value.Length.Value);
    AssertEquals(8.0, Block.GetDeclaration(cpiPaddingLeft).Value.Length.Value);
  finally
    Block.Free();
  end;
end;

procedure TCSSStyleBlockTest.TestFromCSSBorderShorthand();
var
  Block: TCSSStyleBlock;
begin
  Block := TCSSStyleBlock.FromCSS('border: 2px solid #00ff00;');
  try
    // Widths
    AssertEquals(2.0, Block.GetDeclaration(cpiBorderTopWidth).Value.Length.Value);
    AssertEquals(2.0, Block.GetDeclaration(cpiBorderRightWidth).Value.Length.Value);
    AssertEquals(2.0, Block.GetDeclaration(cpiBorderBottomWidth).Value.Length.Value);
    AssertEquals(2.0, Block.GetDeclaration(cpiBorderLeftWidth).Value.Length.Value);

    // Styles
    AssertTrue('Top solid', Block.GetDeclaration(cpiBorderTopStyle).Value.AsBorderStyle() = cbsSolid);
    AssertTrue('Left solid', Block.GetDeclaration(cpiBorderLeftStyle).Value.AsBorderStyle() = cbsSolid);

    // Colors
    AssertEquals(255, Block.GetDeclaration(cpiBorderTopColor).Value.Color.G);
    AssertEquals(255, Block.GetDeclaration(cpiBorderLeftColor).Value.Color.G);
  finally
    Block.Free();
  end;
end;

procedure TCSSStyleBlockTest.TestFromCSSBorderSideShorthand();
var
  Block: TCSSStyleBlock;
begin
  Block := TCSSStyleBlock.FromCSS('border-top: 1px dashed red;');
  try
    AssertTrue('Has border-top-width', Block.HasProperty(cpiBorderTopWidth));
    AssertEquals(1.0, Block.GetDeclaration(cpiBorderTopWidth).Value.Length.Value);

    AssertTrue('Has border-top-style', Block.HasProperty(cpiBorderTopStyle));
    AssertTrue('Top dashed', Block.GetDeclaration(cpiBorderTopStyle).Value.AsBorderStyle() = cbsDashed);

    AssertTrue('Has border-top-color', Block.HasProperty(cpiBorderTopColor));
    AssertEquals(255, Block.GetDeclaration(cpiBorderTopColor).Value.Color.R);
  finally
    Block.Free();
  end;
end;

procedure TCSSStyleBlockTest.TestFromCSSWithoutShorthandExpansion();
var
  Block: TCSSStyleBlock;
  Decl : TCSSStyleDeclaration;
begin
  // When expansion is disabled, margin should be stored directly as cpiMargin with cvkBox
  Block := TCSSStyleBlock.FromCSS('margin: 10px 20px;', False);
  try
    AssertTrue('Has cpiMargin', Block.HasProperty(cpiMargin));
    Decl := Block.GetDeclaration(cpiMargin);
    AssertTrue('Kind is box', Decl.Value.Kind = cvkBox);
    AssertEquals(10.0, Decl.Value.Box.Top.Value);
    AssertEquals(20.0, Decl.Value.Box.Right.Value);
    AssertFalse('No margin-top when unexpanded', Block.HasProperty(cpiMarginTop));
  finally
    Block.Free();
  end;
end;

initialization
  RegisterTest(TCSSPropertiesLookupTest);
  RegisterTest(TCSSPropertyValueTest);
  RegisterTest(TCSSStyleBlockTest);

end.
