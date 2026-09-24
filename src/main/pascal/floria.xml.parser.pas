unit Floria.XML.Parser;

// Floria.XML.Parser
// =================
// High-level XML document parser building DOM tree representations from text,
// streams, or files.
//
// Features:
//   - Well-formedness validation and hierarchy construction
//   - Auto-closing empty elements (<tag ... />)
//   - Prolog extraction (<?xml version="..." encoding="..."?>)
//   - Entity resolution in character data and attributes
//   - DOCTYPE and CDATA block attachment
//   - Static convenience methods: ParseString, ParseFile, ParseStream

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, Classes, Contnrs,
  Floria.XML.Types, Floria.XML.DOM, Floria.XML.Tokenizer;

type
  TXMLParser = class(TObject)
  private
    FTokenizer     : TXMLTokenizer;
    FOwnsTokenizer : Boolean;

    procedure ParseXmlDeclaration(const AData: AnsiString; const ADoc: TXMLDocument);
  public
    constructor Create(const ATokenizer: TXMLTokenizer; const AOwnsTokenizer: Boolean = True);
    constructor Create(const ASource: AnsiString);
    constructor Create(const AStream: TStream);
    destructor Destroy(); override;

    function Parse(): TXMLDocument;

    class function ParseString(const AXML: AnsiString): TXMLDocument; static;
    class function ParseFile(const APath: AnsiString): TXMLDocument; static;
    class function ParseStream(const AStream: TStream): TXMLDocument; static;
  end;

implementation

constructor TXMLParser.Create(const ATokenizer: TXMLTokenizer; const AOwnsTokenizer: Boolean);
begin
  inherited Create();
  FTokenizer     := ATokenizer;
  FOwnsTokenizer := AOwnsTokenizer;
end;

constructor TXMLParser.Create(const ASource: AnsiString);
begin
  Create(TXMLTokenizer.Create(ASource), True);
end;

constructor TXMLParser.Create(const AStream: TStream);
begin
  Create(TXMLTokenizer.Create(AStream), True);
end;

destructor TXMLParser.Destroy();
begin
  if FOwnsTokenizer then
    FTokenizer.Free();
  inherited Destroy();
end;

procedure TXMLParser.ParseXmlDeclaration(const AData: AnsiString; const ADoc: TXMLDocument);
var
  Tokens: TStringList;
  I, EqPos: Integer;
  Part, K, V: AnsiString;
begin
  Tokens := TStringList.Create();
  try
    Tokens.Delimiter := ' ';
    Tokens.StrictDelimiter := False;
    Tokens.DelimitedText := AData;
    for I := 0 to Tokens.Count - 1 do
    begin
      Part := Trim(Tokens[I]);
      EqPos := Pos('=', Part);
      if EqPos > 0 then
      begin
        K := LowerCase(Trim(Copy(Part, 1, EqPos - 1)));
        V := Trim(Copy(Part, EqPos + 1, Length(Part) - EqPos));
        if (Length(V) >= 2) and (((V[1] = '"') and (V[Length(V)] = '"')) or
                                 ((V[1] = '''') and (V[Length(V)] = ''''))) then
          V := Copy(V, 2, Length(V) - 2);

        if K = 'version' then
          ADoc.Version := V
        else if K = 'encoding' then
          ADoc.Encoding := V
        else if K = 'standalone' then
          ADoc.Standalone := V;
      end;
    end;
  finally
    Tokens.Free();
  end;
end;

function TXMLParser.Parse(): TXMLDocument;
var
  Doc           : TXMLDocument;
  Stack         : TObjectList;
  CurrentParent : TXMLNode;
  Tok           : TXMLToken;
  Elem, TopElem : TXMLElement;
  I             : Integer;
begin
  Doc   := TXMLDocument.Create();
  Stack := TObjectList.Create(False); // doesn't own nodes, tracks open elements
  try
    CurrentParent := Doc;

    while not FTokenizer.IsEOF() do
    begin
      Tok := FTokenizer.NextToken();

      case Tok.Kind of
        xtEOF:
          Break;

        xtProcessingInstruction:
        begin
          if LowerCase(Tok.Name) = 'xml' then
            ParseXmlDeclaration(Tok.Value, Doc)
          else
            CurrentParent.AppendChild(Doc.CreateProcessingInstruction(Tok.Name, Tok.Value));
        end;

        xtComment:
        begin
          CurrentParent.AppendChild(Doc.CreateComment(Tok.Value));
        end;

        xtDocType:
        begin
          CurrentParent.AppendChild(Doc.CreateDocType(Tok.Name, '', '', Tok.Value));
        end;

        xtCData:
        begin
          CurrentParent.AppendChild(Doc.CreateCDataSection(Tok.Value));
        end;

        xtText:
        begin
          // Ignore whitespace-only text outside root element
          if (CurrentParent = Doc) and (Trim(Tok.Value) = '') then
            Continue;

          CurrentParent.AppendChild(Doc.CreateTextNode(Tok.Value));
        end;

        xtStartTag:
        begin
          Elem := Doc.CreateElement(Tok.Name);
          for I := 0 to Tok.AttributeCount() - 1 do
            Elem.SetAttribute(Tok.Attributes[I].Name, Tok.Attributes[I].Value);

          CurrentParent.AppendChild(Elem);
          Stack.Add(Elem);
          CurrentParent := Elem;
        end;

        xtEmptyElementTag:
        begin
          Elem := Doc.CreateElement(Tok.Name);
          for I := 0 to Tok.AttributeCount() - 1 do
            Elem.SetAttribute(Tok.Attributes[I].Name, Tok.Attributes[I].Value);

          CurrentParent.AppendChild(Elem);
        end;

        xtEndTag:
        begin
          if Stack.Count > 0 then
          begin
            TopElem := TXMLElement(Stack[Stack.Count - 1]);
            // If tag matches top of stack, pop it
            if SameText(TopElem.TagName, Tok.Name) then
            begin
              Stack.Delete(Stack.Count - 1);
              if Stack.Count > 0 then
                CurrentParent := TXMLNode(Stack[Stack.Count - 1])
              else
                CurrentParent := Doc;
            end
            else
            begin
              // Graceful recovery for unclosed tags: search down the stack
              for I := Stack.Count - 1 downto 0 do
              begin
                if SameText(TXMLElement(Stack[I]).TagName, Tok.Name) then
                begin
                  while Stack.Count > I do
                    Stack.Delete(Stack.Count - 1);
                  Break;
                end;
              end;

              if Stack.Count > 0 then
                CurrentParent := TXMLNode(Stack[Stack.Count - 1])
              else
                CurrentParent := Doc;
            end;
          end;
        end;
      end;
    end;

    Result := Doc;
  finally
    Stack.Free();
  end;
end;

class function TXMLParser.ParseString(const AXML: AnsiString): TXMLDocument;
var
  Parser: TXMLParser;
begin
  Parser := TXMLParser.Create(AXML);
  try
    Result := Parser.Parse();
  finally
    Parser.Free();
  end;
end;

class function TXMLParser.ParseFile(const APath: AnsiString): TXMLDocument;
var
  FS: TFileStream;
begin
  if not FileExists(APath) then
    raise Exception.CreateFmt('XML file not found: %s', [APath]);

  FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    Result := ParseStream(FS);
  finally
    FS.Free();
  end;
end;

class function TXMLParser.ParseStream(const AStream: TStream): TXMLDocument;
var
  Parser: TXMLParser;
begin
  Parser := TXMLParser.Create(AStream);
  try
    Result := Parser.Parse();
  finally
    Parser.Free();
  end;
end;

end.
