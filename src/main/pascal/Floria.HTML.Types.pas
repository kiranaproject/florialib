unit Floria.HTML.Types;

// Floria.HTML.Types
// =================
// Foundational types, constants, token definitions, entity encoders/decoders,
// and exception classes for the Floria HTML subsystem.

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, Classes, Math;

type
  // ── Source Position Tracking ───────────────────────────────────────────────

  THTMLPosition = record
    Line   : Integer;
    Column : Integer;

    class function Create(const ALine, ACol: Integer): THTMLPosition; static;
    function ToString(): AnsiString;
  end;

  // ── Token Kinds ────────────────────────────────────────────────────────────

  THTMLTokenKind = (
    htEOF,
    htDocType,          // <!DOCTYPE ...>
    htStartTag,         // <tag ...>
    htEndTag,           // </tag>
    htSelfClosingTag,   // <tag ... />
    htText,             // Character data between tags
    htComment,          // <!-- ... -->
    htRawText           // Unparsed text inside <script>, <style>, <textarea>, <title>
  );

  // ── Token Attribute Entry ──────────────────────────────────────────────────

  THTMLAttributeEntry = record
    Name  : AnsiString; // Lowercase attribute name
    Value : AnsiString;
  end;

  // ── HTML Token Record ──────────────────────────────────────────────────────

  THTMLToken = record
    Kind       : THTMLTokenKind;
    Name       : AnsiString; // Lowercase element tag name or doctype name
    Value      : AnsiString; // Text, comment, or raw text data
    Position   : THTMLPosition;
    Attributes : array of THTMLAttributeEntry;

    class function Create(const AKind: THTMLTokenKind; const AName, AVal: AnsiString; const APos: THTMLPosition): THTMLToken; static;
    function AttributeCount(): Integer;
    function GetAttribute(const AName: AnsiString): AnsiString;
    function HasAttribute(const AName: AnsiString): Boolean;
    procedure AddAttribute(const AName, AVal: AnsiString);
  end;

  // ── Exception Type ─────────────────────────────────────────────────────────

  EHTMLException = class(Exception)
  private
    FPosition: THTMLPosition;
  public
    constructor Create(const AMsg: AnsiString; const APos: THTMLPosition);
    property Position: THTMLPosition read FPosition;
  end;

// ── Element Classification Helpers ──────────────────────────────────────────

function IsHTMLVoidElement(const ATag: AnsiString): Boolean;
function IsHTMLRawTextElement(const ATag: AnsiString): Boolean;
function IsHTMLBlockElement(const ATag: AnsiString): Boolean;
function CanPElementContain(const ATag: AnsiString): Boolean;

// ── Entity Encoding & Decoding ──────────────────────────────────────────────

function HTMLEncode(const S: AnsiString): AnsiString;
function HTMLDecode(const S: AnsiString): AnsiString;
function CodePointToUTF8(const ACode: Cardinal): AnsiString;

implementation

// ── THTMLPosition ────────────────────────────────────────────────────────────

class function THTMLPosition.Create(const ALine, ACol: Integer): THTMLPosition;
begin
  Result.Line   := ALine;
  Result.Column := ACol;
end;

function THTMLPosition.ToString(): AnsiString;
begin
  Result := Format('(%d:%d)', [Line, Column]);
end;

// ── THTMLToken ───────────────────────────────────────────────────────────────

class function THTMLToken.Create(const AKind: THTMLTokenKind; const AName, AVal: AnsiString; const APos: THTMLPosition): THTMLToken;
begin
  Result.Kind     := AKind;
  Result.Name     := LowerCase(AName);
  Result.Value    := AVal;
  Result.Position := APos;
  SetLength(Result.Attributes, 0);
end;

function THTMLToken.AttributeCount(): Integer;
begin
  Result := Length(Attributes);
end;

function THTMLToken.GetAttribute(const AName: AnsiString): AnsiString;
var
  I: Integer;
  lowName: AnsiString;
