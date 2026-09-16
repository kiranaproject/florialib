unit Floria.CSS.Properties;

// Floria.CSS.Properties
// =====================
// Typed property model and declaration parser for the Floria CSS subsystem.
//
// Bridges the generic AST (TCSSDeclaration with component value nodes) to
// typed, queryable styles needed by UI components and layout engines:
//   - TCSSPropertyId         (canonical enum for all standard CSS properties)
//   - Property metadata      (name mapping, inheritance flag, shorthand flag)
//   - TCSSPropertyValue      (typed value record with type discriminator)
//   - TCSSStyleDeclaration   (typed declaration with property ID and importance)
//   - TCSSStyleBlock         (collection of declarations with shorthand expansion)
//
// Supports convenient construction from AST declaration lists and CSS text.

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, Contnrs, SysUtils, Floria.CSS.Types, Floria.CSS.AST, Floria.CSS.Values;

type
  // ── Canonical CSS Property Identifier ─────────────────────────────────────

  TCSSPropertyId = (
    cpiUnknown,
    cpiCustom,

    // Layout & Box Sizing
    cpiDisplay,
    cpiPosition,
    cpiTop,
    cpiRight,
    cpiBottom,
    cpiLeft,
    cpiZIndex,
    cpiOverflow,
    cpiOverflowX,
    cpiOverflowY,
    cpiBoxSizing,

    // Dimensions
    cpiWidth,
    cpiHeight,
    cpiMinWidth,
    cpiMaxWidth,
    cpiMinHeight,
    cpiMaxHeight,

    // Margin
    cpiMargin,
    cpiMarginTop,
    cpiMarginRight,
    cpiMarginBottom,
    cpiMarginLeft,

    // Padding
    cpiPadding,
    cpiPaddingTop,
    cpiPaddingRight,
    cpiPaddingBottom,
    cpiPaddingLeft,

    // Border Shorthands
    cpiBorder,
    cpiBorderTop,
    cpiBorderRight,
    cpiBorderBottom,
    cpiBorderLeft,

    // Border Widths
    cpiBorderWidth,
    cpiBorderTopWidth,
    cpiBorderRightWidth,
    cpiBorderBottomWidth,
    cpiBorderLeftWidth,

    // Border Styles
    cpiBorderStyle,
    cpiBorderTopStyle,
    cpiBorderRightStyle,
    cpiBorderBottomStyle,
    cpiBorderLeftStyle,

    // Border Colors
    cpiBorderColor,
    cpiBorderTopColor,
    cpiBorderRightColor,
    cpiBorderBottomColor,
    cpiBorderLeftColor,

    // Border Radii
    cpiBorderRadius,
    cpiBorderTopLeftRadius,
    cpiBorderTopRightRadius,
    cpiBorderBottomRightRadius,
    cpiBorderBottomLeftRadius,

    // Colors & Appearance
    cpiColor,
    cpiBackgroundColor,
    cpiOpacity,
    cpiVisibility,

    // Flexbox
    cpiFlexDirection,
    cpiFlexWrap,
    cpiJustifyContent,
    cpiAlignItems,
    cpiFlexGrow,
    cpiFlexShrink,
    cpiFlexBasis,

    // Typography
    cpiFontFamily,
    cpiFontSize,
    cpiFontStyle,
    cpiFontWeight,
    cpiLineHeight,
    cpiTextAlign,
    cpiTextDecoration,

    // Window Manager & UI
    cpiCursor
  );

  // ── Value Kind Discriminator ──────────────────────────────────────────────

  TCSSValueKind = (
    cvkUnset,
    cvkInitial,
    cvkInherit,
    cvkColor,
    cvkLength,
    cvkBox,
    cvkKeyword,
    cvkNumber,
    cvkString,
    cvkCustom
  );

  // ── Typed CSS Property Value ──────────────────────────────────────────────

  TCSSPropertyValue = record
    Kind    : TCSSValueKind;
    Color   : TCSSColor;
    Length  : TCSSLength;
    Box     : TCSSBox;
    Number  : Double;
    Keyword : AnsiString;
    Str     : AnsiString;

    class function FromColor(const AColor: TCSSColor): TCSSPropertyValue; static;
    class function FromLength(const ALength: TCSSLength): TCSSPropertyValue; static;
    class function FromBox(const ABox: TCSSBox): TCSSPropertyValue; static;
    class function FromNumber(const ANum: Double): TCSSPropertyValue; static;
    class function FromKeyword(const AKeyword: AnsiString): TCSSPropertyValue; static;
    class function FromString(const AStr: AnsiString): TCSSPropertyValue; static;
    class function Initial(): TCSSPropertyValue; static;
    class function Inherit(): TCSSPropertyValue; static;
    class function Unset(): TCSSPropertyValue; static;

    function AsDisplay(const ADefault: TCSSDisplay = cdBlock): TCSSDisplay;
    function AsPosition(const ADefault: TCSSPosition = cpStatic): TCSSPosition;
    function AsVisibility(const ADefault: TCSSVisibility = cvVisible): TCSSVisibility;
    function AsOverflow(const ADefault: TCSSOverflow = coVisible): TCSSOverflow;
    function AsBorderStyle(const ADefault: TCSSBorderStyle = cbsNone): TCSSBorderStyle;
    function AsBoxSizing(const ADefault: TCSSBoxSizing = cbsContentBox): TCSSBoxSizing;
    function AsFlexDirection(const ADefault: TCSSFlexDirection = cfdRow): TCSSFlexDirection;
    function AsFlexWrap(const ADefault: TCSSFlexWrap = cfwNowrap): TCSSFlexWrap;
    function AsJustifyContent(const ADefault: TCSSJustifyContent = cjcFlexStart): TCSSJustifyContent;
    function AsAlignItems(const ADefault: TCSSAlignItems = caiStretch): TCSSAlignItems;
    function AsFontStyle(const ADefault: TCSSFontStyle = cfsNormal): TCSSFontStyle;
    function AsTextAlign(const ADefault: TCSSTextAlign = ctaLeft): TCSSTextAlign;
    function AsTextDecoration(const ADefault: TCSSTextDecoration = ctdNone): TCSSTextDecoration;
    function ToString(): AnsiString;
    function Equals(const AOther: TCSSPropertyValue): Boolean;
  end;

  // ── Single Resolved CSS Style Declaration ─────────────────────────────────

  TCSSStyleDeclaration = class(TObject)
  private
    FPropertyId : TCSSPropertyId;
    FCustomName : AnsiString;
    FValue      : TCSSPropertyValue;
    FImportant  : Boolean;
  public
    constructor Create(const APropId: TCSSPropertyId; const AValue: TCSSPropertyValue; const AImportant: Boolean = False);
    constructor CreateCustom(const AName: AnsiString; const AValue: TCSSPropertyValue; const AImportant: Boolean = False);

    function Clone(): TCSSStyleDeclaration;

    property PropertyId : TCSSPropertyId   read FPropertyId write FPropertyId;
    property CustomName : AnsiString       read FCustomName write FCustomName;
    property Value      : TCSSPropertyValue read FValue      write FValue;
    property Important  : Boolean          read FImportant  write FImportant;
  end;

  // ── Collection of Style Declarations ──────────────────────────────────────

  TCSSStyleBlock = class(TObject)
  private
    FDeclarations: TObjectList; // owns TCSSStyleDeclaration
    function GetItem(const AIndex: Integer): TCSSStyleDeclaration;
    function GetCount(): Integer;
  public
    constructor Create();
    destructor Destroy(); override;

    procedure Add(const ADecl: TCSSStyleDeclaration);
    procedure SetProperty(const APropId: TCSSPropertyId; const AValue: TCSSPropertyValue; const AImportant: Boolean = False);
    procedure SetCustom(const AName: AnsiString; const AValue: TCSSPropertyValue; const AImportant: Boolean = False);

    function GetDeclaration(const APropId: TCSSPropertyId): TCSSStyleDeclaration;
    function FindDeclaration(const APropId: TCSSPropertyId; out ADecl: TCSSStyleDeclaration): Boolean;
    function GetCustom(const AName: AnsiString): TCSSStyleDeclaration;
    function HasProperty(const APropId: TCSSPropertyId): Boolean;
    procedure RemoveProperty(const APropId: TCSSPropertyId);
    procedure Clear();

    procedure PopulateFromAST(const ADeclarations: TObjectList; const AExpandShorthands: Boolean = True);

    class function FromDeclarationList(const ADeclarations: TObjectList; const AExpandShorthands: Boolean = True): TCSSStyleBlock; static;
    class function FromCSS(const ACSS: AnsiString; const AExpandShorthands: Boolean = True): TCSSStyleBlock; static;

    property Count: Integer read GetCount;
    property Items[AIndex: Integer]: TCSSStyleDeclaration read GetItem; default;
  end;

