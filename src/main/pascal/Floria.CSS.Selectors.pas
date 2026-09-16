unit Floria.CSS.Selectors;

// Floria.CSS.Selectors
// ====================
// W3C CSS Selectors Level 3 / 4 parser, AST representation, and specificity
// calculation for the Floria CSS subsystem.
//
// Represents:
//   - TCSSSpecificity        (3-tuple (A, B, C) for ID, class/attr/pseudo, type)
//   - TCSSCombinator         (descendant ' ', child '>', adjacent '+', sibling '~')
//   - TCSSAttributeOp        (exists, =, ~=, |=, ^=, $=, *=)
//   - TCSSAttributeSelector  (attribute matching descriptor)
//   - TCSSCompoundSelector   (type, id, classes, attributes, pseudo-classes)
//   - TCSSComplexSelector    (chain of compound selectors with combinators)
//   - TCSSSelectorList       (comma-separated list of complex selectors)
//
// Can parse from raw strings or AST node lists (TCSSQualifiedRule.Prelude).

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, Contnrs, SysUtils, Floria.CSS.Types, Floria.CSS.AST;

type
  // ── Specificity Tuple (A, B, C) ───────────────────────────────────────────
  // A = ID selectors
  // B = Class selectors, attribute selectors, pseudo-classes
  // C = Type selectors, pseudo-elements

  TCSSSpecificity = record
    A : Integer;
    B : Integer;
    C : Integer;

    class function Zero(): TCSSSpecificity; static;
    class function Create(const AA, AB, AC: Integer): TCSSSpecificity; static;

    function CompareTo(const AOther: TCSSSpecificity): Integer;
    function ToString(): AnsiString;
    function Equals(const AOther: TCSSSpecificity): Boolean;
    class operator +(const Left, Right: TCSSSpecificity): TCSSSpecificity;
  end;

  // ── Combinators ───────────────────────────────────────────────────────────

  TCSSCombinator = (
    ccNone,            // Last selector in chain or single selector
    ccDescendant,      // ' ' (whitespace)
    ccChild,           // '>'
    ccAdjacentSibling, // '+'
    ccGeneralSibling   // '~'
  );

  // ── Attribute Operators ───────────────────────────────────────────────────

  TCSSAttributeOp = (
    caoExists,         // [attr]
    caoEquals,         // [attr=val]
    caoIncludes,       // [attr~=val] (space-separated word)
    caoDashMatch,      // [attr|=val] (hyphen-separated or exact)
    caoPrefix,         // [attr^=val] (starts with)
    caoSuffix,         // [attr$=val] (ends with)
    caoSubstring       // [attr*=val] (contains substring)
  );

  // ── Attribute Matcher ─────────────────────────────────────────────────────

  TCSSAttributeSelector = record
    Name            : AnsiString;
    Op              : TCSSAttributeOp;
    Value           : AnsiString;
    CaseInsensitive : Boolean;
  end;

  // ── Compound Selector ─────────────────────────────────────────────────────
  // Matches a single element based on tag, id, classes, attributes, and pseudo-classes.

  TCSSCompoundSelector = class(TObject)
  private
    FUniversal     : Boolean;
    FTagName       : AnsiString;
    FId            : AnsiString;
    FClasses       : TStringList;
    FPseudoClasses : TStringList;
    FAttributes    : array of TCSSAttributeSelector;
    FCombinator    : TCSSCombinator;

    function GetAttributeCount(): Integer;
    function GetAttribute(const AIndex: Integer): TCSSAttributeSelector;
  public
    constructor Create();
    destructor Destroy(); override;

    procedure AddClass(const AClass: AnsiString);
    procedure AddPseudoClass(const APseudo: AnsiString);
    procedure AddAttribute(const AAttr: TCSSAttributeSelector);

    function HasClass(const AClass: AnsiString): Boolean;
    function CalculateSpecificity(): TCSSSpecificity;
    function ToString(): AnsiString;

    property Universal      : Boolean               read FUniversal     write FUniversal;
    property TagName        : AnsiString            read FTagName       write FTagName;
    property Id             : AnsiString            read FId            write FId;
    property Classes        : TStringList           read FClasses;
    property PseudoClasses  : TStringList           read FPseudoClasses;
    property AttributeCount : Integer               read GetAttributeCount;
    property Attributes[AIndex: Integer]: TCSSAttributeSelector read GetAttribute;
    property Combinator     : TCSSCombinator        read FCombinator    write FCombinator;
  end;

  // ── Complex Selector ──────────────────────────────────────────────────────
  // Chain of compound selectors separated by combinators: e.g. "div.sidebar > button.btn-primary"

  TCSSComplexSelector = class(TObject)
  private
    FCompounds: TObjectList; // owns TCSSCompoundSelector
    function GetCount(): Integer;
    function GetItem(const AIndex: Integer): TCSSCompoundSelector;
  public
    constructor Create();
    destructor Destroy(); override;

    procedure Add(const ACompound: TCSSCompoundSelector);
    function CalculateSpecificity(): TCSSSpecificity;
    function ToString(): AnsiString;

    property Count: Integer read GetCount;
    property Items[AIndex: Integer]: TCSSCompoundSelector read GetItem; default;
  end;

  // ── Selector List ─────────────────────────────────────────────────────────
  // Comma-separated list of complex selectors: e.g. "h1, h2, .title"

  TCSSSelectorList = class(TObject)
  private
    FSelectors: TObjectList; // owns TCSSComplexSelector
    function GetCount(): Integer;
    function GetItem(const AIndex: Integer): TCSSComplexSelector;
  public
    constructor Create();
    destructor Destroy(); override;

    procedure Add(const ASelector: TCSSComplexSelector);
    function ToString(): AnsiString;

    property Count: Integer read GetCount;
    property Items[AIndex: Integer]: TCSSComplexSelector read GetItem; default;
  end;

