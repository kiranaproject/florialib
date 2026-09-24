unit Floria.HTML.Tokenizer;

// Floria.HTML.Tokenizer
// =====================
// High-performance streaming HTML5 tokenizer for the Floria HTML subsystem.
//
// Tokenizes raw HTML text or streams into THTMLToken records:
//   - DOCTYPE declarations: <!DOCTYPE html ...>
//   - Start, end, and self-closing tags: <tag ...>, </tag>, <tag ... />
//   - HTML attributes: quoted (double/single), unquoted, and boolean valueless
//   - Character data: text between tags with entity reference resolution (&amp;, etc.)
//   - Raw text: verbatim data inside <script>, <style>, <textarea>, <title>
//   - Comments: <!-- ... --> blocks
//   - Position tracking: 1-indexed Line and Column

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, Classes,
  Floria.HTML.Types;

type
  THTMLTokenizer = class(TObject)
  private
    FSource     : AnsiString;
    FPos        : Integer;
    FLen        : Integer;
    FLine       : Integer;
    FCol        : Integer;
    FRawTextTag : AnsiString;

    function PeekChar(): Char;
    function PeekAheadChar(const AOffset: Integer): Char;
    function NextChar(): Char;
    function MatchString(const S: AnsiString): Boolean;
    function MatchCaseInsensitive(const S: AnsiString): Boolean;
    function ReadUntil(const APattern: AnsiString): AnsiString;
    function ReadName(): AnsiString;
    procedure SkipWhitespace();
    procedure ParseAttributes(var AToken: THTMLToken);
    procedure ParseDocType(var AToken: THTMLToken);
    function ReadRawTextContent(const ATagName: AnsiString): AnsiString;
  public
    constructor Create(const ASource: AnsiString);
    constructor Create(const AStream: TStream);

    function IsEOF(): Boolean;
    function CurrentPosition(): THTMLPosition;
    function NextToken(): THTMLToken;
    procedure SwitchToRawText(const ATagName: AnsiString);
  end;

implementation

constructor THTMLTokenizer.Create(const ASource: AnsiString);
begin
  inherited Create();
  FSource     := ASource;
  FLen        := Length(FSource);
  FPos        := 1;
  FLine       := 1;
  FCol        := 1;
  FRawTextTag := '';
end;

constructor THTMLTokenizer.Create(const AStream: TStream);
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
  FLen        := Length(FSource);
  FPos        := 1;
  FLine       := 1;
  FCol        := 1;
  FRawTextTag := '';
end;

function THTMLTokenizer.IsEOF(): Boolean;
begin
  Result := FPos > FLen;
end;

function THTMLTokenizer.CurrentPosition(): THTMLPosition;
begin
  Result := THTMLPosition.Create(FLine, FCol);
end;

function THTMLTokenizer.PeekChar(): Char;
begin
  if FPos <= FLen then
    Result := FSource[FPos]
  else
    Result := #0;
end;

function THTMLTokenizer.PeekAheadChar(const AOffset: Integer): Char;
var
  target: Integer;
begin
  target := FPos + AOffset;
  if (target >= 1) and (target <= FLen) then
    Result := FSource[target]
  else
    Result := #0;
end;

function THTMLTokenizer.NextChar(): Char;
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

function THTMLTokenizer.MatchString(const S: AnsiString): Boolean;
var
  SLen: Integer;
begin
  SLen := Length(S);
  if (SLen = 0) or (FPos + SLen - 1 > FLen) then
  begin
    Result := False;
    Exit;
  end;
  Result := Copy(FSource, FPos, SLen) = S;
end;

function THTMLTokenizer.MatchCaseInsensitive(const S: AnsiString): Boolean;
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

procedure THTMLTokenizer.SkipWhitespace();
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

function THTMLTokenizer.ReadUntil(const APattern: AnsiString): AnsiString;
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

function THTMLTokenizer.ReadName(): AnsiString;
var
  C: Char;
begin
  Result := '';
  if IsEOF() then Exit;
  C := PeekChar();
  if not ((C in ['a'..'z', 'A'..'Z', '_', ':', '-']) or (Byte(C) >= $80)) then
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

procedure THTMLTokenizer.ParseAttributes(var AToken: THTMLToken);
var
  C, Quote: Char;
  AttrName, AttrVal, RawVal: AnsiString;