// ── Property Metadata Functions ─────────────────────────────────────────────

function CSSPropertyNameToId(const AName: AnsiString): TCSSPropertyId;
function CSSPropertyIdToName(const AId: TCSSPropertyId): AnsiString;
function CSSIsInheritedProperty(const AId: TCSSPropertyId): Boolean;
function CSSIsShorthandProperty(const AId: TCSSPropertyId): Boolean;

// ── Value Parsing Helper from AST ───────────────────────────────────────────

function ParsePropertyValue(const APropId: TCSSPropertyId; const ANodes: TObjectList; out AValue: TCSSPropertyValue): Boolean;

implementation

uses
  Floria.CSS.Parser;

// ── Property Name Mapping Table ─────────────────────────────────────────────

type
  TPropEntry = record
    Name : AnsiString;
    Id   : TCSSPropertyId;
  end;

const
  PROP_TABLE: array[0..70] of TPropEntry = (
    (Name: 'display'; Id: cpiDisplay),
    (Name: 'position'; Id: cpiPosition),
    (Name: 'top'; Id: cpiTop),
    (Name: 'right'; Id: cpiRight),
    (Name: 'bottom'; Id: cpiBottom),
    (Name: 'left'; Id: cpiLeft),
    (Name: 'z-index'; Id: cpiZIndex),
    (Name: 'overflow'; Id: cpiOverflow),
    (Name: 'overflow-x'; Id: cpiOverflowX),
    (Name: 'overflow-y'; Id: cpiOverflowY),
    (Name: 'box-sizing'; Id: cpiBoxSizing),

    (Name: 'width'; Id: cpiWidth),
    (Name: 'height'; Id: cpiHeight),
    (Name: 'min-width'; Id: cpiMinWidth),
    (Name: 'max-width'; Id: cpiMaxWidth),
    (Name: 'min-height'; Id: cpiMinHeight),
    (Name: 'max-height'; Id: cpiMaxHeight),

    (Name: 'margin'; Id: cpiMargin),
    (Name: 'margin-top'; Id: cpiMarginTop),
    (Name: 'margin-right'; Id: cpiMarginRight),
    (Name: 'margin-bottom'; Id: cpiMarginBottom),
    (Name: 'margin-left'; Id: cpiMarginLeft),

    (Name: 'padding'; Id: cpiPadding),
    (Name: 'padding-top'; Id: cpiPaddingTop),
    (Name: 'padding-right'; Id: cpiPaddingRight),
    (Name: 'padding-bottom'; Id: cpiPaddingBottom),
    (Name: 'padding-left'; Id: cpiPaddingLeft),

    (Name: 'border'; Id: cpiBorder),
    (Name: 'border-top'; Id: cpiBorderTop),
    (Name: 'border-right'; Id: cpiBorderRight),
    (Name: 'border-bottom'; Id: cpiBorderBottom),
    (Name: 'border-left'; Id: cpiBorderLeft),

    (Name: 'border-width'; Id: cpiBorderWidth),
    (Name: 'border-top-width'; Id: cpiBorderTopWidth),
    (Name: 'border-right-width'; Id: cpiBorderRightWidth),
    (Name: 'border-bottom-width'; Id: cpiBorderBottomWidth),
    (Name: 'border-left-width'; Id: cpiBorderLeftWidth),

    (Name: 'border-style'; Id: cpiBorderStyle),
    (Name: 'border-top-style'; Id: cpiBorderTopStyle),
    (Name: 'border-right-style'; Id: cpiBorderRightStyle),
    (Name: 'border-bottom-style'; Id: cpiBorderBottomStyle),
    (Name: 'border-left-style'; Id: cpiBorderLeftStyle),

    (Name: 'border-color'; Id: cpiBorderColor),
    (Name: 'border-top-color'; Id: cpiBorderTopColor),
    (Name: 'border-right-color'; Id: cpiBorderRightColor),
    (Name: 'border-bottom-color'; Id: cpiBorderBottomColor),
    (Name: 'border-left-color'; Id: cpiBorderLeftColor),

    (Name: 'border-radius'; Id: cpiBorderRadius),
    (Name: 'border-top-left-radius'; Id: cpiBorderTopLeftRadius),
    (Name: 'border-top-right-radius'; Id: cpiBorderTopRightRadius),
    (Name: 'border-bottom-right-radius'; Id: cpiBorderBottomRightRadius),
    (Name: 'border-bottom-left-radius'; Id: cpiBorderBottomLeftRadius),

    (Name: 'color'; Id: cpiColor),
    (Name: 'background-color'; Id: cpiBackgroundColor),
    (Name: 'opacity'; Id: cpiOpacity),
    (Name: 'visibility'; Id: cpiVisibility),

    (Name: 'flex-direction'; Id: cpiFlexDirection),
    (Name: 'flex-wrap'; Id: cpiFlexWrap),
    (Name: 'justify-content'; Id: cpiJustifyContent),
    (Name: 'align-items'; Id: cpiAlignItems),
    (Name: 'flex-grow'; Id: cpiFlexGrow),
    (Name: 'flex-shrink'; Id: cpiFlexShrink),
    (Name: 'flex-basis'; Id: cpiFlexBasis),

    (Name: 'font-family'; Id: cpiFontFamily),
    (Name: 'font-size'; Id: cpiFontSize),
    (Name: 'font-style'; Id: cpiFontStyle),
    (Name: 'font-weight'; Id: cpiFontWeight),
    (Name: 'line-height'; Id: cpiLineHeight),
    (Name: 'text-align'; Id: cpiTextAlign),
    (Name: 'text-decoration'; Id: cpiTextDecoration),

    (Name: 'cursor'; Id: cpiCursor)
  );

