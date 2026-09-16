unit Floria.XML.DOM;

// Floria.XML.DOM
// ==============
// W3C DOM Core Level 1/2 compatible XML Document Object Model for the Floria
// subsystem.
//
// Key Classes:
//   - TXMLNode: Abstract node base class with hierarchical tree navigation
//   - TXMLDocument: Top-level document container with root element and factory
//   - TXMLElement: Element node with typed attributes, implementing ICSSElement
//   - TXMLTextNode: Character data representation
//   - TXMLCDataSection: Raw unparsed character blocks
//   - TXMLComment: Comment nodes
//   - TXMLProcessingInstruction: Target + data processing directives

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, Classes, Contnrs,
  Floria.XML.Types, Floria.CSS.Cascade;

type
  TXMLDocument = class;
  TXMLElement = class;

  // ── Abstract Base Node ─────────────────────────────────────────────────────

  TXMLNode = class(TObject)
  private
    FNodeType   : TXMLNodeType;
    FParent     : TXMLNode;
    FChildNodes : TObjectList; // owns children

    function GetChildCount(): Integer;
    function GetChild(const AIndex: Integer): TXMLNode;
    function GetFirstChild(): TXMLNode;
    function GetLastChild(): TXMLNode;
    function GetPreviousSibling(): TXMLNode;
    function GetNextSibling(): TXMLNode;
  protected
    procedure SetParent(const AParent: TXMLNode); virtual;
  public
    constructor Create(const AType: TXMLNodeType);
    destructor Destroy(); override;

    function AppendChild(const AChild: TXMLNode): TXMLNode; virtual;
    function InsertBefore(const ANewChild, ARefChild: TXMLNode): TXMLNode; virtual;
    function RemoveChild(const AChild: TXMLNode): TXMLNode; virtual;
    function HasChildNodes(): Boolean;

    function ToXML(const AIndent: AnsiString = ''): AnsiString; virtual; abstract;

    property NodeType        : TXMLNodeType read FNodeType;
    property Parent          : TXMLNode     read FParent;
    property ChildCount      : Integer      read GetChildCount;
    property Children[AIndex: Integer]: TXMLNode read GetChild; default;
    property FirstChild      : TXMLNode     read GetFirstChild;
    property LastChild       : TXMLNode     read GetLastChild;
    property PreviousSibling : TXMLNode     read GetPreviousSibling;
    property NextSibling     : TXMLNode     read GetNextSibling;
  end;

  // ── Text Node ──────────────────────────────────────────────────────────────

  TXMLTextNode = class(TXMLNode)
  private
    FText: AnsiString;
  public
    constructor Create(const AText: AnsiString);
    function ToXML(const AIndent: AnsiString = ''): AnsiString; override;
    property Text: AnsiString read FText write FText;
  end;

  // ── CDATA Section Node ─────────────────────────────────────────────────────

  TXMLCDataSection = class(TXMLTextNode)
  public
    constructor Create(const AData: AnsiString);
    function ToXML(const AIndent: AnsiString = ''): AnsiString; override;
  end;

  // ── Comment Node ───────────────────────────────────────────────────────────

  TXMLComment = class(TXMLNode)
  private
    FText: AnsiString;
  public
    constructor Create(const AText: AnsiString);
    function ToXML(const AIndent: AnsiString = ''): AnsiString; override;
    property Text: AnsiString read FText write FText;
  end;

  // ── Processing Instruction Node ────────────────────────────────────────────

  TXMLProcessingInstruction = class(TXMLNode)
  private
    FTarget : AnsiString;
    FData   : AnsiString;
  public
    constructor Create(const ATarget, AData: AnsiString);
    function ToXML(const AIndent: AnsiString = ''): AnsiString; override;
    property Target : AnsiString read FTarget write FTarget;
    property Data   : AnsiString read FData   write FData;
  end;

  // ── DocType Node ───────────────────────────────────────────────────────────

  TXMLDocType = class(TXMLNode)
  private
    FRootElement : AnsiString;
    FPublicId    : AnsiString;
    FSystemId    : AnsiString;
    FSubset      : AnsiString;
  public
    constructor Create(const ARoot, APublic, ASystem, ASubset: AnsiString);
    function ToXML(const AIndent: AnsiString = ''): AnsiString; override;
    property RootElement : AnsiString read FRootElement write FRootElement;
    property PublicId    : AnsiString read FPublicId    write FPublicId;
    property SystemId    : AnsiString read FSystemId    write FSystemId;
    property Subset      : AnsiString read FSubset      write FSubset;
  end;

  // ── XML Attribute ──────────────────────────────────────────────────────────

  TXMLAttribute = class(TObject)
  private
    FName      : AnsiString;
    FValue     : AnsiString;
    FPrefix    : AnsiString;
    FLocalName : AnsiString;
    procedure SplitPrefix();
  public
    constructor Create(const AName, AValue: AnsiString);
    property Name      : AnsiString read FName      write FName;
    property Value     : AnsiString read FValue     write FValue;
    property Prefix    : AnsiString read FPrefix;
    property LocalName : AnsiString read FLocalName;
  end;

  // ── XML Element Node (with ICSSElement Bridge) ──────────────────────────────

  TXMLElement = class(TXMLNode, ICSSElement)
  private
    FTagName    : AnsiString;
    FPrefix     : AnsiString;
    FLocalName  : AnsiString;
    FAttributes : TObjectList; // owns TXMLAttribute

    procedure SplitTagName();
    function GetAttributeCount(): Integer;
    function GetAttributeItem(const AIndex: Integer): TXMLAttribute;

    // ICSSElement implementation
    function QueryInterface(constref IID: TGUID; out Obj): HResult; cdecl;
    function _AddRef(): Integer; cdecl;
    function _Release(): Integer; cdecl;

    function ICSSElement.GetTagName = CSS_GetTagName;
    function ICSSElement.GetId = CSS_GetId;
    function ICSSElement.HasClass = CSS_HasClass;
    function ICSSElement.HasAttribute = CSS_HasAttribute;
    function ICSSElement.GetAttribute = CSS_GetAttribute;
    function ICSSElement.GetParent = CSS_GetParent;
    function ICSSElement.GetPreviousSibling = CSS_GetPreviousSibling;
    function ICSSElement.GetChildIndex = CSS_GetChildIndex;
    function ICSSElement.GetSiblingCount = CSS_GetSiblingCount;
    function ICSSElement.IsHovered = CSS_IsHovered;
    function ICSSElement.IsFocused = CSS_IsFocused;
    function ICSSElement.IsActive = CSS_IsActive;
    function ICSSElement.IsDisabled = CSS_IsDisabled;
    function ICSSElement.IsChecked = CSS_IsChecked;

    function CSS_GetTagName(): AnsiString;
    function CSS_GetId(): AnsiString;
    function CSS_HasClass(const AClass: AnsiString): Boolean;
    function CSS_HasAttribute(const AName: AnsiString): Boolean;
    function CSS_GetAttribute(const AName: AnsiString): AnsiString;
    function CSS_GetParent(): ICSSElement;
    function CSS_GetPreviousSibling(): ICSSElement;
    function CSS_GetChildIndex(): Integer;
    function CSS_GetSiblingCount(): Integer;
    function CSS_IsHovered(): Boolean;
    function CSS_IsFocused(): Boolean;
    function CSS_IsActive(): Boolean;
    function CSS_IsDisabled(): Boolean;
    function CSS_IsChecked(): Boolean;
  public
    constructor Create(const ATagName: AnsiString);
    destructor Destroy(); override;

    // Attribute Operations
    function GetAttribute(const AName: AnsiString): AnsiString;
    procedure SetAttribute(const AName, AValue: AnsiString);
    function HasAttribute(const AName: AnsiString): Boolean;
    procedure RemoveAttribute(const AName: AnsiString);
    function FindAttribute(const AName: AnsiString): TXMLAttribute;

    // Element Tree Helpers
    function GetFirstChildElement(): TXMLElement;
    function GetNextSiblingElement(): TXMLElement;
    function GetPreviousSiblingElement(): TXMLElement;
    function GetSiblingElementIndex(): Integer;
    function GetSiblingElementCount(): Integer;

    // Content Helpers
    function GetTextContent(): AnsiString;
    procedure SetTextContent(const AText: AnsiString);

    // Queries
    function FindElementById(const AId: AnsiString): TXMLElement;
    procedure GetElementsByTagName(const ATagName: AnsiString; const AResults: TObjectList);

    function ToXML(const AIndent: AnsiString = ''): AnsiString; override;

    property TagName        : AnsiString    read FTagName write FTagName;
    property Prefix         : AnsiString    read FPrefix;
    property LocalName      : AnsiString    read FLocalName;
    property AttributeCount : Integer       read GetAttributeCount;
    property Attributes[AIndex: Integer]: TXMLAttribute read GetAttributeItem;
    property TextContent    : AnsiString    read GetTextContent write SetTextContent;
  end;

  // ── XML Document Root ──────────────────────────────────────────────────────

  TXMLDocument = class(TXMLNode)
  private
    FVersion    : AnsiString;
    FEncoding   : AnsiString;
    FStandalone : AnsiString;

    function GetDocumentElement(): TXMLElement;
    procedure SetDocumentElement(const AElem: TXMLElement);
  public
    constructor Create();

    // Node Factories
    function CreateElement(const ATagName: AnsiString): TXMLElement;
    function CreateTextNode(const AText: AnsiString): TXMLTextNode;
    function CreateCDataSection(const AData: AnsiString): TXMLCDataSection;
    function CreateComment(const AComment: AnsiString): TXMLComment;
    function CreateProcessingInstruction(const ATarget, AData: AnsiString): TXMLProcessingInstruction;
    function CreateDocType(const ARoot, APublic, ASystem, ASubset: AnsiString): TXMLDocType;

    // Queries
    function FindElementById(const AId: AnsiString): TXMLElement;
    function GetElementsByTagName(const ATagName: AnsiString): TObjectList;

    // Serialization
    function ToXML(const AIndent: AnsiString = ''): AnsiString; override;
    function SaveToString(const AIncludeProlog: Boolean = True): AnsiString;
    procedure SaveToFile(const APath: AnsiString; const AIncludeProlog: Boolean = True);

    property DocumentElement : TXMLElement read GetDocumentElement write SetDocumentElement;
    property Version         : AnsiString  read FVersion         write FVersion;
    property Encoding        : AnsiString  read FEncoding        write FEncoding;
    property Standalone      : AnsiString  read FStandalone      write FStandalone;
  end;

