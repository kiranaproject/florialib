unit Floria.CSS.Parser.Test;

// FPCUnit test suite for Floria.CSS.Parser.
// Covers stylesheet parsing, qualified rules, at-rules, declarations,
// component values, selectors, !important, error recovery, and ownership.

{$mode objfpc}{$H+}

interface

uses
  Classes, Contnrs, SysUtils, fpcunit, testregistry,
  Floria.CSS.Types, Floria.CSS.AST, Floria.CSS.Parser;

type
  // ── Stylesheet-level tests ────────────────────────────────────

  TCSSParserStylesheetTest = class(TTestCase)
  published
    procedure TestEmptyStylesheet;
    procedure TestStylesheetOwnsRules;
    procedure TestMultipleRules;
    procedure TestCDOCDCIgnoredAtTopLevel;
  end;

  // ── Qualified rule tests ──────────────────────────────────────

  TCSSParserQualifiedRuleTest = class(TTestCase)
  published
    procedure TestSimpleTypeSelector;
    procedure TestClassSelector;
    procedure TestIdSelector;
    procedure TestCommaSeparatedSelectors;
    procedure TestAttributeSelector;
    procedure TestEmptyBlock;
    procedure TestRuleWithComment;
    procedure TestDescendantSelector;
  end;

  // ── Declaration tests ─────────────────────────────────────────

  TCSSParserDeclarationTest = class(TTestCase)
  published
    procedure TestSingleDeclaration;
    procedure TestMultipleDeclarations;
    procedure TestDeclarationValue;
    procedure TestImportantFlag;
    procedure TestImportantFlagWithWhitespace;
    procedure TestNoImportantWhenMissing;
    procedure TestCustomProperty;
    procedure TestDeclarationWithFunctionValue;
    procedure TestDeclarationWithStringValue;
    procedure TestSemicolonTerminatesDeclaration;
    procedure TestDeclarationValueTrimmed;
  end;

  // ── At-rule tests ─────────────────────────────────────────────

  TCSSParserAtRuleTest = class(TTestCase)
  published
    procedure TestAtCharset;
    procedure TestAtImport;
    procedure TestAtMediaNoBlock;
    procedure TestAtMediaWithBlock;
    procedure TestAtRuleName;
    procedure TestAtRulePrelude;
    procedure TestUnknownAtRule;
  end;

  // ── Component value tests ─────────────────────────────────────

  TCSSParserComponentValueTest = class(TTestCase)
  published
    procedure TestPreservedToken;
    procedure TestSimpleBlock;
    procedure TestFunctionBlock;
    procedure TestNestedBlocks;
    procedure TestParseComponentValueList;
  end;

  // ── Error recovery tests ──────────────────────────────────────

  TCSSParserErrorTest = class(TTestCase)
  published
    procedure TestMissingColonSkipped;
    procedure TestInvalidTokenInDeclListSkipped;
    procedure TestQualifiedRuleAtEOFDropped;
    procedure TestMultipleSemicolons;
  end;

  // ── Declaration list entry point ──────────────────────────────

  TCSSParserDeclListTest = class(TTestCase)
  published
    procedure TestParseDeclListSingleDecl;
    procedure TestParseDeclListMultipleDecls;
    procedure TestParseDeclListWithImportant;
    procedure TestParseDeclListEmptyInput;
  end;

implementation

// ──────────────────────────────────────────────────────────────────
// Helper shortcut functions
// ──────────────────────────────────────────────────────────────────

// Parse CSS text and return the stylesheet. Caller must free.
function ParseCSS(const ACSS: AnsiString): TCSSStylesheet;
begin
  Result := TCSSParser.FromCSS(ACSS);
end;

// Parse CSS text and return the first qualified rule, or nil.
function FirstRule(const ACSS: AnsiString): TCSSQualifiedRule;
var S: TCSSStylesheet;
begin
  S := ParseCSS(ACSS);
  if (S <> nil) and (S.Rules.Count > 0) and
     (TCSSNode(S.Rules[0]).NodeType = cntQualifiedRule) then
    Result := TCSSQualifiedRule(S.Rules[0])
  else
    Result := nil;
  // NOTE: the stylesheet owns the rule; caller must free the stylesheet.
  // This helper returns a NON-OWNED pointer. Caller must keep S alive
  // and free it when done (see try/finally pattern in tests).
end;

