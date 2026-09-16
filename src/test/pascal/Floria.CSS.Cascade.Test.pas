unit Floria.CSS.Cascade.Test;

// Floria.CSS.Cascade.Test
// =======================
// Comprehensive unit tests for Floria.CSS.Cascade:
//   - Element tree modeling (TCSSMockElement)
//   - Selector matching: tag, id, class, attributes, pseudo-classes
//   - Combinator matching: child, descendant, adjacent, general sibling
//   - Cascade resolution (TCSSStyleResolver):
//     - Specificity precedence
//     - !important precedence
//     - Source order tie-breaking
//     - Property inheritance from parent elements

{$mode objfpc}{$H+}

interface

uses
  Classes, Contnrs, SysUtils, fpcunit, testregistry,
  Floria.CSS.Types, Floria.CSS.AST, Floria.CSS.Values,
  Floria.CSS.Properties, Floria.CSS.Selectors, Floria.CSS.Cascade;

type
  TCSSCascadeMatchingTest = class(TTestCase)
  published
    procedure TestTagAndIdMatching();
    procedure TestClassMatching();
    procedure TestAttributeMatching();
    procedure TestPseudoClassMatching();
    procedure TestChildCombinator();
    procedure TestDescendantCombinator();
    procedure TestAdjacentSiblingCombinator();
    procedure TestGeneralSiblingCombinator();
  end;

  TCSSCascadeResolutionTest = class(TTestCase)
  published
    procedure TestSpecificityPrecedence();
    procedure TestImportancePrecedence();
    procedure TestSourceOrderPrecedence();
    procedure TestPropertyInheritance();
    procedure TestMultipleRulesCombined();
  end;

implementation

// ── TCSSCascadeMatchingTest ─────────────────────────────────────────────────

procedure TCSSCascadeMatchingTest.TestTagAndIdMatching();
var
  El1, El2: TCSSMockElement;
  Sel     : TCSSSelectorList;
  Spec    : TCSSSpecificity;
begin
  El1 := TCSSMockElement.Create('button', 'submit-btn');
  El2 := TCSSMockElement.Create('div', 'container');
  try
    Sel := ParseSelectorListFromCSS('button');
    try
      AssertTrue('Matches button', MatchesSelectorList(Sel, El1, Spec));
      AssertFalse('Div does not match button', MatchesSelectorList(Sel, El2, Spec));
    finally
      Sel.Free();
    end;

    Sel := ParseSelectorListFromCSS('#submit-btn');
    try
      AssertTrue('Matches id', MatchesSelectorList(Sel, El1, Spec));
      AssertFalse('Div does not match id', MatchesSelectorList(Sel, El2, Spec));
    finally
      Sel.Free();
    end;
  finally
    El1.Free();
    El2.Free();
  end;
end;

procedure TCSSCascadeMatchingTest.TestClassMatching();
var
  El : TCSSMockElement;
  Sel: TCSSSelectorList;
  Spec: TCSSSpecificity;
begin
  El := TCSSMockElement.Create('button');
  try
    El.AddClass('btn');
    El.AddClass('btn-primary');

    Sel := ParseSelectorListFromCSS('.btn');
    try
      AssertTrue('Matches .btn', MatchesSelectorList(Sel, El, Spec));
    finally
      Sel.Free();
    end;

    Sel := ParseSelectorListFromCSS('.btn.btn-primary');
    try
      AssertTrue('Matches both classes', MatchesSelectorList(Sel, El, Spec));
    finally
      Sel.Free();
    end;

    Sel := ParseSelectorListFromCSS('.btn.btn-danger');
    try
      AssertFalse('Does not match absent class', MatchesSelectorList(Sel, El, Spec));
    finally
      Sel.Free();
    end;
  finally
    El.Free();
  end;
end;

procedure TCSSCascadeMatchingTest.TestAttributeMatching();
var
  El  : TCSSMockElement;
  Sel : TCSSSelectorList;
  Spec: TCSSSpecificity;
