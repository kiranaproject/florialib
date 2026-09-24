unit Floria.HTML.DOM;

// Floria.HTML.DOM
// ===============
// HTML5 DOM node hierarchy, elements, and document container for the Floria
// HTML subsystem.
//
// Key Features:
//   - Fully compatible with Floria.XML.DOM and Floria.CSS.Cascade (ICSSElement)
//   - THTMLElement: HTML element base with Id, ClassName, InnerHTML, OuterHTML,
//     InnerText, QuerySelector, and QuerySelectorAll
//   - Specialized element classes: THTMLAnchorElement, THTMLImageElement,
//     THTMLInputElement, THTMLButtonElement, THTMLTableElement, etc.
//   - THTMLDocument: Document root with Head, Body, Title, DocumentElement,
//     GetElementById, GetElementsByTagName, GetElementsByClassName, QuerySelector

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, Classes, Contnrs,
  Floria.XML.Types, Floria.XML.DOM, Floria.CSS.Cascade, Floria.CSS.Selectors,
  Floria.HTML.Types;

type
  THTMLDocument = class;
  THTMLElement = class;

  // ── HTML Document Type Node ────────────────────────────────────────────────

  THTMLDocumentType = class(TXMLDocType)
  public
    function ToHTML(): AnsiString; virtual;
  end;

  // ── HTML Text Node ─────────────────────────────────────────────────────────

  THTMLTextNode = class(TXMLTextNode)
  public
    function ToHTML(): AnsiString; virtual;
  end;

  // ── HTML Comment Node ──────────────────────────────────────────────────────

  THTMLComment = class(TXMLComment)
  public
    function ToHTML(): AnsiString; virtual;
  end;

  // ── HTML Element Node ──────────────────────────────────────────────────────

  THTMLElement = class(TXMLElement)
  private
    function GetId(): AnsiString;
    procedure SetId(const AValue: AnsiString);
    function GetClassName(): AnsiString;
    procedure SetClassName(const AValue: AnsiString);
    function GetTitle(): AnsiString;
    procedure SetTitle(const AValue: AnsiString);
    function GetHidden(): Boolean;
    procedure SetHidden(const AValue: Boolean);
    function GetStyle(): AnsiString;
    procedure SetStyle(const AValue: AnsiString);
    function GetInnerHTML(): AnsiString;
    procedure SetInnerHTML(const AValue: AnsiString);
    function GetOuterHTML(): AnsiString;
    function GetInnerText(): AnsiString;
    procedure SetInnerText(const AValue: AnsiString);
  public
    constructor Create(const ATagName: AnsiString);
    function ToHTML(): AnsiString; virtual;

    function HasClass(const AClassName: AnsiString): Boolean;
    function GetElementsByClassName(const AClassName: AnsiString; const AResults: TObjectList = nil): TObjectList;
    function QuerySelector(const ASelector: AnsiString): THTMLElement;
    function QuerySelectorAll(const ASelector: AnsiString; const AResults: TObjectList = nil): TObjectList;

    property Id         : AnsiString read GetId        write SetId;
    property ClassName  : AnsiString read GetClassName write SetClassName;
    property Title      : AnsiString read GetTitle     write SetTitle;
    property Hidden     : Boolean    read GetHidden    write SetHidden;
    property Style      : AnsiString read GetStyle     write SetStyle;
    property InnerHTML  : AnsiString read GetInnerHTML write SetInnerHTML;
    property OuterHTML  : AnsiString read GetOuterHTML;
    property InnerText  : AnsiString read GetInnerText write SetInnerText;
  end;

  // ── Specialized HTML Elements ──────────────────────────────────────────────

  THTMLAnchorElement = class(THTMLElement)
  private
    function GetHref(): AnsiString;
    procedure SetHref(const AValue: AnsiString);
    function GetTarget(): AnsiString;
    procedure SetTarget(const AValue: AnsiString);
  public
    property Href   : AnsiString read GetHref   write SetHref;
    property Target : AnsiString read GetTarget write SetTarget;
  end;

  THTMLImageElement = class(THTMLElement)
  private
    function GetSrc(): AnsiString;
    procedure SetSrc(const AValue: AnsiString);
    function GetAlt(): AnsiString;
    procedure SetAlt(const AValue: AnsiString);
    function GetWidth(): Integer;
    procedure SetWidth(const AValue: Integer);
    function GetHeight(): Integer;
    procedure SetHeight(const AValue: Integer);
  public
    property Src    : AnsiString read GetSrc    write SetSrc;
    property Alt    : AnsiString read GetAlt    write SetAlt;
    property Width  : Integer    read GetWidth  write SetWidth;
    property Height : Integer    read GetHeight write SetHeight;
  end;

  THTMLInputElement = class(THTMLElement)
  private
    function GetInputType(): AnsiString;
    procedure SetInputType(const AValue: AnsiString);
    function GetValue(): AnsiString;
    procedure SetValue(const AValue: AnsiString);
    function GetName(): AnsiString;
    procedure SetName(const AValue: AnsiString);
    function GetChecked(): Boolean;
    procedure SetChecked(const AValue: Boolean);
    function GetDisabled(): Boolean;
    procedure SetDisabled(const AValue: Boolean);
    function GetPlaceholder(): AnsiString;
    procedure SetPlaceholder(const AValue: AnsiString);
  public
    property InputType   : AnsiString read GetInputType   write SetInputType;
    property Value       : AnsiString read GetValue       write SetValue;
    property Name        : AnsiString read GetName        write SetName;
    property Checked     : Boolean    read GetChecked     write SetChecked;
    property Disabled    : Boolean    read GetDisabled    write SetDisabled;
    property Placeholder : AnsiString read GetPlaceholder write SetPlaceholder;
  end;

  THTMLButtonElement = class(THTMLElement)
  private
    function GetButtonType(): AnsiString;
    procedure SetButtonType(const AValue: AnsiString);
    function GetDisabled(): Boolean;
    procedure SetDisabled(const AValue: Boolean);
  public
    property ButtonType : AnsiString read GetButtonType write SetButtonType;
    property Disabled   : Boolean    read GetDisabled   write SetDisabled;
  end;

  THTMLHeadingElement = class(THTMLElement)
  private
    FLevel: Integer;
  public
    constructor Create(const ATagName: AnsiString; const ALevel: Integer = 1);
    property Level: Integer read FLevel;
  end;

  THTMLParagraphElement = class(THTMLElement);

  THTMLTableElement = class(THTMLElement)
  public
    function GetRows(): TObjectList;
  end;

  THTMLTableRowElement = class(THTMLElement)
  public
    function GetCells(): TObjectList;
    function GetRowIndex(): Integer;
    property RowIndex: Integer read GetRowIndex;
  end;

  THTMLTableCellElement = class(THTMLElement)
  private
    function GetColSpan(): Integer;
    procedure SetColSpan(const AValue: Integer);
    function GetRowSpan(): Integer;
    procedure SetRowSpan(const AValue: Integer);
  public
    function GetCellIndex(): Integer;
    property ColSpan   : Integer read GetColSpan   write SetColSpan;
    property RowSpan   : Integer read GetRowSpan   write SetRowSpan;
    property CellIndex : Integer read GetCellIndex;
  end;

  THTMLScriptElement = class(THTMLElement)
  private
    function GetSrc(): AnsiString;
    procedure SetSrc(const AValue: AnsiString);
    function GetScriptType(): AnsiString;
    procedure SetScriptType(const AValue: AnsiString);
  public
    property Src        : AnsiString read GetSrc        write SetSrc;
    property ScriptType : AnsiString read GetScriptType write SetScriptType;
  end;

  THTMLStyleElement = class(THTMLElement)
  private
    function GetStyleType(): AnsiString;
    procedure SetStyleType(const AValue: AnsiString);
    function GetMedia(): AnsiString;
    procedure SetMedia(const AValue: AnsiString);
  public
    property StyleType : AnsiString read GetStyleType write SetStyleType;
    property Media     : AnsiString read GetMedia     write SetMedia;
  end;

  // ── HTML Document Container ────────────────────────────────────────────────

  THTMLDocument = class(TXMLDocument)
  private
    FDocTypeStr: AnsiString;
    function GetHead(): THTMLElement;
    function GetBody(): THTMLElement;
    function GetTitle(): AnsiString;
    procedure SetTitle(const ATitle: AnsiString);
    function GetDocumentElementHTML(): THTMLElement;
    procedure SetDocumentElementHTML(const AElem: THTMLElement);
  public
    constructor Create();

    function CreateElement(const ATagName: AnsiString): THTMLElement; reintroduce;
    function CreateTextNode(const AText: AnsiString): THTMLTextNode; reintroduce;
    function CreateComment(const AComment: AnsiString): THTMLComment; reintroduce;

    function GetElementById(const AId: AnsiString): THTMLElement;
    function GetElementsByTagName(const ATagName: AnsiString; const AResults: TObjectList = nil): TObjectList; reintroduce;
    function GetElementsByClassName(const AClassName: AnsiString; const AResults: TObjectList = nil): TObjectList;
    function QuerySelector(const ASelector: AnsiString): THTMLElement;
    function QuerySelectorAll(const ASelector: AnsiString; const AResults: TObjectList = nil): TObjectList;

    function ToHTML(): AnsiString; virtual;

    property DocumentElement : THTMLElement     read GetDocumentElementHTML write SetDocumentElementHTML;
    property Head            : THTMLElement     read GetHead;
    property Body            : THTMLElement     read GetBody;
    property Title           : AnsiString       read GetTitle write SetTitle;
    property DocTypeStr      : AnsiString       read FDocTypeStr write FDocTypeStr;
  end;