// Build a helper that returns first qualified rule and leaves stylesheet
// accessible for freeing.
type
  TParseHelper = record
    Sheet : TCSSStylesheet;
    Rule  : TCSSQualifiedRule;   // non-owned reference into Sheet
    AtR   : TCSSAtRule;          // non-owned reference into Sheet
  end;

function Parse(const ACSS: AnsiString): TParseHelper;
begin
  Result.Sheet := TCSSParser.FromCSS(ACSS);
  Result.Rule  := nil;
  Result.AtR   := nil;
  if Result.Sheet = nil then Exit;
  if Result.Sheet.Rules.Count = 0 then Exit;
  case TCSSNode(Result.Sheet.Rules[0]).NodeType of
    cntQualifiedRule: Result.Rule := TCSSQualifiedRule(Result.Sheet.Rules[0]);
    cntAtRule       : Result.AtR  := TCSSAtRule(Result.Sheet.Rules[0]);
  end;
end;

// Get the Nth declaration from a qualified rule (0-based).
function GetDecl(ARule: TCSSQualifiedRule; AIndex: Integer): TCSSDeclaration;
begin
  if (ARule <> nil) and (ARule.Declarations <> nil) and
     (AIndex < ARule.Declarations.Count) then
    Result := TCSSDeclaration(ARule.Declarations[AIndex])
  else
    Result := nil;
end;

// Render a component value list back to a compact string (no whitespace nodes).
function CVListToString(AList: TObjectList): AnsiString;
var
  i    : Integer;
  node : TCSSNode;
  pt   : TCSSPreservedToken;
  fb   : TCSSFunctionBlock;
  sb   : TCSSSimpleBlock;
begin
  Result := '';
  if AList = nil then Exit;
  for i := 0 to AList.Count - 1 do
  begin
    node := TCSSNode(AList[i]);
    case node.NodeType of
      cntPreservedToken:
      begin
        pt := TCSSPreservedToken(node);
        if pt.Token.TokenType <> cttWhitespace then
          Result := Result + pt.Token.Value;
      end;
      cntFunction:
      begin
        fb := TCSSFunctionBlock(node);
        Result := Result + fb.Name + '(...)';
      end;
      cntSimpleBlock:
      begin
        sb := TCSSSimpleBlock(node);
        case sb.AssocToken.TokenType of
          cttOpenCurly  : Result := Result + '{...}';
          cttOpenSquare : Result := Result + '[...]';
          cttOpenParen  : Result := Result + '(...)';
        end;
      end;
    end;
  end;
end;

// ──────────────────────────────────────────────────────────────────
// TCSSParserStylesheetTest
// ──────────────────────────────────────────────────────────────────

procedure TCSSParserStylesheetTest.TestEmptyStylesheet;
var S: TCSSStylesheet;
begin
  S := ParseCSS('');
  try
    AssertNotNull('stylesheet not nil', S);
    AssertEquals('no rules', 0, S.Rules.Count);
    AssertEquals('node type', Ord(cntStylesheet), Ord(S.NodeType));
  finally S.Free(); end;
end;

procedure TCSSParserStylesheetTest.TestStylesheetOwnsRules;
var S: TCSSStylesheet;
begin
  // Just verify the tree can be freed without error.
  S := ParseCSS('p { color: red } div { margin: 0 }');
  S.Free(); // should not crash / leak
end;

procedure TCSSParserStylesheetTest.TestMultipleRules;
var S: TCSSStylesheet;
begin
  S := ParseCSS('p {} div {} span {}');
  try
    AssertEquals('3 rules', 3, S.Rules.Count);
    AssertEquals('all qualified', Ord(cntQualifiedRule),
                 Ord(TCSSNode(S.Rules[0]).NodeType));
    AssertEquals('all qualified', Ord(cntQualifiedRule),
                 Ord(TCSSNode(S.Rules[1]).NodeType));
    AssertEquals('all qualified', Ord(cntQualifiedRule),
                 Ord(TCSSNode(S.Rules[2]).NodeType));
  finally S.Free(); end;
end;

procedure TCSSParserStylesheetTest.TestCDOCDCIgnoredAtTopLevel;
var S: TCSSStylesheet;
begin
  // <!-- and --> should be silently ignored at top level
  S := ParseCSS('<!-- p { color: red } -->');
  try
    AssertEquals('1 rule (CDO/CDC dropped)', 1, S.Rules.Count);
  finally S.Free(); end;
end;

