unit Floria.CSS.Selectors.Test;

// Floria.CSS.Selectors.Test
// =========================
// Comprehensive unit tests for Floria.CSS.Selectors:
//   - Specificity scoring (A, B, C) and comparison
//   - Simple & compound selector parsing
//   - Attribute selector operators
//   - Combinator parsing (child, descendant, adjacent, sibling)
//   - Comma-separated selector lists

{$mode objfpc}{$H+}

interface

uses
  Classes, Contnrs, SysUtils, fpcunit, testregistry,
  Floria.CSS.Types, Floria.CSS.AST, Floria.CSS.Selectors;

type
  TCSSSelectorsSpecificityTest = class(TTestCase)
  published
    procedure TestUniversalSpecificity();
    procedure TestTypeSpecificity();
    procedure TestClassSpecificity();
    procedure TestIdSpecificity();
    procedure TestCombinedCompoundSpecificity();
    procedure TestComplexChainSpecificity();
    procedure TestSpecificityComparisons();
  end;

  TCSSSelectorsParsingTest = class(TTestCase)
  published
    procedure TestSingleTypeSelector();
    procedure TestClassSelector();
    procedure TestIdSelector();
    procedure TestCompoundSelector();
    procedure TestAttributeSelectors();
    procedure TestPseudoClasses();
    procedure TestChildCombinator();
    procedure TestDescendantCombinator();
    procedure TestSiblingCombinators();
    procedure TestComplexChain();
    procedure TestCommaSeparatedList();
  end;

implementation

// ── TCSSSelectorsSpecificityTest ────────────────────────────────────────────

procedure TCSSSelectorsSpecificityTest.TestUniversalSpecificity();
var
  List: TCSSSelectorList;
begin
  List := ParseSelectorListFromCSS('*');
  try
    AssertEquals(1, List.Count);
    AssertTrue('Universal is (0,0,0)', List[0].CalculateSpecificity().Equals(TCSSSpecificity.Create(0, 0, 0)));
  finally
    List.Free();
  end;
end;

procedure TCSSSelectorsSpecificityTest.TestTypeSpecificity();
var
  List: TCSSSelectorList;
begin
  List := ParseSelectorListFromCSS('button');
  try
    AssertEquals(1, List.Count);
    AssertTrue('Type button is (0,0,1)', List[0].CalculateSpecificity().Equals(TCSSSpecificity.Create(0, 0, 1)));
  finally
    List.Free();
  end;
end;

procedure TCSSSelectorsSpecificityTest.TestClassSpecificity();
var
  List: TCSSSelectorList;
begin
  List := ParseSelectorListFromCSS('.btn');
  try
    AssertEquals(1, List.Count);
    AssertTrue('.btn is (0,1,0)', List[0].CalculateSpecificity().Equals(TCSSSpecificity.Create(0, 1, 0)));
  finally
    List.Free();
  end;
end;

procedure TCSSSelectorsSpecificityTest.TestIdSpecificity();
var
  List: TCSSSelectorList;
begin
  List := ParseSelectorListFromCSS('#header');
  try
    AssertEquals(1, List.Count);
    AssertTrue('#header is (1,0,0)', List[0].CalculateSpecificity().Equals(TCSSSpecificity.Create(1, 0, 0)));
  finally
    List.Free();
  end;
end;

procedure TCSSSelectorsSpecificityTest.TestCombinedCompoundSpecificity();
var
  List: TCSSSelectorList;
begin
  // button.btn.active#submit:hover -> 1 ID, 3 (2 classes + 1 pseudo), 1 type = (1, 3, 1)
  List := ParseSelectorListFromCSS('button.btn.active#submit:hover');
  try
    AssertEquals(1, List.Count);
    AssertTrue('Compound is (1,3,1)', List[0].CalculateSpecificity().Equals(TCSSSpecificity.Create(1, 3, 1)));
  finally
    List.Free();
  end;
end;

procedure TCSSSelectorsSpecificityTest.TestComplexChainSpecificity();
var
  List: TCSSSelectorList;