// Forward reference for fragment parsing used in InnerHTML setter
type
  THTMLFragmentParserFunc = function(const AHTML: AnsiString; AContextElement: THTMLElement): TObjectList;

var
  HTMLFragmentParser: THTMLFragmentParserFunc = nil;

function CreateHTMLElement(const ATagName: AnsiString): THTMLElement;

implementation

// ── THTMLDocumentType ────────────────────────────────────────────────────────

function THTMLDocumentType.ToHTML(): AnsiString;
begin
  Result := '<!DOCTYPE html>';
end;

// ── THTMLTextNode ────────────────────────────────────────────────────────────

function THTMLTextNode.ToHTML(): AnsiString;
begin
  Result := HTMLEncode(Text);
end;

// ── THTMLComment ─────────────────────────────────────────────────────────────

function THTMLComment.ToHTML(): AnsiString;
begin
  Result := '<!--' + Text + '-->';
end;

// ── THTMLElement ─────────────────────────────────────────────────────────────

constructor THTMLElement.Create(const ATagName: AnsiString);
begin
  inherited Create(LowerCase(ATagName));
end;

function THTMLElement.GetId(): AnsiString;
begin
  Result := GetAttribute('id');
end;

procedure THTMLElement.SetId(const AValue: AnsiString);
begin
  SetAttribute('id', AValue);