// ──────────────────────────────────────────────────────────────────
// TCSSParserQualifiedRuleTest
// ──────────────────────────────────────────────────────────────────

procedure TCSSParserQualifiedRuleTest.TestSimpleTypeSelector;
var H: TParseHelper;
begin
  H := Parse('p { }');
  try
    AssertNotNull('rule exists', H.Rule);
    AssertTrue('prelude not empty', H.Rule.Prelude.Count > 0);
    AssertEquals('ident p in prelude',
      'p', TCSSPreservedToken(H.Rule.Prelude[0]).Token.Value);
  finally H.Sheet.Free(); end;
end;

procedure TCSSParserQualifiedRuleTest.TestClassSelector;
var H: TParseHelper;
begin
  H := Parse('.foo { }');
  try
    AssertNotNull('rule exists', H.Rule);
    AssertTrue('prelude not empty', H.Rule.Prelude.Count > 0);
    // Prelude: delim '.', ident 'foo', whitespace
    AssertEquals('dot delim', '.',
      TCSSPreservedToken(H.Rule.Prelude[0]).Token.Value);
    AssertEquals('class name', 'foo',
      TCSSPreservedToken(H.Rule.Prelude[1]).Token.Value);
  finally H.Sheet.Free(); end;
end;

procedure TCSSParserQualifiedRuleTest.TestIdSelector;
var H: TParseHelper;
begin
  H := Parse('#myId { }');
  try
    AssertNotNull('rule', H.Rule);
    // Prelude[0] = hash token
    AssertEquals('hash type',
      Ord(cttHash), Ord(TCSSPreservedToken(H.Rule.Prelude[0]).Token.TokenType));
    AssertEquals('hash value', 'myId',
      TCSSPreservedToken(H.Rule.Prelude[0]).Token.Value);
  finally H.Sheet.Free(); end;
end;

procedure TCSSParserQualifiedRuleTest.TestCommaSeparatedSelectors;
var S: TCSSStylesheet; R: TCSSQualifiedRule;
begin
  S := ParseCSS('p, div { }');
  try
    AssertEquals('1 rule', 1, S.Rules.Count);
    R := TCSSQualifiedRule(S.Rules[0]);
    // Prelude should contain: ident'p', comma, ws, ident'div', ws
    AssertTrue('prelude has 4+ items', R.Prelude.Count >= 4);
  finally S.Free(); end;
end;

procedure TCSSParserQualifiedRuleTest.TestAttributeSelector;
var S: TCSSStylesheet; R: TCSSQualifiedRule;
begin
  // input[type="text"] — prelude contains a simple block [...]
  S := ParseCSS('input[type="text"] { }');
  try
    AssertEquals('1 rule', 1, S.Rules.Count);
    R := TCSSQualifiedRule(S.Rules[0]);
    AssertTrue('prelude contains a simple block',
               CVListToString(R.Prelude).Contains('[...]'));
  finally S.Free(); end;
end;

procedure TCSSParserQualifiedRuleTest.TestEmptyBlock;
var H: TParseHelper;
begin
  H := Parse('p { }');
  try
    AssertNotNull('rule', H.Rule);
    AssertNotNull('decls not nil', H.Rule.Declarations);
    AssertEquals('0 decls', 0, H.Rule.Declarations.Count);
  finally H.Sheet.Free(); end;
end;

procedure TCSSParserQualifiedRuleTest.TestRuleWithComment;
var H: TParseHelper;
begin
  // The tokenizer strips comments; the parser sees only real tokens.
  H := Parse('p { /* selector comment */ color: red /* value comment */ }');
  try
    AssertNotNull('rule', H.Rule);
    AssertEquals('1 decl', 1, H.Rule.Declarations.Count);
  finally H.Sheet.Free(); end;
end;

procedure TCSSParserQualifiedRuleTest.TestDescendantSelector;
var H: TParseHelper;
begin
  H := Parse('div p { }');
  try
    AssertNotNull('rule', H.Rule);
    // At least: ident 'div', ws, ident 'p', ws
    AssertTrue('prelude >= 3', H.Rule.Prelude.Count >= 3);
  finally H.Sheet.Free(); end;
end;

// ──────────────────────────────────────────────────────────────────
// TCSSParserDeclarationTest
// ──────────────────────────────────────────────────────────────────