begin
  El := TCSSMockElement.Create('input');
  try
    El.SetAttribute('type', 'text');
    El.SetAttribute('data-role', 'admin-user');
    El.SetAttribute('title', 'hello world test');

    Sel := ParseSelectorListFromCSS('[type="text"]');
    try
      AssertTrue('Equals operator', MatchesSelectorList(Sel, El, Spec));
    finally
      Sel.Free();
    end;

    Sel := ParseSelectorListFromCSS('[title~="world"]');
    try
      AssertTrue('Includes word operator', MatchesSelectorList(Sel, El, Spec));
    finally
      Sel.Free();
    end;

    Sel := ParseSelectorListFromCSS('[data-role^="admin"]');
    try
      AssertTrue('Prefix operator', MatchesSelectorList(Sel, El, Spec));
    finally
      Sel.Free();
    end;

    Sel := ParseSelectorListFromCSS('[data-role$="user"]');
    try
      AssertTrue('Suffix operator', MatchesSelectorList(Sel, El, Spec));
    finally
      Sel.Free();
    end;

    Sel := ParseSelectorListFromCSS('[data-role*="min-u"]');
    try
      AssertTrue('Substring operator', MatchesSelectorList(Sel, El, Spec));
    finally
      Sel.Free();
    end;

    Sel := ParseSelectorListFromCSS('[type="password"]');
    try
      AssertFalse('Wrong value does not match', MatchesSelectorList(Sel, El, Spec));
    finally
      Sel.Free();
    end;
  finally
    El.Free();
  end;
end;

procedure TCSSCascadeMatchingTest.TestPseudoClassMatching();
var
  Parent, C1, C2, C3: TCSSMockElement;
  Sel               : TCSSSelectorList;
  Spec              : TCSSSpecificity;
begin
  Parent := TCSSMockElement.Create('ul');
  C1     := TCSSMockElement.Create('li');
  C2     := TCSSMockElement.Create('li');
  C3     := TCSSMockElement.Create('li');
  try
    Parent.AppendChild(C1);
    Parent.AppendChild(C2);
    Parent.AppendChild(C3);

    C2.SetHovered(True);
    C3.SetDisabled(True);

    Sel := ParseSelectorListFromCSS(':first-child');
    try
      AssertTrue('C1 is first-child', MatchesSelectorList(Sel, C1, Spec));
      AssertFalse('C2 is not first-child', MatchesSelectorList(Sel, C2, Spec));
    finally
      Sel.Free();
    end;

    Sel := ParseSelectorListFromCSS(':last-child');
    try
      AssertTrue('C3 is last-child', MatchesSelectorList(Sel, C3, Spec));
      AssertFalse('C1 is not last-child', MatchesSelectorList(Sel, C1, Spec));
    finally
      Sel.Free();
    end;

    Sel := ParseSelectorListFromCSS(':hover');
    try
      AssertTrue('C2 is hover', MatchesSelectorList(Sel, C2, Spec));
      AssertFalse('C1 is not hover', MatchesSelectorList(Sel, C1, Spec));
    finally
      Sel.Free();
    end;

    Sel := ParseSelectorListFromCSS(':disabled');
    try
      AssertTrue('C3 is disabled', MatchesSelectorList(Sel, C3, Spec));
      AssertFalse('C1 is not disabled', MatchesSelectorList(Sel, C1, Spec));
    finally
      Sel.Free();
    end;

    C1.SetChecked(True);
    Sel := ParseSelectorListFromCSS(':checked');
    try
      AssertTrue('C1 is checked', MatchesSelectorList(Sel, C1, Spec));
      AssertFalse('C2 is not checked', MatchesSelectorList(Sel, C2, Spec));
    finally
      Sel.Free();
    end;
  finally
    Parent.Free();
  end;
end;

procedure TCSSCascadeMatchingTest.TestChildCombinator();
var
  Grandparent, Parent, Child: TCSSMockElement;
  Sel                       : TCSSSelectorList;
  Spec                      : TCSSSpecificity;
begin
  Grandparent := TCSSMockElement.Create('div', 'gp');
  Parent      := TCSSMockElement.Create('section', 'p');
  Child       := TCSSMockElement.Create('span', 'c');
  try
    Grandparent.AppendChild(Parent);
    Parent.AppendChild(Child);

    // section > span matches direct child
    Sel := ParseSelectorListFromCSS('section > span');
    try
      AssertTrue('section > span matches Child', MatchesSelectorList(Sel, Child, Spec));
    finally
      Sel.Free();
    end;

    // div > span does NOT match because div is grandparent, not parent
    Sel := ParseSelectorListFromCSS('div > span');
    try
      AssertFalse('div > span does not match grandchild', MatchesSelectorList(Sel, Child, Spec));
    finally
      Sel.Free();
    end;
  finally
    Grandparent.Free();
  end;
end;