begin
  Result := '';
  lowName := LowerCase(AName);
  for I := 0 to High(Attributes) do
  begin
    if Attributes[I].Name = lowName then
    begin
      Result := Attributes[I].Value;
      Exit;
    end;
  end;
end;

function THTMLToken.HasAttribute(const AName: AnsiString): Boolean;
var
  I: Integer;
  lowName: AnsiString;
begin
  Result := False;
  lowName := LowerCase(AName);
  for I := 0 to High(Attributes) do
  begin
    if Attributes[I].Name = lowName then
      Exit(True);
  end;
end;

procedure THTMLToken.AddAttribute(const AName, AVal: AnsiString);
var
  N: Integer;
begin
  N := Length(Attributes);
  SetLength(Attributes, N + 1);
  Attributes[N].Name  := LowerCase(AName);
  Attributes[N].Value := AVal;
end;

// ── EHTMLException ──────────────────────────────────────────────────────────

constructor EHTMLException.Create(const AMsg: AnsiString; const APos: THTMLPosition);
begin
  inherited CreateFmt('%s at %s', [AMsg, APos.ToString()]);
  FPosition := APos;
end;

// ── Element Classification Helpers ──────────────────────────────────────────

function IsHTMLVoidElement(const ATag: AnsiString): Boolean;
var
  T: AnsiString;
begin
  T := LowerCase(ATag);
  Result := (T = 'area') or (T = 'base') or (T = 'br') or (T = 'col') or
            (T = 'embed') or (T = 'hr') or (T = 'img') or (T = 'input') or
            (T = 'link') or (T = 'meta') or (T = 'param') or (T = 'source') or
            (T = 'track') or (T = 'wbr');
end;

function IsHTMLRawTextElement(const ATag: AnsiString): Boolean;
var
  T: AnsiString;
begin
  T := LowerCase(ATag);
  Result := (T = 'script') or (T = 'style') or (T = 'textarea') or (T = 'title');
end;

function IsHTMLBlockElement(const ATag: AnsiString): Boolean;
var
  T: AnsiString;
begin
  T := LowerCase(ATag);
  Result := (T = 'address') or (T = 'article') or (T = 'aside') or (T = 'blockquote') or
            (T = 'details') or (T = 'dialog') or (T = 'div') or (T = 'dl') or
            (T = 'fieldset') or (T = 'figcaption') or (T = 'figure') or (T = 'footer') or
            (T = 'form') or (T = 'h1') or (T = 'h2') or (T = 'h3') or (T = 'h4') or
            (T = 'h5') or (T = 'h6') or (T = 'header') or (T = 'hgroup') or (T = 'hr') or
            (T = 'main') or (T = 'menu') or (T = 'nav') or (T = 'ol') or (T = 'p') or
            (T = 'pre') or (T = 'section') or (T = 'table') or (T = 'ul');
end;

function CanPElementContain(const ATag: AnsiString): Boolean;
begin
  // A <p> element is auto-closed if any block-level element is encountered
  Result := not IsHTMLBlockElement(ATag);
end;

// ── Unicode to UTF-8 Helper ─────────────────────────────────────────────────

function CodePointToUTF8(const ACode: Cardinal): AnsiString;
begin
  if ACode <= $7F then
  begin
    Result := AnsiChar(Chr(ACode));
  end
  else if ACode <= $7FF then
  begin
    SetLength(Result, 2);
    Result[1] := AnsiChar(Chr($C0 or (ACode shr 6)));
    Result[2] := AnsiChar(Chr($80 or (ACode and $3F)));
  end
  else if ACode <= $FFFF then
  begin
    SetLength(Result, 3);
    Result[1] := AnsiChar(Chr($E0 or (ACode shr 12)));
    Result[2] := AnsiChar(Chr($80 or ((ACode shr 6) and $3F)));
    Result[3] := AnsiChar(Chr($80 or (ACode and $3F)));
  end
  else if ACode <= $10FFFF then
  begin
    SetLength(Result, 4);
    Result[1] := AnsiChar(Chr($F0 or (ACode shr 18)));
    Result[2] := AnsiChar(Chr($80 or ((ACode shr 12) and $3F)));
    Result[3] := AnsiChar(Chr($80 or ((ACode shr 6) and $3F)));
    Result[4] := AnsiChar(Chr($80 or (ACode and $3F)));
  end
  else
    Result := '';