begin
  while not IsEOF() do
  begin
    SkipWhitespace();
    C := PeekChar();
    if (C = '>') or (C = '/') or (C = #0) then
      Break;

    AttrName := ReadName();
    if AttrName = '' then
    begin
      // Skip unexpected character if any
      NextChar();
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
        AttrVal := HTMLDecode(RawVal);
      end
      else
      begin
        // Unquoted attribute value
        RawVal := '';
        while not IsEOF() do
        begin
          C := PeekChar();
          if (C in [' ', #9, #10, #13, '>', '/']) or (C = #0) then
            Break;
          RawVal := RawVal + NextChar();
        end;
        AttrVal := HTMLDecode(RawVal);
      end;
    end
    else
    begin
      // Valueless boolean attribute (e.g. <input disabled>)
      AttrVal := '';
    end;

    AToken.AddAttribute(AttrName, AttrVal);
  end;
end;

procedure THTMLTokenizer.ParseDocType(var AToken: THTMLToken);
var
  C, Quote: Char;
  Body: AnsiString;
begin
  Body := AToken.Name;
  Quote := #0;

  while not IsEOF() do
  begin
    C := NextChar();
    if Quote <> #0 then
    begin
      if C = Quote then
        Quote := #0;
    end
    else if (C = '"') or (C = '''') then
    begin
      Quote := C;
    end
    else if C = '>' then
      Break;

    Body := Body + C;
  end;

  AToken.Value := Trim(Body);
end;

function THTMLTokenizer.ReadRawTextContent(const ATagName: AnsiString): AnsiString;
var
  StartPos: Integer;
  Target: AnsiString;
  TargetLen: Integer;
  C: Char;
begin
  Result := '';
  Target := '</' + LowerCase(ATagName);
  TargetLen := Length(Target);
  StartPos := FPos;

  while not IsEOF() do
  begin
    if (FPos + TargetLen - 1 <= FLen) and SameText(Copy(FSource, FPos, TargetLen), Target) then
    begin
      if FPos + TargetLen <= FLen then
        C := FSource[FPos + TargetLen]
      else
        C := #0;

      if (C = '>') or (C = '/') or (C = ' ') or (C = #9) or (C = #10) or (C = #13) or (C = #0) then
      begin
        Result := Copy(FSource, StartPos, FPos - StartPos);
        FRawTextTag := '';
        Exit;
      end;
    end;

    NextChar();
  end;

  Result := Copy(FSource, StartPos, FLen - StartPos + 1);
  FRawTextTag := '';
end;

procedure THTMLTokenizer.SwitchToRawText(const ATagName: AnsiString);
begin
  FRawTextTag := LowerCase(ATagName);
end;

function THTMLTokenizer.NextToken(): THTMLToken;
var
  StartPos: THTMLPosition;
  C, NextC: Char;
  RawText, Content, TargetName: AnsiString;
begin
  if IsEOF() then
  begin
    Result := THTMLToken.Create(htEOF, '', '', CurrentPosition());
    Exit;
  end;

  StartPos := CurrentPosition();

  // 1. If currently in raw text mode (<script>, <style>, etc.), read raw content
  if FRawTextTag <> '' then
  begin
    TargetName := FRawTextTag;
    RawText := ReadRawTextContent(FRawTextTag);
    Result := THTMLToken.Create(htRawText, TargetName, RawText, StartPos);
    Exit;
  end;

  // 2. Check if next character is '<' and followed by markup indicator
  if PeekChar() = '<' then
  begin
    NextC := PeekAheadChar(1);
    if (NextC in ['a'..'z', 'A'..'Z', '/', '!', '?']) then
    begin
      NextChar(); // consume '<'

      // A. Comment, CDATA, DOCTYPE: <! ...
      if PeekChar() = '!' then
      begin
        NextChar(); // consume '!'

        if MatchString('--') then
        begin
          // Comment: <!-- ... -->
          NextChar(); NextChar(); // consume '--'
          Content := ReadUntil('-->');
          Result := THTMLToken.Create(htComment, '', Content, StartPos);
          Exit;
        end
        else if MatchCaseInsensitive('DOCTYPE') then
        begin
          // DOCTYPE: <!DOCTYPE ...>
          ReadName(); // consume DOCTYPE
          SkipWhitespace();
          TargetName := ReadName();
          Result := THTMLToken.Create(htDocType, TargetName, '', StartPos);
          ParseDocType(Result);
          Exit;
        end
        else if MatchString('[CDATA[') then
        begin
          // CDATA: <![CDATA[ ... ]]>
          FPos := FPos + 7; // consume '[CDATA['
          Content := ReadUntil(']]>');
          Result := THTMLToken.Create(htText, '', Content, StartPos);
          Exit;
        end;
      end;

      // B. Processing Instruction / XML Prolog: <? ... ?>
      if PeekChar() = '?' then
      begin
        NextChar(); // consume '?'
        Content := ReadUntil('?>');
        Result := THTMLToken.Create(htComment, 'xml-pi', Content, StartPos);
        Exit;
      end;

      // C. End Tag: </tag ... >
      if PeekChar() = '/' then
      begin
        NextChar(); // consume '/'
        SkipWhitespace();
        TargetName := ReadName();
        SkipWhitespace();
        if PeekChar() = '>' then
          NextChar(); // consume '>'
        Result := THTMLToken.Create(htEndTag, TargetName, '', StartPos);
        Exit;
      end;

      // D. Start Tag or Self-Closing Tag: <tag ... > or <tag ... />
      TargetName := ReadName();
      Result := THTMLToken.Create(htStartTag, TargetName, '', StartPos);
      ParseAttributes(Result);

      SkipWhitespace();
      if PeekChar() = '/' then
      begin
        NextChar(); // consume '/'
        SkipWhitespace();
        if PeekChar() = '>' then
          NextChar(); // consume '>'
        Result.Kind := htSelfClosingTag;
      end
      else if PeekChar() = '>' then
      begin
        NextChar(); // consume '>'
        Result.Kind := htStartTag;
      end;

      Exit;
    end;
  end;

  // 3. Otherwise, it is character data (text content)
  RawText := '';
  while not IsEOF() do
  begin
    C := PeekChar();
    if C = '<' then
    begin
      NextC := PeekAheadChar(1);
      if (NextC in ['a'..'z', 'A'..'Z', '/', '!', '?']) then
        Break;
    end;
    RawText := RawText + NextChar();
  end;

  Result := THTMLToken.Create(htText, '', HTMLDecode(RawText), StartPos);
end;

end.