implementation

// ── TXMLNode ────────────────────────────────────────────────────────────────

constructor TXMLNode.Create(const AType: TXMLNodeType);
begin
  inherited Create();
  FNodeType   := AType;
  FParent     := nil;
  FChildNodes := TObjectList.Create(True); // owns children
end;

destructor TXMLNode.Destroy();
begin
  FChildNodes.Free();
  inherited Destroy();
end;

procedure TXMLNode.SetParent(const AParent: TXMLNode);
begin
  FParent := AParent;
end;

function TXMLNode.GetChildCount(): Integer;
begin
  Result := FChildNodes.Count;
end;

function TXMLNode.GetChild(const AIndex: Integer): TXMLNode;
begin
  Result := TXMLNode(FChildNodes[AIndex]);
end;

function TXMLNode.GetFirstChild(): TXMLNode;
begin
  if FChildNodes.Count > 0 then
    Result := TXMLNode(FChildNodes[0])
  else
    Result := nil;
end;

function TXMLNode.GetLastChild(): TXMLNode;
begin
  if FChildNodes.Count > 0 then
    Result := TXMLNode(FChildNodes[FChildNodes.Count - 1])
  else
    Result := nil;
end;

function TXMLNode.GetPreviousSibling(): TXMLNode;
var
  Idx: Integer;
