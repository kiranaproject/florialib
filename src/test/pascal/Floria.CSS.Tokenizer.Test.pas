unit Floria.CSS.Tokenizer.Test;

// FPCUnit test suite for Floria.CSS.Tokenizer.
// Covers all 25 token types, position tracking, error recovery,
// multi-chunk streaming, encoding (BOM), and comment stripping.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Floria.CSS.Types, Floria.CSS.Tokenizer;

type
  // ── Helpers ──────────────────────────────────────────────────

  // Collects tokens emitted by the tokenizer into a plain array.
  // Implements IInterface manually with no-op _AddRef/_Release so the object
  // lifetime is controlled with try/finally C.Free() rather than refcounting.
  TTokenCollector = class(TObject, ICSSTokenListener)
  private
    FTokens : array of TCSSToken;
    FCount  : Integer;
  protected
    // IInterface — manual, non-refcounted implementation
    function QueryInterface(constref IID: TGUID; out Obj): HResult; cdecl;
    function _AddRef(): Integer; cdecl;
    function _Release(): Integer; cdecl;
  public
    constructor Create();
    procedure   OnToken(const AToken: TCSSToken);
    function    Count(): Integer;
    function    GetToken(AIndex: Integer): TCSSToken;
    procedure   Clear();
  end;

  // ── Test cases ───────────────────────────────────────────────

  TCSSTokenizerWhitespaceTest = class(TTestCase)
  published
    procedure TestSingleSpace;
    procedure TestMultipleSpaces;
    procedure TestTab;
    procedure TestNewline;
    procedure TestMixedWhitespaceCollapsed;
    procedure TestWhitespaceThenIdent;
  end;

  TCSSTokenizerIdentTest = class(TTestCase)
  published
    procedure TestSimpleIdent;
    procedure TestUpperCaseIdent;
    procedure TestHyphenPrefixIdent;
    procedure TestUnderscorePrefixIdent;
    procedure TestCustomProperty;
    procedure TestEscapedCharInIdent;
  end;

  TCSSTokenizerStringTest = class(TTestCase)
  published
    procedure TestDoubleQuotedString;
    procedure TestSingleQuotedString;
    procedure TestEmptyString;
    procedure TestStringWithEscapedNewline;
    procedure TestUnterminatedString;
    procedure TestBadStringNewlineInMiddle;
  end;

  TCSSTokenizerNumericTest = class(TTestCase)
  published
    procedure TestInteger;
    procedure TestNegativeInteger;
    procedure TestDecimalNumber;
    procedure TestScientificNumber;
    procedure TestPercentage;
    procedure TestDimensionPx;
    procedure TestDimensionEm;
    procedure TestDimensionNegative;
    procedure TestDimensionFractional;
    procedure TestNumberFlagInteger;
    procedure TestNumberFlagDecimal;
  end;

  TCSSTokenizerHashTest = class(TTestCase)
  published
    procedure TestHashID;
    procedure TestHashUnrestricted;
    procedure TestHashNoIdent;
  end;

  TCSSTokenizerUrlTest = class(TTestCase)
  published
    procedure TestBareUrl;
    procedure TestBareUrlWithWhitespace;
    procedure TestQuotedUrlBecomesFunction;
    procedure TestBadUrlWithSpace;
    procedure TestBadUrlWithQuote;
    procedure TestEmptyUrl;
  end;

  TCSSTokenizerCommentTest = class(TTestCase)
  published
    procedure TestCommentOnly;
    procedure TestCommentBetweenTokens;
    procedure TestMultipleConsecutiveComments;
    procedure TestUnterminatedComment;
  end;

  TCSSTokenizerAtKeywordTest = class(TTestCase)
  published
    procedure TestAtMedia;
    procedure TestAtCharset;
    procedure TestAtUnknown;
    procedure TestAtWithNoIdent;
  end;

  TCSSTokenizerDelimTest = class(TTestCase)
  published
    procedure TestSlash;
    procedure TestAsterisk;
    procedure TestTilde;
    procedure TestPipe;
    procedure TestHashDelim;
    procedure TestAtDelim;
  end;

  TCSSTokenizerCDOCDCTest = class(TTestCase)
  published
    procedure TestCDO;
    procedure TestCDC;
    procedure TestLessThanNotCDO;
    procedure TestDashNotCDC;
  end;

  TCSSTokenizerPunctuationTest = class(TTestCase)
  published
    procedure TestColon;
    procedure TestSemicolon;
    procedure TestComma;
    procedure TestBrackets;
    procedure TestParens;
    procedure TestCurlies;
  end;

  TCSSTokenizerPositionTest = class(TTestCase)
  published
    procedure TestFirstTokenAt1_1;
    procedure TestPositionAfterNewline;
    procedure TestColumnIncrement;
    procedure TestEOFPosition;
  end;

  TCSSTokenizerStreamingTest = class(TTestCase)
  published
    procedure TestSingleChunk;
    procedure TestTwoChunks;
    procedure TestIdentAcrossChunks;
    procedure TestStringAcrossChunks;
    procedure TestEmptyFeeds;
  end;

  TCSSTokenizerEncodingTest = class(TTestCase)
  published
    procedure TestBOMStripped;
    procedure TestNoBOMUnaffected;
    procedure TestNulReplacedWithFFFD;
    procedure TestCRLFNormalized;
    procedure TestCRNormalized;
    procedure TestFFNormalized;
  end;

  TCSSTokenizerFunctionTest = class(TTestCase)
  published
    procedure TestRgbFunction;
    procedure TestUrlFunction;
    procedure TestNestedFunctionName;
  end;

