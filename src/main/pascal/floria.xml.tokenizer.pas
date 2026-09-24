unit Floria.XML.Tokenizer;

// Floria.XML.Tokenizer
// ====================
// Fast, streaming XML 1.0 tokenizer for the Floria XML subsystem.
//
// Tokenizes raw XML text or streams into TXMLToken records:
//   - Elements: opening, closing, and self-closing tags with parsed attributes
//   - Text: character data with decoded entity references
//   - CDATA: unescaped raw character blocks
//   - Comments: <!-- ... --> blocks
//   - Processing Instructions: <?target data?> directives
//   - DOCTYPE: <!DOCTYPE ...> declarations

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, Classes,
  Floria.XML.Types;

type
  TXMLTokenizer = class(TObject)
  private
    FSource : AnsiString;
    FPos    : Integer;
    FLen    : Integer;
    FLine   : Integer;
    FCol    : Integer;

    function PeekChar(): Char;
    function NextChar(): Char;
    function MatchString(const S: AnsiString): Boolean;
    function ReadUntil(const APattern: AnsiString): AnsiString;
    function ReadName(): AnsiString;
    procedure SkipWhitespace();
    procedure ParseAttributes(var AToken: TXMLToken);
    procedure ParseDocType(var AToken: TXMLToken);
  public
    constructor Create(const ASource: AnsiString);
    constructor Create(const AStream: TStream);

    function IsEOF(): Boolean;
    function CurrentPosition(): TXMLPosition;
    function NextToken(): TXMLToken;
  end;

implementation

constructor TXMLTokenizer.Create(const ASource: AnsiString);
begin
  inherited Create();
  FSource := ASource;
  FLen    := Length(FSource);
  FPos    := 1;
  FLine   := 1;
  FCol    := 1;
end;

constructor TXMLTokenizer.Create(const AStream: TStream);
var
  SS: TStringStream;
begin
  inherited Create();
  SS := TStringStream.Create('');
  try
    if AStream <> nil then
      SS.CopyFrom(AStream, AStream.Size - AStream.Position);
    FSource := SS.DataString;
  finally
    SS.Free();
  end;
  FLen  := Length(FSource);
  FPos  := 1;
  FLine := 1;
  FCol  := 1;
end;

function TXMLTokenizer.IsEOF(): Boolean;
begin
  Result := FPos > FLen;
end;

function TXMLTokenizer.CurrentPosition(): TXMLPosition;
begin
  Result := TXMLPosition.Create(FLine, FCol);
end;

function TXMLTokenizer.PeekChar(): Char;
begin
  if FPos <= FLen then
    Result := FSource[FPos]
  else
    Result := #0;
end;

function TXMLTokenizer.NextChar(): Char;
begin
  if FPos <= FLen then
  begin
    Result := FSource[FPos];
    Inc(FPos);
    if Result = #10 then
    begin
      Inc(FLine);
      FCol := 1;
    end
    else
      Inc(FCol);
  end
  else
    Result := #0;
end;

function TXMLTokenizer.MatchString(const S: AnsiString): Boolean;
var
  SLen: Integer;
begin
  SLen := Length(S);
  if (SLen = 0) or (FPos + SLen - 1 > FLen) then
  begin
    Result := False;
    Exit;
  end;
  Result := SameText(Copy(FSource, FPos, SLen), S);
end;

procedure TXMLTokenizer.SkipWhitespace();
var
  C: Char;