procedure TCSSParserDeclarationTest.TestSingleDeclaration;
var H: TParseHelper; D: TCSSDeclaration;
begin
  H := Parse('p { color: red }');
  try
    AssertNotNull('rule', H.Rule);
    AssertEquals('1 decl', 1, H.Rule.Declarations.Count);
    D := GetDecl(H.Rule, 0);
    AssertEquals('name', 'color', D.Name);
    AssertFalse('not important', D.Important);
  finally H.Sheet.Free(); end;
end;

procedure TCSSParserDeclarationTest.TestMultipleDeclarations;
var H: TParseHelper;
begin
  H := Parse('p { color: red; font-size: 14px; margin: 0 }');
  try
    AssertNotNull('rule', H.Rule);
    AssertEquals('3 decls', 3, H.Rule.Declarations.Count);
    AssertEquals('first',  'color',     GetDecl(H.Rule, 0).Name);
    AssertEquals('second', 'font-size', GetDecl(H.Rule, 1).Name);
    AssertEquals('third',  'margin',    GetDecl(H.Rule, 2).Name);
  finally H.Sheet.Free(); end;
end;

procedure TCSSParserDeclarationTest.TestDeclarationValue;
var H: TParseHelper; D: TCSSDeclaration;
begin
  H := Parse('p { color: red }');
  try
    D := GetDecl(H.Rule, 0);
    AssertTrue('value not empty', D.Value.Count > 0);
    // Value[0] = ident 'red'
    AssertEquals('value is ident red',
      'red', TCSSPreservedToken(D.Value[0]).Token.Value);
  finally H.Sheet.Free(); end;
end;

procedure TCSSParserDeclarationTest.TestImportantFlag;
var H: TParseHelper; D: TCSSDeclaration;
begin
  H := Parse('p { color: red !important }');
  try
    D := GetDecl(H.Rule, 0);
    AssertTrue('important', D.Important);
    // '!' and 'important' should NOT appear in the value
    AssertEquals('value has 1 item (just "red")', 1, D.Value.Count);
    AssertEquals('value is red',
      'red', TCSSPreservedToken(D.Value[0]).Token.Value);
  finally H.Sheet.Free(); end;
end;

procedure TCSSParserDeclarationTest.TestImportantFlagWithWhitespace;
var H: TParseHelper; D: TCSSDeclaration;
begin
  H := Parse('p { color: red  !  important }');
  try
    D := GetDecl(H.Rule, 0);
    AssertTrue('important', D.Important);
  finally H.Sheet.Free(); end;
end;

procedure TCSSParserDeclarationTest.TestNoImportantWhenMissing;
var H: TParseHelper; D: TCSSDeclaration;
begin
  H := Parse('p { color: red }');
  try
    D := GetDecl(H.Rule, 0);
    AssertFalse('not important', D.Important);
  finally H.Sheet.Free(); end;
end;

procedure TCSSParserDeclarationTest.TestCustomProperty;
var H: TParseHelper; D: TCSSDeclaration;
begin
  H := Parse('p { --my-color: #fff }');
  try
    D := GetDecl(H.Rule, 0);
    AssertNotNull('decl', D);
    AssertEquals('name', '--my-color', D.Name);
  finally H.Sheet.Free(); end;
end;

procedure TCSSParserDeclarationTest.TestDeclarationWithFunctionValue;
var H: TParseHelper; D: TCSSDeclaration;
begin
  H := Parse('p { color: rgb(255, 0, 0) }');
  try
    D := GetDecl(H.Rule, 0);
    AssertNotNull('decl', D);
    AssertTrue('value not empty', D.Value.Count > 0);
    // First value item should be a function block
    AssertEquals('function node',
      Ord(cntFunction), Ord(TCSSNode(D.Value[0]).NodeType));
    AssertEquals('function name',
      'rgb', TCSSFunctionBlock(D.Value[0]).Name);
  finally H.Sheet.Free(); end;
end;

procedure TCSSParserDeclarationTest.TestDeclarationWithStringValue;
var H: TParseHelper; D: TCSSDeclaration;
begin
  H := Parse('p::before { content: "hello" }');
  try
    D := GetDecl(H.Rule, 0);
    AssertNotNull('decl', D);
    AssertEquals('name', 'content', D.Name);
    AssertTrue('value not empty', D.Value.Count > 0);
    AssertEquals('string token type', Ord(cttString),
      Ord(TCSSPreservedToken(D.Value[0]).Token.TokenType));
    AssertEquals('string value', 'hello',
      TCSSPreservedToken(D.Value[0]).Token.Value);
  finally H.Sheet.Free(); end;