begin
  Result := nil;
  if FParent = nil then Exit;
  Idx := FParent.FChildNodes.IndexOf(Self);
  if Idx > 0 then
    Result := TXMLNode(FParent.FChildNodes[Idx - 1]);
end;

function TXMLNode.GetNextSibling(): TXMLNode;
var
  Idx: Integer;
begin
  Result := nil;
  if FParent = nil then Exit;
  Idx := FParent.FChildNodes.IndexOf(Self);
  if (Idx >= 0) and (Idx < FParent.FChildNodes.Count - 1) then
    Result := TXMLNode(FParent.FChildNodes[Idx + 1]);
end;

function TXMLNode.AppendChild(const AChild: TXMLNode): TXMLNode;
begin
  if AChild <> nil then
  begin
    if AChild.FParent <> nil then
      AChild.FParent.RemoveChild(AChild);
    AChild.SetParent(Self);
    FChildNodes.Add(AChild);
  end;
  Result := AChild;
end;

function TXMLNode.InsertBefore(const ANewChild, ARefChild: TXMLNode): TXMLNode;
var
  Idx: Integer;
begin
  if ANewChild = nil then
  begin
    Result := nil;
    Exit;
  end;

  if ARefChild = nil then
  begin
    Result := AppendChild(ANewChild);
    Exit;
  end;

  Idx := FChildNodes.IndexOf(ARefChild);
  if Idx < 0 then
  begin
    Result := AppendChild(ANewChild);
    Exit;
  end;

  if ANewChild.FParent <> nil then
    ANewChild.FParent.RemoveChild(ANewChild);
  ANewChild.SetParent(Self);
  FChildNodes.Insert(Idx, ANewChild);
  Result := ANewChild;