procedure TCSSCascadeMatchingTest.TestDescendantCombinator();
var
  Grandparent, Parent, Child: TCSSMockElement;
  Sel                       : TCSSSelectorList;
  Spec                      : TCSSSpecificity;
begin
  Grandparent := TCSSMockElement.Create('div', 'gp');
  Parent      := TCSSMockElement.Create('section', 'p');
  Child       := TCSSMockElement.Create('span', 'c');
  try
    Grandparent.AppendChild(Parent);
    Parent.AppendChild(Child);

    // div span matches grandchild through descendant combinator
    Sel := ParseSelectorListFromCSS('div span');
    try
      AssertTrue('div span matches grandchild', MatchesSelectorList(Sel, Child, Spec));
    finally
      Sel.Free();
    end;
  finally
    Grandparent.Free();
  end;
end;

procedure TCSSCascadeMatchingTest.TestAdjacentSiblingCombinator();
var
  Parent, S1, S2, S3: TCSSMockElement;
  Sel               : TCSSSelectorList;
  Spec              : TCSSSpecificity;
begin
  Parent := TCSSMockElement.Create('div');
  S1     := TCSSMockElement.Create('h1');
  S2     := TCSSMockElement.Create('p');
  S3     := TCSSMockElement.Create('p');
  try
    Parent.AppendChild(S1);
    Parent.AppendChild(S2);
    Parent.AppendChild(S3);

    Sel := ParseSelectorListFromCSS('h1 + p');
    try
      AssertTrue('h1 + p matches immediately adjacent S2', MatchesSelectorList(Sel, S2, Spec));
      AssertFalse('h1 + p does not match non-adjacent S3', MatchesSelectorList(Sel, S3, Spec));
    finally
      Sel.Free();
    end;
  finally
    Parent.Free();
  end;
end;

procedure TCSSCascadeMatchingTest.TestGeneralSiblingCombinator();
var
  Parent, S1, S2, S3: TCSSMockElement;
  Sel               : TCSSSelectorList;
  Spec              : TCSSSpecificity;
begin
  Parent := TCSSMockElement.Create('div');
  S1     := TCSSMockElement.Create('h1');
  S2     := TCSSMockElement.Create('p');
  S3     := TCSSMockElement.Create('p');
  try
    Parent.AppendChild(S1);
    Parent.AppendChild(S2);
    Parent.AppendChild(S3);

    Sel := ParseSelectorListFromCSS('h1 ~ p');
    try
      AssertTrue('h1 ~ p matches first following sibling S2', MatchesSelectorList(Sel, S2, Spec));
      AssertTrue('h1 ~ p matches second following sibling S3', MatchesSelectorList(Sel, S3, Spec));
    finally
      Sel.Free();
    end;
  finally
    Parent.Free();
  end;
end;

// ── TCSSCascadeResolutionTest ───────────────────────────────────────────────

procedure TCSSCascadeResolutionTest.TestSpecificityPrecedence();
var
  Resolver: TCSSStyleResolver;
  El      : TCSSMockElement;
  Style   : TCSSStyleBlock;
begin
  Resolver := TCSSStyleResolver.Create();
  El       := TCSSMockElement.Create('button', 'submit-btn');
  try
    El.AddClass('btn');
    // Three rules matching El:
    // button -> (0,0,1)
    // .btn   -> (0,1,0)
    // #submit-btn -> (1,0,0)
    Resolver.AddCSS('button { color: red; }');
    Resolver.AddCSS('.btn { color: green; }');
    Resolver.AddCSS('#submit-btn { color: blue; }');

    Style := Resolver.ResolveStyle(El);
    try
      AssertNotNull('Style resolved', Style);
      AssertTrue('Has color', Style.HasProperty(cpiColor));
      // ID rule has highest specificity -> blue
      AssertEquals(255, Style.GetDeclaration(cpiColor).Value.Color.B);
    finally
      Style.Free();
    end;
  finally
    El.Free();
    Resolver.Free();
  end;
end;

procedure TCSSCascadeResolutionTest.TestImportancePrecedence();
var
  Resolver: TCSSStyleResolver;
  El      : TCSSMockElement;
  Style   : TCSSStyleBlock;