// ── Parsing Functions ───────────────────────────────────────────────────────

function ParseSelectorList(const ANodes: TObjectList): TCSSSelectorList;
function ParseSelectorListFromCSS(const ACSS: AnsiString): TCSSSelectorList;

implementation

uses
  Floria.CSS.Parser;

// ── TCSSSpecificity ─────────────────────────────────────────────────────────

class function TCSSSpecificity.Zero(): TCSSSpecificity;
begin
  Result.A := 0;
  Result.B := 0;
  Result.C := 0;
end;

class function TCSSSpecificity.Create(const AA, AB, AC: Integer): TCSSSpecificity;
begin
  Result.A := AA;
  Result.B := AB;
  Result.C := AC;
end;

function TCSSSpecificity.CompareTo(const AOther: TCSSSpecificity): Integer;
begin
  if A <> AOther.A then
  begin
    if A > AOther.A then Result := 1 else Result := -1;
    Exit;
  end;
  if B <> AOther.B then
  begin
    if B > AOther.B then Result := 1 else Result := -1;
    Exit;
  end;
  if C <> AOther.C then
  begin
    if C > AOther.C then Result := 1 else Result := -1;
    Exit;
  end;
  Result := 0;
end;

function TCSSSpecificity.ToString(): AnsiString;
begin
  Result := Format('(%d,%d,%d)', [A, B, C]);
end;

function TCSSSpecificity.Equals(const AOther: TCSSSpecificity): Boolean;
begin
  Result := (A = AOther.A) and (B = AOther.B) and (C = AOther.C);
end;

class operator TCSSSpecificity.+(const Left, Right: TCSSSpecificity): TCSSSpecificity;
begin
  Result.A := Left.A + Right.A;
  Result.B := Left.B + Right.B;
  Result.C := Left.C + Right.C;
end;

// ── TCSSCompoundSelector ────────────────────────────────────────────────────

constructor TCSSCompoundSelector.Create();
begin
  inherited Create();
  FUniversal     := False;
  FTagName       := '';
  FId            := '';
  FClasses       := TStringList.Create();
  FPseudoClasses := TStringList.Create();
  SetLength(FAttributes, 0);
  FCombinator    := ccNone;
end;

destructor TCSSCompoundSelector.Destroy();
begin
  FClasses.Free();
  FPseudoClasses.Free();
  SetLength(FAttributes, 0);
  inherited Destroy();
end;

procedure TCSSCompoundSelector.AddClass(const AClass: AnsiString);
begin
  if FClasses.IndexOf(AClass) < 0 then
    FClasses.Add(AClass);
end;

procedure TCSSCompoundSelector.AddPseudoClass(const APseudo: AnsiString);
begin
  FPseudoClasses.Add(APseudo);
end;

procedure TCSSCompoundSelector.AddAttribute(const AAttr: TCSSAttributeSelector);
var
  Len: Integer;
begin
  Len := Length(FAttributes);
  SetLength(FAttributes, Len + 1);
  FAttributes[Len] := AAttr;
