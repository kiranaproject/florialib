unit Floria.XML.Types;

// Floria.XML.Types
// ================
// Foundational types, constants, entities, and exception definitions for the
// Floria XML subsystem.

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, Classes, Math;

type
  // ── Source Position Tracking ───────────────────────────────────────────────

  TXMLPosition = record
    Line   : Integer;
    Column : Integer;

    class function Create(const ALine, ACol: Integer): TXMLPosition; static;
    function ToString(): AnsiString;
  end;

  // ── Token Kinds ────────────────────────────────────────────────────────────

  TXMLTokenKind = (
    xtEOF,
    xtStartTag,                // <tag
    xtEndTag,                  // </tag>
    xtEmptyElementTag,         // <tag ... />
    xtText,                    // Character data between tags
    xtCData,                   // <![CDATA[ ... ]]>
    xtComment,                 // <!-- ... -->
    xtProcessingInstruction,   // <?target ... ?>
    xtDocType                  // <!DOCTYPE ... >
  );

  // ── DOM Node Kinds ─────────────────────────────────────────────────────────

  TXMLNodeType = (
    xntDocument,
    xntElement,
    xntText,
    xntCData,
    xntComment,
    xntProcessingInstruction,
    xntDocType
  );

  // ── Token Attribute Entry ──────────────────────────────────────────────────

  TXMLAttributeEntry = record
    Name  : AnsiString;
    Value : AnsiString;
  end;

  // ── XML Token Record ───────────────────────────────────────────────────────

  TXMLToken = record
    Kind       : TXMLTokenKind;
    Name       : AnsiString;      // Element tag name, PI target, or DocType name
    Value      : AnsiString;      // Text data, comment, CDATA, or PI data
    Position   : TXMLPosition;
    Attributes : array of TXMLAttributeEntry;

    class function Create(const AKind: TXMLTokenKind; const AName, AVal: AnsiString; const APos: TXMLPosition): TXMLToken; static;
    function AttributeCount(): Integer;
    function GetAttribute(const AName: AnsiString): AnsiString;
    function HasAttribute(const AName: AnsiString): Boolean;
    procedure AddAttribute(const AName, AVal: AnsiString);
  end;

  // ── Exception Type ─────────────────────────────────────────────────────────

  EXMLException = class(Exception)
  private
    FPosition: TXMLPosition;
  public
    constructor Create(const AMsg: AnsiString; const APos: TXMLPosition);
    property Position: TXMLPosition read FPosition;
  end;

// ── Entity Encoding & Decoding ──────────────────────────────────────────────

function XMLEncode(const S: AnsiString): AnsiString;
function XMLDecode(const S: AnsiString): AnsiString;

implementation

// ── TXMLPosition ────────────────────────────────────────────────────────────

class function TXMLPosition.Create(const ALine, ACol: Integer): TXMLPosition;
begin
  Result.Line   := ALine;
  Result.Column := ACol;
end;

function TXMLPosition.ToString(): AnsiString;
begin
  Result := Format('(%d:%d)', [Line, Column]);
end;

// ── TXMLToken ───────────────────────────────────────────────────────────────

class function TXMLToken.Create(const AKind: TXMLTokenKind; const AName, AVal: AnsiString; const APos: TXMLPosition): TXMLToken;
begin
  Result.Kind     := AKind;
  Result.Name     := AName;
  Result.Value    := AVal;
  Result.Position := APos;
  SetLength(Result.Attributes, 0);
end;

function TXMLToken.AttributeCount(): Integer;
begin
  Result := Length(Attributes);
end;

function TXMLToken.GetAttribute(const AName: AnsiString): AnsiString;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(Attributes) do
  begin
    if SameText(Attributes[I].Name, AName) then
    begin
      Result := Attributes[I].Value;
      Exit;
    end;
  end;
end;

function TXMLToken.HasAttribute(const AName: AnsiString): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(Attributes) do
  begin
    if SameText(Attributes[I].Name, AName) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

procedure TXMLToken.AddAttribute(const AName, AVal: AnsiString);
var
  Len: Integer;
begin
  Len := Length(Attributes);
  SetLength(Attributes, Len + 1);
  Attributes[Len].Name  := AName;
  Attributes[Len].Value := AVal;
end;

// ── EXMLException ───────────────────────────────────────────────────────────