implementation

// ──────────────────────────────────────────────────────────────
// TTokenCollector
// ──────────────────────────────────────────────────────────────

constructor TTokenCollector.Create();
begin
  inherited Create();
  FCount := 0;
  SetLength(FTokens, 0);
end;

function TTokenCollector.QueryInterface(constref IID: TGUID; out Obj): HResult; cdecl;
begin
  if GetInterface(IID, Obj) then Result := S_OK else Result := E_NOINTERFACE;
end;

function TTokenCollector._AddRef(): Integer; cdecl;
begin
  Result := -1; // disable automatic reference-count destruction
end;

function TTokenCollector._Release(): Integer; cdecl;
begin
  Result := -1; // lifetime managed manually via try/finally C.Free()
end;

procedure TTokenCollector.OnToken(const AToken: TCSSToken);
begin
  if FCount >= Length(FTokens) then
    SetLength(FTokens, FCount + 32);
  FTokens[FCount] := AToken;
  Inc(FCount);
end;

function TTokenCollector.Count(): Integer;
begin
  Result := FCount;
end;

function TTokenCollector.GetToken(AIndex: Integer): TCSSToken;
begin
  Result := FTokens[AIndex];
end;

procedure TTokenCollector.Clear();
begin
  FCount := 0;
end;

// ──────────────────────────────────────────────────────────────
// Helper: tokenise a CSS string and return the collector.
// Caller is responsible for freeing the collector.
// ──────────────────────────────────────────────────────────────

function Tokenize(const ACSS: AnsiString): TTokenCollector;
var
  Tok : TCSSTokenizer;
begin
  Result := TTokenCollector.Create();
  Tok    := TCSSTokenizer.Create(Result);
  try
    Tok.Feed(ACSS);
    Tok.Finish();
  finally
    Tok.Free();
  end;
end;

// Helper: tokenise across two chunks.
function Tokenize2(const AChunk1, AChunk2: AnsiString): TTokenCollector;
var
  Tok : TCSSTokenizer;
begin
  Result := TTokenCollector.Create();
  Tok    := TCSSTokenizer.Create(Result);
  try
    Tok.Feed(AChunk1);
    Tok.Feed(AChunk2);
    Tok.Finish();
  finally
    Tok.Free();
  end;
end;

// ──────────────────────────────────────────────────────────────
// Whitespace tests
// ──────────────────────────────────────────────────────────────

procedure TCSSTokenizerWhitespaceTest.TestSingleSpace;
var C: TTokenCollector;
begin
  C := Tokenize(' ');
  try
    AssertEquals('token count', 2, C.Count());
    AssertEquals('type[0]', Ord(cttWhitespace), Ord(C.GetToken(0).TokenType));
    AssertEquals('type[1]', Ord(cttEOF),        Ord(C.GetToken(1).TokenType));
  finally C.Free(); end;
end;

procedure TCSSTokenizerWhitespaceTest.TestMultipleSpaces;
var C: TTokenCollector;
begin
  C := Tokenize('   ');
  try
    AssertEquals('token count', 2, C.Count());
    AssertEquals('type[0]', Ord(cttWhitespace), Ord(C.GetToken(0).TokenType));
  finally C.Free(); end;
end;

