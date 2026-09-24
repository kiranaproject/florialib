unit Floria.CSS.Parser;

(*
  Floria.CSS.Parser
  =================
  CSS Syntax Level 3 parser, §5.
  Reference: https://www.w3.org/TR/css-syntax-3/#parsing

  Parses a sequence of TCSSToken (produced by Floria.CSS.Tokenizer) into a
  typed AST rooted at TCSSStylesheet.

  Entry points
  ------------
    ParseStylesheet         – parses a full CSS file (§5.3.2)
    ParseDeclarationList    – parses a sequence of declarations (§5.3.8)
    ParseComponentValue     – parses one component value (§5.3.6)
    ParseComponentValueList – parses a list of component values (§5.3.7)

  Convenience
  -----------
    TokenizeCSS(css)        – shortcut to tokenize a string into a TCSSTokenArray
    TCSSParser.FromCSS(css) – tokenize + ParseStylesheet in one call

  Qualified rule blocks are automatically parsed as declaration lists.
  At-rule blocks are preserved as raw TCSSSimpleBlock nodes (the at-rule type
  determines whether the block is rules or declarations — that is a higher-level
  concern resolved by later pipeline stages).

  Memory
  ------
  The returned TCSSStylesheet owns the entire tree. Free it when done.
  If ParseStylesheet returns nil (only on catastrophic internal error),
  nothing needs freeing.
*)

{$mode objfpc}{$H+}

interface

uses
  Classes, Contnrs, SysUtils, Floria.CSS.Types, Floria.CSS.Tokenizer, Floria.CSS.AST;

type
  { Dynamic array of tokens produced by the tokenizer. }
  TCSSTokenArray = array of TCSSToken;

  // TCSSParser
  // Takes a pre-collected token array and implements the §5.4 consume
  // algorithms. Create → call a ParseXxx entry point → free.
  TCSSParser = class(TObject)
  private
    FTokens : TCSSTokenArray;
    FPos    : Integer;   // index of the next token to consume (0-based)

    // ── Cursor ──
    function  NextToken(): TCSSToken;
    procedure Reconsume();
    function  PeekToken(): TCSSToken;

    // ── Helpers ──
    function IsWhitespaceNode(ANode: TCSSNode): Boolean;
    procedure SkipUntilSemicolon();
    procedure CheckImportant(ADecl: TCSSDeclaration);

    // ── §5.4 consume algorithms ──
    function ConsumeListOfRules(ATopLevel: Boolean): TObjectList;
    function ConsumeAtRule(): TCSSAtRule;
    function ConsumeQualifiedRule(): TCSSQualifiedRule;
    function ConsumeListOfDeclarations(): TObjectList;
    function ConsumeDeclaration(): TCSSDeclaration;
    function ConsumeComponentValue(): TCSSNode;
    function ConsumeSimpleBlock(const AOpenToken: TCSSToken): TCSSSimpleBlock;
    function ConsumeFunctionBlock(const AFuncToken: TCSSToken): TCSSFunctionBlock;

  public
    constructor Create(const ATokens: TCSSTokenArray);

    { §5.3.2 – parse a full CSS stylesheet. Caller owns the result. }
    function ParseStylesheet(): TCSSStylesheet;
    { §5.3.8 – parse a declaration list (inline style or rule block contents). }
    function ParseDeclarationList(): TObjectList;
    { §5.3.6 – parse a single component value. }
    function ParseComponentValue(): TCSSNode;
    { §5.3.7 – parse a list of component values. }
    function ParseComponentValueList(): TObjectList;

    { Convenience: tokenize CSS text then parse a stylesheet. }
    class function FromCSS(const ACSS: AnsiString): TCSSStylesheet;
  end;

{ Tokenize a CSS string into a TCSSTokenArray (including final EOF token).
  The array is always safe to pass to TCSSParser. }
function TokenizeCSS(const ACSS: AnsiString): TCSSTokenArray;