end;

function TXMLNode.RemoveChild(const AChild: TXMLNode): TXMLNode;
var
  Idx: Integer;
begin
  Result := nil;
  if AChild = nil then Exit;
  Idx := FChildNodes.IndexOf(AChild);
  if Idx >= 0 then
  begin
    AChild.SetParent(nil);
    FChildNodes.Extract(AChild); // detach without freeing
    Result := AChild;
  end;
end;

function TXMLNode.HasChildNodes(): Boolean;
begin
  Result := FChildNodes.Count > 0;
end;

// ── TXMLTextNode ────────────────────────────────────────────────────────────

constructor TXMLTextNode.Create(const AText: AnsiString);
begin
  inherited Create(xntText);
  FText := AText;
end;

function TXMLTextNode.ToXML(const AIndent: AnsiString): AnsiString;
begin
  Result := XMLEncode(FText);
end;

// ── TXMLCDataSection ────────────────────────────────────────────────────────

constructor TXMLCDataSection.Create(const AData: AnsiString);
begin
  inherited Create(AData);
  FNodeType := xntCData;
end;

function TXMLCDataSection.ToXML(const AIndent: AnsiString): AnsiString;
begin
  Result := '<![CDATA[' + FText + ']]>';
end;

// ── TXMLComment ─────────────────────────────────────────────────────────────

constructor TXMLComment.Create(const AText: AnsiString);
begin
  inherited Create(xntComment);
  FText := AText;
end;

function TXMLComment.ToXML(const AIndent: AnsiString): AnsiString;
begin
  Result := AIndent + '<!--' + FText + '-->';
end;

// ── TXMLProcessingInstruction ───────────────────────────────────────────────

constructor TXMLProcessingInstruction.Create(const ATarget, AData: AnsiString);
begin
  inherited Create(xntProcessingInstruction);
  FTarget := ATarget;
  FData   := AData;
end;

function TXMLProcessingInstruction.ToXML(const AIndent: AnsiString): AnsiString;
begin
  if FData <> '' then
    Result := AIndent + '<?' + FTarget + ' ' + FData + '?>'
  else
    Result := AIndent + '<?' + FTarget + '?>';
end;

// ── TXMLDocType ─────────────────────────────────────────────────────────────

constructor TXMLDocType.Create(const ARoot, APublic, ASystem, ASubset: AnsiString);
begin
  inherited Create(xntDocType);
  FRootElement := ARoot;
  FPublicId    := APublic;
  FSystemId    := ASystem;
  FSubset      := ASubset;