function CSSPropertyNameToId(const AName: AnsiString): TCSSPropertyId;
var
  LowName: AnsiString;
  I      : Integer;
begin
  LowName := LowerCase(Trim(AName));
  if (Length(LowName) >= 2) and (LowName[1] = '-') and (LowName[2] = '-') then
  begin
    Result := cpiCustom;
    Exit;
  end;

  for I := Low(PROP_TABLE) to High(PROP_TABLE) do
  begin
    if PROP_TABLE[I].Name = LowName then
    begin
      Result := PROP_TABLE[I].Id;
      Exit;
    end;
  end;
  Result := cpiUnknown;
end;

function CSSPropertyIdToName(const AId: TCSSPropertyId): AnsiString;
var
  I: Integer;
begin
  for I := Low(PROP_TABLE) to High(PROP_TABLE) do
  begin
    if PROP_TABLE[I].Id = AId then
    begin
      Result := PROP_TABLE[I].Name;
      Exit;
    end;
  end;

  case AId of
    cpiCustom:  Result := '--custom';
    cpiUnknown: Result := 'unknown';
  else
    Result := '';
  end;
end;

function CSSIsInheritedProperty(const AId: TCSSPropertyId): Boolean;
begin
  case AId of
    cpiColor,
    cpiFontFamily,
    cpiFontSize,
    cpiFontStyle,
    cpiFontWeight,
    cpiLineHeight,
    cpiTextAlign,
    cpiVisibility,
    cpiCursor:
      Result := True;
  else
    Result := False;
  end;
end;

function CSSIsShorthandProperty(const AId: TCSSPropertyId): Boolean;
begin
  case AId of
    cpiMargin,
    cpiPadding,
    cpiBorder,
    cpiBorderTop,
    cpiBorderRight,
    cpiBorderBottom,
    cpiBorderLeft,
    cpiBorderWidth,
    cpiBorderStyle,
    cpiBorderColor,
    cpiBorderRadius,
    cpiOverflow:
      Result := True;
  else
    Result := False;
  end;