end;

function THTMLElement.GetClassName(): AnsiString;
begin
  Result := GetAttribute('class');
end;

procedure THTMLElement.SetClassName(const AValue: AnsiString);
begin
  SetAttribute('class', AValue);
end;

function THTMLElement.GetTitle(): AnsiString;
begin
  Result := GetAttribute('title');
end;

procedure THTMLElement.SetTitle(const AValue: AnsiString);
begin
  SetAttribute('title', AValue);
end;

function THTMLElement.GetHidden(): Boolean;
begin
  Result := HasAttribute('hidden');
end;

procedure THTMLElement.SetHidden(const AValue: Boolean);
begin
  if AValue then
    SetAttribute('hidden', '')
  else
    RemoveAttribute('hidden');
end;

function THTMLElement.GetStyle(): AnsiString;
begin
  Result := GetAttribute('style');
end;

procedure THTMLElement.SetStyle(const AValue: AnsiString);
begin
  SetAttribute('style', AValue);
end;

function THTMLElement.GetInnerHTML(): AnsiString;
var
  I: Integer;
  child: TXMLNode;
begin
  Result := '';
  for I := 0 to ChildCount - 1 do
  begin
    child := Children[I];
    if child is THTMLElement then
      Result := Result + THTMLElement(child).ToHTML()
    else if child is THTMLTextNode then
      Result := Result + THTMLTextNode(child).ToHTML()
    else if child is TXMLTextNode then
      Result := Result + HTMLEncode(TXMLTextNode(child).Text)
    else if child is THTMLComment then
      Result := Result + THTMLComment(child).ToHTML()
    else if child is TXMLComment then
      Result := Result + '<!--' + TXMLComment(child).Text + '-->'
    else
      Result := Result + child.ToXML();
  end;