procedure TCSSTokenizerWhitespaceTest.TestTab;
var C: TTokenCollector;
begin
  C := Tokenize(#$09);
  try
    AssertEquals('token count', 2, C.Count());
    AssertEquals('type', Ord(cttWhitespace), Ord(C.GetToken(0).TokenType));
  finally C.Free(); end;
end;

procedure TCSSTokenizerWhitespaceTest.TestNewline;
var C: TTokenCollector;
begin
  C := Tokenize(#$0A);
  try
    AssertEquals('token count', 2, C.Count());
    AssertEquals('type', Ord(cttWhitespace), Ord(C.GetToken(0).TokenType));
  finally C.Free(); end;
end;

procedure TCSSTokenizerWhitespaceTest.TestMixedWhitespaceCollapsed;
var C: TTokenCollector;
begin
  // Multiple different whitespace characters collapse into one token
  C := Tokenize(' '#$09#$0A' ');
  try
    AssertEquals('one whitespace token', 2, C.Count());
    AssertEquals('type', Ord(cttWhitespace), Ord(C.GetToken(0).TokenType));
  finally C.Free(); end;
end;

procedure TCSSTokenizerWhitespaceTest.TestWhitespaceThenIdent;
var C: TTokenCollector;
begin
  C := Tokenize(' color');
  try
    AssertEquals('token count', 3, C.Count());
    AssertEquals('ws', Ord(cttWhitespace), Ord(C.GetToken(0).TokenType));
    AssertEquals('ident', Ord(cttIdent),   Ord(C.GetToken(1).TokenType));
    AssertEquals('value', 'color',          C.GetToken(1).Value);
  finally C.Free(); end;
end;

// ──────────────────────────────────────────────────────────────
// Identifier tests
// ──────────────────────────────────────────────────────────────

procedure TCSSTokenizerIdentTest.TestSimpleIdent;
var C: TTokenCollector;
begin
  C := Tokenize('color');
  try
    AssertEquals(2, C.Count());
    AssertEquals(Ord(cttIdent), Ord(C.GetToken(0).TokenType));
    AssertEquals('color', C.GetToken(0).Value);
  finally C.Free(); end;
end;

procedure TCSSTokenizerIdentTest.TestUpperCaseIdent;
var C: TTokenCollector;
begin
  // Identifiers are case-sensitive; the tokenizer preserves case.
  C := Tokenize('COLOR');
  try
    AssertEquals(2, C.Count());
    AssertEquals('COLOR', C.GetToken(0).Value);
  finally C.Free(); end;
end;

procedure TCSSTokenizerIdentTest.TestHyphenPrefixIdent;
var C: TTokenCollector;
begin
  C := Tokenize('-webkit-transform');
  try
    AssertEquals(2, C.Count());
    AssertEquals(Ord(cttIdent),        Ord(C.GetToken(0).TokenType));
    AssertEquals('-webkit-transform',  C.GetToken(0).Value);
  finally C.Free(); end;
end;

procedure TCSSTokenizerIdentTest.TestUnderscorePrefixIdent;
var C: TTokenCollector;
begin
  C := Tokenize('_private');
  try
    AssertEquals(2, C.Count());
    AssertEquals('_private', C.GetToken(0).Value);
  finally C.Free(); end;
end;

procedure TCSSTokenizerIdentTest.TestCustomProperty;
var C: TTokenCollector;
begin
  // CSS custom properties start with '--'
  C := Tokenize('--my-color');
  try
    AssertEquals(2, C.Count());
    AssertEquals(Ord(cttIdent), Ord(C.GetToken(0).TokenType));
    AssertEquals('--my-color', C.GetToken(0).Value);
  finally C.Free(); end;
end;

procedure TCSSTokenizerIdentTest.TestEscapedCharInIdent;
var C: TTokenCollector;
begin
  // '\41' is the hex escape for 'A'; result ident is 'Aolor'
  C := Tokenize('\41 olor');
  try
    AssertEquals(2, C.Count());
    AssertEquals(Ord(cttIdent), Ord(C.GetToken(0).TokenType));
    AssertEquals('Aolor', C.GetToken(0).Value);
  finally C.Free(); end;
end;

// ──────────────────────────────────────────────────────────────
// String tests
// ──────────────────────────────────────────────────────────────

procedure TCSSTokenizerStringTest.TestDoubleQuotedString;
var C: TTokenCollector;
begin
  C := Tokenize('"hello"');
  try
    AssertEquals(2, C.Count());
    AssertEquals(Ord(cttString), Ord(C.GetToken(0).TokenType));
    AssertEquals('hello', C.GetToken(0).Value);
  finally C.Free(); end;
end;

procedure TCSSTokenizerStringTest.TestSingleQuotedString;
var C: TTokenCollector;
begin
  C := Tokenize('''world''');
  try
    AssertEquals(2, C.Count());
    AssertEquals(Ord(cttString), Ord(C.GetToken(0).TokenType));
    AssertEquals('world', C.GetToken(0).Value);
  finally C.Free(); end;
end;

procedure TCSSTokenizerStringTest.TestEmptyString;
var C: TTokenCollector;
begin
  C := Tokenize('""');
  try
    AssertEquals(2, C.Count());
    AssertEquals(Ord(cttString), Ord(C.GetToken(0).TokenType));
    AssertEquals('', C.GetToken(0).Value);
  finally C.Free(); end;
end;

procedure TCSSTokenizerStringTest.TestStringWithEscapedNewline;
var C: TTokenCollector;
begin
  // '\' followed by LF means the newline is ignored inside the string value.
  C := Tokenize('"foo\'#$0A'bar"');
  try
    AssertEquals(2, C.Count());
    AssertEquals(Ord(cttString), Ord(C.GetToken(0).TokenType));
    AssertEquals('foobar', C.GetToken(0).Value);
  finally C.Free(); end;
end;

procedure TCSSTokenizerStringTest.TestUnterminatedString;
var C: TTokenCollector;
begin
  // EOF inside a string is a parse error; the string token is still emitted.
  C := Tokenize('"hello');
  try
    AssertEquals(2, C.Count());
    AssertEquals(Ord(cttString), Ord(C.GetToken(0).TokenType));
    AssertEquals('hello', C.GetToken(0).Value);
    AssertEquals(Ord(cttEOF), Ord(C.GetToken(1).TokenType));
  finally C.Free(); end;
end;

procedure TCSSTokenizerStringTest.TestBadStringNewlineInMiddle;
var C: TTokenCollector;
begin
  // A literal newline inside a string → <bad-string-token>.
  // After the bad-string, tokenisation resumes; the bare newline produces a
  // whitespace token.
  C := Tokenize('"foo'#$0A);
  try
    AssertTrue('at least 2 tokens', C.Count() >= 2);
    AssertEquals('bad-string', Ord(cttBadString), Ord(C.GetToken(0).TokenType));
    AssertEquals('bad-string value', 'foo', C.GetToken(0).Value);
    AssertEquals('whitespace after', Ord(cttWhitespace), Ord(C.GetToken(1).TokenType));
  finally C.Free(); end;
end;

// ──────────────────────────────────────────────────────────────
// Numeric tests
// ──────────────────────────────────────────────────────────────

procedure TCSSTokenizerNumericTest.TestInteger;
var C: TTokenCollector;
begin
  C := Tokenize('42');
  try
    AssertEquals(2, C.Count());
    AssertEquals(Ord(cttNumber), Ord(C.GetToken(0).TokenType));
    AssertEquals(42.0, C.GetToken(0).NumericVal, 1e-9);
  finally C.Free(); end;
end;

procedure TCSSTokenizerNumericTest.TestNegativeInteger;
var C: TTokenCollector;
begin
  C := Tokenize('-7');
  try
    AssertEquals(2, C.Count());
    AssertEquals(Ord(cttNumber), Ord(C.GetToken(0).TokenType));
    AssertEquals(-7.0, C.GetToken(0).NumericVal, 1e-9);
  finally C.Free(); end;
end;

procedure TCSSTokenizerNumericTest.TestDecimalNumber;
var C: TTokenCollector;
begin
  C := Tokenize('3.14');
  try
    AssertEquals(Ord(cttNumber), Ord(C.GetToken(0).TokenType));
    AssertEquals(3.14, C.GetToken(0).NumericVal, 1e-9);
  finally C.Free(); end;
end;

procedure TCSSTokenizerNumericTest.TestScientificNumber;
var C: TTokenCollector;
begin
  C := Tokenize('1e3');
  try
    AssertEquals(Ord(cttNumber),   Ord(C.GetToken(0).TokenType));
    AssertEquals(1000.0, C.GetToken(0).NumericVal, 1e-6);
    AssertEquals(Ord(cnfNumber),   Ord(C.GetToken(0).NumFlag));
  finally C.Free(); end;
end;

procedure TCSSTokenizerNumericTest.TestPercentage;
var C: TTokenCollector;
begin
  C := Tokenize('50%');
  try
    AssertEquals(2, C.Count());
    AssertEquals(Ord(cttPercentage), Ord(C.GetToken(0).TokenType));
    AssertEquals(50.0, C.GetToken(0).NumericVal, 1e-9);
  finally C.Free(); end;
end;

procedure TCSSTokenizerNumericTest.TestDimensionPx;
var C: TTokenCollector;
begin
  C := Tokenize('10px');
  try
    AssertEquals(2, C.Count());
    AssertEquals(Ord(cttDimension), Ord(C.GetToken(0).TokenType));
    AssertEquals(10.0, C.GetToken(0).NumericVal, 1e-9);
    AssertEquals('px',  C.GetToken(0).Unit_);
  finally C.Free(); end;
end;

procedure TCSSTokenizerNumericTest.TestDimensionEm;
var C: TTokenCollector;
begin
  C := Tokenize('2em');
  try
    AssertEquals(Ord(cttDimension), Ord(C.GetToken(0).TokenType));
    AssertEquals('em', C.GetToken(0).Unit_);
  finally C.Free(); end;
end;

procedure TCSSTokenizerNumericTest.TestDimensionNegative;
var C: TTokenCollector;
begin
  C := Tokenize('-3px');
  try
    AssertEquals(Ord(cttDimension), Ord(C.GetToken(0).TokenType));
    AssertEquals(-3.0, C.GetToken(0).NumericVal, 1e-9);
    AssertEquals('px', C.GetToken(0).Unit_);
  finally C.Free(); end;
end;

procedure TCSSTokenizerNumericTest.TestDimensionFractional;
var C: TTokenCollector;
begin
  C := Tokenize('1.5rem');
  try
    AssertEquals(Ord(cttDimension), Ord(C.GetToken(0).TokenType));
    AssertEquals(1.5, C.GetToken(0).NumericVal, 1e-9);
    AssertEquals('rem', C.GetToken(0).Unit_);
  finally C.Free(); end;
end;

procedure TCSSTokenizerNumericTest.TestNumberFlagInteger;
var C: TTokenCollector;
begin
  C := Tokenize('99');
  try
    AssertEquals(Ord(cnfInteger), Ord(C.GetToken(0).NumFlag));
  finally C.Free(); end;
end;

procedure TCSSTokenizerNumericTest.TestNumberFlagDecimal;
var C: TTokenCollector;
begin
  C := Tokenize('99.0');
  try
    AssertEquals(Ord(cnfNumber), Ord(C.GetToken(0).NumFlag));
  finally C.Free(); end;
end;

// ──────────────────────────────────────────────────────────────
// Hash tests
// ──────────────────────────────────────────────────────────────

procedure TCSSTokenizerHashTest.TestHashID;
var C: TTokenCollector;
begin
  C := Tokenize('#myId');
  try
    AssertEquals(2, C.Count());
    AssertEquals(Ord(cttHash), Ord(C.GetToken(0).TokenType));
    AssertEquals('myId', C.GetToken(0).Value);
    AssertEquals(Ord(chfID), Ord(C.GetToken(0).HashFlag));
  finally C.Free(); end;
end;

procedure TCSSTokenizerHashTest.TestHashUnrestricted;
var C: TTokenCollector;
begin
  // '#123' — starts with a digit; not a valid ident-start → unrestricted
  C := Tokenize('#123');
  try
    AssertEquals(Ord(cttHash), Ord(C.GetToken(0).TokenType));
    AssertEquals('123', C.GetToken(0).Value);
    AssertEquals(Ord(chfUnrestricted), Ord(C.GetToken(0).HashFlag));
  finally C.Free(); end;
end;

procedure TCSSTokenizerHashTest.TestHashNoIdent;
var C: TTokenCollector;
begin
  // '#' followed by space → <delim-token> '#', then whitespace
  C := Tokenize('# ');
  try
    AssertTrue('at least 2', C.Count() >= 2);
    AssertEquals(Ord(cttDelim), Ord(C.GetToken(0).TokenType));
    AssertEquals('#', C.GetToken(0).Value);
  finally C.Free(); end;
end;

// ──────────────────────────────────────────────────────────────
// URL tests
// ──────────────────────────────────────────────────────────────

procedure TCSSTokenizerUrlTest.TestBareUrl;
var C: TTokenCollector;
begin
  C := Tokenize('url(foo.png)');
  try
    AssertEquals(2, C.Count());
    AssertEquals(Ord(cttUrl), Ord(C.GetToken(0).TokenType));
    AssertEquals('foo.png', C.GetToken(0).Value);
  finally C.Free(); end;
end;

procedure TCSSTokenizerUrlTest.TestBareUrlWithWhitespace;
var C: TTokenCollector;
begin
  // Whitespace around the URL content is stripped
  C := Tokenize('url(  foo.png  )');
  try
    AssertEquals(Ord(cttUrl), Ord(C.GetToken(0).TokenType));
    AssertEquals('foo.png', C.GetToken(0).Value);
  finally C.Free(); end;
end;

procedure TCSSTokenizerUrlTest.TestQuotedUrlBecomesFunction;
var C: TTokenCollector;
begin
  // url("...") is a <function-token> followed by a <string-token>
  C := Tokenize('url("foo.png")');
  try
    AssertTrue('at least 3', C.Count() >= 3);
    AssertEquals(Ord(cttFunction),   Ord(C.GetToken(0).TokenType));
    AssertEquals('url',               C.GetToken(0).Value);
    AssertEquals(Ord(cttString),     Ord(C.GetToken(1).TokenType));
    AssertEquals('foo.png',           C.GetToken(1).Value);
    AssertEquals(Ord(cttCloseParen), Ord(C.GetToken(2).TokenType));
  finally C.Free(); end;
end;

procedure TCSSTokenizerUrlTest.TestBadUrlWithSpace;
var C: TTokenCollector;
begin
  // Space between url fragments → <bad-url-token>
  C := Tokenize('url(foo bar)');
  try
    AssertTrue('at least 1', C.Count() >= 1);
    AssertEquals(Ord(cttBadUrl), Ord(C.GetToken(0).TokenType));
  finally C.Free(); end;
end;

procedure TCSSTokenizerUrlTest.TestBadUrlWithQuote;
var C: TTokenCollector;
begin
  // Unescaped quote inside bare url → <bad-url-token>
  C := Tokenize('url(fo"o)');
  try
    AssertEquals(Ord(cttBadUrl), Ord(C.GetToken(0).TokenType));
  finally C.Free(); end;
end;

procedure TCSSTokenizerUrlTest.TestEmptyUrl;
var C: TTokenCollector;
begin
  C := Tokenize('url()');
  try
    AssertEquals(Ord(cttUrl), Ord(C.GetToken(0).TokenType));
    AssertEquals('', C.GetToken(0).Value);
  finally C.Free(); end;
end;

// ──────────────────────────────────────────────────────────────
// Comment tests
// ──────────────────────────────────────────────────────────────

procedure TCSSTokenizerCommentTest.TestCommentOnly;
var C: TTokenCollector;
begin
  // A standalone comment produces no tokens (only EOF)
  C := Tokenize('/* nothing here */');
  try
    AssertEquals(1, C.Count());
    AssertEquals(Ord(cttEOF), Ord(C.GetToken(0).TokenType));
  finally C.Free(); end;
end;

procedure TCSSTokenizerCommentTest.TestCommentBetweenTokens;
var C: TTokenCollector;
begin
  C := Tokenize('a/* comment */b');
  try
    AssertEquals(3, C.Count());
    AssertEquals(Ord(cttIdent), Ord(C.GetToken(0).TokenType));
    AssertEquals('a', C.GetToken(0).Value);
    AssertEquals(Ord(cttIdent), Ord(C.GetToken(1).TokenType));
    AssertEquals('b', C.GetToken(1).Value);
    AssertEquals(Ord(cttEOF),   Ord(C.GetToken(2).TokenType));
  finally C.Free(); end;
end;

procedure TCSSTokenizerCommentTest.TestMultipleConsecutiveComments;
var C: TTokenCollector;
begin
  C := Tokenize('/* a *//* b */x');
  try
    AssertEquals(2, C.Count());
    AssertEquals(Ord(cttIdent), Ord(C.GetToken(0).TokenType));
    AssertEquals('x', C.GetToken(0).Value);
  finally C.Free(); end;
end;

procedure TCSSTokenizerCommentTest.TestUnterminatedComment;
var C: TTokenCollector;
begin
  // Parse error; tokeniser reaches EOF inside the comment.
  C := Tokenize('/* unterminated');
  try
    AssertEquals(1, C.Count());
    AssertEquals(Ord(cttEOF), Ord(C.GetToken(0).TokenType));
  finally C.Free(); end;
end;

// ──────────────────────────────────────────────────────────────
// At-keyword tests
// ──────────────────────────────────────────────────────────────

procedure TCSSTokenizerAtKeywordTest.TestAtMedia;
var C: TTokenCollector;
begin
  C := Tokenize('@media');
  try
    AssertEquals(2, C.Count());
    AssertEquals(Ord(cttAtKeyword), Ord(C.GetToken(0).TokenType));
    AssertEquals('media', C.GetToken(0).Value);
  finally C.Free(); end;
end;

procedure TCSSTokenizerAtKeywordTest.TestAtCharset;
var C: TTokenCollector;
begin
  C := Tokenize('@charset');
  try
    AssertEquals(Ord(cttAtKeyword), Ord(C.GetToken(0).TokenType));
    AssertEquals('charset', C.GetToken(0).Value);
  finally C.Free(); end;
end;

procedure TCSSTokenizerAtKeywordTest.TestAtUnknown;
var C: TTokenCollector;
begin
  C := Tokenize('@foo-bar');
  try
    AssertEquals(Ord(cttAtKeyword), Ord(C.GetToken(0).TokenType));
    AssertEquals('foo-bar', C.GetToken(0).Value);
  finally C.Free(); end;
end;

procedure TCSSTokenizerAtKeywordTest.TestAtWithNoIdent;
var C: TTokenCollector;
begin
  // '@' not followed by an ident-start → <delim-token> '@'
  C := Tokenize('@ ');
  try
    AssertTrue('at least 2', C.Count() >= 2);
    AssertEquals(Ord(cttDelim), Ord(C.GetToken(0).TokenType));
    AssertEquals('@', C.GetToken(0).Value);
  finally C.Free(); end;
end;

// ──────────────────────────────────────────────────────────────
// Delimiter tests
// ──────────────────────────────────────────────────────────────

procedure TCSSTokenizerDelimTest.TestSlash;
var C: TTokenCollector;
begin
  C := Tokenize('/');
  try
    AssertEquals(Ord(cttDelim), Ord(C.GetToken(0).TokenType));
    AssertEquals('/', C.GetToken(0).Value);
  finally C.Free(); end;
end;

procedure TCSSTokenizerDelimTest.TestAsterisk;
var C: TTokenCollector;
begin
  C := Tokenize('*');
  try
    AssertEquals(Ord(cttDelim), Ord(C.GetToken(0).TokenType));
    AssertEquals('*', C.GetToken(0).Value);
  finally C.Free(); end;
end;

procedure TCSSTokenizerDelimTest.TestTilde;
var C: TTokenCollector;
begin
  C := Tokenize('~');
  try
    AssertEquals(Ord(cttDelim), Ord(C.GetToken(0).TokenType));
    AssertEquals('~', C.GetToken(0).Value);
  finally C.Free(); end;
end;

procedure TCSSTokenizerDelimTest.TestPipe;
var C: TTokenCollector;
begin
  C := Tokenize('|');
  try
    AssertEquals(Ord(cttDelim), Ord(C.GetToken(0).TokenType));
    AssertEquals('|', C.GetToken(0).Value);
  finally C.Free(); end;
end;

procedure TCSSTokenizerDelimTest.TestHashDelim;
var C: TTokenCollector;
begin
  // '#' not followed by ident-code-point or valid escape
  C := Tokenize('#;');
  try
    AssertEquals(Ord(cttDelim), Ord(C.GetToken(0).TokenType));
    AssertEquals('#', C.GetToken(0).Value);
  finally C.Free(); end;
end;

procedure TCSSTokenizerDelimTest.TestAtDelim;
var C: TTokenCollector;
begin
  C := Tokenize('@;');
  try
    AssertEquals(Ord(cttDelim), Ord(C.GetToken(0).TokenType));
    AssertEquals('@', C.GetToken(0).Value);
  finally C.Free(); end;
end;

// ──────────────────────────────────────────────────────────────
// CDO / CDC tests
// ──────────────────────────────────────────────────────────────

procedure TCSSTokenizerCDOCDCTest.TestCDO;
var C: TTokenCollector;
begin
  C := Tokenize('<!--');
  try
    AssertEquals(2, C.Count());
    AssertEquals(Ord(cttCDO), Ord(C.GetToken(0).TokenType));
    AssertEquals('<!--', C.GetToken(0).Value);
  finally C.Free(); end;
end;

procedure TCSSTokenizerCDOCDCTest.TestCDC;
var C: TTokenCollector;
begin
  C := Tokenize('-->');
  try
    AssertEquals(2, C.Count());
    AssertEquals(Ord(cttCDC), Ord(C.GetToken(0).TokenType));
    AssertEquals('-->', C.GetToken(0).Value);
  finally C.Free(); end;
end;

procedure TCSSTokenizerCDOCDCTest.TestLessThanNotCDO;
var C: TTokenCollector;
begin
  // '<' followed by something other than '!--' is a delim
  C := Tokenize('<p');
  try
    AssertEquals(Ord(cttDelim), Ord(C.GetToken(0).TokenType));
    AssertEquals('<', C.GetToken(0).Value);
  finally C.Free(); end;
end;

procedure TCSSTokenizerCDOCDCTest.TestDashNotCDC;
var C: TTokenCollector;
begin
  // '->' is NOT CDC ('-->' is); second char must also be '-'
  C := Tokenize('->');
  try
    // '-' not a number start, not '-->', not ident-start (next is '>') → delim '-'
    AssertEquals(Ord(cttDelim), Ord(C.GetToken(0).TokenType));
    AssertEquals('-', C.GetToken(0).Value);
  finally C.Free(); end;
end;

// ──────────────────────────────────────────────────────────────
// Punctuation tests
// ──────────────────────────────────────────────────────────────

procedure TCSSTokenizerPunctuationTest.TestColon;
var C: TTokenCollector;
begin
  C := Tokenize(':');
  try AssertEquals(Ord(cttColon), Ord(C.GetToken(0).TokenType));
  finally C.Free(); end;
end;

procedure TCSSTokenizerPunctuationTest.TestSemicolon;
var C: TTokenCollector;
begin
  C := Tokenize(';');
  try AssertEquals(Ord(cttSemicolon), Ord(C.GetToken(0).TokenType));
  finally C.Free(); end;
end;

procedure TCSSTokenizerPunctuationTest.TestComma;
var C: TTokenCollector;
begin
  C := Tokenize(',');
  try AssertEquals(Ord(cttComma), Ord(C.GetToken(0).TokenType));
  finally C.Free(); end;
end;

procedure TCSSTokenizerPunctuationTest.TestBrackets;
var C: TTokenCollector;
begin
  C := Tokenize('[]');
  try
    AssertEquals(Ord(cttOpenSquare),  Ord(C.GetToken(0).TokenType));
    AssertEquals(Ord(cttCloseSquare), Ord(C.GetToken(1).TokenType));
  finally C.Free(); end;
end;

procedure TCSSTokenizerPunctuationTest.TestParens;
var C: TTokenCollector;
begin
  C := Tokenize('()');
  try
    AssertEquals(Ord(cttOpenParen),  Ord(C.GetToken(0).TokenType));
    AssertEquals(Ord(cttCloseParen), Ord(C.GetToken(1).TokenType));
  finally C.Free(); end;
end;

procedure TCSSTokenizerPunctuationTest.TestCurlies;
var C: TTokenCollector;
begin
  C := Tokenize('{}');
  try
    AssertEquals(Ord(cttOpenCurly),  Ord(C.GetToken(0).TokenType));
    AssertEquals(Ord(cttCloseCurly), Ord(C.GetToken(1).TokenType));
  finally C.Free(); end;
end;

// ──────────────────────────────────────────────────────────────
// Position tests
// ──────────────────────────────────────────────────────────────

procedure TCSSTokenizerPositionTest.TestFirstTokenAt1_1;
var C: TTokenCollector;
begin
  C := Tokenize('color');
  try
    AssertEquals('line',   1, C.GetToken(0).Pos.Line);
    AssertEquals('column', 1, C.GetToken(0).Pos.Column);
  finally C.Free(); end;
end;

procedure TCSSTokenizerPositionTest.TestPositionAfterNewline;
var C: TTokenCollector;
begin
  // After a newline, the next token should be on line 2, column 1.
  C := Tokenize(#$0A'color');
  try
    // Token 0 = whitespace (the newline)
    AssertEquals('ws line',    1, C.GetToken(0).Pos.Line);
    AssertEquals('ws col',     1, C.GetToken(0).Pos.Column);
    // Token 1 = ident 'color'
    AssertEquals('ident line', 2, C.GetToken(1).Pos.Line);
    AssertEquals('ident col',  1, C.GetToken(1).Pos.Column);
  finally C.Free(); end;
end;

procedure TCSSTokenizerPositionTest.TestColumnIncrement;
var C: TTokenCollector;
begin
  // 'a b': ident at col 1, whitespace at col 2, ident at col 3
  C := Tokenize('a b');
  try
    AssertEquals('a col',  1, C.GetToken(0).Pos.Column);
    AssertEquals('ws col', 2, C.GetToken(1).Pos.Column);
    AssertEquals('b col',  3, C.GetToken(2).Pos.Column);
  finally C.Free(); end;
end;

procedure TCSSTokenizerPositionTest.TestEOFPosition;
var C: TTokenCollector;
begin
  C := Tokenize('x');
  try
    // EOF token position is right after the 'x' → col 2
    AssertEquals('eof col', 2, C.GetToken(1).Pos.Column);
  finally C.Free(); end;
end;

// ──────────────────────────────────────────────────────────────
// Streaming tests
// ──────────────────────────────────────────────────────────────

procedure TCSSTokenizerStreamingTest.TestSingleChunk;
var C: TTokenCollector;
begin
  C := Tokenize('px');
  try
    AssertEquals(Ord(cttIdent), Ord(C.GetToken(0).TokenType));
    AssertEquals('px', C.GetToken(0).Value);
  finally C.Free(); end;
end;

procedure TCSSTokenizerStreamingTest.TestTwoChunks;
var C: TTokenCollector;
begin
  C := Tokenize2('co', 'lor');
  try
    AssertEquals(2, C.Count());
    AssertEquals(Ord(cttIdent), Ord(C.GetToken(0).TokenType));
    AssertEquals('color', C.GetToken(0).Value);
  finally C.Free(); end;
end;

procedure TCSSTokenizerStreamingTest.TestIdentAcrossChunks;
var C: TTokenCollector;
begin
  C := Tokenize2('ident', 'ifier');
  try
    AssertEquals(Ord(cttIdent), Ord(C.GetToken(0).TokenType));
    AssertEquals('identifier', C.GetToken(0).Value);
  finally C.Free(); end;
end;

procedure TCSSTokenizerStreamingTest.TestStringAcrossChunks;
var C: TTokenCollector;
begin
  C := Tokenize2('"hel', 'lo"');
  try
    AssertEquals(Ord(cttString), Ord(C.GetToken(0).TokenType));
    AssertEquals('hello', C.GetToken(0).Value);
  finally C.Free(); end;
end;

procedure TCSSTokenizerStreamingTest.TestEmptyFeeds;
var Tok: TCSSTokenizer;
    C  : TTokenCollector;
begin
  C   := TTokenCollector.Create();
  Tok := TCSSTokenizer.Create(C);
  try
    Tok.Feed('');
    Tok.Feed('');
    Tok.Feed('a');
    Tok.Feed('');
    Tok.Finish();
  finally
    Tok.Free();
  end;
  try
    AssertEquals(2, C.Count());
    AssertEquals(Ord(cttIdent), Ord(C.GetToken(0).TokenType));
    AssertEquals('a', C.GetToken(0).Value);
  finally C.Free(); end;
end;

// ──────────────────────────────────────────────────────────────
// Encoding tests
// ──────────────────────────────────────────────────────────────

procedure TCSSTokenizerEncodingTest.TestBOMStripped;
var C: TTokenCollector;
begin
  // UTF-8 BOM + 'color'
  C := Tokenize(#$EF#$BB#$BF'color');
  try
    AssertEquals(2, C.Count());
    AssertEquals(Ord(cttIdent), Ord(C.GetToken(0).TokenType));
    AssertEquals('color', C.GetToken(0).Value);
    AssertEquals(1, C.GetToken(0).Pos.Column); // BOM does not shift column
  finally C.Free(); end;
end;

procedure TCSSTokenizerEncodingTest.TestNoBOMUnaffected;
var C: TTokenCollector;
begin
  C := Tokenize('color');
  try
    AssertEquals('color', C.GetToken(0).Value);
  finally C.Free(); end;
end;

procedure TCSSTokenizerEncodingTest.TestNulReplacedWithFFFD;
var C: TTokenCollector;
begin
  // NUL (0x00) in the source is replaced with U+FFFD by preprocessing.
  // U+FFFD is a non-ASCII code point, so it is an ident-start.
  C := Tokenize('a'#$00'b');
  try
    // 'a' + U+FFFD + 'b' all form one ident token (all are ident code points)
    AssertEquals(Ord(cttIdent), Ord(C.GetToken(0).TokenType));
    AssertTrue('value length >= 2', Length(C.GetToken(0).Value) >= 2);
  finally C.Free(); end;
end;

procedure TCSSTokenizerEncodingTest.TestCRLFNormalized;
var C: TTokenCollector;
begin
  // CR+LF → single LF → single whitespace token
  C := Tokenize('a'#$0D#$0A'b');
  try
    AssertEquals(4, C.Count());   // ident 'a', whitespace, ident 'b', EOF
    AssertEquals(Ord(cttWhitespace), Ord(C.GetToken(1).TokenType));
  finally C.Free(); end;
end;

procedure TCSSTokenizerEncodingTest.TestCRNormalized;
var C: TTokenCollector;
begin
  // Bare CR → LF → whitespace token
  C := Tokenize('a'#$0D'b');
  try
    AssertEquals(4, C.Count());
    AssertEquals(Ord(cttWhitespace), Ord(C.GetToken(1).TokenType));
  finally C.Free(); end;
end;

procedure TCSSTokenizerEncodingTest.TestFFNormalized;
var C: TTokenCollector;
begin
  // Form feed (FF, 0x0C) → LF → whitespace token
  C := Tokenize('a'#$0C'b');
  try
    AssertEquals(4, C.Count());
    AssertEquals(Ord(cttWhitespace), Ord(C.GetToken(1).TokenType));
  finally C.Free(); end;
end;

// ──────────────────────────────────────────────────────────────
// Function token tests
// ──────────────────────────────────────────────────────────────

procedure TCSSTokenizerFunctionTest.TestRgbFunction;
var C: TTokenCollector;
begin
  C := Tokenize('rgb(');
  try
    AssertEquals(2, C.Count());
    AssertEquals(Ord(cttFunction), Ord(C.GetToken(0).TokenType));
    AssertEquals('rgb', C.GetToken(0).Value);
  finally C.Free(); end;
end;

procedure TCSSTokenizerFunctionTest.TestUrlFunction;
var C: TTokenCollector;
begin
  // url( with a quoted argument → function token, not url token
  C := Tokenize('url(''http://example.com'')');
  try
    AssertEquals(Ord(cttFunction), Ord(C.GetToken(0).TokenType));
    AssertEquals('url', C.GetToken(0).Value);
  finally C.Free(); end;
end;

procedure TCSSTokenizerFunctionTest.TestNestedFunctionName;
var C: TTokenCollector;
begin
  C := Tokenize('linear-gradient(');
  try
    AssertEquals(Ord(cttFunction), Ord(C.GetToken(0).TokenType));
    AssertEquals('linear-gradient', C.GetToken(0).Value);
  finally C.Free(); end;
end;

// ──────────────────────────────────────────────────────────────
// Registration
// ──────────────────────────────────────────────────────────────

initialization
  RegisterTest(TCSSTokenizerWhitespaceTest);
  RegisterTest(TCSSTokenizerIdentTest);
  RegisterTest(TCSSTokenizerStringTest);
  RegisterTest(TCSSTokenizerNumericTest);
  RegisterTest(TCSSTokenizerHashTest);
  RegisterTest(TCSSTokenizerUrlTest);
  RegisterTest(TCSSTokenizerCommentTest);
  RegisterTest(TCSSTokenizerAtKeywordTest);
  RegisterTest(TCSSTokenizerDelimTest);
  RegisterTest(TCSSTokenizerCDOCDCTest);
  RegisterTest(TCSSTokenizerPunctuationTest);
  RegisterTest(TCSSTokenizerPositionTest);
  RegisterTest(TCSSTokenizerStreamingTest);
  RegisterTest(TCSSTokenizerEncodingTest);
  RegisterTest(TCSSTokenizerFunctionTest);

end.