end;

// ── TCSSPropertyValue ───────────────────────────────────────────────────────

class function TCSSPropertyValue.FromColor(const AColor: TCSSColor): TCSSPropertyValue;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Kind := cvkColor;
  Result.Color := AColor;
end;

class function TCSSPropertyValue.FromLength(const ALength: TCSSLength): TCSSPropertyValue;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Kind := cvkLength;
  Result.Length := ALength;
end;

class function TCSSPropertyValue.FromBox(const ABox: TCSSBox): TCSSPropertyValue;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Kind := cvkBox;
  Result.Box := ABox;
end;

class function TCSSPropertyValue.FromNumber(const ANum: Double): TCSSPropertyValue;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Kind := cvkNumber;
  Result.Number := ANum;
end;

class function TCSSPropertyValue.FromKeyword(const AKeyword: AnsiString): TCSSPropertyValue;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Kind := cvkKeyword;
  Result.Keyword := AKeyword;
end;

class function TCSSPropertyValue.FromString(const AStr: AnsiString): TCSSPropertyValue;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Kind := cvkString;
  Result.Str := AStr;
end;

class function TCSSPropertyValue.Initial(): TCSSPropertyValue;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Kind := cvkInitial;
end;

class function TCSSPropertyValue.Inherit(): TCSSPropertyValue;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Kind := cvkInherit;
end;

class function TCSSPropertyValue.Unset(): TCSSPropertyValue;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Kind := cvkUnset;
end;

function TCSSPropertyValue.AsDisplay(const ADefault: TCSSDisplay): TCSSDisplay;
begin
  if (Kind = cvkKeyword) and TryParseDisplay(Keyword, Result) then
    Exit;
  Result := ADefault;
end;

function TCSSPropertyValue.AsPosition(const ADefault: TCSSPosition): TCSSPosition;
begin
  if (Kind = cvkKeyword) and TryParsePosition(Keyword, Result) then
    Exit;
  Result := ADefault;
end;

function TCSSPropertyValue.AsVisibility(const ADefault: TCSSVisibility): TCSSVisibility;
begin
  if (Kind = cvkKeyword) and TryParseVisibility(Keyword, Result) then
    Exit;
  Result := ADefault;
end;

function TCSSPropertyValue.AsOverflow(const ADefault: TCSSOverflow): TCSSOverflow;
begin
  if (Kind = cvkKeyword) and TryParseOverflow(Keyword, Result) then
    Exit;
  Result := ADefault;
end;

function TCSSPropertyValue.AsBorderStyle(const ADefault: TCSSBorderStyle): TCSSBorderStyle;
begin
  if (Kind = cvkKeyword) and TryParseBorderStyle(Keyword, Result) then
    Exit;
  Result := ADefault;
end;

function TCSSPropertyValue.AsBoxSizing(const ADefault: TCSSBoxSizing): TCSSBoxSizing;
begin
  if (Kind = cvkKeyword) and TryParseBoxSizing(Keyword, Result) then
    Exit;
  Result := ADefault;
end;

function TCSSPropertyValue.AsFlexDirection(const ADefault: TCSSFlexDirection): TCSSFlexDirection;
begin
  if (Kind = cvkKeyword) and TryParseFlexDirection(Keyword, Result) then
    Exit;
  Result := ADefault;
end;

function TCSSPropertyValue.AsFlexWrap(const ADefault: TCSSFlexWrap): TCSSFlexWrap;
begin
  if (Kind = cvkKeyword) and TryParseFlexWrap(Keyword, Result) then
    Exit;
  Result := ADefault;
end;

function TCSSPropertyValue.AsJustifyContent(const ADefault: TCSSJustifyContent): TCSSJustifyContent;
begin
  if (Kind = cvkKeyword) and TryParseJustifyContent(Keyword, Result) then
    Exit;
  Result := ADefault;
end;

function TCSSPropertyValue.AsAlignItems(const ADefault: TCSSAlignItems): TCSSAlignItems;
begin
  if (Kind = cvkKeyword) and TryParseAlignItems(Keyword, Result) then
    Exit;
  Result := ADefault;
end;

function TCSSPropertyValue.AsFontStyle(const ADefault: TCSSFontStyle): TCSSFontStyle;
begin
  if (Kind = cvkKeyword) and TryParseFontStyle(Keyword, Result) then
    Exit;
  Result := ADefault;
end;

function TCSSPropertyValue.AsTextAlign(const ADefault: TCSSTextAlign): TCSSTextAlign;
begin
  if (Kind = cvkKeyword) and TryParseTextAlign(Keyword, Result) then
    Exit;
  Result := ADefault;
end;

function TCSSPropertyValue.AsTextDecoration(const ADefault: TCSSTextDecoration): TCSSTextDecoration;
begin
  if (Kind = cvkKeyword) and TryParseTextDecoration(Keyword, Result) then
    Exit;
  Result := ADefault;
end;

function TCSSPropertyValue.ToString(): AnsiString;
begin
  case Kind of
    cvkColor:   Result := Color.ToHex(Color.A <> 255);
    cvkLength:  Result := Length.ToString();
    cvkBox:     Result := Format('%s %s %s %s', [Box.Top.ToString(), Box.Right.ToString(), Box.Bottom.ToString(), Box.Left.ToString()]);
    cvkNumber:  Result := FloatToStr(Number);
    cvkKeyword: Result := Keyword;
    cvkString:  Result := Str;
    cvkInitial: Result := 'initial';
    cvkInherit: Result := 'inherit';
    cvkUnset:   Result := 'unset';
    cvkCustom:  Result := Str;
  else
    Result := '';
  end;
