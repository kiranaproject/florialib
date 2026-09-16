unit Floria.CSS.Cascade;

// Floria.CSS.Cascade
// ==================
// CSS selector matching and cascading style resolution engine for Floria.
//
// Features:
//   - ICSSElement interface: toolkit-agnostic element contract
//   - TCSSMockElement: concrete element node tree for testing and headless UI
//   - Selector matching: right-to-left evaluation of complex selectors
//     (tag, class, id, attribute operators, pseudo-classes, and all combinators:
//      child '>', descendant ' ', adjacent '+', general sibling '~')
//   - Cascading resolution (TCSSStyleResolver):
//     - Specificity ordering (A, B, C)
//     - Source order resolution
//     - !important flag precedence
//     - Inheritance of CSS properties from parent style blocks

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, Contnrs, SysUtils,
  Floria.CSS.Types, Floria.CSS.AST, Floria.CSS.Parser,
  Floria.CSS.Values, Floria.CSS.Properties, Floria.CSS.Selectors;

type
  // ── Element Interface ─────────────────────────────────────────────────────

  ICSSElement = interface(IInterface)
    ['{A5B8E7C3-2F4D-4A9E-8B1C-6D3E5F7A9B2D}']
    function GetTagName(): AnsiString;
    function GetId(): AnsiString;
    function HasClass(const AClass: AnsiString): Boolean;
    function HasAttribute(const AName: AnsiString): Boolean;
    function GetAttribute(const AName: AnsiString): AnsiString;
    function GetParent(): ICSSElement;
    function GetPreviousSibling(): ICSSElement;
    function GetChildIndex(): Integer;   // 1-based index among siblings
    function GetSiblingCount(): Integer;
    function IsHovered(): Boolean;
    function IsFocused(): Boolean;
    function IsActive(): Boolean;
    function IsDisabled(): Boolean;
    function IsChecked(): Boolean;
  end;

  // ── Concrete Mock Element ─────────────────────────────────────────────────
  // Implements ICSSElement for headless styling and unit testing.

  TCSSMockElement = class(TObject, ICSSElement)
  private
    FTagName    : AnsiString;
    FId         : AnsiString;
    FClasses    : TStringList;
    FAttributes : TStringList;
    FParent     : TCSSMockElement;
    FChildren   : TObjectList; // owns children
    FHovered    : Boolean;
    FFocused    : Boolean;
    FActive     : Boolean;
    FDisabled   : Boolean;
    FChecked    : Boolean;

    // ICSSElement implementation
    function QueryInterface(constref IID: TGUID; out Obj): HResult; cdecl;
    function _AddRef(): Integer; cdecl;
    function _Release(): Integer; cdecl;

    function GetTagName(): AnsiString;
    function GetId(): AnsiString;
    function HasClass(const AClass: AnsiString): Boolean;
    function HasAttribute(const AName: AnsiString): Boolean;
    function GetAttribute(const AName: AnsiString): AnsiString;
    function GetParent(): ICSSElement;
    function GetPreviousSibling(): ICSSElement;
    function GetChildIndex(): Integer;
    function GetSiblingCount(): Integer;
    function IsHovered(): Boolean;
    function IsFocused(): Boolean;
    function IsActive(): Boolean;
    function IsDisabled(): Boolean;
    function IsChecked(): Boolean;
  public
    constructor Create(const ATagName: AnsiString; const AId: AnsiString = '');
    destructor Destroy(); override;

    procedure AddClass(const AClass: AnsiString);
    procedure SetAttribute(const AName, AValue: AnsiString);
    procedure AppendChild(const AChild: TCSSMockElement);

    procedure SetHovered(const AVal: Boolean);
    procedure SetFocused(const AVal: Boolean);
    procedure SetActive(const AVal: Boolean);
    procedure SetDisabled(const AVal: Boolean);
    procedure SetChecked(const AVal: Boolean);

    property TagName : AnsiString read FTagName write FTagName;
    property Id      : AnsiString read FId      write FId;
  end;

  // ── Cascading Style Resolver ──────────────────────────────────────────────

  TCSSStyleResolver = class(TObject)
  private
    FStylesheets: TObjectList; // owns TCSSStylesheet
  public
    constructor Create();
    destructor Destroy(); override;

    procedure AddStylesheet(const ASheet: TCSSStylesheet);
    procedure AddCSS(const ACSS: AnsiString);
    procedure Clear();

    function ResolveStyle(const AElement: ICSSElement; const AParentStyle: TCSSStyleBlock = nil): TCSSStyleBlock;
  end;