end;

function TXMLDocType.ToXML(const AIndent: AnsiString): AnsiString;
begin
  Result := AIndent + '<!DOCTYPE ' + FRootElement;
  if FPublicId <> '' then
    Result := Result + ' PUBLIC "' + FPublicId + '" "' + FSystemId + '"'
  else if FSystemId <> '' then
    Result := Result + ' SYSTEM "' + FSystemId + '"';

  if FSubset <> '' then
    Result := Result + ' [' + FSubset + ']';
  Result := Result + '>';
end;

// ── TXMLAttribute ───────────────────────────────────────────────────────────

constructor TXMLAttribute.Create(const AName, AValue: AnsiString);
begin
  inherited Create();
  FName  := AName;
  FValue := AValue;
  SplitPrefix();
end;

procedure TXMLAttribute.SplitPrefix();
var
  ColonPos: Integer;
begin
  ColonPos := Pos(':', FName);
  if ColonPos > 0 then
  begin
    FPrefix    := Copy(FName, 1, ColonPos - 1);
    FLocalName := Copy(FName, ColonPos + 1, Length(FName) - ColonPos);
  end
  else
  begin
    FPrefix    := '';
    FLocalName := FName;
  end;
end;

// ── TXMLElement ─────────────────────────────────────────────────────────────

constructor TXMLElement.Create(const ATagName: AnsiString);
begin
  inherited Create(xntElement);
  FTagName    := ATagName;
  FAttributes := TObjectList.Create(True); // owns attributes
  SplitTagName();
end;

destructor TXMLElement.Destroy();
begin
  FAttributes.Free();
  inherited Destroy();
end;

procedure TXMLElement.SplitTagName();
var
  ColonPos: Integer;
begin
  ColonPos := Pos(':', FTagName);
  if ColonPos > 0 then
  begin
    FPrefix    := Copy(FTagName, 1, ColonPos - 1);
    FLocalName := Copy(FTagName, ColonPos + 1, Length(FTagName) - ColonPos);
  end
  else
  begin
    FPrefix    := '';
    FLocalName := FTagName;
  end;
end;

function TXMLElement.GetAttributeCount(): Integer;
begin
  Result := FAttributes.Count;
end;

function TXMLElement.GetAttributeItem(const AIndex: Integer): TXMLAttribute;
begin
  Result := TXMLAttribute(FAttributes[AIndex]);
end;

function TXMLElement.FindAttribute(const AName: AnsiString): TXMLAttribute;
var
  I: Integer;
  Attr: TXMLAttribute;
begin
  Result := nil;
  for I := 0 to FAttributes.Count - 1 do
  begin
    Attr := TXMLAttribute(FAttributes[I]);
    if SameText(Attr.Name, AName) then
    begin
      Result := Attr;
      Exit;
    end;
  end;
end;

function TXMLElement.GetAttribute(const AName: AnsiString): AnsiString;
var
  Attr: TXMLAttribute;
begin
  Attr := FindAttribute(AName);
  if Attr <> nil then
    Result := Attr.Value
  else
    Result := '';
end;

procedure TXMLElement.SetAttribute(const AName, AValue: AnsiString);
var
  Attr: TXMLAttribute;
begin
  Attr := FindAttribute(AName);
  if Attr <> nil then
    Attr.Value := AValue
  else
    FAttributes.Add(TXMLAttribute.Create(AName, AValue));
end;

function TXMLElement.HasAttribute(const AName: AnsiString): Boolean;
begin
  Result := FindAttribute(AName) <> nil;
end;

procedure TXMLElement.RemoveAttribute(const AName: AnsiString);
var
  I: Integer;
  Attr: TXMLAttribute;
begin
  for I := FAttributes.Count - 1 downto 0 do
  begin
    Attr := TXMLAttribute(FAttributes[I]);
    if SameText(Attr.Name, AName) then
    begin
      FAttributes.Delete(I);
      Exit;
    end;
  end;
end;

