unit Floria.HTML.Parser;

// Floria.HTML.Parser
// ==================
// High-level HTML5 document and fragment parser constructing standard DOM trees.
//
// Features:
//   - HTML5 tree construction with implied <html>, <head>, and <body>
//   - Void elements handling (no closing tag required)
//   - Auto-closing elements:
//       * <p> auto-closed on block elements
//       * <li> auto-closed on consecutive <li>
//       * <dt>/<dd> auto-closed on consecutive definition list entries
//       * <tr>/<td>/<th> auto-closed in table structures
//       * <option> auto-closed on consecutive <option>
//   - Raw text element switching (<script>, <style>, <textarea>, <title>)
//   - Fragment parsing for InnerHTML and dynamic injection
//   - Seamless integration with Floria.HTML.DOM and Floria.CSS.Cascade (ICSSElement)
//   - Static convenience methods: ParseString, ParseFile, ParseStream, ParseFragment

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, Classes, Contnrs,
  Floria.XML.Types, Floria.XML.DOM,
  Floria.HTML.Types, Floria.HTML.DOM, Floria.HTML.Tokenizer;

type
  THTMLParser = class(TObject)
  private
    FTokenizer     : THTMLTokenizer;
    FOwnsTokenizer : Boolean;
  public
    constructor Create(const ATokenizer: THTMLTokenizer; const AOwnsTokenizer: Boolean = True);
    constructor Create(const ASource: AnsiString);
    constructor Create(const AStream: TStream);
    destructor Destroy(); override;

    function Parse(): THTMLDocument;

    class function ParseString(const AHTML: AnsiString): THTMLDocument; static;
    class function ParseFile(const APath: AnsiString): THTMLDocument; static;
    class function ParseStream(const AStream: TStream): THTMLDocument; static;
    class function ParseFragment(const AHTML: AnsiString; AContextElement: THTMLElement = nil): TObjectList; static;
  end;

function ParseHTMLFragment(const AHTML: AnsiString; AContextElement: THTMLElement): TObjectList;

implementation

constructor THTMLParser.Create(const ATokenizer: THTMLTokenizer; const AOwnsTokenizer: Boolean);
begin
  inherited Create();
  FTokenizer     := ATokenizer;
  FOwnsTokenizer := AOwnsTokenizer;
end;

constructor THTMLParser.Create(const ASource: AnsiString);
begin
  Create(THTMLTokenizer.Create(ASource), True);
end;

constructor THTMLParser.Create(const AStream: TStream);
begin
  Create(THTMLTokenizer.Create(AStream), True);
end;

destructor THTMLParser.Destroy();
begin
  if FOwnsTokenizer then
    FTokenizer.Free();
  inherited Destroy();
end;

function IsHeadTag(const ATag: AnsiString): Boolean;
begin
  Result := (ATag = 'title') or (ATag = 'meta') or (ATag = 'link') or
            (ATag = 'style') or (ATag = 'base') or (ATag = 'noscript');
end;

procedure CopyAttributes(const ATok: THTMLToken; const AElem: THTMLElement);
var
  I: Integer;
begin
  for I := 0 to ATok.AttributeCount() - 1 do
    AElem.SetAttribute(ATok.Attributes[I].Name, ATok.Attributes[I].Value);
end;