end;

procedure THTMLElement.SetInnerHTML(const AValue: AnsiString);
var
  I: Integer;
  parsedList: TObjectList;
begin
  // Remove existing children
  while ChildCount > 0 do
    RemoveChild(Children[ChildCount - 1]);

  // Parse new content
  if Assigned(HTMLFragmentParser) then
  begin
    parsedList := HTMLFragmentParser(AValue, Self);
    if Assigned(parsedList) then
    begin
      try
        for I := 0 to parsedList.Count - 1 do
          AppendChild(TXMLNode(parsedList[I]));
      finally
        parsedList.Free();
      end;
    end;
  end
  else
  begin
    // Fallback: simple text node
    AppendChild(THTMLTextNode.Create(AValue));
  end;
end;

function THTMLElement.GetOuterHTML(): AnsiString;
begin
  Result := ToHTML();
end;

function THTMLElement.GetInnerText(): AnsiString;
begin
  Result := GetTextContent();
end;

procedure THTMLElement.SetInnerText(const AValue: AnsiString);
begin
  SetTextContent(AValue);
end;

function THTMLElement.ToHTML(): AnsiString;
var
  I: Integer;
  attr: TXMLAttribute;
begin
  Result := '<' + TagName;

  for I := 0 to AttributeCount - 1 do
  begin
    attr := Attributes[I];
    if attr.Value = '' then
      Result := Result + ' ' + attr.Name
    else
      Result := Result + ' ' + attr.Name + '="' + HTMLEncode(attr.Value) + '"';
  end;

  if IsHTMLVoidElement(TagName) then
  begin
    Result := Result + '>';
    Exit;
  end;

  Result := Result + '>' + GetInnerHTML() + '</' + TagName + '>';
end;

function THTMLElement.HasClass(const AClassName: AnsiString): Boolean;
var
  ClsStr: AnsiString;
  Words: TStringList;
  I: Integer;
begin
  Result := False;
  ClsStr := GetAttribute('class');
  if ClsStr = '' then Exit;

  Words := TStringList.Create();
  try
    Words.Delimiter := ' ';
    Words.StrictDelimiter := False;
    Words.DelimitedText := ClsStr;
    for I := 0 to Words.Count - 1 do
    begin
      if SameText(Words[I], AClassName) then
      begin
        Result := True;
        Break;
      end;
    end;
  finally
    Words.Free();
  end;
end;

function THTMLElement.GetElementsByClassName(const AClassName: AnsiString; const AResults: TObjectList): TObjectList;
var
  I: Integer;
  child: TXMLNode;
  elem: THTMLElement;
begin
  if Assigned(AResults) then
    Result := AResults
  else
    Result := TObjectList.Create(False);

  for I := 0 to ChildCount - 1 do
  begin
    child := Children[I];
    if child is THTMLElement then
    begin
      elem := THTMLElement(child);
      if elem.HasClass(AClassName) then
        Result.Add(elem);
      elem.GetElementsByClassName(AClassName, Result);
    end;
  end;
end;

function THTMLElement.QuerySelector(const ASelector: AnsiString): THTMLElement;
var
  list: TObjectList;
begin
  Result := nil;
  list := QuerySelectorAll(ASelector);
  try
    if (list <> nil) and (list.Count > 0) then
      Result := THTMLElement(list[0]);
  finally
    list.Free();
  end;
end;