// ── Selector Matching Helpers ───────────────────────────────────────────────

function MatchesCompoundSelector(const ACompound: TCSSCompoundSelector; const AElement: ICSSElement): Boolean;
function MatchesComplexSelector(const AComplex: TCSSComplexSelector; const AElement: ICSSElement): Boolean;
function MatchesSelectorList(const AList: TCSSSelectorList; const AElement: ICSSElement; out ABestSpecificity: TCSSSpecificity): Boolean;

implementation

// ── TCSSMockElement ─────────────────────────────────────────────────────────

constructor TCSSMockElement.Create(const ATagName: AnsiString; const AId: AnsiString);
begin
  inherited Create();
  FTagName    := ATagName;
  FId         := AId;
  FClasses    := TStringList.Create();
  FAttributes := TStringList.Create();
  FChildren   := TObjectList.Create(True); // owns children
  FParent     := nil;
  FHovered    := False;
  FFocused    := False;
  FActive     := False;
  FDisabled   := False;
  FChecked    := False;
end;

destructor TCSSMockElement.Destroy();
begin
  FChildren.Free();
  FClasses.Free();
  FAttributes.Free();
  inherited Destroy();
end;

function TCSSMockElement.QueryInterface(constref IID: TGUID; out Obj): HResult; cdecl;
begin
  if GetInterface(IID, Obj) then
    Result := S_OK
  else
    Result := E_NOINTERFACE;
end;

function TCSSMockElement._AddRef(): Integer; cdecl;
begin
  Result := -1;
end;

function TCSSMockElement._Release(): Integer; cdecl;
begin
  Result := -1;
end;

function TCSSMockElement.GetTagName(): AnsiString;
begin
  Result := FTagName;
end;

function TCSSMockElement.GetId(): AnsiString;
begin
  Result := FId;
end;

function TCSSMockElement.HasClass(const AClass: AnsiString): Boolean;
begin
  Result := FClasses.IndexOf(AClass) >= 0;
end;

function TCSSMockElement.HasAttribute(const AName: AnsiString): Boolean;
begin
  Result := FAttributes.IndexOfName(AName) >= 0;
end;

function TCSSMockElement.GetAttribute(const AName: AnsiString): AnsiString;
begin
  Result := FAttributes.Values[AName];
end;

function TCSSMockElement.GetParent(): ICSSElement;
begin
  Result := FParent;
end;

function TCSSMockElement.GetPreviousSibling(): ICSSElement;
var
  Idx: Integer;
begin
  Result := nil;
  if FParent = nil then
    Exit;
  Idx := FParent.FChildren.IndexOf(Self);
  if Idx > 0 then
    Result := TCSSMockElement(FParent.FChildren[Idx - 1]);
end;

function TCSSMockElement.GetChildIndex(): Integer;
begin
  Result := 1;
  if FParent <> nil then
    Result := FParent.FChildren.IndexOf(Self) + 1;
end;

function TCSSMockElement.GetSiblingCount(): Integer;
begin
  Result := 1;
  if FParent <> nil then
    Result := FParent.FChildren.Count;
end;

function TCSSMockElement.IsHovered(): Boolean;
begin
  Result := FHovered;
end;

function TCSSMockElement.IsFocused(): Boolean;
begin
  Result := FFocused;
end;

function TCSSMockElement.IsActive(): Boolean;
begin
  Result := FActive;
end;

function TCSSMockElement.IsDisabled(): Boolean;
begin
  Result := FDisabled;
end;

function TCSSMockElement.IsChecked(): Boolean;
begin
  Result := FChecked;
end;

procedure TCSSMockElement.AddClass(const AClass: AnsiString);
begin
  if FClasses.IndexOf(AClass) < 0 then
    FClasses.Add(AClass);
end;

procedure TCSSMockElement.SetAttribute(const AName, AValue: AnsiString);
begin
  FAttributes.Values[AName] := AValue;
end;

procedure TCSSMockElement.AppendChild(const AChild: TCSSMockElement);
begin
  if AChild <> nil then
  begin
    AChild.FParent := Self;
    FChildren.Add(AChild);
  end;
end;

procedure TCSSMockElement.SetHovered(const AVal: Boolean);
begin
  FHovered := AVal;
end;

procedure TCSSMockElement.SetFocused(const AVal: Boolean);
begin
  FFocused := AVal;
end;

procedure TCSSMockElement.SetActive(const AVal: Boolean);
begin
  FActive := AVal;
end;