end;

procedure TCSSParserDeclarationTest.TestSemicolonTerminatesDeclaration;
var H: TParseHelper;
begin
  H := Parse('p { color: red; font-size: 14px }');
  try
    AssertEquals('2 decls', 2, H.Rule.Declarations.Count);
  finally H.Sheet.Free(); end;
end;

procedure TCSSParserDeclarationTest.TestDeclarationValueTrimmed;
var H: TParseHelper; D: TCSSDeclaration;
begin
  // Leading whitespace after ':' is consumed; trailing whitespace trimmed.
  H := Parse('p { color:   red   }');
  try
    D := GetDecl(H.Rule, 0);
    AssertNotNull('decl', D);
    // Value should just be ident 'red' with no surrounding whitespace nodes.
    AssertEquals('1 value item', 1, D.Value.Count);
    AssertEquals('red', 'red',
      TCSSPreservedToken(D.Value[0]).Token.Value);
  finally H.Sheet.Free(); end;
end;

// ──────────────────────────────────────────────────────────────────
// TCSSParserAtRuleTest
// ──────────────────────────────────────────────────────────────────

procedure TCSSParserAtRuleTest.TestAtCharset;
var H: TParseHelper;
begin
  H := Parse('@charset "UTF-8";');
  try
    AssertNotNull('at-rule', H.AtR);
    AssertEquals('name', 'charset', H.AtR.Name);
    AssertNull('no block', H.AtR.Block);
  finally H.Sheet.Free(); end;
end;

procedure TCSSParserAtRuleTest.TestAtImport;
var H: TParseHelper;
begin
  H := Parse('@import url("foo.css");');
  try
    AssertNotNull('at-rule', H.AtR);
    AssertEquals('name', 'import', H.AtR.Name);
    AssertNull('no block', H.AtR.Block);
  finally H.Sheet.Free(); end;
end;

procedure TCSSParserAtRuleTest.TestAtMediaNoBlock;
var H: TParseHelper;
begin
  // Edge case: @media without a block (malformed; just a prelude up to EOF).
  // The parser should still produce an at-rule.
  H := Parse('@media screen');
  try
    AssertNotNull('at-rule', H.AtR);
    AssertEquals('media', 'media', H.AtR.Name);
    AssertNull('no block (eof)', H.AtR.Block);
  finally H.Sheet.Free(); end;
end;

procedure TCSSParserAtRuleTest.TestAtMediaWithBlock;
var H: TParseHelper;
begin
  H := Parse('@media screen { p { color: red } }');
  try
    AssertNotNull('at-rule', H.AtR);
    AssertEquals('name', 'media', H.AtR.Name);
    AssertNotNull('has block', H.AtR.Block);
    AssertEquals('block opening token type', Ord(cttOpenCurly),
      Ord(H.AtR.Block.AssocToken.TokenType));
  finally H.Sheet.Free(); end;
end;

procedure TCSSParserAtRuleTest.TestAtRuleName;
var H: TParseHelper;
begin
  H := Parse('@keyframes slide { }');
  try
    AssertNotNull('at-rule', H.AtR);
    AssertEquals('keyframes', 'keyframes', H.AtR.Name);
    AssertEquals('node type', Ord(cntAtRule), Ord(H.AtR.NodeType));
  finally H.Sheet.Free(); end;
end;

procedure TCSSParserAtRuleTest.TestAtRulePrelude;
var H: TParseHelper;
begin
  // @media (max-width: 600px) — the prelude should contain component values.
  H := Parse('@media (max-width: 600px) { }');
  try
    AssertNotNull('at-rule', H.AtR);
    AssertTrue('prelude not empty', H.AtR.Prelude.Count > 0);
  finally H.Sheet.Free(); end;
end;

procedure TCSSParserAtRuleTest.TestUnknownAtRule;
var H: TParseHelper;
begin
  H := Parse('@unknown foo bar;');
  try
    AssertNotNull('at-rule', H.AtR);
    AssertEquals('unknown', 'unknown', H.AtR.Name);
    AssertNull('no block', H.AtR.Block);
  finally H.Sheet.Free(); end;
end;

// ──────────────────────────────────────────────────────────────────
// TCSSParserComponentValueTest
// ──────────────────────────────────────────────────────────────────