implementation

{ ============================================================
  TokenizeCSS helper — connects tokenizer → parser
  ============================================================ }

type
  { Private token collector — not exposed publicly. }
  TCSSTokenCollector = class(TObject, ICSSTokenListener)
  private
    FTokens : TCSSTokenArray;
    FCount  : Integer;
    function  QueryInterface(constref IID: TGUID; out Obj): HResult; cdecl;
    function  _AddRef(): Integer; cdecl;
    function  _Release(): Integer; cdecl;
  public
    procedure OnToken(const AToken: TCSSToken);
    function  ToArray(): TCSSTokenArray;
  end;

function TCSSTokenCollector.QueryInterface(constref IID: TGUID; out Obj): HResult; cdecl;
begin
  if GetInterface(IID, Obj) then Result := S_OK else Result := E_NOINTERFACE;
end;
function TCSSTokenCollector._AddRef(): Integer; cdecl; begin Result := -1; end;
function TCSSTokenCollector._Release(): Integer; cdecl; begin Result := -1; end;

procedure TCSSTokenCollector.OnToken(const AToken: TCSSToken);
begin
  if FCount >= Length(FTokens) then
    SetLength(FTokens, FCount + 64);
  FTokens[FCount] := AToken;
  Inc(FCount);
end;

function TCSSTokenCollector.ToArray(): TCSSTokenArray;
begin
  SetLength(FTokens, FCount);
  Result := FTokens;
end;

function TokenizeCSS(const ACSS: AnsiString): TCSSTokenArray;
var
  Col : TCSSTokenCollector;
  Tok : TCSSTokenizer;
begin
  Col := TCSSTokenCollector.Create();
  try
    Tok := TCSSTokenizer.Create(Col);
    try
      Tok.Feed(ACSS);
      Tok.Finish();
    finally
      Tok.Free();
    end;
    Result := Col.ToArray();
  finally
    Col.Free();
  end;
end;

{ ============================================================
  TCSSParser — constructor / entry points
  ============================================================ }

constructor TCSSParser.Create(const ATokens: TCSSTokenArray);
begin
  inherited Create();
  FTokens := ATokens;
  FPos    := 0;
end;

class function TCSSParser.FromCSS(const ACSS: AnsiString): TCSSStylesheet;
var
  P : TCSSParser;
begin
  P := TCSSParser.Create(TokenizeCSS(ACSS));
  try
    Result := P.ParseStylesheet();
  finally
    P.Free();
  end;
end;

// ── Public entry points ──

function TCSSParser.ParseStylesheet(): TCSSStylesheet;
var
  Rules : TObjectList;
  i     : Integer;
begin
  // §5.3.2: consume a list of rules (top-level = true)
  Rules := ConsumeListOfRules(True);
  Result := TCSSStylesheet.Create();
  for i := 0 to Rules.Count - 1 do
  begin
    Rules.OwnsObjects := False; // transfer ownership
    Result.Rules.Add(Rules[i]);
    Rules.OwnsObjects := True;
  end;
  Rules.OwnsObjects := False; // already transferred
  Rules.Free();
end;

function TCSSParser.ParseDeclarationList(): TObjectList;
begin
  // §5.3.8: consume list of declarations until EOF
  Result := ConsumeListOfDeclarations();
end;

function TCSSParser.ParseComponentValue(): TCSSNode;
begin
  // §5.3.6
  // Skip leading whitespace (spec says the input is already normalized).
  while PeekToken().TokenType = cttWhitespace do NextToken();
  if PeekToken().TokenType = cttEOF then
    Result := TCSSPreservedToken.Create(NextToken())
  else
    Result := ConsumeComponentValue();
end;

function TCSSParser.ParseComponentValueList(): TObjectList;
var
  cv  : TCSSNode;
  tok : TCSSToken;