function THTMLElement.QuerySelectorAll(const ASelector: AnsiString; const AResults: TObjectList): TObjectList;
var
  selList: TCSSSelectorList;

  procedure WalkAndMatch(AElem: THTMLElement);
  var
    I: Integer;
    ch: TXMLNode;
    childElem: THTMLElement;
    spec: TCSSSpecificity;
  begin
    for I := 0 to AElem.ChildCount - 1 do
    begin
      ch := AElem.Children[I];
      if ch is THTMLElement then
      begin
        childElem := THTMLElement(ch);
        if MatchesSelectorList(selList, childElem as ICSSElement, spec) then
          Result.Add(childElem);
        WalkAndMatch(childElem);
      end;
    end;
  end;

begin
  if Assigned(AResults) then
    Result := AResults
  else
    Result := TObjectList.Create(False);

  selList := ParseSelectorListFromCSS(ASelector);
  if not Assigned(selList) then Exit;
  try
    WalkAndMatch(Self);
  finally
    selList.Free();
  end;
end;

// ── Specialized Elements ─────────────────────────────────────────────────────

function THTMLAnchorElement.GetHref(): AnsiString;
begin
  Result := GetAttribute('href');
end;

procedure THTMLAnchorElement.SetHref(const AValue: AnsiString);
begin
  SetAttribute('href', AValue);
end;

function THTMLAnchorElement.GetTarget(): AnsiString;
begin
  Result := GetAttribute('target');
end;

procedure THTMLAnchorElement.SetTarget(const AValue: AnsiString);
begin
  SetAttribute('target', AValue);
end;

function THTMLImageElement.GetSrc(): AnsiString;
begin
  Result := GetAttribute('src');
end;

procedure THTMLImageElement.SetSrc(const AValue: AnsiString);
begin
  SetAttribute('src', AValue);
end;

function THTMLImageElement.GetAlt(): AnsiString;
begin
  Result := GetAttribute('alt');
end;

procedure THTMLImageElement.SetAlt(const AValue: AnsiString);
begin
  SetAttribute('alt', AValue);
end;

function THTMLImageElement.GetWidth(): Integer;
begin
  Result := StrToIntDef(GetAttribute('width'), 0);
end;

procedure THTMLImageElement.SetWidth(const AValue: Integer);
begin
  SetAttribute('width', IntToStr(AValue));
end;

function THTMLImageElement.GetHeight(): Integer;
begin
  Result := StrToIntDef(GetAttribute('height'), 0);
end;

procedure THTMLImageElement.SetHeight(const AValue: Integer);
begin
  SetAttribute('height', IntToStr(AValue));
end;

function THTMLInputElement.GetInputType(): AnsiString;
begin
  Result := GetAttribute('type');
  if Result = '' then Result := 'text';
end;

procedure THTMLInputElement.SetInputType(const AValue: AnsiString);
begin
  SetAttribute('type', AValue);
end;

function THTMLInputElement.GetValue(): AnsiString;
begin
  Result := GetAttribute('value');
end;

procedure THTMLInputElement.SetValue(const AValue: AnsiString);
begin
  SetAttribute('value', AValue);
end;

function THTMLInputElement.GetName(): AnsiString;
begin
  Result := GetAttribute('name');
end;

procedure THTMLInputElement.SetName(const AValue: AnsiString);
begin
  SetAttribute('name', AValue);
end;

function THTMLInputElement.GetChecked(): Boolean;
begin
  Result := HasAttribute('checked');
end;

procedure THTMLInputElement.SetChecked(const AValue: Boolean);
begin
  if AValue then
    SetAttribute('checked', '')
  else
    RemoveAttribute('checked');
end;

function THTMLInputElement.GetDisabled(): Boolean;
begin
  Result := HasAttribute('disabled');
end;

procedure THTMLInputElement.SetDisabled(const AValue: Boolean);
begin
  if AValue then
    SetAttribute('disabled', '')
  else
    RemoveAttribute('disabled');
end;

function THTMLInputElement.GetPlaceholder(): AnsiString;
begin
  Result := GetAttribute('placeholder');
end;

procedure THTMLInputElement.SetPlaceholder(const AValue: AnsiString);
begin
  SetAttribute('placeholder', AValue);
end;

function THTMLButtonElement.GetButtonType(): AnsiString;
begin
  Result := GetAttribute('type');
  if Result = '' then Result := 'submit';
end;