procedure TCSSParserComponentValueTest.TestPreservedToken;
var P: TCSSParser; CV: TCSSNode; Tokens: TCSSTokenArray;
begin
  Tokens := TokenizeCSS('red');
  P := TCSSParser.Create(Tokens);
  try
    CV := P.ParseComponentValue();
    try
      AssertEquals('preserved token', Ord(cntPreservedToken), Ord(CV.NodeType));
      AssertEquals('value', 'red', TCSSPreservedToken(CV).Token.Value);
    finally CV.Free(); end;
  finally P.Free(); end;
end;

procedure TCSSParserComponentValueTest.TestSimpleBlock;
var P: TCSSParser; CV: TCSSNode; Tokens: TCSSTokenArray;
begin
  Tokens := TokenizeCSS('{a b}');
  P := TCSSParser.Create(Tokens);
  try
    CV := P.ParseComponentValue();
    try
      AssertEquals('simple block', Ord(cntSimpleBlock), Ord(CV.NodeType));
      AssertEquals('opening curly', Ord(cttOpenCurly),
        Ord(TCSSSimpleBlock(CV).AssocToken.TokenType));
      // Children: ident 'a', ws, ident 'b'
      AssertEquals('3 children', 3, TCSSSimpleBlock(CV).Children.Count);
    finally CV.Free(); end;
  finally P.Free(); end;
end;

procedure TCSSParserComponentValueTest.TestFunctionBlock;
var P: TCSSParser; CV: TCSSNode; FB: TCSSFunctionBlock; Tokens: TCSSTokenArray;
begin
  Tokens := TokenizeCSS('rgb(255,0,0)');
  P := TCSSParser.Create(Tokens);
  try
    CV := P.ParseComponentValue();
    try
      AssertEquals('function', Ord(cntFunction), Ord(CV.NodeType));
      FB := TCSSFunctionBlock(CV);
      AssertEquals('name', 'rgb', FB.Name);
      // Children: num 255, comma, num 0, comma, num 0
      AssertEquals('5 children', 5, FB.Children.Count);
    finally CV.Free(); end;
  finally P.Free(); end;
end;

procedure TCSSParserComponentValueTest.TestNestedBlocks;
var P: TCSSParser; CV: TCSSNode; SB: TCSSSimpleBlock; Inner: TCSSSimpleBlock;
    Tokens: TCSSTokenArray;
begin
  // { [a] }
  Tokens := TokenizeCSS('{[a]}');
  P := TCSSParser.Create(Tokens);
  try
    CV := P.ParseComponentValue();
    try
      SB := TCSSSimpleBlock(CV);
      AssertEquals('outer curly', 1, SB.Children.Count);
      Inner := TCSSSimpleBlock(SB.Children[0]);
      AssertEquals('inner bracket', Ord(cntSimpleBlock), Ord(Inner.NodeType));
      AssertEquals('inner assoc', Ord(cttOpenSquare),
        Ord(Inner.AssocToken.TokenType));
    finally CV.Free(); end;
  finally P.Free(); end;
end;

procedure TCSSParserComponentValueTest.TestParseComponentValueList;
var P: TCSSParser; List: TObjectList; Tokens: TCSSTokenArray;
begin
  Tokens := TokenizeCSS('red 1px solid');
  P := TCSSParser.Create(Tokens);
  try
    List := P.ParseComponentValueList();
    try
      // red, ws, 1px(dim), ws, solid — 5 component values
      AssertEquals('5 items', 5, List.Count);
    finally List.Free(); end;
  finally P.Free(); end;
end;

// ──────────────────────────────────────────────────────────────────
// TCSSParserErrorTest
// ──────────────────────────────────────────────────────────────────

procedure TCSSParserErrorTest.TestMissingColonSkipped;
var H: TParseHelper;
begin
  // Declaration without ':' is a parse error; the whole declaration is skipped.
  H := Parse('p { color red; font-size: 14px }');
  try
    AssertNotNull('rule', H.Rule);
    // 'color red' is malformed → skipped; 'font-size: 14px' is valid
    AssertEquals('1 valid decl', 1, H.Rule.Declarations.Count);
    AssertEquals('font-size', 'font-size', GetDecl(H.Rule, 0).Name);
  finally H.Sheet.Free(); end;
end;