function TXMLElement.GetFirstChildElement(): TXMLElement;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to FChildNodes.Count - 1 do
  begin
    if TXMLNode(FChildNodes[I]).NodeType = xntElement then
    begin
      Result := TXMLElement(FChildNodes[I]);
      Exit;
    end;
  end;
end;

function TXMLElement.GetNextSiblingElement(): TXMLElement;
var
  Node: TXMLNode;
begin
  Result := nil;
  Node := GetNextSibling();
  while Node <> nil do
  begin
    if Node.NodeType = xntElement then
    begin
      Result := TXMLElement(Node);
      Exit;
    end;
    Node := Node.GetNextSibling();
  end;
end;

function TXMLElement.GetPreviousSiblingElement(): TXMLElement;
var
  Node: TXMLNode;
begin
  Result := nil;
  Node := GetPreviousSibling();
  while Node <> nil do
  begin
    if Node.NodeType = xntElement then
    begin
      Result := TXMLElement(Node);
      Exit;
    end;
    Node := Node.GetPreviousSibling();
  end;
end;

function TXMLElement.GetSiblingElementIndex(): Integer;
var
  Idx, I: Integer;
  Node: TXMLNode;
begin
  Result := 1;
  if FParent = nil then Exit;

  Idx := 0;
  for I := 0 to FParent.FChildNodes.Count - 1 do
  begin
    Node := TXMLNode(FParent.FChildNodes[I]);
    if Node.NodeType = xntElement then
    begin
      Inc(Idx);
      if Node = Self then
      begin
        Result := Idx;
        Exit;
      end;
    end;
  end;
end;

function TXMLElement.GetSiblingElementCount(): Integer;
var
  Count, I: Integer;
  Node: TXMLNode;
begin
  Result := 1;
  if FParent = nil then Exit;

  Count := 0;
  for I := 0 to FParent.FChildNodes.Count - 1 do
  begin
    Node := TXMLNode(FParent.FChildNodes[I]);
    if Node.NodeType = xntElement then
      Inc(Count);
  end;
  Result := Count;
end;

function TXMLElement.GetTextContent(): AnsiString;
var
  I: Integer;
  Node: TXMLNode;
begin
  Result := '';
  for I := 0 to FChildNodes.Count - 1 do
  begin
    Node := TXMLNode(FChildNodes[I]);
    case Node.NodeType of
      xntText, xntCData:
        Result := Result + TXMLTextNode(Node).Text;
      xntElement:
        Result := Result + TXMLElement(Node).GetTextContent();
    end;
  end;
end;

procedure TXMLElement.SetTextContent(const AText: AnsiString);
begin
  FChildNodes.Clear();
  if AText <> '' then
    AppendChild(TXMLTextNode.Create(AText));
end;

function TXMLElement.FindElementById(const AId: AnsiString): TXMLElement;
var
  I: Integer;
  Child: TXMLNode;
  Found: TXMLElement;
begin
  Result := nil;
  if SameText(GetAttribute('id'), AId) then
  begin
    Result := Self;
    Exit;
  end;

  for I := 0 to FChildNodes.Count - 1 do
  begin
    Child := TXMLNode(FChildNodes[I]);
    if Child.NodeType = xntElement then
    begin
      Found := TXMLElement(Child).FindElementById(AId);
      if Found <> nil then
      begin
        Result := Found;
        Exit;
      end;
    end;
  end;
end;

procedure TXMLElement.GetElementsByTagName(const ATagName: AnsiString; const AResults: TObjectList);
var
  I: Integer;
  Child: TXMLNode;
  MatchAll: Boolean;
begin
  if AResults = nil then Exit;
  MatchAll := ATagName = '*';

  for I := 0 to FChildNodes.Count - 1 do
  begin
    Child := TXMLNode(FChildNodes[I]);
    if Child.NodeType = xntElement then
    begin
      if MatchAll or SameText(TXMLElement(Child).TagName, ATagName) or SameText(TXMLElement(Child).LocalName, ATagName) then
        AResults.Add(Child);
      TXMLElement(Child).GetElementsByTagName(ATagName, AResults);
    end;
  end;