begin
  // div.container > ul.menu li a.active
  // div.container: (0, 1, 1)
  // ul.menu: (0, 1, 1)
  // li: (0, 0, 1)
  // a.active: (0, 1, 1)
  // Total: (0, 3, 4)
  List := ParseSelectorListFromCSS('div.container > ul.menu li a.active');
  try
    AssertEquals(1, List.Count);
    AssertTrue('Chain is (0,3,4)', List[0].CalculateSpecificity().Equals(TCSSSpecificity.Create(0, 3, 4)));
  finally
    List.Free();
  end;
end;

procedure TCSSSelectorsSpecificityTest.TestSpecificityComparisons();
var
  S1, S2: TCSSSpecificity;
begin
  // (1,0,0) beats (0,10,10)
  S1 := TCSSSpecificity.Create(1, 0, 0);
  S2 := TCSSSpecificity.Create(0, 10, 10);
  AssertTrue('ID beats classes', S1.CompareTo(S2) > 0);
  AssertTrue('Classes lose to ID', S2.CompareTo(S1) < 0);

  // (0,1,5) beats (0,1,2)
  S1 := TCSSSpecificity.Create(0, 1, 5);
  S2 := TCSSSpecificity.Create(0, 1, 2);
  AssertTrue('More types win', S1.CompareTo(S2) > 0);

  // Equal specificities
  S1 := TCSSSpecificity.Create(0, 2, 1);
  S2 := TCSSSpecificity.Create(0, 2, 1);
  AssertEquals(0, S1.CompareTo(S2));
end;

// ── TCSSSelectorsParsingTest ────────────────────────────────────────────────

procedure TCSSSelectorsParsingTest.TestSingleTypeSelector();
var
  List: TCSSSelectorList;
  Comp: TCSSCompoundSelector;
begin
  List := ParseSelectorListFromCSS('window');
  try
    AssertEquals(1, List.Count);
    AssertEquals(1, List[0].Count);
    Comp := List[0][0];
    AssertEquals('window', Comp.TagName);
    AssertFalse('Not universal', Comp.Universal);
  finally
    List.Free();
  end;
end;

procedure TCSSSelectorsParsingTest.TestClassSelector();
var
  List: TCSSSelectorList;
  Comp: TCSSCompoundSelector;
begin
  List := ParseSelectorListFromCSS('.primary-button');
  try
    AssertEquals(1, List.Count);
    Comp := List[0][0];
    AssertEquals(1, Comp.Classes.Count);
    AssertEquals('primary-button', Comp.Classes[0]);
  finally
    List.Free();
  end;
end;

procedure TCSSSelectorsParsingTest.TestIdSelector();
var
  List: TCSSSelectorList;
  Comp: TCSSCompoundSelector;
begin
  List := ParseSelectorListFromCSS('#main-container');
  try
    AssertEquals(1, List.Count);
    Comp := List[0][0];
    AssertEquals('main-container', Comp.Id);
  finally
    List.Free();
  end;
end;

procedure TCSSSelectorsParsingTest.TestCompoundSelector();
var
  List: TCSSSelectorList;
  Comp: TCSSCompoundSelector;
begin
  List := ParseSelectorListFromCSS('button.btn.btn-danger#delete-btn');
  try
    AssertEquals(1, List.Count);
    Comp := List[0][0];
    AssertEquals('button', Comp.TagName);
    AssertEquals('delete-btn', Comp.Id);
    AssertEquals(2, Comp.Classes.Count);
    AssertTrue('Has btn', Comp.HasClass('btn'));
    AssertTrue('Has btn-danger', Comp.HasClass('btn-danger'));
  finally
    List.Free();
  end;
end;

procedure TCSSSelectorsParsingTest.TestAttributeSelectors();
var
  List: TCSSSelectorList;
  Comp: TCSSCompoundSelector;
begin
  List := ParseSelectorListFromCSS('input[type="text"][disabled]');
  try
    AssertEquals(1, List.Count);
    Comp := List[0][0];
    AssertEquals('input', Comp.TagName);
    AssertEquals(2, Comp.AttributeCount);

    AssertEquals('type', Comp.Attributes[0].Name);
    AssertTrue('Op is equals', Comp.Attributes[0].Op = caoEquals);
    AssertEquals('text', Comp.Attributes[0].Value);

    AssertEquals('disabled', Comp.Attributes[1].Name);
    AssertTrue('Op is exists', Comp.Attributes[1].Op = caoExists);
  finally
    List.Free();
  end;