end;

function TCSSCompoundSelector.GetAttributeCount(): Integer;
begin
  Result := Length(FAttributes);
end;

function TCSSCompoundSelector.GetAttribute(const AIndex: Integer): TCSSAttributeSelector;
begin
  Result := FAttributes[AIndex];
end;

function TCSSCompoundSelector.HasClass(const AClass: AnsiString): Boolean;
begin
  Result := FClasses.IndexOf(AClass) >= 0;
end;

function TCSSCompoundSelector.CalculateSpecificity(): TCSSSpecificity;
var
  A, B, C: Integer;
begin
  A := 0;
  B := 0;
  C := 0;

  if FId <> '' then
    Inc(A);

  Inc(B, FClasses.Count);
  Inc(B, Length(FAttributes));
  Inc(B, FPseudoClasses.Count);

  if (FTagName <> '') and (not FUniversal) then
    Inc(C);

  Result := TCSSSpecificity.Create(A, B, C);
end;

function TCSSCompoundSelector.ToString(): AnsiString;
var
  I: Integer;
begin
  Result := '';
  if FTagName <> '' then
    Result := FTagName
  else if FUniversal then
    Result := '*';

  if FId <> '' then
    Result := Result + '#' + FId;

  for I := 0 to FClasses.Count - 1 do
    Result := Result + '.' + FClasses[I];

  for I := 0 to Length(FAttributes) - 1 do
  begin
    case FAttributes[I].Op of
      caoExists:     Result := Result + '[' + FAttributes[I].Name + ']';
      caoEquals:     Result := Result + '[' + FAttributes[I].Name + '="' + FAttributes[I].Value + '"]';
      caoIncludes:   Result := Result + '[' + FAttributes[I].Name + '~="' + FAttributes[I].Value + '"]';
      caoDashMatch:  Result := Result + '[' + FAttributes[I].Name + '|="' + FAttributes[I].Value + '"]';
      caoPrefix:     Result := Result + '[' + FAttributes[I].Name + '^="' + FAttributes[I].Value + '"]';
      caoSuffix:     Result := Result + '[' + FAttributes[I].Name + '$="' + FAttributes[I].Value + '"]';
      caoSubstring:  Result := Result + '[' + FAttributes[I].Name + '*="' + FAttributes[I].Value + '"]';
    end;
  end;

  for I := 0 to FPseudoClasses.Count - 1 do
    Result := Result + ':' + FPseudoClasses[I];
end;

// ── TCSSComplexSelector ─────────────────────────────────────────────────────

constructor TCSSComplexSelector.Create();
begin
  inherited Create();
  FCompounds := TObjectList.Create(True); // owns compound selectors
end;

destructor TCSSComplexSelector.Destroy();
begin
  FCompounds.Free();
  inherited Destroy();
end;

procedure TCSSComplexSelector.Add(const ACompound: TCSSCompoundSelector);
begin
  FCompounds.Add(ACompound);
end;

function TCSSComplexSelector.GetCount(): Integer;
begin
  Result := FCompounds.Count;
end;

function TCSSComplexSelector.GetItem(const AIndex: Integer): TCSSCompoundSelector;
begin
  Result := TCSSCompoundSelector(FCompounds[AIndex]);
end;

function TCSSComplexSelector.CalculateSpecificity(): TCSSSpecificity;
var
  I: Integer;
begin
  Result := TCSSSpecificity.Zero();
  for I := 0 to FCompounds.Count - 1 do
    Result := Result + TCSSCompoundSelector(FCompounds[I]).CalculateSpecificity();
end;

function TCSSComplexSelector.ToString(): AnsiString;
var
  I   : Integer;
  Comp: TCSSCompoundSelector;
begin
  Result := '';
  for I := 0 to FCompounds.Count - 1 do
  begin
    Comp := TCSSCompoundSelector(FCompounds[I]);
    Result := Result + Comp.ToString();
    case Comp.Combinator of
      ccDescendant:      Result := Result + ' ';
      ccChild:           Result := Result + ' > ';
      ccAdjacentSibling: Result := Result + ' + ';
      ccGeneralSibling:  Result := Result + ' ~ ';
    end;
  end;
end;

// ── TCSSSelectorList ────────────────────────────────────────────────────────

constructor TCSSSelectorList.Create();
begin
  inherited Create();
  FSelectors := TObjectList.Create(True); // owns complex selectors
end;