end;

function TXMLElement.ToXML(const AIndent: AnsiString): AnsiString;
var
  I: Integer;
  Attr: TXMLAttribute;
  HasNonTextChildren: Boolean;
  NextIndent: AnsiString;
begin
  Result := AIndent + '<' + FTagName;

  for I := 0 to FAttributes.Count - 1 do
  begin
    Attr := TXMLAttribute(FAttributes[I]);
    Result := Result + ' ' + Attr.Name + '="' + XMLEncode(Attr.Value) + '"';
  end;

  if FChildNodes.Count = 0 then
  begin
    Result := Result + ' />';
    Exit;
  end;

  Result := Result + '>';

  // Check if children contain any non-text elements
  HasNonTextChildren := False;
  for I := 0 to FChildNodes.Count - 1 do
  begin
    if TXMLNode(FChildNodes[I]).NodeType <> xntText then
    begin
      HasNonTextChildren := True;
      Break;
    end;
  end;

  if HasNonTextChildren then
  begin
    Result := Result + LineEnding;
    NextIndent := AIndent + '  ';
    for I := 0 to FChildNodes.Count - 1 do
    begin
      Result := Result + TXMLNode(FChildNodes[I]).ToXML(NextIndent) + LineEnding;
    end;
    Result := Result + AIndent + '</' + FTagName + '>';
  end
  else
  begin
    for I := 0 to FChildNodes.Count - 1 do
      Result := Result + TXMLNode(FChildNodes[I]).ToXML('');
    Result := Result + '</' + FTagName + '>';
  end;
end;

// ── ICSSElement Bridge Implementation ───────────────────────────────────────

function TXMLElement.QueryInterface(constref IID: TGUID; out Obj): HResult; cdecl;
begin
  if GetInterface(IID, Obj) then
    Result := S_OK
  else
    Result := E_NOINTERFACE;
end;

function TXMLElement._AddRef(): Integer; cdecl;
begin
  Result := -1; // DOM owns memory
end;

function TXMLElement._Release(): Integer; cdecl;
begin
  Result := -1; // DOM owns memory
end;

function TXMLElement.CSS_GetTagName(): AnsiString;
begin
  Result := FLocalName;
  if Result = '' then
    Result := FTagName;
end;

function TXMLElement.CSS_GetId(): AnsiString;
begin
  Result := GetAttribute('id');
end;

function TXMLElement.CSS_HasClass(const AClass: AnsiString): Boolean;
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
      if SameText(Words[I], AClass) then
      begin
        Result := True;
        Break;
      end;
    end;
  finally
    Words.Free();
  end;
end;

function TXMLElement.CSS_HasAttribute(const AName: AnsiString): Boolean;
begin
  Result := HasAttribute(AName);
end;

function TXMLElement.CSS_GetAttribute(const AName: AnsiString): AnsiString;
begin
  Result := GetAttribute(AName);
end;

function TXMLElement.CSS_GetParent(): ICSSElement;
begin
  Result := nil;
  if (FParent <> nil) and (FParent.NodeType = xntElement) then
    Result := TXMLElement(FParent) as ICSSElement;
end;

function TXMLElement.CSS_GetPreviousSibling(): ICSSElement;
var
  Elem: TXMLElement;
begin
  Result := nil;
  Elem := GetPreviousSiblingElement();
  if Elem <> nil then
    Result := Elem as ICSSElement;
end;

function TXMLElement.CSS_GetChildIndex(): Integer;
begin
  Result := GetSiblingElementIndex();
end;

function TXMLElement.CSS_GetSiblingCount(): Integer;
begin
  Result := GetSiblingElementCount();
end;

function TXMLElement.CSS_IsHovered(): Boolean;
begin
  Result := False;
end;

function TXMLElement.CSS_IsFocused(): Boolean;
begin
  Result := False;
end;

function TXMLElement.CSS_IsActive(): Boolean;
begin
  Result := False;
end;

function TXMLElement.CSS_IsDisabled(): Boolean;
begin
  Result := HasAttribute('disabled');