procedure THTMLButtonElement.SetButtonType(const AValue: AnsiString);
begin
  SetAttribute('type', AValue);
end;

function THTMLButtonElement.GetDisabled(): Boolean;
begin
  Result := HasAttribute('disabled');
end;

procedure THTMLButtonElement.SetDisabled(const AValue: Boolean);
begin
  if AValue then
    SetAttribute('disabled', '')
  else
    RemoveAttribute('disabled');
end;

constructor THTMLHeadingElement.Create(const ATagName: AnsiString; const ALevel: Integer);
begin
  inherited Create(ATagName);
  FLevel := ALevel;
end;

function THTMLTableElement.GetRows(): TObjectList;
var
  I, J: Integer;
  child, subChild: TXMLNode;
begin
  Result := TObjectList.Create(False);
  for I := 0 to ChildCount - 1 do
  begin
    child := Children[I];
    if (child is THTMLElement) and (THTMLElement(child).TagName = 'tr') then
      Result.Add(child)
    else if (child is THTMLElement) and ((THTMLElement(child).TagName = 'tbody') or
                                         (THTMLElement(child).TagName = 'thead') or
                                         (THTMLElement(child).TagName = 'tfoot')) then
    begin
      for J := 0 to child.ChildCount - 1 do
      begin
        subChild := child.Children[J];
        if (subChild is THTMLElement) and (THTMLElement(subChild).TagName = 'tr') then
          Result.Add(subChild);
      end;
    end;
  end;
end;

function THTMLTableRowElement.GetCells(): TObjectList;
var
  I: Integer;
  child: TXMLNode;
  elem: THTMLElement;
begin
  Result := TObjectList.Create(False);
  for I := 0 to ChildCount - 1 do
  begin
    child := Children[I];
    if child is THTMLElement then
    begin
      elem := THTMLElement(child);
      if (elem.TagName = 'td') or (elem.TagName = 'th') then
        Result.Add(elem);
    end;
  end;
end;

function THTMLTableRowElement.GetRowIndex(): Integer;
var
  p: TXMLNode;
  I, idx: Integer;
begin
  Result := -1;
  p := Parent;
  if not Assigned(p) then Exit;

  idx := 0;
  for I := 0 to p.ChildCount - 1 do
  begin
    if p.Children[I] = Self then
      Exit(idx);
    if (p.Children[I] is THTMLElement) and (THTMLElement(p.Children[I]).TagName = 'tr') then
      Inc(idx);
  end;
end;

function THTMLTableCellElement.GetColSpan(): Integer;
begin
  Result := StrToIntDef(GetAttribute('colspan'), 1);
  if Result < 1 then Result := 1;
end;

procedure THTMLTableCellElement.SetColSpan(const AValue: Integer);
begin
  SetAttribute('colspan', IntToStr(AValue));
end;

function THTMLTableCellElement.GetRowSpan(): Integer;
begin
  Result := StrToIntDef(GetAttribute('rowspan'), 1);
  if Result < 1 then Result := 1;
end;

procedure THTMLTableCellElement.SetRowSpan(const AValue: Integer);
begin
  SetAttribute('rowspan', IntToStr(AValue));
end;

function THTMLTableCellElement.GetCellIndex(): Integer;
var
  p: TXMLNode;
  I, idx: Integer;
  elem: THTMLElement;
begin
  Result := -1;
  p := Parent;
  if not Assigned(p) then Exit;

  idx := 0;
  for I := 0 to p.ChildCount - 1 do
  begin
    if p.Children[I] = Self then
      Exit(idx);
    if p.Children[I] is THTMLElement then
    begin
      elem := THTMLElement(p.Children[I]);
      if (elem.TagName = 'td') or (elem.TagName = 'th') then
        Inc(idx);
    end;
  end;
end;

function THTMLScriptElement.GetSrc(): AnsiString;
begin
  Result := GetAttribute('src');
end;

procedure THTMLScriptElement.SetSrc(const AValue: AnsiString);
begin
  SetAttribute('src', AValue);
end;

function THTMLScriptElement.GetScriptType(): AnsiString;
begin
  Result := GetAttribute('type');
end;