procedure TCSSMockElement.SetDisabled(const AVal: Boolean);
begin
  FDisabled := AVal;
end;

procedure TCSSMockElement.SetChecked(const AVal: Boolean);
begin
  FChecked := AVal;
end;

// ── Matching Engine ─────────────────────────────────────────────────────────

function MatchAttribute(const AAttr: TCSSAttributeSelector; const AElement: ICSSElement): Boolean;
var
  AttrVal: AnsiString;
  TargetVal: AnsiString;
  Words: TStringList;
  I: Integer;
begin
  Result := False;
  if not AElement.HasAttribute(AAttr.Name) then
    Exit;

  if AAttr.Op = caoExists then
  begin
    Result := True;
    Exit;
  end;

  AttrVal := AElement.GetAttribute(AAttr.Name);
  TargetVal := AAttr.Value;

  case AAttr.Op of
    caoEquals:
      Result := AttrVal = TargetVal;

    caoIncludes:
    begin
      // Space-separated list containing word
      Words := TStringList.Create();
      try
        Words.Delimiter := ' ';
        Words.StrictDelimiter := False;
        Words.DelimitedText := AttrVal;
        for I := 0 to Words.Count - 1 do
        begin
          if Words[I] = TargetVal then
          begin
            Result := True;
            Break;
          end;
        end;
      finally
        Words.Free();
      end;
    end;

    caoDashMatch:
    begin
      // Exactly targetVal or starts with targetVal + '-'
      Result := (AttrVal = TargetVal) or
                ((Length(AttrVal) > Length(TargetVal)) and
                 (Copy(AttrVal, 1, Length(TargetVal) + 1) = TargetVal + '-'));
    end;

    caoPrefix:
    begin
      Result := (Length(AttrVal) >= Length(TargetVal)) and
                (Copy(AttrVal, 1, Length(TargetVal)) = TargetVal);
    end;

    caoSuffix:
    begin
      Result := (Length(AttrVal) >= Length(TargetVal)) and
                (Copy(AttrVal, Length(AttrVal) - Length(TargetVal) + 1, Length(TargetVal)) = TargetVal);
    end;

    caoSubstring:
      Result := Pos(TargetVal, AttrVal) > 0;
  end;
end;

function MatchPseudoClass(const APseudo: AnsiString; const AElement: ICSSElement): Boolean;
var
  Low: AnsiString;
begin
  Low := LowerCase(Trim(APseudo));
  if Low = 'hover' then Result := AElement.IsHovered()
  else if Low = 'focus' then Result := AElement.IsFocused()
  else if Low = 'active' then Result := AElement.IsActive()
  else if Low = 'disabled' then Result := AElement.IsDisabled()
  else if Low = 'checked' then Result := AElement.IsChecked()
  else if Low = 'first-child' then Result := AElement.GetChildIndex() = 1
  else if Low = 'last-child' then Result := AElement.GetChildIndex() = AElement.GetSiblingCount()
  else if Low = 'only-child' then Result := AElement.GetSiblingCount() = 1
  else Result := False;
end;

function MatchesCompoundSelector(const ACompound: TCSSCompoundSelector; const AElement: ICSSElement): Boolean;
var
  I: Integer;
begin
  Result := False;
  if (ACompound = nil) or (AElement = nil) then
    Exit;

  // Tag name / universal
  if not ACompound.Universal then
  begin
    if (ACompound.TagName <> '') and
       (LowerCase(ACompound.TagName) <> LowerCase(AElement.GetTagName())) then
      Exit;
  end;

  // ID selector
  if (ACompound.Id <> '') and (ACompound.Id <> AElement.GetId()) then
    Exit;

  // Class selectors
  for I := 0 to ACompound.Classes.Count - 1 do
  begin
    if not AElement.HasClass(ACompound.Classes[I]) then
      Exit;
  end;

  // Attribute selectors
  for I := 0 to ACompound.AttributeCount - 1 do
  begin
    if not MatchAttribute(ACompound.Attributes[I], AElement) then
      Exit;
  end;

  // Pseudo-classes
  for I := 0 to ACompound.PseudoClasses.Count - 1 do
  begin
    if not MatchPseudoClass(ACompound.PseudoClasses[I], AElement) then
      Exit;
  end;

  Result := True;
end;

function MatchesComplexSelector(const AComplex: TCSSComplexSelector; const AElement: ICSSElement): Boolean;
var
  CompIdx   : Integer;
  CurElem   : ICSSElement;
  TargetComp: TCSSCompoundSelector;
  Comb      : TCSSCombinator;
  Matched   : Boolean;