end;

function TXMLElement.CSS_IsChecked(): Boolean;
begin
  Result := HasAttribute('checked');
end;

// ── TXMLDocument ────────────────────────────────────────────────────────────

constructor TXMLDocument.Create();
begin
  inherited Create(xntDocument);
  FVersion    := '1.0';
  FEncoding   := 'UTF-8';
  FStandalone := '';
end;

function TXMLDocument.GetDocumentElement(): TXMLElement;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to FChildNodes.Count - 1 do
  begin
    if TXMLNode(FChildNodes[I]).NodeType = xntElement then
    begin
      Result := TXMLElement(FChildNodes[I]);
      Exit;
    end;
  end;
end;

procedure TXMLDocument.SetDocumentElement(const AElem: TXMLElement);
var
  CurRoot: TXMLElement;
begin
  CurRoot := GetDocumentElement();
  if CurRoot <> nil then
    RemoveChild(CurRoot);
  if AElem <> nil then
    AppendChild(AElem);
end;

function TXMLDocument.CreateElement(const ATagName: AnsiString): TXMLElement;
begin
  Result := TXMLElement.Create(ATagName);
end;

function TXMLDocument.CreateTextNode(const AText: AnsiString): TXMLTextNode;
begin
  Result := TXMLTextNode.Create(AText);
end;

function TXMLDocument.CreateCDataSection(const AData: AnsiString): TXMLCDataSection;
begin
  Result := TXMLCDataSection.Create(AData);
end;

function TXMLDocument.CreateComment(const AComment: AnsiString): TXMLComment;
begin
  Result := TXMLComment.Create(AComment);
end;

function TXMLDocument.CreateProcessingInstruction(const ATarget, AData: AnsiString): TXMLProcessingInstruction;
begin
  Result := TXMLProcessingInstruction.Create(ATarget, AData);
end;

function TXMLDocument.CreateDocType(const ARoot, APublic, ASystem, ASubset: AnsiString): TXMLDocType;
begin
  Result := TXMLDocType.Create(ARoot, APublic, ASystem, ASubset);
end;

function TXMLDocument.FindElementById(const AId: AnsiString): TXMLElement;
var
  Root: TXMLElement;
begin
  Result := nil;
  Root := GetDocumentElement();
  if Root <> nil then
    Result := Root.FindElementById(AId);
end;

function TXMLDocument.GetElementsByTagName(const ATagName: AnsiString): TObjectList;
var
  Root: TXMLElement;
begin
  Result := TObjectList.Create(False); // does NOT own elements
  Root := GetDocumentElement();
  if Root <> nil then
  begin
    if (ATagName = '*') or SameText(Root.TagName, ATagName) or SameText(Root.LocalName, ATagName) then
      Result.Add(Root);
    Root.GetElementsByTagName(ATagName, Result);
  end;
end;

function TXMLDocument.ToXML(const AIndent: AnsiString): AnsiString;
begin
  Result := SaveToString(True);
end;

function TXMLDocument.SaveToString(const AIncludeProlog: Boolean): AnsiString;
var
  I: Integer;
  Node: TXMLNode;
begin
  Result := '';
  if AIncludeProlog then
  begin
    Result := '<?xml version="' + FVersion + '" encoding="' + FEncoding + '"';
    if FStandalone <> '' then
      Result := Result + ' standalone="' + FStandalone + '"';
    Result := Result + '?>' + LineEnding;
  end;

  for I := 0 to FChildNodes.Count - 1 do
  begin
    Node := TXMLNode(FChildNodes[I]);
    Result := Result + Node.ToXML('') + LineEnding;
  end;
end;

procedure TXMLDocument.SaveToFile(const APath: AnsiString; const AIncludeProlog: Boolean);
var
  S: AnsiString;
  FS: TFileStream;
begin
  S := SaveToString(AIncludeProlog);
  FS := TFileStream.Create(APath, fmCreate);
  try
    if Length(S) > 0 then
      FS.WriteBuffer(S[1], Length(S));
  finally
    FS.Free();
  end;
end;

end.