begin
  // §5.3.7
  Result := TObjectList.Create(True);
  repeat
    tok := PeekToken();
    if tok.TokenType = cttEOF then Break;
    cv := ConsumeComponentValue();
    Result.Add(cv);
  until False;
end;

{ ============================================================
  Cursor
  ============================================================ }

function TCSSParser.NextToken(): TCSSToken;
begin
  Result := FTokens[FPos];
  if FPos < High(FTokens) then Inc(FPos);
  // If already at the EOF token (last slot), stay there; keeps returning EOF.
end;

procedure TCSSParser.Reconsume();
begin
  if FPos > 0 then Dec(FPos);
end;

function TCSSParser.PeekToken(): TCSSToken;
begin
  Result := FTokens[FPos];
end;

{ ============================================================
  Helpers
  ============================================================ }

function TCSSParser.IsWhitespaceNode(ANode: TCSSNode): Boolean;
begin
  Result := (ANode is TCSSPreservedToken) and
            (TCSSPreservedToken(ANode).Token.TokenType = cttWhitespace);
end;

// Consume tokens until ';' (consumed), closing brace (NOT consumed), or EOF (not consumed).
// Used for error-recovery skips inside declaration lists.
procedure TCSSParser.SkipUntilSemicolon();
var tok: TCSSToken;
begin
  repeat
    tok := NextToken();
    if tok.TokenType = cttSemicolon then Exit;       // semicolon consumed
    if tok.TokenType in [cttCloseCurly, cttEOF] then
    begin
      Reconsume(); // put closing brace or EOF back for the outer list loop
      Exit;
    end;
    // Skip all other tokens (including nested blocks handled via
    // simple-block consumption to maintain balance)
    if tok.TokenType in [cttOpenCurly, cttOpenSquare, cttOpenParen] then
    begin
      Reconsume();
      ConsumeComponentValue().Free(); // consume and discard the balanced block
    end;
  until False;
end;

// Check the tail of ADecl.Value for "! important" and set Important flag.
// If found, removes the "!" and "important" tokens (plus any whitespace
// between them) and trims the trailing whitespace from Value.
procedure TCSSParser.CheckImportant(ADecl: TCSSDeclaration);
var
  i      : Integer;
  node   : TCSSNode;
  pt     : TCSSPreservedToken;
  idxImp : Integer; // index of 'important' ident
  idxBang: Integer; // index of '!' delim
begin
  // Find last non-whitespace item
  i := ADecl.Value.Count - 1;
  while (i >= 0) and IsWhitespaceNode(TCSSNode(ADecl.Value[i])) do Dec(i);
  if i < 0 then Exit;

  // Must be ident 'important'
  node := TCSSNode(ADecl.Value[i]);
  if not (node is TCSSPreservedToken) then Exit;
  pt := TCSSPreservedToken(node);
  if pt.Token.TokenType <> cttIdent then Exit;
  if LowerCase(pt.Token.Value) <> 'important' then Exit;
  idxImp := i;

  // Find previous non-whitespace item
  Dec(i);
  while (i >= 0) and IsWhitespaceNode(TCSSNode(ADecl.Value[i])) do Dec(i);
  if i < 0 then Exit;

  // Must be delim '!'
  node := TCSSNode(ADecl.Value[i]);
  if not (node is TCSSPreservedToken) then Exit;
  pt := TCSSPreservedToken(node);
  if pt.Token.TokenType <> cttDelim then Exit;
  if pt.Token.Value <> '!' then Exit;
  idxBang := i;

  // Found: remove from idxBang onwards
  while ADecl.Value.Count > idxBang do
    ADecl.Value.Delete(ADecl.Value.Count - 1);

  ADecl.Important := True;

  // Trim trailing whitespace left after removing !important
  while (ADecl.Value.Count > 0) and
        IsWhitespaceNode(TCSSNode(ADecl.Value[ADecl.Value.Count - 1])) do
    ADecl.Value.Delete(ADecl.Value.Count - 1);