end;

procedure TCSSSelectorsParsingTest.TestPseudoClasses();
var
  List: TCSSSelectorList;
  Comp: TCSSCompoundSelector;
begin
  List := ParseSelectorListFromCSS('a:hover:active');
  try
    AssertEquals(1, List.Count);
    Comp := List[0][0];
    AssertEquals('a', Comp.TagName);
    AssertEquals(2, Comp.PseudoClasses.Count);
    AssertEquals('hover', Comp.PseudoClasses[0]);
    AssertEquals('active', Comp.PseudoClasses[1]);
  finally
    List.Free();
  end;
end;

procedure TCSSSelectorsParsingTest.TestChildCombinator();
var
  List: TCSSSelectorList;
  Comp1, Comp2: TCSSCompoundSelector;
begin
  List := ParseSelectorListFromCSS('div > p');
  try
    AssertEquals(1, List.Count);
    AssertEquals(2, List[0].Count);
    Comp1 := List[0][0];
    Comp2 := List[0][1];

    AssertEquals('div', Comp1.TagName);
    AssertTrue('Combinator is child', Comp1.Combinator = ccChild);

    AssertEquals('p', Comp2.TagName);
    AssertTrue('Last combinator is none', Comp2.Combinator = ccNone);
  finally
    List.Free();
  end;
end;

procedure TCSSSelectorsParsingTest.TestDescendantCombinator();
var
  List: TCSSSelectorList;
  Comp1, Comp2: TCSSCompoundSelector;
begin
  List := ParseSelectorListFromCSS('nav a');
  try
    AssertEquals(1, List.Count);
    AssertEquals(2, List[0].Count);
    Comp1 := List[0][0];
    Comp2 := List[0][1];

    AssertEquals('nav', Comp1.TagName);
    AssertTrue('Combinator is descendant', Comp1.Combinator = ccDescendant);

    AssertEquals('a', Comp2.TagName);
    AssertTrue('Last combinator is none', Comp2.Combinator = ccNone);
  finally
    List.Free();
  end;
end;

procedure TCSSSelectorsParsingTest.TestSiblingCombinators();
var
  List: TCSSSelectorList;
begin
  List := ParseSelectorListFromCSS('h1 + p');
  try
    AssertEquals(1, List.Count);
    AssertEquals(2, List[0].Count);
    AssertTrue('Adjacent sibling', List[0][0].Combinator = ccAdjacentSibling);
  finally
    List.Free();
  end;

  List := ParseSelectorListFromCSS('h1 ~ p');
  try
    AssertEquals(1, List.Count);
    AssertEquals(2, List[0].Count);
    AssertTrue('General sibling', List[0][0].Combinator = ccGeneralSibling);
  finally
    List.Free();
  end;
end;

procedure TCSSSelectorsParsingTest.TestComplexChain();
var
  List: TCSSSelectorList;
begin
  List := ParseSelectorListFromCSS('.sidebar > ul.nav > li + li a:hover');
  try
    AssertEquals(1, List.Count);
    AssertEquals(5, List[0].Count);
    AssertTrue('Combinator 1 is child', List[0][0].Combinator = ccChild);
    AssertTrue('Combinator 2 is child', List[0][1].Combinator = ccChild);
    AssertTrue('Combinator 3 is adjacent', List[0][2].Combinator = ccAdjacentSibling);
    AssertTrue('Combinator 4 is descendant', List[0][3].Combinator = ccDescendant);
    AssertTrue('Combinator 5 is none', List[0][4].Combinator = ccNone);
  finally
    List.Free();
  end;
end;

procedure TCSSSelectorsParsingTest.TestCommaSeparatedList();
var
  List: TCSSSelectorList;
begin
  List := ParseSelectorListFromCSS('h1, h2, h3, .subtitle');
  try
    AssertEquals(4, List.Count);
    AssertEquals('h1', List[0][0].TagName);
    AssertEquals('h2', List[1][0].TagName);
    AssertEquals('h3', List[2][0].TagName);
    AssertTrue('Has subtitle class', List[3][0].HasClass('subtitle'));
  finally
    List.Free();
  end;
end;

initialization
  RegisterTest(TCSSSelectorsSpecificityTest);
  RegisterTest(TCSSSelectorsParsingTest);

end.