begin
  Resolver := TCSSStyleResolver.Create();
  El       := TCSSMockElement.Create('button', 'submit-btn');
  try
    // Low-specificity rule marked !important beats higher-specificity normal rule
    Resolver.AddCSS('button { color: red !important; }');
    Resolver.AddCSS('#submit-btn { color: blue; }');

    Style := Resolver.ResolveStyle(El);
    try
      AssertNotNull('Style resolved', Style);
      // button is red !important -> red wins despite #submit-btn higher specificity
      AssertEquals(255, Style.GetDeclaration(cpiColor).Value.Color.R);
      AssertTrue('Flag is important', Style.GetDeclaration(cpiColor).Important);
    finally
      Style.Free();
    end;
  finally
    El.Free();
    Resolver.Free();
  end;
end;

procedure TCSSCascadeResolutionTest.TestSourceOrderPrecedence();
var
  Resolver: TCSSStyleResolver;
  El      : TCSSMockElement;
  Style   : TCSSStyleBlock;
begin
  Resolver := TCSSStyleResolver.Create();
  El       := TCSSMockElement.Create('button');
  try
    El.AddClass('primary');
    El.AddClass('active');

    // Both rules have equal specificity (0,1,0). The later rule must win.
    Resolver.AddCSS('.primary { background-color: #ff0000; }');
    Resolver.AddCSS('.active { background-color: #00ff00; }');

    Style := Resolver.ResolveStyle(El);
    try
      AssertNotNull('Style resolved', Style);
      AssertTrue('Has bg color', Style.HasProperty(cpiBackgroundColor));
      AssertEquals(255, Style.GetDeclaration(cpiBackgroundColor).Value.Color.G);
    finally
      Style.Free();
    end;
  finally
    El.Free();
    Resolver.Free();
  end;
end;

procedure TCSSCascadeResolutionTest.TestPropertyInheritance();
var
  Resolver     : TCSSStyleResolver;
  ParentEl     : TCSSMockElement;
  ChildEl      : TCSSMockElement;
  ParentStyle  : TCSSStyleBlock;
  ChildStyle   : TCSSStyleBlock;
begin
  Resolver := TCSSStyleResolver.Create();
  ParentEl := TCSSMockElement.Create('div');
  ChildEl  := TCSSMockElement.Create('span');
  try
    ParentEl.AppendChild(ChildEl);

    // Parent has color (inherited) and margin (not inherited)
    Resolver.AddCSS('div { color: #123456; margin: 20px; }');

    ParentStyle := Resolver.ResolveStyle(ParentEl);
    try
      // Resolve child style passing parentStyle
      ChildStyle := Resolver.ResolveStyle(ChildEl, ParentStyle);
      try
        AssertNotNull('Child style resolved', ChildStyle);
        // color is inherited
        AssertTrue('Child inherited color', ChildStyle.HasProperty(cpiColor));
        AssertEquals($12, ChildStyle.GetDeclaration(cpiColor).Value.Color.R);

        // margin is not inherited
        AssertFalse('Child did not inherit margin', ChildStyle.HasProperty(cpiMarginTop));
      finally
        ChildStyle.Free();
      end;
    finally
      ParentStyle.Free();
    end;
  finally
    ParentEl.Free();
    Resolver.Free();
  end;
end;

procedure TCSSCascadeResolutionTest.TestMultipleRulesCombined();
var
  Resolver: TCSSStyleResolver;
  El      : TCSSMockElement;
  Style   : TCSSStyleBlock;
begin
  Resolver := TCSSStyleResolver.Create();
  El       := TCSSMockElement.Create('button', 'ok-btn');
  try
    El.AddClass('btn');

    Resolver.AddCSS('button { width: 120px; height: 40px; }');
    Resolver.AddCSS('.btn { display: flex; }');
    Resolver.AddCSS('#ok-btn { background-color: #0000ff; }');

    Style := Resolver.ResolveStyle(El);
    try
      AssertNotNull('Style resolved', Style);
      AssertEquals(120.0, Style.GetDeclaration(cpiWidth).Value.Length.Value);
      AssertEquals(40.0, Style.GetDeclaration(cpiHeight).Value.Length.Value);
      AssertTrue('Display is flex', Style.GetDeclaration(cpiDisplay).Value.AsDisplay() = cdFlex);
      AssertEquals(255, Style.GetDeclaration(cpiBackgroundColor).Value.Color.B);
    finally
      Style.Free();
    end;
  finally
    El.Free();
    Resolver.Free();
  end;
end;

initialization
  RegisterTest(TCSSCascadeMatchingTest);
  RegisterTest(TCSSCascadeResolutionTest);

end.