end;

{ ============================================================
  §5.4.1 — Consume a list of rules
  ============================================================ }

function TCSSParser.ConsumeListOfRules(ATopLevel: Boolean): TObjectList;
var
  tok    : TCSSToken;
  qRule  : TCSSQualifiedRule;
  aRule  : TCSSAtRule;
begin
  Result := TObjectList.Create(True);
  repeat
    tok := NextToken();
    case tok.TokenType of

      cttWhitespace:
        ; // do nothing

      cttEOF:
        Break; // return the rules list

      cttCDO, cttCDC:
      begin
        if ATopLevel then
          // do nothing (ignore at top level)
        else
        begin
          // Treat as part of a qualified rule prelude
          Reconsume();
          qRule := ConsumeQualifiedRule();
          if qRule <> nil then Result.Add(qRule);
        end;
      end;

      cttAtKeyword:
      begin
        Reconsume();
        aRule := ConsumeAtRule();
        if aRule <> nil then Result.Add(aRule);
      end;

      else // anything else
      begin
        Reconsume();
        qRule := ConsumeQualifiedRule();
        if qRule <> nil then Result.Add(qRule);
      end;
    end;
  until False;
end;

{ ============================================================
  §5.4.2 — Consume an at-rule
  ============================================================ }

function TCSSParser.ConsumeAtRule(): TCSSAtRule;
var
  tok : TCSSToken;
  cv  : TCSSNode;
begin
  tok    := NextToken(); // the <at-keyword-token>
  Result := TCSSAtRule.Create(tok.Value);

  repeat
    tok := NextToken();
    case tok.TokenType of
      cttSemicolon:
        Exit; // at-rule with no block: @charset "x";

      cttEOF:
      begin
        // parse error; return what we have
        Exit;
      end;

      cttOpenCurly:
      begin
        // Consume the block as a raw simple block
        Result.Block := ConsumeSimpleBlock(tok);
        Exit;
      end;

      else
      begin
        Reconsume();
        cv := ConsumeComponentValue();
        Result.Prelude.Add(cv);
      end;
    end;
  until False;
end;

{ ============================================================
  §5.4.3 — Consume a qualified rule
  ============================================================ }

function TCSSParser.ConsumeQualifiedRule(): TCSSQualifiedRule;
var
  tok : TCSSToken;
  cv  : TCSSNode;
begin
  Result := TCSSQualifiedRule.Create();

  repeat
    tok := NextToken();
    case tok.TokenType of
      cttEOF:
      begin
        // parse error — return nil
        Result.Free();
        Result := nil;
        Exit;
      end;

      cttOpenCurly:
      begin
        // Parse the block contents as a list of declarations
        Result.Declarations := ConsumeListOfDeclarations();
        Exit;
      end;

      else
      begin
        Reconsume();
        cv := ConsumeComponentValue();
        Result.Prelude.Add(cv);
      end;
    end;
  until False;
end;

(* ============================================================
   §5.4.4 — Consume a list of declarations
   Stops on closing brace (consumed) or EOF. Returns a TObjectList containing
   TCSSDeclaration and/or TCSSAtRule objects.
   ============================================================ *)

function TCSSParser.ConsumeListOfDeclarations(): TObjectList;
var
  tok   : TCSSToken;
  decl  : TCSSDeclaration;
  aRule : TCSSAtRule;
begin
  Result := TObjectList.Create(True);
  repeat
    tok := NextToken();
    case tok.TokenType of

      cttWhitespace, cttSemicolon:
        ; // skip

      cttEOF, cttCloseCurly:
        Break; // end of list

      cttAtKeyword:
      begin
        Reconsume();
        aRule := ConsumeAtRule();
        if aRule <> nil then Result.Add(aRule);
      end;

      cttIdent:
      begin
        Reconsume();
        decl := ConsumeDeclaration();
        if decl <> nil then Result.Add(decl);
      end;

      else
      begin
        // parse error — consume until safe point
        Reconsume();
        SkipUntilSemicolon();
      end;
    end;
  until False;