end;

// ── Entity Encoding & Decoding ──────────────────────────────────────────────

function HTMLEncode(const S: AnsiString): AnsiString;
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
      '''': Result := Result + '&#39;';
    else
      Result := Result + S[I];
    end;
  end;
end;

function HTMLDecode(const S: AnsiString): AnsiString;
var
  I, Semi: Integer;
  Entity: AnsiString;
  Code: Cardinal;
begin
  Result := '';
  I := 1;
  while I <= Length(S) do
  begin
    if S[I] = '&' then
    begin
      Semi := I + 1;
      while (Semi <= Length(S)) and (Semi <= I + 12) and (S[Semi] <> ';') and (S[Semi] <> '&') and (S[Semi] <> '<') and (S[Semi] > ' ') do
        Inc(Semi);

      if (Semi <= Length(S)) and (S[Semi] = ';') then
      begin
        Entity := Copy(S, I + 1, Semi - I - 1);

        if (Length(Entity) > 1) and (Entity[1] = '#') then
        begin
          // Numeric character reference
          if (Length(Entity) > 2) and ((Entity[2] = 'x') or (Entity[2] = 'X')) then
          begin
            // Hexadecimal &#x...;
            Code := StrToIntDef('$' + Copy(Entity, 3, Length(Entity) - 2), 0);
          end
          else
          begin
            // Decimal &#...;
            Code := StrToIntDef(Copy(Entity, 2, Length(Entity) - 1), 0);
          end;

          if Code > 0 then
            Result := Result + CodePointToUTF8(Code)
          else
            Result := Result + '&' + Entity + ';';
        end
        else
        begin
          // Named HTML entities
          if Entity = 'amp' then Result := Result + '&'
          else if Entity = 'lt' then Result := Result + '<'
          else if Entity = 'gt' then Result := Result + '>'
          else if Entity = 'quot' then Result := Result + '"'
          else if Entity = 'apos' then Result := Result + ''''
          else if Entity = 'nbsp' then Result := Result + #194#160   // UTF-8 non-breaking space
          else if Entity = 'copy' then Result := Result + #194#169   // ©
          else if Entity = 'reg' then Result := Result + #194#174    // ®
          else if Entity = 'trade' then Result := Result + #226#132#162 // ™
          else if Entity = 'mdash' then Result := Result + #226#128#148 // —
          else if Entity = 'ndash' then Result := Result + #226#128#147 // –
          else if Entity = 'bull' then Result := Result + #226#128#162  // •
          else if Entity = 'hellip' then Result := Result + #226#128#166 // …
          else if Entity = 'euro' then Result := Result + #226#130#172  // €
          else if Entity = 'pound' then Result := Result + #194#163  // £
          else if Entity = 'yen' then Result := Result + #194#165    // ¥
          else if Entity = 'cent' then Result := Result + #194#162   // ¢
          else if Entity = 'deg' then Result := Result + #194#176    // °
          else if Entity = 'plusmn' then Result := Result + #194#177 // ±
          else if Entity = 'times' then Result := Result + #194#215  // ×
          else if Entity = 'divide' then Result := Result + #194#247 // ÷
          else if Entity = 'laquo' then Result := Result + #194#171  // «
          else if Entity = 'raquo' then Result := Result + #194#187  // »
          else if Entity = 'check' then Result := Result + #226#156#147 // ✓
          else if Entity = 'hearts' then Result := Result + #226#153#165 // ♥
          else if Entity = 'diams' then Result := Result + #226#153#166  // ♦
          else if Entity = 'clubs' then Result := Result + #226#153#163  // ♣
          else if Entity = 'spades' then Result := Result + #226#153#160 // ♠
          else
            Result := Result + '&' + Entity + ';';
        end;

        I := Semi + 1;
        Continue;
      end;
    end;

    Result := Result + S[I];
    Inc(I);
  end;
end;

end.