constructor EXMLException.Create(const AMsg: AnsiString; const APos: TXMLPosition);
begin
  inherited Create(Format('%s at line %d, col %d', [AMsg, APos.Line, APos.Column]));
  FPosition := APos;
end;

// ── Entity Encoding & Decoding ──────────────────────────────────────────────

function XMLEncode(const S: AnsiString): AnsiString;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    case S[I] of
      '&': Result := Result + '&amp;';
      '<': Result := Result + '&lt;';
      '>': Result := Result + '&gt;';
      '"': Result := Result + '&quot;';
      '''': Result := Result + '&apos;';
    else
      Result := Result + S[I];
    end;
  end;
end;

function ParseHexChar(const C: Char): Integer;
begin
  case C of
    '0'..'9': Result := Ord(C) - Ord('0');
    'a'..'f': Result := Ord(C) - Ord('a') + 10;
    'A'..'F': Result := Ord(C) - Ord('A') + 10;
  else
    Result := -1;
  end;
end;

function XMLDecode(const S: AnsiString): AnsiString;
var
  I, J, SemiPos: Integer;
  Entity: AnsiString;
  CodePoint, Nib: Integer;
begin
  Result := '';
  I := 1;
  while I <= Length(S) do
  begin
    if S[I] = '&' then
    begin
      SemiPos := 0;
      for J := I + 1 to Min(I + 10, Length(S)) do
      begin
        if S[J] = ';' then
        begin
          SemiPos := J;
          Break;
        end;
        if S[J] in [' ', #9, #10, #13, '<', '&'] then
          Break;
      end;

      if SemiPos > 0 then
      begin
        Entity := Copy(S, I + 1, SemiPos - I - 1);
        if Entity = 'amp' then
          Result := Result + '&'
        else if Entity = 'lt' then
          Result := Result + '<'
        else if Entity = 'gt' then
          Result := Result + '>'
        else if Entity = 'quot' then
          Result := Result + '"'
        else if Entity = 'apos' then
          Result := Result + ''''
        else if (Length(Entity) >= 2) and (Entity[1] = '#') then
        begin
          CodePoint := 0;
          if (Length(Entity) >= 3) and ((Entity[2] = 'x') or (Entity[2] = 'X')) then
          begin
            // Hex character reference: &#xHH;
            for J := 3 to Length(Entity) do
            begin
              Nib := ParseHexChar(Entity[J]);
              if Nib < 0 then
              begin
                CodePoint := -1;
                Break;
              end;
              CodePoint := (CodePoint shl 4) or Nib;
            end;
          end
          else
          begin
            // Decimal character reference: &#NNN;
            for J := 2 to Length(Entity) do
            begin
              if (Entity[J] in ['0'..'9']) then
                CodePoint := CodePoint * 10 + (Ord(Entity[J]) - Ord('0'))
              else
              begin
                CodePoint := -1;
                Break;
              end;
            end;
          end;

          if (CodePoint > 0) and (CodePoint <= 127) then
            Result := Result + Chr(CodePoint)
          else if (CodePoint > 127) and (CodePoint <= $7FF) then
          begin
            Result := Result + Chr($C0 or (CodePoint shr 6));
            Result := Result + Chr($80 or (CodePoint and $3F));
          end
          else if (CodePoint > $7FF) and (CodePoint <= $FFFF) then
          begin
            Result := Result + Chr($E0 or (CodePoint shr 12));
            Result := Result + Chr($80 or ((CodePoint shr 6) and $3F));
            Result := Result + Chr($80 or (CodePoint and $3F));
          end
          else if (CodePoint > $FFFF) and (CodePoint <= $10FFFF) then
          begin
            Result := Result + Chr($F0 or (CodePoint shr 18));
            Result := Result + Chr($80 or ((CodePoint shr 12) and $3F));
            Result := Result + Chr($80 or ((CodePoint shr 6) and $3F));
            Result := Result + Chr($80 or (CodePoint and $3F));
          end
          else
            Result := Result + Copy(S, I, SemiPos - I + 1);
        end
        else
          Result := Result + Copy(S, I, SemiPos - I + 1);

        I := SemiPos + 1;
        Continue;
      end;
    end;

    Result := Result + S[I];
    Inc(I);
  end;
end;

end.