begin
  Result := False;
  if (AComplex = nil) or (AComplex.Count = 0) or (AElement = nil) then
    Exit;

  // Right-most compound selector must match the current element
  CompIdx := AComplex.Count - 1;
  TargetComp := AComplex[CompIdx];
  if not MatchesCompoundSelector(TargetComp, AElement) then
    Exit;

  // If it's a single compound selector, we're done
  if CompIdx = 0 then
  begin
    Result := True;
    Exit;
  end;

  CurElem := AElement;

  // Walk backwards from right to left
  while CompIdx > 0 do
  begin
    Dec(CompIdx);
    TargetComp := AComplex[CompIdx];
    Comb := TargetComp.Combinator;

    case Comb of
      ccChild: // '>' direct parent
      begin
        CurElem := CurElem.GetParent();
        if (CurElem = nil) or (not MatchesCompoundSelector(TargetComp, CurElem)) then
          Exit;
      end;

      ccDescendant: // ' ' any ancestor
      begin
        Matched := False;
        CurElem := CurElem.GetParent();
        while CurElem <> nil do
        begin
          if MatchesCompoundSelector(TargetComp, CurElem) then
          begin
            Matched := True;
            Break;
          end;
          CurElem := CurElem.GetParent();
        end;
        if not Matched then
          Exit;
      end;

      ccAdjacentSibling: // '+' immediately preceding sibling
      begin
        CurElem := CurElem.GetPreviousSibling();
        if (CurElem = nil) or (not MatchesCompoundSelector(TargetComp, CurElem)) then
          Exit;
      end;

      ccGeneralSibling: // '~' any preceding sibling
      begin
        Matched := False;
        CurElem := CurElem.GetPreviousSibling();
        while CurElem <> nil do
        begin
          if MatchesCompoundSelector(TargetComp, CurElem) then
          begin
            Matched := True;
            Break;
          end;
          CurElem := CurElem.GetPreviousSibling();
        end;
        if not Matched then
          Exit;
      end;
    else
      Exit;
    end;
  end;

  Result := True;
end;

function MatchesSelectorList(const AList: TCSSSelectorList; const AElement: ICSSElement; out ABestSpecificity: TCSSSpecificity): Boolean;
var
  I   : Integer;
  Spec: TCSSSpecificity;
begin
  Result := False;
  ABestSpecificity := TCSSSpecificity.Zero();

  if (AList = nil) or (AElement = nil) then
    Exit;

  for I := 0 to AList.Count - 1 do
  begin
    if MatchesComplexSelector(AList[I], AElement) then
    begin
      Spec := AList[I].CalculateSpecificity();
      if (not Result) or (Spec.CompareTo(ABestSpecificity) > 0) then
        ABestSpecificity := Spec;
      Result := True;
    end;
  end;
end;

// ── TCSSStyleResolver ───────────────────────────────────────────────────────

type
  TCSSMatchedDecl = record
    PropertyId  : TCSSPropertyId;
    CustomName  : AnsiString;
    Value       : TCSSPropertyValue;
    Important   : Boolean;
    Specificity : TCSSSpecificity;
    SourceOrder : Integer;
  end;

constructor TCSSStyleResolver.Create();
begin
  inherited Create();
  FStylesheets := TObjectList.Create(True); // owns stylesheets
end;

destructor TCSSStyleResolver.Destroy();
begin
  FStylesheets.Free();
  inherited Destroy();
end;

procedure TCSSStyleResolver.AddStylesheet(const ASheet: TCSSStylesheet);
begin
  if ASheet <> nil then
    FStylesheets.Add(ASheet);
end;

procedure TCSSStyleResolver.AddCSS(const ACSS: AnsiString);
begin
  AddStylesheet(TCSSParser.FromCSS(ACSS));
end;

procedure TCSSStyleResolver.Clear();
begin
  FStylesheets.Clear();
end;

function TCSSStyleResolver.ResolveStyle(const AElement: ICSSElement; const AParentStyle: TCSSStyleBlock): TCSSStyleBlock;
var
  ResultBlock : TCSSStyleBlock;
  SheetIdx    : Integer;
  Sheet       : TCSSStylesheet;
  RuleIdx     : Integer;
  Rule        : TCSSQualifiedRule;
  SelList     : TCSSSelectorList;
  BestSpec    : TCSSSpecificity;
  MatchedList : array of TCSSMatchedDecl;
  MatchedCount: Integer;
  SourceSeq   : Integer;
  ParsedBlock : TCSSStyleBlock;
  DIdx        : Integer;
  Decl        : TCSSStyleDeclaration;
  I, J        : Integer;
  Temp        : TCSSMatchedDecl;
  TakeA       : Boolean;
  Prop        : TCSSPropertyId;
  ParentDecl  : TCSSStyleDeclaration;