end;

{ ============================================================
  §5.4.5 — Consume a declaration
  Current position must be at the leading ident token.
  Returns nil on parse error.
  ============================================================ }

function TCSSParser.ConsumeDeclaration(): TCSSDeclaration;
var
  tok : TCSSToken;
  cv  : TCSSNode;
begin
  Result := nil;

  tok := NextToken();  // the <ident-token> (caller guarantees this)

  Result := TCSSDeclaration.Create(tok.Value);

  // Skip whitespace before the colon
  while PeekToken().TokenType = cttWhitespace do NextToken();

  // Expect ':'
  tok := NextToken();
  if tok.TokenType <> cttColon then
  begin
    // parse error — skip to safe boundary
    Reconsume();
    SkipUntilSemicolon();
    FreeAndNil(Result);
    Exit;
  end;

  // Skip whitespace after the colon
  while PeekToken().TokenType = cttWhitespace do NextToken();

  // Consume component values until ';', '}', or EOF
  while not (PeekToken().TokenType in [cttSemicolon, cttCloseCurly, cttEOF]) do
  begin
    cv := ConsumeComponentValue();
    Result.Value.Add(cv);
  end;

  // Trim trailing whitespace from value
  while (Result.Value.Count > 0) and
        IsWhitespaceNode(TCSSNode(Result.Value[Result.Value.Count - 1])) do
    Result.Value.Delete(Result.Value.Count - 1);

  // Detect and extract !important
  CheckImportant(Result);
end;

{ ============================================================
  §5.4.6 — Consume a component value
  ============================================================ }

function TCSSParser.ConsumeComponentValue(): TCSSNode;
var
  tok : TCSSToken;
begin
  tok := NextToken();
  case tok.TokenType of
    cttOpenCurly, cttOpenSquare, cttOpenParen:
      Result := ConsumeSimpleBlock(tok);
    cttFunction:
      Result := ConsumeFunctionBlock(tok);
    else
      Result := TCSSPreservedToken.Create(tok);
  end;
end;

{ ============================================================
  §5.4.7 — Consume a simple block
  AOpenToken is the already-consumed opening bracket token.
  ============================================================ }

function TCSSParser.ConsumeSimpleBlock(const AOpenToken: TCSSToken): TCSSSimpleBlock;
var
  tok       : TCSSToken;
  cv        : TCSSNode;
  closeType : TCSSTokenType;
begin
  case AOpenToken.TokenType of
    cttOpenCurly  : closeType := cttCloseCurly;
    cttOpenSquare : closeType := cttCloseSquare;
    cttOpenParen  : closeType := cttCloseParen;
    else            closeType := cttEOF; // fallback, shouldn't happen
  end;

  Result := TCSSSimpleBlock.Create(AOpenToken);
  repeat
    tok := NextToken();
    if tok.TokenType = cttEOF then Break;          // parse error
    if tok.TokenType = closeType then Break;        // matching close
    Reconsume();
    cv := ConsumeComponentValue();
    Result.Children.Add(cv);
  until False;
end;

{ ============================================================
  §5.4.8 — Consume a function
  AFuncToken is the already-consumed <function-token>.
  ============================================================ }

function TCSSParser.ConsumeFunctionBlock(const AFuncToken: TCSSToken): TCSSFunctionBlock;
var
  tok : TCSSToken;
  cv  : TCSSNode;
begin
  Result := TCSSFunctionBlock.Create(AFuncToken.Value);
  repeat
    tok := NextToken();
    if tok.TokenType = cttEOF then Break;            // parse error
    if tok.TokenType = cttCloseParen then Break;     // ')'
    Reconsume();
    cv := ConsumeComponentValue();
    Result.Children.Add(cv);
  until False;
end;

end.