function THTMLParser.Parse(): THTMLDocument;
var
  Doc           : THTMLDocument;
  Stack         : TObjectList;
  HtmlElem      : THTMLElement;
  HeadElem      : THTMLElement;
  BodyElem      : THTMLElement;
  CurrentParent : TXMLNode;
  Tok           : THTMLToken;
  Elem          : THTMLElement;
  TagName       : AnsiString;
  I, MatchIdx   : Integer;

  procedure EnsureHtml();
  begin
    if HtmlElem = nil then
    begin
      HtmlElem := Doc.CreateElement('html');
      Doc.AppendChild(HtmlElem);
      Stack.Add(HtmlElem);
      CurrentParent := HtmlElem;
    end;
  end;

  procedure EnsureHead();
  begin
    EnsureHtml();
    if HeadElem = nil then
    begin
      HeadElem := Doc.CreateElement('head');
      if HtmlElem.ChildCount > 0 then
        HtmlElem.InsertBefore(HeadElem, HtmlElem.FirstChild)
      else
        HtmlElem.AppendChild(HeadElem);
      Stack.Add(HeadElem);
      CurrentParent := HeadElem;
    end;
  end;

  procedure CloseHead();
  var
    Idx: Integer;
  begin
    if HeadElem <> nil then
    begin
      for Idx := Stack.Count - 1 downto 0 do
      begin
        if TXMLElement(Stack[Idx]) = HeadElem then
        begin
          while Stack.Count > Idx do
            Stack.Delete(Stack.Count - 1);
          Break;
        end;
      end;
      if Stack.Count > 0 then
        CurrentParent := TXMLNode(Stack[Stack.Count - 1])
      else if HtmlElem <> nil then
        CurrentParent := HtmlElem
      else
        CurrentParent := Doc;
    end;
  end;

  procedure EnsureBody();
  begin
    EnsureHtml();
    if BodyElem = nil then
    begin
      CloseHead();
      BodyElem := Doc.CreateElement('body');
      HtmlElem.AppendChild(BodyElem);
      Stack.Add(BodyElem);
      CurrentParent := BodyElem;
    end;
  end;

  procedure CloseParagraphIfOpen();
  var
    PIdx: Integer;
  begin
    for PIdx := Stack.Count - 1 downto 0 do
    begin
      if TXMLElement(Stack[PIdx]).TagName = 'p' then
      begin
        while Stack.Count > PIdx do
          Stack.Delete(Stack.Count - 1);
        if Stack.Count > 0 then
          CurrentParent := TXMLNode(Stack[Stack.Count - 1])
        else if BodyElem <> nil then
          CurrentParent := BodyElem
        else
          CurrentParent := HtmlElem;
        Break;
      end;
    end;
  end;