end;

function TCSSPropertyValue.Equals(const AOther: TCSSPropertyValue): Boolean;
begin
  if Kind <> AOther.Kind then
    Exit(False);
  case Kind of
    cvkColor:   Result := Color.Equals(AOther.Color);
    cvkLength:  Result := Length.Equals(AOther.Length);
    cvkBox:     Result := Box.Equals(AOther.Box);
    cvkNumber:  Result := Abs(Number - AOther.Number) < 0.00001;
    cvkKeyword: Result := Keyword = AOther.Keyword;
    cvkString,
    cvkCustom:  Result := Str = AOther.Str;
    cvkInitial,
    cvkInherit,
    cvkUnset:   Result := True;
  else
    Result := False;
  end;
end;

// ── TCSSStyleDeclaration ────────────────────────────────────────────────────

constructor TCSSStyleDeclaration.Create(const APropId: TCSSPropertyId; const AValue: TCSSPropertyValue; const AImportant: Boolean);
begin
  inherited Create();
  FPropertyId := APropId;
  FCustomName := '';
  FValue      := AValue;
  FImportant  := AImportant;
end;

constructor TCSSStyleDeclaration.CreateCustom(const AName: AnsiString; const AValue: TCSSPropertyValue; const AImportant: Boolean);
begin
  inherited Create();
  FPropertyId := cpiCustom;
  FCustomName := AName;
  FValue      := AValue;
  FImportant  := AImportant;
end;

function TCSSStyleDeclaration.Clone(): TCSSStyleDeclaration;
begin
  if FPropertyId = cpiCustom then
    Result := TCSSStyleDeclaration.CreateCustom(FCustomName, FValue, FImportant)
  else
    Result := TCSSStyleDeclaration.Create(FPropertyId, FValue, FImportant);
end;

// ── TCSSStyleBlock ──────────────────────────────────────────────────────────

constructor TCSSStyleBlock.Create();
begin
  inherited Create();
  FDeclarations := TObjectList.Create(True); // owns declarations
end;

destructor TCSSStyleBlock.Destroy();
begin
  FDeclarations.Free();
  inherited Destroy();
end;

function TCSSStyleBlock.GetItem(const AIndex: Integer): TCSSStyleDeclaration;
begin
  Result := TCSSStyleDeclaration(FDeclarations[AIndex]);
end;

function TCSSStyleBlock.GetCount(): Integer;
begin
  Result := FDeclarations.Count;
end;

procedure TCSSStyleBlock.Add(const ADecl: TCSSStyleDeclaration);
begin
  FDeclarations.Add(ADecl);
end;

procedure TCSSStyleBlock.SetProperty(const APropId: TCSSPropertyId; const AValue: TCSSPropertyValue; const AImportant: Boolean);
var
  Decl: TCSSStyleDeclaration;
begin
  if FindDeclaration(APropId, Decl) then
  begin
    // Update existing if not overridden by higher importance
    if (not Decl.Important) or AImportant then
    begin
      Decl.Value     := AValue;
      Decl.Important := AImportant;
    end;
  end
  else
    Add(TCSSStyleDeclaration.Create(APropId, AValue, AImportant));
end;

procedure TCSSStyleBlock.SetCustom(const AName: AnsiString; const AValue: TCSSPropertyValue; const AImportant: Boolean);
var
  Decl: TCSSStyleDeclaration;
begin
  Decl := GetCustom(AName);
  if Decl <> nil then
  begin
    if (not Decl.Important) or AImportant then
    begin
      Decl.Value     := AValue;
      Decl.Important := AImportant;
    end;
  end
  else
    Add(TCSSStyleDeclaration.CreateCustom(AName, AValue, AImportant));
end;

function TCSSStyleBlock.FindDeclaration(const APropId: TCSSPropertyId; out ADecl: TCSSStyleDeclaration): Boolean;
var
  I: Integer;
  D: TCSSStyleDeclaration;
begin
  Result := False;
  // Search in reverse order so latest declaration wins
  for I := FDeclarations.Count - 1 downto 0 do
  begin
    D := TCSSStyleDeclaration(FDeclarations[I]);
    if D.PropertyId = APropId then
    begin
      ADecl := D;
      Result := True;
      Exit;
    end;
  end;
end;

function TCSSStyleBlock.GetDeclaration(const APropId: TCSSPropertyId): TCSSStyleDeclaration;
begin
  if not FindDeclaration(APropId, Result) then
    Result := nil;
end;

function TCSSStyleBlock.GetCustom(const AName: AnsiString): TCSSStyleDeclaration;
var
  I: Integer;
  D: TCSSStyleDeclaration;
begin
  Result := nil;
  for I := FDeclarations.Count - 1 downto 0 do
  begin
    D := TCSSStyleDeclaration(FDeclarations[I]);
    if (D.PropertyId = cpiCustom) and SameText(D.CustomName, AName) then
    begin
      Result := D;
      Exit;
    end;
  end;
end;

function TCSSStyleBlock.HasProperty(const APropId: TCSSPropertyId): Boolean;
var
  Dummy: TCSSStyleDeclaration;
begin
  Result := FindDeclaration(APropId, Dummy);
end;