destructor TCSSSelectorList.Destroy();
begin
  FSelectors.Free();
  inherited Destroy();
end;

procedure TCSSSelectorList.Add(const ASelector: TCSSComplexSelector);
begin
  FSelectors.Add(ASelector);
end;

function TCSSSelectorList.GetCount(): Integer;
begin
  Result := FSelectors.Count;
end;

function TCSSSelectorList.GetItem(const AIndex: Integer): TCSSComplexSelector;
begin
  Result := TCSSComplexSelector(FSelectors[AIndex]);
end;

function TCSSSelectorList.ToString(): AnsiString;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to FSelectors.Count - 1 do
  begin
    if I > 0 then
      Result := Result + ', ';
    Result := Result + TCSSComplexSelector(FSelectors[I]).ToString();
  end;
end;

// ── Selector Parsing Logic ──────────────────────────────────────────────────

procedure ParseAttributeSelectorFromBlock(const ABlock: TCSSSimpleBlock; out AAttr: TCSSAttributeSelector);
var
  I      : Integer;
  Tok    : TCSSToken;
  NameStr: AnsiString;
  ValStr : AnsiString;
  OpStr  : AnsiString;
  Node   : TCSSNode;
begin
  FillChar(AAttr, SizeOf(AAttr), 0);
  AAttr.Op := caoExists;

  if ABlock = nil then
    Exit;

  NameStr := '';
  ValStr  := '';
  OpStr   := '';

  for I := 0 to ABlock.Children.Count - 1 do
  begin
    Node := TCSSNode(ABlock.Children[I]);
    if Node.NodeType = cntPreservedToken then
    begin
      Tok := TCSSPreservedToken(Node).Token;
      if Tok.TokenType = cttWhitespace then
        Continue;

      if OpStr = '' then
      begin
        if Tok.TokenType = cttIdent then
          NameStr := Tok.Value
        else if Tok.TokenType = cttDelim then
        begin
          if Tok.Value = '=' then
            OpStr := '='
          else
            OpStr := Tok.Value;
        end;
      end
      else
      begin
        if (Length(OpStr) = 1) and (OpStr[1] in ['~', '|', '^', '$', '*']) and (Tok.TokenType = cttDelim) and (Tok.Value = '=') then
          OpStr := OpStr + '='
        else if (Tok.TokenType = cttString) or (Tok.TokenType = cttIdent) then
          ValStr := Tok.Value;
      end;
    end;
  end;

  AAttr.Name := NameStr;
  AAttr.Value := ValStr;

  if OpStr = '=' then AAttr.Op := caoEquals
  else if OpStr = '~=' then AAttr.Op := caoIncludes
  else if OpStr = '|=' then AAttr.Op := caoDashMatch
  else if OpStr = '^=' then AAttr.Op := caoPrefix
  else if OpStr = '$=' then AAttr.Op := caoSuffix
  else if OpStr = '*=' then AAttr.Op := caoSubstring
  else AAttr.Op := caoExists;
end;

function ParseSelectorList(const ANodes: TObjectList): TCSSSelectorList;
var
  CurrentList     : TCSSSelectorList;
  CurrentComplex  : TCSSComplexSelector;
  CurrentCompound : TCSSCompoundSelector;
  PendingCombinator: TCSSCombinator;
  HadWhitespace   : Boolean;
  I               : Integer;
  Node            : TCSSNode;
  Tok             : TCSSToken;
  Attr            : TCSSAttributeSelector;

  procedure EnsureCompound();
  begin
    if CurrentCompound = nil then
    begin
      CurrentCompound := TCSSCompoundSelector.Create();
      if PendingCombinator <> ccNone then
      begin
        // The previous compound selector leads into this one with PendingCombinator
        if CurrentComplex.Count > 0 then
          CurrentComplex[CurrentComplex.Count - 1].Combinator := PendingCombinator;
        PendingCombinator := ccNone;
      end;
      CurrentComplex.Add(CurrentCompound);
    end;
  end;

  procedure EndCompound();
  begin
    CurrentCompound := nil;
  end;

  procedure FlushComplex();
  begin
    EndCompound();
    if CurrentComplex.Count > 0 then
    begin
      CurrentList.Add(CurrentComplex);
      CurrentComplex := TCSSComplexSelector.Create();
    end;
    PendingCombinator := ccNone;
    HadWhitespace := False;
  end;