procedure THTMLScriptElement.SetScriptType(const AValue: AnsiString);
begin
  SetAttribute('type', AValue);
end;

function THTMLStyleElement.GetStyleType(): AnsiString;
begin
  Result := GetAttribute('type');
end;

procedure THTMLStyleElement.SetStyleType(const AValue: AnsiString);
begin
  SetAttribute('type', AValue);
end;

function THTMLStyleElement.GetMedia(): AnsiString;
begin
  Result := GetAttribute('media');
end;

procedure THTMLStyleElement.SetMedia(const AValue: AnsiString);
begin
  SetAttribute('media', AValue);
end;

// ── THTMLDocument ────────────────────────────────────────────────────────────

constructor THTMLDocument.Create();
begin
  inherited Create();
  FDocTypeStr := '<!DOCTYPE html>';
end;

function THTMLDocument.GetDocumentElementHTML(): THTMLElement;
var
  elem: TXMLElement;
begin
  elem := inherited DocumentElement;
  if Assigned(elem) and (elem is THTMLElement) then
    Result := THTMLElement(elem)
  else
    Result := nil;
end;

procedure THTMLDocument.SetDocumentElementHTML(const AElem: THTMLElement);
var
  CurRoot: TXMLElement;
begin
  CurRoot := inherited DocumentElement;
  if CurRoot <> nil then
    RemoveChild(CurRoot);
  if AElem <> nil then
    AppendChild(AElem);
end;

function THTMLDocument.GetHead(): THTMLElement;
var
  docElem: THTMLElement;
  I: Integer;
  child: TXMLNode;
begin
  Result := nil;
  docElem := DocumentElement;
  if not Assigned(docElem) then Exit;

  for I := 0 to docElem.ChildCount - 1 do
  begin
    child := docElem.Children[I];
    if (child is THTMLElement) and (THTMLElement(child).TagName = 'head') then
      Exit(THTMLElement(child));
  end;
end;

function THTMLDocument.GetBody(): THTMLElement;
var
  docElem: THTMLElement;
  I: Integer;
  child: TXMLNode;
begin
  Result := nil;
  docElem := DocumentElement;
  if not Assigned(docElem) then Exit;

  for I := 0 to docElem.ChildCount - 1 do
  begin
    child := docElem.Children[I];
    if (child is THTMLElement) and (THTMLElement(child).TagName = 'body') then
      Exit(THTMLElement(child));
  end;
end;

function THTMLDocument.GetTitle(): AnsiString;
var
  h: THTMLElement;
  I: Integer;
  child: TXMLNode;
begin
  Result := '';
  h := Head;
  if not Assigned(h) then Exit;

  for I := 0 to h.ChildCount - 1 do
  begin
    child := h.Children[I];
    if (child is THTMLElement) and (THTMLElement(child).TagName = 'title') then
      Exit(THTMLElement(child).GetTextContent());
  end;
end;

procedure THTMLDocument.SetTitle(const ATitle: AnsiString);
var
  h, titleElem: THTMLElement;
  I: Integer;
  child: TXMLNode;
begin
  h := Head;
  if not Assigned(h) then
  begin
    if not Assigned(DocumentElement) then
      DocumentElement := CreateElement('html');
    h := CreateElement('head');
    DocumentElement.InsertBefore(h, DocumentElement.FirstChild);
  end;

  titleElem := nil;
  for I := 0 to h.ChildCount - 1 do
  begin
    child := h.Children[I];
    if (child is THTMLElement) and (THTMLElement(child).TagName = 'title') then
    begin
      titleElem := THTMLElement(child);
      Break;
    end;
  end;

  if not Assigned(titleElem) then
  begin
    titleElem := CreateElement('title');
    h.AppendChild(titleElem);
  end;

  titleElem.SetTextContent(ATitle);
end;

function CreateHTMLElement(const ATagName: AnsiString): THTMLElement;
var
  T: AnsiString;