procedure TCSSStyleBlock.RemoveProperty(const APropId: TCSSPropertyId);
var
  I: Integer;
begin
  for I := FDeclarations.Count - 1 downto 0 do
  begin
    if TCSSStyleDeclaration(FDeclarations[I]).PropertyId = APropId then
      FDeclarations.Delete(I);
  end;
end;

procedure TCSSStyleBlock.Clear();
begin
  FDeclarations.Clear();
end;

// ── Value Parsing Logic ─────────────────────────────────────────────────────

function ParseNodesToString(const ANodes: TObjectList): AnsiString;
var
  I   : Integer;
  Node: TCSSNode;
  Tok : TCSSToken;
begin
  Result := '';
  if ANodes = nil then
    Exit;
  for I := 0 to ANodes.Count - 1 do
  begin
    Node := TCSSNode(ANodes[I]);
    if Node.NodeType = cntPreservedToken then
    begin
      Tok := TCSSPreservedToken(Node).Token;
      case Tok.TokenType of
        cttWhitespace: Result := Result + ' ';
        cttComma:      Result := Result + ', ';
        cttHash:       Result := Result + '#' + Tok.Value;
        cttPercentage: Result := Result + Tok.Value + '%';
        cttDimension:  Result := Result + Tok.Value + Tok.Unit_;
      else
        Result := Result + Tok.Value;
      end;
    end;
  end;
  Result := Trim(Result);
end;

function ParsePropertyValue(const APropId: TCSSPropertyId; const ANodes: TObjectList; out AValue: TCSSPropertyValue): Boolean;
var
  Col      : TCSSColor;
  Len      : TCSSLength;
  Box      : TCSSBox;
  BorderSide: TCSSBorderSide;
  Node     : TCSSNode;
  Tok      : TCSSToken;
  S        : AnsiString;
  Filtered : TObjectList;
  I        : Integer;
begin
  Result := False;
  if (ANodes = nil) or (ANodes.Count = 0) then
    Exit;

  // Filter out whitespace
  Filtered := TObjectList.Create(False);
  try
    for I := 0 to ANodes.Count - 1 do
    begin
      Node := TCSSNode(ANodes[I]);
      if (Node.NodeType = cntPreservedToken) and
         (TCSSPreservedToken(Node).Token.TokenType = cttWhitespace) then
        Continue;
      Filtered.Add(Node);
    end;

    if Filtered.Count = 0 then
      Exit;

    // Check generic CSS-wide keywords: initial, inherit, unset
    if Filtered.Count = 1 then
    begin
      Node := TCSSNode(Filtered[0]);
      if Node.NodeType = cntPreservedToken then
      begin
        Tok := TCSSPreservedToken(Node).Token;
        if Tok.TokenType = cttIdent then
        begin
          S := LowerCase(Tok.Value);
          if S = 'initial' then
          begin
            AValue := TCSSPropertyValue.Initial();
            Result := True;
            Exit;
          end
          else if S = 'inherit' then
          begin
            AValue := TCSSPropertyValue.Inherit();
            Result := True;
            Exit;
          end
          else if S = 'unset' then
          begin
            AValue := TCSSPropertyValue.Unset();
            Result := True;
            Exit;
          end;
        end;
      end;
    end;

    // Custom properties: capture raw token text
    if APropId = cpiCustom then
    begin
      AValue := TCSSPropertyValue.FromString(ParseNodesToString(ANodes));
      AValue.Kind := cvkCustom;
      Result := True;
      Exit;
    end;

    // Color properties
    case APropId of
      cpiColor,
      cpiBackgroundColor,
      cpiBorderColor,
      cpiBorderTopColor,
      cpiBorderRightColor,
      cpiBorderBottomColor,
      cpiBorderLeftColor:
      begin
        if ParseColorFromNodes(ANodes, Col) then
        begin
          AValue := TCSSPropertyValue.FromColor(Col);
          Result := True;
          Exit;
        end;
      end;
    end;

    // Dimension / Length properties
    case APropId of
      cpiWidth, cpiHeight,
      cpiMinWidth, cpiMaxWidth,
      cpiMinHeight, cpiMaxHeight,
      cpiTop, cpiRight, cpiBottom, cpiLeft,
      cpiFontSize, cpiLineHeight,
      cpiMarginTop, cpiMarginRight, cpiMarginBottom, cpiMarginLeft,
      cpiPaddingTop, cpiPaddingRight, cpiPaddingBottom, cpiPaddingLeft,
      cpiBorderTopWidth, cpiBorderRightWidth, cpiBorderBottomWidth, cpiBorderLeftWidth,
      cpiBorderTopLeftRadius, cpiBorderTopRightRadius,
      cpiBorderBottomRightRadius, cpiBorderBottomLeftRadius,
      cpiFlexBasis:
      begin
        if ParseLengthFromNodes(ANodes, Len) then
        begin
          AValue := TCSSPropertyValue.FromLength(Len);
          Result := True;
          Exit;
        end;
      end;
    end;

    // Box Model shorthands: margin, padding, border-width, border-radius
    case APropId of
      cpiMargin, cpiPadding, cpiBorderWidth, cpiBorderRadius:
      begin
        if ParseBoxFromNodes(ANodes, Box) then
        begin
          AValue := TCSSPropertyValue.FromBox(Box);
          Result := True;
          Exit;
        end;
      end;
    end;

    // Border shorthands: border, border-top, border-right, border-bottom, border-left
    case APropId of
      cpiBorder, cpiBorderTop, cpiBorderRight, cpiBorderBottom, cpiBorderLeft:
      begin
        if ParseBorderSideFromNodes(ANodes, BorderSide) then
        begin
          // For composite border side, we store a string representation or custom keyword
          AValue := TCSSPropertyValue.FromKeyword(Format('%s %s %s', [
            BorderSide.Width.ToString(),
            BorderStyleToString(BorderSide.Style),
            BorderSide.Color.ToHex(BorderSide.Color.A <> 255)
          ]));
          Result := True;
          Exit;
        end;
      end;
    end;

    // Keyword properties
    if Filtered.Count = 1 then
    begin
      Node := TCSSNode(Filtered[0]);
      if Node.NodeType = cntPreservedToken then
      begin
        Tok := TCSSPreservedToken(Node).Token;
        if Tok.TokenType = cttIdent then
        begin
          AValue := TCSSPropertyValue.FromKeyword(Tok.Value);
          Result := True;
          Exit;
        end
        else if Tok.TokenType = cttNumber then
        begin
          // Numeric value (e.g. z-index: 100, opacity: 0.5, flex-grow: 1)
          AValue := TCSSPropertyValue.FromNumber(Tok.NumericVal);
          Result := True;
          Exit;
        end
        else if Tok.TokenType = cttString then
        begin
          AValue := TCSSPropertyValue.FromString(Tok.Value);
          Result := True;
          Exit;
        end;
      end;
    end;

    // Generic fallback: string representation
    AValue := TCSSPropertyValue.FromString(ParseNodesToString(ANodes));
    Result := True;
  finally
    Filtered.Free();
  end;