begin
  Doc           := THTMLDocument.Create();
  Stack         := TObjectList.Create(False);
  HtmlElem      := nil;
  HeadElem      := nil;
  BodyElem      := nil;
  CurrentParent := Doc;

  try
    while not FTokenizer.IsEOF() do
    begin
      Tok := FTokenizer.NextToken();

      case Tok.Kind of
        htEOF:
          Break;

        htDocType:
        begin
          Doc.DocTypeStr := '<!DOCTYPE ' + Tok.Value + '>';
        end;

        htComment:
        begin
          CurrentParent.AppendChild(Doc.CreateComment(Tok.Value));
        end;

        htText:
        begin
          if HtmlElem = nil then
          begin
            if Trim(Tok.Value) = '' then
              Continue;
            EnsureHtml();
            EnsureBody();
          end
          else if (BodyElem = nil) and (HeadElem <> nil) and (CurrentParent = HeadElem) then
          begin
            if Trim(Tok.Value) = '' then
              Continue;
            CloseHead();
            EnsureBody();
          end
          else if BodyElem = nil then
          begin
            if Trim(Tok.Value) = '' then
              Continue;
            EnsureBody();
          end;

          CurrentParent.AppendChild(Doc.CreateTextNode(Tok.Value));
        end;

        htRawText:
        begin
          CurrentParent.AppendChild(Doc.CreateTextNode(Tok.Value));
        end;

        htStartTag, htSelfClosingTag:
        begin
          TagName := Tok.Name;

          // 1. Root <html> element
          if TagName = 'html' then
          begin
            if HtmlElem = nil then
            begin
              HtmlElem := Doc.CreateElement('html');
              CopyAttributes(Tok, HtmlElem);
              Doc.AppendChild(HtmlElem);
              Stack.Add(HtmlElem);
              CurrentParent := HtmlElem;
            end
            else
              CopyAttributes(Tok, HtmlElem);
            Continue;
          end;

          EnsureHtml();

          // 2. <head> element
          if TagName = 'head' then
          begin
            if HeadElem = nil then
            begin
              HeadElem := Doc.CreateElement('head');
              CopyAttributes(Tok, HeadElem);
              if HtmlElem.ChildCount > 0 then
                HtmlElem.InsertBefore(HeadElem, HtmlElem.FirstChild)
              else
                HtmlElem.AppendChild(HeadElem);
              Stack.Add(HeadElem);
              CurrentParent := HeadElem;
            end;
            Continue;
          end;

          // 3. <body> element
          if TagName = 'body' then
          begin
            CloseHead();
            if BodyElem = nil then
            begin
              BodyElem := Doc.CreateElement('body');
              CopyAttributes(Tok, BodyElem);
              HtmlElem.AppendChild(BodyElem);
              Stack.Add(BodyElem);
              CurrentParent := BodyElem;
            end
            else
              CopyAttributes(Tok, BodyElem);
            Continue;
          end;

          // 4. Determine container: Head vs Body
          if IsHeadTag(TagName) and (BodyElem = nil) then
          begin
            EnsureHead();
          end
          else if (TagName = 'script') and (BodyElem = nil) and (HeadElem <> nil) then
          begin
            // Stay inside <head>
          end
          else if (TagName = 'script') and (BodyElem = nil) and (HeadElem = nil) then
          begin
            EnsureHead();
          end
          else
          begin
            CloseHead();
            EnsureBody();
          end;

          // 5. Auto-closing rules
          if IsHTMLBlockElement(TagName) then
            CloseParagraphIfOpen();

          if TagName = 'li' then
          begin
            for I := Stack.Count - 1 downto 0 do
            begin
              if (TXMLElement(Stack[I]).TagName = 'ul') or (TXMLElement(Stack[I]).TagName = 'ol') then
              begin
                while Stack.Count - 1 > I do
                  Stack.Delete(Stack.Count - 1);
                CurrentParent := TXMLNode(Stack[Stack.Count - 1]);
                Break;
              end;
            end;
          end
          else if (TagName = 'dt') or (TagName = 'dd') then
          begin
            for I := Stack.Count - 1 downto 0 do
            begin
              if TXMLElement(Stack[I]).TagName = 'dl' then
              begin
                while Stack.Count - 1 > I do
                  Stack.Delete(Stack.Count - 1);
                CurrentParent := TXMLNode(Stack[Stack.Count - 1]);
                Break;
              end;
            end;
          end
          else if TagName = 'tr' then
          begin
            for I := Stack.Count - 1 downto 0 do
            begin
              if (TXMLElement(Stack[I]).TagName = 'table') or (TXMLElement(Stack[I]).TagName = 'tbody') or
                 (TXMLElement(Stack[I]).TagName = 'thead') or (TXMLElement(Stack[I]).TagName = 'tfoot') then
              begin
                while Stack.Count - 1 > I do
                  Stack.Delete(Stack.Count - 1);
                CurrentParent := TXMLNode(Stack[Stack.Count - 1]);
                Break;
              end;
            end;
          end
          else if (TagName = 'td') or (TagName = 'th') then
          begin
            for I := Stack.Count - 1 downto 0 do
            begin
              if TXMLElement(Stack[I]).TagName = 'tr' then
              begin
                while Stack.Count - 1 > I do
                  Stack.Delete(Stack.Count - 1);
                CurrentParent := TXMLNode(Stack[Stack.Count - 1]);
                Break;
              end
              else if (TXMLElement(Stack[I]).TagName = 'table') then
                Break;
            end;
          end
          else if TagName = 'option' then
          begin
            for I := Stack.Count - 1 downto 0 do
            begin
              if (TXMLElement(Stack[I]).TagName = 'select') or (TXMLElement(Stack[I]).TagName = 'optgroup') then
              begin
                while Stack.Count - 1 > I do
                  Stack.Delete(Stack.Count - 1);
                CurrentParent := TXMLNode(Stack[Stack.Count - 1]);
                Break;
              end;
            end;
          end;

          // 6. Create DOM element
          Elem := Doc.CreateElement(TagName);
          CopyAttributes(Tok, Elem);
          CurrentParent.AppendChild(Elem);

          // 7. Void elements vs Container elements
          if IsHTMLVoidElement(TagName) or (Tok.Kind = htSelfClosingTag) then
          begin
            // Void or self-closing: do not push to stack
          end
          else
          begin
            Stack.Add(Elem);
            CurrentParent := Elem;

            if IsHTMLRawTextElement(TagName) then
              FTokenizer.SwitchToRawText(TagName);
          end;
        end;

        htEndTag:
        begin
          TagName := Tok.Name;
          if IsHTMLVoidElement(TagName) then
            Continue;

          MatchIdx := -1;
          for I := Stack.Count - 1 downto 0 do
          begin
            if TXMLElement(Stack[I]).TagName = TagName then
            begin
              MatchIdx := I;
              Break;
            end;
          end;

          if MatchIdx >= 0 then
          begin
            while Stack.Count > MatchIdx do
              Stack.Delete(Stack.Count - 1);

            if Stack.Count > 0 then
              CurrentParent := TXMLNode(Stack[Stack.Count - 1])
            else if BodyElem <> nil then
              CurrentParent := BodyElem
            else if HtmlElem <> nil then
              CurrentParent := HtmlElem
            else
              CurrentParent := Doc;
          end;
        end;
      end;
    end;

    // Ensure fundamental document structures exist
    EnsureHtml();
    EnsureHead();
    EnsureBody();

    Result := Doc;
  finally
    Stack.Free();
  end;