begin
  while not IsEOF() do
  begin
    C := PeekChar();
    if (C = ' ') or (C = #9) or (C = #10) or (C = #13) then
      NextChar()
    else
      Break;
  end;
end;

function TXMLTokenizer.ReadUntil(const APattern: AnsiString): AnsiString;
var
  PatLen: Integer;
  StartPos: Integer;
begin
  Result := '';
  PatLen := Length(APattern);
  if PatLen = 0 then Exit;

  StartPos := FPos;
  while not IsEOF() do
  begin
    if (FPos + PatLen - 1 <= FLen) and (Copy(FSource, FPos, PatLen) = APattern) then
    begin
      Result := Copy(FSource, StartPos, FPos - StartPos);
      // Advance past pattern
      while PatLen > 0 do
      begin
        NextChar();
        Dec(PatLen);
      end;
      Exit;
    end;
    NextChar();
  end;

  Result := Copy(FSource, StartPos, FLen - StartPos + 1);
end;

function TXMLTokenizer.ReadName(): AnsiString;
var
  C: Char;
begin
  Result := '';
  if IsEOF() then Exit;
  C := PeekChar();
  if not ((C in ['a'..'z', 'A'..'Z', '_', ':']) or (Byte(C) >= $80)) then
    Exit;

  Result := Result + NextChar();
  while not IsEOF() do
  begin
    C := PeekChar();
    if (C in ['a'..'z', 'A'..'Z', '0'..'9', '_', '-', ':', '.']) or (Byte(C) >= $80) then
      Result := Result + NextChar()
    else
      Break;
  end;
end;

procedure TXMLTokenizer.ParseAttributes(var AToken: TXMLToken);
var
  C, Quote: Char;
  AttrName, AttrVal, RawVal: AnsiString;
begin
  while not IsEOF() do
  begin
    SkipWhitespace();
    C := PeekChar();
    if (C = '>') or (C = '/') or (C = '?') or (C = #0) then
      Break;

    AttrName := ReadName();
    if AttrName = '' then
    begin
      NextChar(); // skip unexpected character
      Continue;
    end;

    SkipWhitespace();
    AttrVal := '';

    if PeekChar() = '=' then
    begin
      NextChar(); // consume '='
      SkipWhitespace();
      Quote := PeekChar();

      if (Quote = '"') or (Quote = '''') then
      begin
        NextChar(); // consume quote
        RawVal := '';
        while not IsEOF() do
        begin
          C := NextChar();
          if C = Quote then
            Break;
          RawVal := RawVal + C;
        end;
        AttrVal := XMLDecode(RawVal);
      end
      else
      begin
        // Unquoted attribute value
        RawVal := '';
        while not IsEOF() do
        begin
          C := PeekChar();
          if (C in [' ', #9, #10, #13, '>', '/']) then
            Break;
          RawVal := RawVal + NextChar();
        end;
        AttrVal := XMLDecode(RawVal);
      end;
    end;

    AToken.AddAttribute(AttrName, AttrVal);
  end;
end;

procedure TXMLTokenizer.ParseDocType(var AToken: TXMLToken);
var
  C: Char;
  BracketDepth: Integer;
  Body: AnsiString;
begin
  Body := '';
  BracketDepth := 0;

  while not IsEOF() do
  begin
    C := NextChar();
    if C = '[' then
      Inc(BracketDepth)
    else if C = ']' then
    begin
      if BracketDepth > 0 then
        Dec(BracketDepth);
    end
    else if (C = '>') and (BracketDepth = 0) then
      Break;
    Body := Body + C;
  end;

  AToken.Value := Trim(Body);
end;

function TXMLTokenizer.NextToken(): TXMLToken;
var
  StartPos: TXMLPosition;
  C: Char;
  RawText, Content: AnsiString;
  TargetName: AnsiString;
begin
  if IsEOF() then
  begin
    Result := TXMLToken.Create(xtEOF, '', '', CurrentPosition());
    Exit;
  end;

  StartPos := CurrentPosition();

  // If next character is '<', it's a markup tag, PI, comment, CDATA, or DOCTYPE
  if PeekChar() = '<' then
  begin
    NextChar(); // consume '<'

    // 1. Processing Instruction: <?target ... ?>
    if PeekChar() = '?' then
    begin
      NextChar(); // consume '?'
      TargetName := ReadName();
      Content := ReadUntil('?>');
      Result := TXMLToken.Create(xtProcessingInstruction, TargetName, Trim(Content), StartPos);
      Exit;
    end;

    // 2. Comments, CDATA, DOCTYPE: <! ...
    if PeekChar() = '!' then
    begin
      NextChar(); // consume '!'

      if MatchString('--') then
      begin
        // Comment: <!-- ... -->
        NextChar(); NextChar(); // consume '--'
        Content := ReadUntil('-->');
        Result := TXMLToken.Create(xtComment, '', Content, StartPos);
        Exit;
      end
      else if MatchString('[CDATA[') then
      begin
        // CDATA: <![CDATA[ ... ]]>
        Content := Copy(FSource, FPos, 7);
        FPos := FPos + 7; // consume '[CDATA['
        Content := ReadUntil(']]>');
        Result := TXMLToken.Create(xtCData, '', Content, StartPos);
        Exit;
      end
      else if MatchString('DOCTYPE') or MatchString('doctype') then
      begin
        // DOCTYPE: <!DOCTYPE ...>
        ReadName(); // consume DOCTYPE
        SkipWhitespace();
        TargetName := ReadName();
        Result := TXMLToken.Create(xtDocType, TargetName, '', StartPos);
        ParseDocType(Result);
        Exit;
      end;
    end;

    // 3. End Tag: </tag>
    if PeekChar() = '/' then
    begin
      NextChar(); // consume '/'
      SkipWhitespace();
      TargetName := ReadName();
      SkipWhitespace();
      if PeekChar() = '>' then
        NextChar(); // consume '>'
      Result := TXMLToken.Create(xtEndTag, TargetName, '', StartPos);
      Exit;
    end;

    // 4. Start Tag or Empty Element Tag: <tag ... > or <tag ... />
    TargetName := ReadName();
    Result := TXMLToken.Create(xtStartTag, TargetName, '', StartPos);
    ParseAttributes(Result);

    SkipWhitespace();
    if PeekChar() = '/' then
    begin
      NextChar(); // consume '/'
      if PeekChar() = '>' then
        NextChar(); // consume '>'
      Result.Kind := xtEmptyElementTag;
    end
    else if PeekChar() = '>' then
    begin
      NextChar(); // consume '>'
      Result.Kind := xtStartTag;
    end;

    Exit;
  end;

  // Otherwise, it's character data / text content
  RawText := '';
  while not IsEOF() do
  begin
    C := PeekChar();
    if C = '<' then
      Break;
    RawText := RawText + NextChar();
  end;

  Result := TXMLToken.Create(xtText, '', XMLDecode(RawText), StartPos);
end;

end.