end;

procedure TCSSStyleBlock.PopulateFromAST(const ADeclarations: TObjectList; const AExpandShorthands: Boolean);
var
  I           : Integer;
  ASTDecl     : TCSSDeclaration;
  PropId      : TCSSPropertyId;
  Val         : TCSSPropertyValue;
  Side        : TCSSBorderSide;
  Box         : TCSSBox;
begin
  if ADeclarations = nil then
    Exit;

  for I := 0 to ADeclarations.Count - 1 do
  begin
    if not (TObject(ADeclarations[I]) is TCSSDeclaration) then
      Continue;
    ASTDecl := TCSSDeclaration(ADeclarations[I]);
    PropId  := CSSPropertyNameToId(ASTDecl.Name);

    if PropId = cpiCustom then
    begin
      if ParsePropertyValue(cpiCustom, ASTDecl.Value, Val) then
        SetCustom(ASTDecl.Name, Val, ASTDecl.Important);
      Continue;
    end;

    if PropId = cpiUnknown then
    begin
      // Store unknown declaration as raw string
      Val := TCSSPropertyValue.FromString(ParseNodesToString(ASTDecl.Value));
      Add(TCSSStyleDeclaration.CreateCustom(ASTDecl.Name, Val, ASTDecl.Important));
      Continue;
    end;

    // Parse value
    if not ParsePropertyValue(PropId, ASTDecl.Value, Val) then
      Continue;

    // Shorthand expansions
    if AExpandShorthands then
    begin
      case PropId of
        cpiMargin:
        begin
          if Val.Kind = cvkBox then
          begin
            SetProperty(cpiMarginTop, TCSSPropertyValue.FromLength(Val.Box.Top), ASTDecl.Important);
            SetProperty(cpiMarginRight, TCSSPropertyValue.FromLength(Val.Box.Right), ASTDecl.Important);
            SetProperty(cpiMarginBottom, TCSSPropertyValue.FromLength(Val.Box.Bottom), ASTDecl.Important);
            SetProperty(cpiMarginLeft, TCSSPropertyValue.FromLength(Val.Box.Left), ASTDecl.Important);
          end;
        end;
        cpiPadding:
        begin
          if Val.Kind = cvkBox then
          begin
            SetProperty(cpiPaddingTop, TCSSPropertyValue.FromLength(Val.Box.Top), ASTDecl.Important);
            SetProperty(cpiPaddingRight, TCSSPropertyValue.FromLength(Val.Box.Right), ASTDecl.Important);
            SetProperty(cpiPaddingBottom, TCSSPropertyValue.FromLength(Val.Box.Bottom), ASTDecl.Important);
            SetProperty(cpiPaddingLeft, TCSSPropertyValue.FromLength(Val.Box.Left), ASTDecl.Important);
          end;
        end;
        cpiBorderWidth:
        begin
          if Val.Kind = cvkBox then
          begin
            SetProperty(cpiBorderTopWidth, TCSSPropertyValue.FromLength(Val.Box.Top), ASTDecl.Important);
            SetProperty(cpiBorderRightWidth, TCSSPropertyValue.FromLength(Val.Box.Right), ASTDecl.Important);
            SetProperty(cpiBorderBottomWidth, TCSSPropertyValue.FromLength(Val.Box.Bottom), ASTDecl.Important);
            SetProperty(cpiBorderLeftWidth, TCSSPropertyValue.FromLength(Val.Box.Left), ASTDecl.Important);
          end;
        end;
        cpiBorderRadius:
        begin
          if Val.Kind = cvkBox then
          begin
            SetProperty(cpiBorderTopLeftRadius, TCSSPropertyValue.FromLength(Val.Box.Top), ASTDecl.Important);
            SetProperty(cpiBorderTopRightRadius, TCSSPropertyValue.FromLength(Val.Box.Right), ASTDecl.Important);
            SetProperty(cpiBorderBottomRightRadius, TCSSPropertyValue.FromLength(Val.Box.Bottom), ASTDecl.Important);
            SetProperty(cpiBorderBottomLeftRadius, TCSSPropertyValue.FromLength(Val.Box.Left), ASTDecl.Important);
          end;
        end;
        cpiBorder:
        begin
          if ParseBorderSideFromNodes(ASTDecl.Value, Side) then
          begin
            Box := TCSSBox.All(Side.Width);
            SetProperty(cpiBorderTopWidth, TCSSPropertyValue.FromLength(Box.Top), ASTDecl.Important);
            SetProperty(cpiBorderRightWidth, TCSSPropertyValue.FromLength(Box.Right), ASTDecl.Important);
            SetProperty(cpiBorderBottomWidth, TCSSPropertyValue.FromLength(Box.Bottom), ASTDecl.Important);
            SetProperty(cpiBorderLeftWidth, TCSSPropertyValue.FromLength(Box.Left), ASTDecl.Important);

            SetProperty(cpiBorderTopStyle, TCSSPropertyValue.FromKeyword(BorderStyleToString(Side.Style)), ASTDecl.Important);
            SetProperty(cpiBorderRightStyle, TCSSPropertyValue.FromKeyword(BorderStyleToString(Side.Style)), ASTDecl.Important);
            SetProperty(cpiBorderBottomStyle, TCSSPropertyValue.FromKeyword(BorderStyleToString(Side.Style)), ASTDecl.Important);
            SetProperty(cpiBorderLeftStyle, TCSSPropertyValue.FromKeyword(BorderStyleToString(Side.Style)), ASTDecl.Important);

            SetProperty(cpiBorderTopColor, TCSSPropertyValue.FromColor(Side.Color), ASTDecl.Important);
            SetProperty(cpiBorderRightColor, TCSSPropertyValue.FromColor(Side.Color), ASTDecl.Important);
            SetProperty(cpiBorderBottomColor, TCSSPropertyValue.FromColor(Side.Color), ASTDecl.Important);
            SetProperty(cpiBorderLeftColor, TCSSPropertyValue.FromColor(Side.Color), ASTDecl.Important);
          end;
        end;
        cpiBorderTop:
        begin
          if ParseBorderSideFromNodes(ASTDecl.Value, Side) then
          begin
            SetProperty(cpiBorderTopWidth, TCSSPropertyValue.FromLength(Side.Width), ASTDecl.Important);
            SetProperty(cpiBorderTopStyle, TCSSPropertyValue.FromKeyword(BorderStyleToString(Side.Style)), ASTDecl.Important);
            SetProperty(cpiBorderTopColor, TCSSPropertyValue.FromColor(Side.Color), ASTDecl.Important);
          end;
        end;
        cpiBorderRight:
        begin
          if ParseBorderSideFromNodes(ASTDecl.Value, Side) then
          begin
            SetProperty(cpiBorderRightWidth, TCSSPropertyValue.FromLength(Side.Width), ASTDecl.Important);
            SetProperty(cpiBorderRightStyle, TCSSPropertyValue.FromKeyword(BorderStyleToString(Side.Style)), ASTDecl.Important);
            SetProperty(cpiBorderRightColor, TCSSPropertyValue.FromColor(Side.Color), ASTDecl.Important);
          end;
        end;
        cpiBorderBottom:
        begin
          if ParseBorderSideFromNodes(ASTDecl.Value, Side) then
          begin
            SetProperty(cpiBorderBottomWidth, TCSSPropertyValue.FromLength(Side.Width), ASTDecl.Important);
            SetProperty(cpiBorderBottomStyle, TCSSPropertyValue.FromKeyword(BorderStyleToString(Side.Style)), ASTDecl.Important);
            SetProperty(cpiBorderBottomColor, TCSSPropertyValue.FromColor(Side.Color), ASTDecl.Important);
          end;
        end;
        cpiBorderLeft:
        begin
          if ParseBorderSideFromNodes(ASTDecl.Value, Side) then
          begin
            SetProperty(cpiBorderLeftWidth, TCSSPropertyValue.FromLength(Side.Width), ASTDecl.Important);
            SetProperty(cpiBorderLeftStyle, TCSSPropertyValue.FromKeyword(BorderStyleToString(Side.Style)), ASTDecl.Important);
            SetProperty(cpiBorderLeftColor, TCSSPropertyValue.FromColor(Side.Color), ASTDecl.Important);
          end;
        end;
      else
        SetProperty(PropId, Val, ASTDecl.Important);
      end;
    end
    else
      SetProperty(PropId, Val, ASTDecl.Important);
  end;
end;

class function TCSSStyleBlock.FromDeclarationList(const ADeclarations: TObjectList; const AExpandShorthands: Boolean): TCSSStyleBlock;
begin
  Result := TCSSStyleBlock.Create();
  Result.PopulateFromAST(ADeclarations, AExpandShorthands);
end;

class function TCSSStyleBlock.FromCSS(const ACSS: AnsiString; const AExpandShorthands: Boolean): TCSSStyleBlock;
var
  Tokens: TCSSTokenArray;
  Parser: TCSSParser;
  Decls : TObjectList;
begin
  Result := TCSSStyleBlock.Create();
  Tokens := TokenizeCSS(ACSS);
  Parser := TCSSParser.Create(Tokens);
  try
    Decls := Parser.ParseDeclarationList();
    try
      Result.PopulateFromAST(Decls, AExpandShorthands);
    finally
      Decls.Free();
    end;
  finally
    Parser.Free();
  end;
end;

end.