end;

class function THTMLParser.ParseString(const AHTML: AnsiString): THTMLDocument;
var
  Parser: THTMLParser;
begin
  Parser := THTMLParser.Create(AHTML);
  try
    Result := Parser.Parse();
  finally
    Parser.Free();
  end;
end;

class function THTMLParser.ParseFile(const APath: AnsiString): THTMLDocument;
var
  FS: TFileStream;
begin
  if not FileExists(APath) then
    raise Exception.CreateFmt('HTML file not found: %s', [APath]);

  FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    Result := ParseStream(FS);
  finally
    FS.Free();
  end;
end;

class function THTMLParser.ParseStream(const AStream: TStream): THTMLDocument;
var
  Parser: THTMLParser;
begin
  Parser := THTMLParser.Create(AStream);
  try
    Result := Parser.Parse();
  finally
    Parser.Free();
  end;
end;

class function THTMLParser.ParseFragment(const AHTML: AnsiString; AContextElement: THTMLElement): TObjectList;
var
  Tokenizer     : THTMLTokenizer;
  Container     : THTMLElement;
  Stack         : TObjectList;
  CurrentParent : TXMLNode;
  Tok           : THTMLToken;
  Elem          : THTMLElement;
  TagName       : AnsiString;
  I, MatchIdx   : Integer;

  procedure CloseParagraphIfOpen();
  var
    PIdx: Integer;
  begin
    for PIdx := Stack.Count - 1 downto 0 do
    begin
      if TXMLElement(Stack[PIdx]).TagName = 'p' then
      begin
        while Stack.Count > PIdx do
          Stack.Delete(Stack.Count - 1);
        if Stack.Count > 0 then
          CurrentParent := TXMLNode(Stack[Stack.Count - 1])
        else
          CurrentParent := Container;
        Break;
      end;
    end;
  end;