begin
  T := LowerCase(ATagName);
  if T = 'a' then
    Result := THTMLAnchorElement.Create(T)
  else if T = 'img' then
    Result := THTMLImageElement.Create(T)
  else if T = 'input' then
    Result := THTMLInputElement.Create(T)
  else if T = 'button' then
    Result := THTMLButtonElement.Create(T)
  else if T = 'p' then
    Result := THTMLParagraphElement.Create(T)
  else if T = 'table' then
    Result := THTMLTableElement.Create(T)
  else if T = 'tr' then
    Result := THTMLTableRowElement.Create(T)
  else if (T = 'td') or (T = 'th') then
    Result := THTMLTableCellElement.Create(T)
  else if T = 'script' then
    Result := THTMLScriptElement.Create(T)
  else if T = 'style' then
    Result := THTMLStyleElement.Create(T)
  else if (Length(T) = 2) and (T[1] = 'h') and (T[2] in ['1'..'6']) then
    Result := THTMLHeadingElement.Create(T, Ord(T[2]) - Ord('0'))
  else
    Result := THTMLElement.Create(T);
end;

function THTMLDocument.CreateElement(const ATagName: AnsiString): THTMLElement;
begin
  Result := CreateHTMLElement(ATagName);
end;

function THTMLDocument.CreateTextNode(const AText: AnsiString): THTMLTextNode;
begin
  Result := THTMLTextNode.Create(AText);
end;

function THTMLDocument.CreateComment(const AComment: AnsiString): THTMLComment;
begin
  Result := THTMLComment.Create(AComment);
end;

function THTMLDocument.GetElementById(const AId: AnsiString): THTMLElement;
var
  docElem: THTMLElement;
  elem: TXMLElement;
begin
  Result := nil;
  docElem := DocumentElement;
  if not Assigned(docElem) then Exit;

  elem := docElem.FindElementById(AId);
  if Assigned(elem) and (elem is THTMLElement) then
    Result := THTMLElement(elem);
end;

function THTMLDocument.GetElementsByTagName(const ATagName: AnsiString; const AResults: TObjectList): TObjectList;
var
  docElem: THTMLElement;
begin
  if Assigned(AResults) then
    Result := AResults
  else
    Result := TObjectList.Create(False);

  docElem := DocumentElement;
  if not Assigned(docElem) then Exit;

  if (ATagName = '*') or (docElem.TagName = LowerCase(ATagName)) then
    Result.Add(docElem);

  docElem.GetElementsByTagName(LowerCase(ATagName), Result);
end;

function THTMLDocument.GetElementsByClassName(const AClassName: AnsiString; const AResults: TObjectList): TObjectList;
var
  docElem: THTMLElement;
begin
  if Assigned(AResults) then
    Result := AResults
  else
    Result := TObjectList.Create(False);

  docElem := DocumentElement;
  if not Assigned(docElem) then Exit;

  if docElem.HasClass(AClassName) then
    Result.Add(docElem);

  docElem.GetElementsByClassName(AClassName, Result);
end;

function THTMLDocument.QuerySelector(const ASelector: AnsiString): THTMLElement;
var
  list: TObjectList;
begin
  Result := nil;
  list := QuerySelectorAll(ASelector);
  try
    if (list <> nil) and (list.Count > 0) then
      Result := THTMLElement(list[0]);
  finally
    list.Free();
  end;
end;

function THTMLDocument.QuerySelectorAll(const ASelector: AnsiString; const AResults: TObjectList): TObjectList;
var
  docElem: THTMLElement;
  selList: TCSSSelectorList;
  spec: TCSSSpecificity;
begin
  if Assigned(AResults) then
    Result := AResults
  else
    Result := TObjectList.Create(False);

  docElem := DocumentElement;
  if not Assigned(docElem) then Exit;

  selList := ParseSelectorListFromCSS(ASelector);
  if not Assigned(selList) then Exit;
  try
    if MatchesSelectorList(selList, docElem as ICSSElement, spec) then
      Result.Add(docElem);
    docElem.QuerySelectorAll(ASelector, Result);
  finally
    selList.Free();
  end;
end;

function THTMLDocument.ToHTML(): AnsiString;
var
  docElem: THTMLElement;
begin
  Result := FDocTypeStr;
  if Result <> '' then Result := Result + LineEnding;

  docElem := DocumentElement;
  if Assigned(docElem) then
    Result := Result + docElem.ToHTML();
end;

end.