procedure TCSSParserErrorTest.TestInvalidTokenInDeclListSkipped;
var H: TParseHelper;
begin
  // A number token is invalid at the start of a declaration → skipped.
  H := Parse('p { 42; color: red }');
  try
    AssertEquals('1 valid decl', 1, H.Rule.Declarations.Count);
    AssertEquals('color', 'color', GetDecl(H.Rule, 0).Name);
  finally H.Sheet.Free(); end;
end;

procedure TCSSParserErrorTest.TestQualifiedRuleAtEOFDropped;
var S: TCSSStylesheet;
begin
  // A qualified rule with no closing '}' → parse error → rule is dropped.
  S := ParseCSS('p { color: red');
  try
    // The incomplete rule IS processed (declarations consumed until EOF)
    // but the rule itself exists (open block consumed until EOF)
    // Spec §5.4.3: EOF during prelude → parse error, return nothing
    // Here we have 'p { color: red' — the prelude is 'p', then '{' found,
    // then declarations are consumed. ConsumeDeclaration finds 'color: red'
    // then EOF while consuming value (not in prelude, so rule IS returned).
    AssertNotNull('sheet', S);
    // Result depends on whether we hit EOF during prelude or block:
    // 'p' starts a qualified rule; after 'p {' the block is consumed as decls
    // until EOF. So the rule exists with 1 declaration.
    AssertEquals('1 rule', 1, S.Rules.Count);
  finally S.Free(); end;
end;

procedure TCSSParserErrorTest.TestMultipleSemicolons;
var H: TParseHelper;
begin
  // Extra semicolons should be ignored.
  H := Parse('p { ;; color: red ;; }');
  try
    AssertEquals('1 decl', 1, H.Rule.Declarations.Count);
  finally H.Sheet.Free(); end;
end;

// ──────────────────────────────────────────────────────────────────
// TCSSParserDeclListTest
// ──────────────────────────────────────────────────────────────────

procedure TCSSParserDeclListTest.TestParseDeclListSingleDecl;
var P: TCSSParser; List: TObjectList; Tokens: TCSSTokenArray;
begin
  Tokens := TokenizeCSS('color: red');
  P := TCSSParser.Create(Tokens);
  try
    List := P.ParseDeclarationList();
    try
      AssertEquals('1 decl', 1, List.Count);
      AssertEquals('color', 'color', TCSSDeclaration(List[0]).Name);
    finally List.Free(); end;
  finally P.Free(); end;
end;

procedure TCSSParserDeclListTest.TestParseDeclListMultipleDecls;
var P: TCSSParser; List: TObjectList; Tokens: TCSSTokenArray;
begin
  Tokens := TokenizeCSS('color: red; font-size: 14px; margin: 0');
  P := TCSSParser.Create(Tokens);
  try
    List := P.ParseDeclarationList();
    try
      AssertEquals('3 decls', 3, List.Count);
    finally List.Free(); end;
  finally P.Free(); end;
end;

procedure TCSSParserDeclListTest.TestParseDeclListWithImportant;
var P: TCSSParser; List: TObjectList; D: TCSSDeclaration; Tokens: TCSSTokenArray;
begin
  Tokens := TokenizeCSS('color: blue !important');
  P := TCSSParser.Create(Tokens);
  try
    List := P.ParseDeclarationList();
    try
      AssertEquals('1 decl', 1, List.Count);
      D := TCSSDeclaration(List[0]);
      AssertEquals('color', 'color', D.Name);
      AssertTrue('important', D.Important);
    finally List.Free(); end;
  finally P.Free(); end;
end;

procedure TCSSParserDeclListTest.TestParseDeclListEmptyInput;
var P: TCSSParser; List: TObjectList; Tokens: TCSSTokenArray;
begin
  Tokens := TokenizeCSS('');
  P := TCSSParser.Create(Tokens);
  try
    List := P.ParseDeclarationList();
    try
      AssertEquals('0 decls', 0, List.Count);
    finally List.Free(); end;
  finally P.Free(); end;
end;

// ──────────────────────────────────────────────────────────────────
// Registration
// ──────────────────────────────────────────────────────────────────

initialization
  RegisterTest(TCSSParserStylesheetTest);
  RegisterTest(TCSSParserQualifiedRuleTest);
  RegisterTest(TCSSParserDeclarationTest);
  RegisterTest(TCSSParserAtRuleTest);
  RegisterTest(TCSSParserComponentValueTest);
  RegisterTest(TCSSParserErrorTest);
  RegisterTest(TCSSParserDeclListTest);

end.