begin
  CurrentList     := TCSSSelectorList.Create();
  CurrentComplex  := TCSSComplexSelector.Create();
  CurrentCompound := nil;
  PendingCombinator := ccNone;
  HadWhitespace   := False;

  if ANodes <> nil then
  begin
    I := 0;
    while I < ANodes.Count do
    begin
      Node := TCSSNode(ANodes[I]);

      if Node.NodeType = cntPreservedToken then
      begin
        Tok := TCSSPreservedToken(Node).Token;

        case Tok.TokenType of
          cttComma:
          begin
            FlushComplex();
            Inc(I);
            Continue;
          end;

          cttWhitespace:
          begin
            HadWhitespace := True;
            if CurrentCompound <> nil then
            begin
              EndCompound();
              if PendingCombinator = ccNone then
                PendingCombinator := ccDescendant;
            end;
            Inc(I);
            Continue;
          end;

          cttDelim:
          begin
            if Tok.Value = '>' then
            begin
              PendingCombinator := ccChild;
              EndCompound();
              HadWhitespace := False;
              Inc(I);
              Continue;
            end
            else if Tok.Value = '+' then
            begin
              PendingCombinator := ccAdjacentSibling;
              EndCompound();
              HadWhitespace := False;
              Inc(I);
              Continue;
            end
            else if Tok.Value = '~' then
            begin
              PendingCombinator := ccGeneralSibling;
              EndCompound();
              HadWhitespace := False;
              Inc(I);
              Continue;
            end
            else if Tok.Value = '*' then
            begin
              EnsureCompound();
              CurrentCompound.Universal := True;
              HadWhitespace := False;
              Inc(I);
              Continue;
            end
            else if Tok.Value = '.' then
            begin
              // Class selector: next token is ident
              Inc(I);
              if (I < ANodes.Count) and (TCSSNode(ANodes[I]).NodeType = cntPreservedToken) then
              begin
                Tok := TCSSPreservedToken(ANodes[I]).Token;
                if Tok.TokenType = cttIdent then
                begin
                  EnsureCompound();
                  CurrentCompound.AddClass(Tok.Value);
                end;
              end;
              HadWhitespace := False;
              Inc(I);
              Continue;
            end;
          end;

          cttHash:
          begin
            EnsureCompound();
            CurrentCompound.Id := Tok.Value;
            HadWhitespace := False;
            Inc(I);
            Continue;
          end;

          cttColon:
          begin
            // Pseudo-class: next token is ident
            Inc(I);
            if (I < ANodes.Count) and (TCSSNode(ANodes[I]).NodeType = cntPreservedToken) then
            begin
              Tok := TCSSPreservedToken(ANodes[I]).Token;
              if Tok.TokenType = cttIdent then
              begin
                EnsureCompound();
                CurrentCompound.AddPseudoClass(Tok.Value);
              end;
            end;
            HadWhitespace := False;
            Inc(I);
            Continue;
          end;

          cttIdent:
          begin
            EnsureCompound();
            CurrentCompound.TagName := Tok.Value;
            HadWhitespace := False;
            Inc(I);
            Continue;
          end;
        end;
      end
      else if Node.NodeType = cntSimpleBlock then
      begin
        // Square bracket attribute selector: [attr=val]
        if TCSSSimpleBlock(Node).AssocToken.TokenType = cttOpenSquare then
        begin
          EnsureCompound();
          ParseAttributeSelectorFromBlock(TCSSSimpleBlock(Node), Attr);
          if Attr.Name <> '' then
            CurrentCompound.AddAttribute(Attr);
          HadWhitespace := False;
          Inc(I);
          Continue;
        end;
      end;

      Inc(I);
    end;
  end;

  if CurrentComplex.Count > 0 then
    CurrentList.Add(CurrentComplex)
  else
    CurrentComplex.Free();

  Result := CurrentList;
end;

function ParseSelectorListFromCSS(const ACSS: AnsiString): TCSSSelectorList;
var
  Sheet : TCSSStylesheet;
  Rule  : TCSSQualifiedRule;
begin
  // Convenience wrapper using parser
  Sheet := TCSSParser.FromCSS(ACSS + ' { }');
  try
    if (Sheet.Rules.Count > 0) and (TObject(Sheet.Rules[0]) is TCSSQualifiedRule) then
    begin
      Rule := TCSSQualifiedRule(Sheet.Rules[0]);
      Result := ParseSelectorList(Rule.Prelude);
    end
    else
      Result := TCSSSelectorList.Create();
  finally
    Sheet.Free();
  end;
end;

end.