begin
  Result        := TObjectList.Create(False);
  Container     := THTMLElement.Create('fragment');
  Stack         := TObjectList.Create(False);
  Tokenizer     := THTMLTokenizer.Create(AHTML);
  CurrentParent := Container;

  try
    while not Tokenizer.IsEOF() do
    begin
      Tok := Tokenizer.NextToken();

      case Tok.Kind of
        htEOF, htDocType:
          ; // ignore in fragment

        htComment:
        begin
          CurrentParent.AppendChild(THTMLComment.Create(Tok.Value));
        end;

        htText:
        begin
          CurrentParent.AppendChild(THTMLTextNode.Create(Tok.Value));
        end;

        htRawText:
        begin
          CurrentParent.AppendChild(THTMLTextNode.Create(Tok.Value));
        end;

        htStartTag, htSelfClosingTag:
        begin
          TagName := Tok.Name;

          if IsHTMLBlockElement(TagName) then
            CloseParagraphIfOpen();

          if TagName = 'li' then
          begin
            for I := Stack.Count - 1 downto 0 do
            begin
              if (TXMLElement(Stack[I]).TagName = 'ul') or (TXMLElement(Stack[I]).TagName = 'ol') then
              begin
                while Stack.Count - 1 > I do
                  Stack.Delete(Stack.Count - 1);
                CurrentParent := TXMLNode(Stack[Stack.Count - 1]);
                Break;
              end;
            end;
          end
          else if (TagName = 'dt') or (TagName = 'dd') then
          begin
            for I := Stack.Count - 1 downto 0 do
            begin
              if TXMLElement(Stack[I]).TagName = 'dl' then
              begin
                while Stack.Count - 1 > I do
                  Stack.Delete(Stack.Count - 1);
                CurrentParent := TXMLNode(Stack[Stack.Count - 1]);
                Break;
              end;
            end;
          end
          else if TagName = 'tr' then
          begin
            for I := Stack.Count - 1 downto 0 do
            begin
              if (TXMLElement(Stack[I]).TagName = 'table') or (TXMLElement(Stack[I]).TagName = 'tbody') or
                 (TXMLElement(Stack[I]).TagName = 'thead') or (TXMLElement(Stack[I]).TagName = 'tfoot') then
              begin
                while Stack.Count - 1 > I do
                  Stack.Delete(Stack.Count - 1);
                CurrentParent := TXMLNode(Stack[Stack.Count - 1]);
                Break;
              end;
            end;
          end
          else if (TagName = 'td') or (TagName = 'th') then
          begin
            for I := Stack.Count - 1 downto 0 do
            begin
              if TXMLElement(Stack[I]).TagName = 'tr' then
              begin
                while Stack.Count - 1 > I do
                  Stack.Delete(Stack.Count - 1);
                CurrentParent := TXMLNode(Stack[Stack.Count - 1]);
                Break;
              end
              else if (TXMLElement(Stack[I]).TagName = 'table') then
                Break;
            end;
          end
          else if TagName = 'option' then
          begin
            for I := Stack.Count - 1 downto 0 do
            begin
              if (TXMLElement(Stack[I]).TagName = 'select') or (TXMLElement(Stack[I]).TagName = 'optgroup') then
              begin
                while Stack.Count - 1 > I do
                  Stack.Delete(Stack.Count - 1);
                CurrentParent := TXMLNode(Stack[Stack.Count - 1]);
                Break;
              end;
            end;
          end;

          Elem := CreateHTMLElement(TagName);
          CopyAttributes(Tok, Elem);
          CurrentParent.AppendChild(Elem);

          if IsHTMLVoidElement(TagName) or (Tok.Kind = htSelfClosingTag) then
          begin
            // Void or self-closing
          end
          else
          begin
            Stack.Add(Elem);
            CurrentParent := Elem;

            if IsHTMLRawTextElement(TagName) then
              Tokenizer.SwitchToRawText(TagName);
          end;
        end;

        htEndTag:
        begin
          TagName := Tok.Name;
          if IsHTMLVoidElement(TagName) then
            Continue;

          MatchIdx := -1;
          for I := Stack.Count - 1 downto 0 do
          begin
            if TXMLElement(Stack[I]).TagName = TagName then
            begin
              MatchIdx := I;
              Break;
            end;
          end;

          if MatchIdx >= 0 then
          begin
            while Stack.Count > MatchIdx do
              Stack.Delete(Stack.Count - 1);

            if Stack.Count > 0 then
              CurrentParent := TXMLNode(Stack[Stack.Count - 1])
            else
              CurrentParent := Container;
          end;
        end;
      end;
    end;

    // Extract children from Container into Result list
    while Container.ChildCount > 0 do
      Result.Add(Container.RemoveChild(Container.Children[0]));
  finally
    Container.Free();
    Stack.Free();
    Tokenizer.Free();
  end;
end;

function ParseHTMLFragment(const AHTML: AnsiString; AContextElement: THTMLElement): TObjectList;
begin
  Result := THTMLParser.ParseFragment(AHTML, AContextElement);
end;

initialization
  Floria.HTML.DOM.HTMLFragmentParser := @ParseHTMLFragment;

finalization
  Floria.HTML.DOM.HTMLFragmentParser := nil;

end.