begin
  ResultBlock := TCSSStyleBlock.Create();
  if AElement = nil then
  begin
    Result := ResultBlock;
    Exit;
  end;

  SetLength(MatchedList, 0);
  MatchedCount := 0;
  SourceSeq := 0;

  // 1. Collect all matching rules across stylesheets
  for SheetIdx := 0 to FStylesheets.Count - 1 do
  begin
    Sheet := TCSSStylesheet(FStylesheets[SheetIdx]);
    for RuleIdx := 0 to Sheet.Rules.Count - 1 do
    begin
      if not (TObject(Sheet.Rules[RuleIdx]) is TCSSQualifiedRule) then
        Continue;

      Inc(SourceSeq);
      Rule := TCSSQualifiedRule(Sheet.Rules[RuleIdx]);
      SelList := ParseSelectorList(Rule.Prelude);
      try
        if MatchesSelectorList(SelList, AElement, BestSpec) then
        begin
          // Parse declaration block with shorthand expansions
          ParsedBlock := TCSSStyleBlock.FromDeclarationList(Rule.Declarations, True);
          try
            for DIdx := 0 to ParsedBlock.Count - 1 do
            begin
              Decl := ParsedBlock[DIdx];
              SetLength(MatchedList, MatchedCount + 1);
              MatchedList[MatchedCount].PropertyId  := Decl.PropertyId;
              MatchedList[MatchedCount].CustomName  := Decl.CustomName;
              MatchedList[MatchedCount].Value       := Decl.Value;
              MatchedList[MatchedCount].Important   := Decl.Important;
              MatchedList[MatchedCount].Specificity := BestSpec;
              MatchedList[MatchedCount].SourceOrder := SourceSeq;
              Inc(MatchedCount);
            end;
          finally
            ParsedBlock.Free();
          end;
        end;
      finally
        SelList.Free();
      end;
    end;
  end;

  // 2. Sort matched declarations by CSS cascade precedence:
  //    Importance > Specificity > Source Order
  for I := 0 to MatchedCount - 2 do
  begin
    for J := I + 1 to MatchedCount - 1 do
    begin
      // Does MatchedList[J] beat MatchedList[I]?
      TakeA := True;
      if MatchedList[I].Important <> MatchedList[J].Important then
      begin
        if MatchedList[J].Important then
          TakeA := False;
      end
      else
      begin
        // Both equal importance: compare specificity
        if MatchedList[J].Specificity.CompareTo(MatchedList[I].Specificity) > 0 then
          TakeA := False
        else if MatchedList[J].Specificity.CompareTo(MatchedList[I].Specificity) = 0 then
        begin
          // Equal specificity: compare source order
          if MatchedList[J].SourceOrder > MatchedList[I].SourceOrder then
            TakeA := False;
        end;
      end;

      if not TakeA then
      begin
        Temp := MatchedList[I];
        MatchedList[I] := MatchedList[J];
        MatchedList[J] := Temp;
      end;
    end;
  end;

  // 3. Apply sorted winning declarations to the resulting style block
  for I := 0 to MatchedCount - 1 do
  begin
    if MatchedList[I].PropertyId = cpiCustom then
    begin
      if ResultBlock.GetCustom(MatchedList[I].CustomName) = nil then
        ResultBlock.SetCustom(MatchedList[I].CustomName, MatchedList[I].Value, MatchedList[I].Important);
    end
    else
    begin
      if not ResultBlock.HasProperty(MatchedList[I].PropertyId) then
        ResultBlock.SetProperty(MatchedList[I].PropertyId, MatchedList[I].Value, MatchedList[I].Important);
    end;
  end;

  // 4. Inherit properties from parent if not set
  if AParentStyle <> nil then
  begin
    for Prop := Low(TCSSPropertyId) to High(TCSSPropertyId) do
    begin
      if CSSIsInheritedProperty(Prop) and (not ResultBlock.HasProperty(Prop)) then
      begin
        ParentDecl := AParentStyle.GetDeclaration(Prop);
        if ParentDecl <> nil then
          ResultBlock.SetProperty(Prop, ParentDecl.Value, False);
      end;
    end;
  end;

  SetLength(MatchedList, 0);
  Result := ResultBlock;
end;

end.
