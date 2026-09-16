unit Floria.CSS.Tokenizer;

// Floria.CSS.Tokenizer
// ====================
// Streaming CSS tokenizer strictly conforming to W3C CSS Syntax Level 3 §4.
// Reference: https://www.w3.org/TR/css-syntax-3/#tokenization
//
// Usage
// -----
//   tok := TCSSTokenizer.Create(myListener);
//   try
//     tok.Feed(chunk1);
//     tok.Feed(chunk2);   // call Feed as many times as needed
//     tok.Finish();       // flushes remaining input and emits <EOF-token>
//   finally
//     tok.Free();
//   end;
//
// The listener's OnToken is called for every token (including <EOF-token>).
// Comments are stripped and never surfaced as tokens.
//
// Encoding
// --------
// Input is treated as UTF-8. Invalid UTF-8 byte sequences fall back to
// Latin-1 (the byte value is used directly as the Unicode code point).
// A UTF-8 BOM (EF BB BF) at the start of the stream is silently stripped.
//
// Error recovery
// --------------
// Parse errors produce <bad-string-token> or <bad-url-token> and tokenisation
// continues from the next safe position, following the spec's error model.

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Floria.CSS.Types;

type
  TCSSTokenizer = class(TObject)
  private
    FListener   : ICSSTokenListener;
    FBuffer     : AnsiString;  // accumulated raw input (all Feed chunks)
    FFinished   : Boolean;
    FEOFEmitted : Boolean;

    // Tokenisation cursor
    FPos    : Integer;  // byte offset in FBuffer (1-based)
    FLine   : Integer;  // current line (1-based)
    FColumn : Integer;  // current column in code points (1-based)

    // Preprocessing (spec §3.3)
    function Preprocess(const AInput: AnsiString): AnsiString;

    // UTF-8 / encoding helpers
    // Decode one UTF-8 code point at byte position ABytePos.
    // Returns $FFFFFFFF on EOF. Invalid bytes fall back to their Latin-1 value.
    function DecodeUTF8At(ABytePos: Integer; out AByteLen: Integer): Cardinal;
    // Byte length of the UTF-8 sequence starting at ABytePos.
    function CPByteLen(ABytePos: Integer): Integer;
    // Current code point (does not advance).
    function CurrentCP(): Cardinal;
    // Peek AOffset code points ahead of current position (0 = current).
    function PeekCP(AOffset: Integer): Cardinal;
    // Advance past the current code point, updating line/column.
    procedure AdvanceCP();
    // Encode a Unicode code point back to UTF-8.
    function EncodeUTF8(ACodePoint: Cardinal): AnsiString;

    // Spec character predicates
    function IsWhitespace(cp: Cardinal): Boolean;
    function IsDigit(cp: Cardinal): Boolean;
    function IsHexDigit(cp: Cardinal): Boolean;
    function IsAlpha(cp: Cardinal): Boolean;
    function IsNonASCII(cp: Cardinal): Boolean;
    function IsIdentStartCP(cp: Cardinal): Boolean;
    function IsIdentCP(cp: Cardinal): Boolean;

    // Three-code-point lookahead checks (spec §4.3.8-4.3.10)
    // Whether the two code points starting at byte position p form a valid escape.
    function WouldStartValidEscape(p: Integer): Boolean;
    // Whether the code points starting at byte position p start an ident sequence.
    function WouldStartIdentSequence(p: Integer): Boolean;
    // Whether the code points starting at byte position p start a number.
    function WouldStartNumber(p: Integer): Boolean;

    // Consume algorithms (spec §4.3.x)
    // §4.3.11 — returns the consumed ident sequence as a string.
    function ConsumeIdentSequence(): AnsiString;
    // §4.3.7  — backslash already consumed; returns the escaped code point.
    function ConsumeEscapedCP(): Cardinal;
    // §4.3.12 — returns repr string, sets AValue and AFlag.
    function ConsumeNumber(out AValue: Double; out AFlag: TCSSNumberFlag): AnsiString;
    // §4.3.3
    procedure ConsumeNumericToken(const AStartPos: TCSSSourcePos);
    // §4.3.4
    procedure ConsumeIdentLikeToken(const AStartPos: TCSSSourcePos);
    // §4.3.5 — opening quote already consumed; AEndCP is the quote char.
    procedure ConsumeStringToken(AEndCP: Cardinal; const AStartPos: TCSSSourcePos);
    // §4.3.6 — "url(" already consumed.
    procedure ConsumeUrlToken(const AStartPos: TCSSSourcePos);
    // §4.3.14
    procedure ConsumeRemnantsOfBadUrl();
    // §4.3.2
    procedure ConsumeComments();

    // Main token consumer
    procedure ConsumeToken();
    procedure ProcessBuffer();

    // Emit helpers
    function  MakePos(): TCSSSourcePos;
    procedure Emit(const AToken: TCSSToken);
    procedure EmitSimple(AType: TCSSTokenType; const AValue: AnsiString;
                         const APos: TCSSSourcePos);

  public
    constructor Create(AListener: ICSSTokenListener);
    // Append a chunk of CSS text. May be called multiple times before Finish.
    procedure Feed(const AChunk: AnsiString);
    // Signal end of input. Preprocesses the accumulated buffer, tokenises it,
    // and emits an <EOF-token>. Calling Finish more than once is a no-op.
    procedure Finish();
  end;

implementation

const
  EOF_CP = $FFFFFFFF;  // sentinel returned when the input stream is exhausted

// ============================================================
// Constructor / Feed / Finish
// ============================================================

constructor TCSSTokenizer.Create(AListener: ICSSTokenListener);
begin
  inherited Create();
  FListener   := AListener;
  FBuffer     := '';
  FFinished   := False;
  FEOFEmitted := False;
  FPos        := 1;
  FLine       := 1;
  FColumn     := 1;
end;

procedure TCSSTokenizer.Feed(const AChunk: AnsiString);
begin
  if FFinished then Exit;
  FBuffer := FBuffer + AChunk;
end;

procedure TCSSTokenizer.Finish();
begin
  if FFinished then Exit;
  FFinished := True;

  // Preprocess the complete input (handles CR/CRLF/FF and NUL, spec §3.3)
  FBuffer := Preprocess(FBuffer);

  // Strip UTF-8 BOM (EF BB BF) if present
  if (Length(FBuffer) >= 3)
     and (Byte(FBuffer[1]) = $EF)
     and (Byte(FBuffer[2]) = $BB)
     and (Byte(FBuffer[3]) = $BF) then
    Delete(FBuffer, 1, 3);

  ProcessBuffer();
end;

// ============================================================
// Preprocessing — spec §3.3
// ============================================================

function TCSSTokenizer.Preprocess(const AInput: AnsiString): AnsiString;
var
  i : Integer;
  b : Byte;
begin
  Result := '';
  i := 1;
  while i <= Length(AInput) do
  begin
    b := Byte(AInput[i]);
    if b = $0D then          // CR
    begin
      Result := Result + #$0A;
      // If followed by LF, skip the LF (CRLF -> single LF)
      if (i + 1 <= Length(AInput)) and (Byte(AInput[i + 1]) = $0A) then
        Inc(i);
    end
    else if b = $0C then     // FF -> LF
      Result := Result + #$0A
    else if b = $00 then     // NUL -> U+FFFD (UTF-8: EF BF BD)
      Result := Result + #$EF#$BF#$BD
    else
      Result := Result + AInput[i];
    Inc(i);
  end;
end;

// ============================================================
// UTF-8 / encoding helpers
// ============================================================

function TCSSTokenizer.DecodeUTF8At(ABytePos: Integer;
                                    out AByteLen: Integer): Cardinal;
var
  b0, b1, b2, b3 : Byte;
  cp              : Cardinal;
begin
  AByteLen := 1; // default: consume one byte
  if ABytePos > Length(FBuffer) then
  begin
    AByteLen := 0;
    Result := EOF_CP;
    Exit;
  end;

  b0 := Byte(FBuffer[ABytePos]);

  // 1-byte (ASCII)
  if b0 <= $7F then
  begin
    Result := b0;
    Exit;
  end;

  // 2-byte  110xxxxx 10xxxxxx
  if (b0 and $E0) = $C0 then
  begin
    if ABytePos + 1 <= Length(FBuffer) then
    begin
      b1 := Byte(FBuffer[ABytePos + 1]);
      if (b1 and $C0) = $80 then
      begin
        cp := ((b0 and $1F) shl 6) or (b1 and $3F);
        if cp >= $80 then  // reject overlong
        begin
          AByteLen := 2;
          Result := cp;
          Exit;
        end;
      end;
    end;
    Result := b0; // Latin-1 fallback
    Exit;
  end;

  // 3-byte  1110xxxx 10xxxxxx 10xxxxxx
  if (b0 and $F0) = $E0 then
  begin
    if ABytePos + 2 <= Length(FBuffer) then
    begin
      b1 := Byte(FBuffer[ABytePos + 1]);
      b2 := Byte(FBuffer[ABytePos + 2]);
      if ((b1 and $C0) = $80) and ((b2 and $C0) = $80) then
      begin
        cp := ((b0 and $0F) shl 12) or ((b1 and $3F) shl 6) or (b2 and $3F);
        // Reject overlong and surrogate halves
        if (cp >= $800) and not ((cp >= $D800) and (cp <= $DFFF)) then
        begin
          AByteLen := 3;
          Result := cp;
          Exit;
        end;
      end;
    end;
    Result := b0; // Latin-1 fallback
    Exit;
  end;

  // 4-byte  11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
  if (b0 and $F8) = $F0 then
  begin
    if ABytePos + 3 <= Length(FBuffer) then
    begin
      b1 := Byte(FBuffer[ABytePos + 1]);
      b2 := Byte(FBuffer[ABytePos + 2]);
      b3 := Byte(FBuffer[ABytePos + 3]);
      if ((b1 and $C0) = $80) and ((b2 and $C0) = $80) and ((b3 and $C0) = $80) then
      begin
        cp := ((b0 and $07) shl 18) or ((b1 and $3F) shl 12)
           or ((b2 and $3F) shl 6) or (b3 and $3F);
        if (cp >= $10000) and (cp <= $10FFFF) then
        begin
          AByteLen := 4;
          Result := cp;
          Exit;
        end;
      end;
    end;
    Result := b0; // Latin-1 fallback
    Exit;
  end;

  // Continuation byte or other invalid leading byte - Latin-1 fallback
  Result := b0;
end;

function TCSSTokenizer.CPByteLen(ABytePos: Integer): Integer;
var
  dummy : Cardinal;
begin
  dummy  := DecodeUTF8At(ABytePos, Result);
  if Result = 0 then Result := 1; // safety: never return 0 for a non-EOF position
end;

function TCSSTokenizer.CurrentCP(): Cardinal;
var
  bl : Integer;
begin
  Result := DecodeUTF8At(FPos, bl);
end;

function TCSSTokenizer.PeekCP(AOffset: Integer): Cardinal;
var
  bp, bl, i : Integer;
  dummy      : Cardinal;
begin
  bp := FPos;
  for i := 1 to AOffset do
  begin
    if bp > Length(FBuffer) then Exit(EOF_CP);
    dummy := DecodeUTF8At(bp, bl);
    if bl = 0 then Exit(EOF_CP);
    Inc(bp, bl);
  end;
  Result := DecodeUTF8At(bp, bl);
end;

procedure TCSSTokenizer.AdvanceCP();
var
  bl : Integer;
  cp : Cardinal;
begin
  if FPos > Length(FBuffer) then Exit;
  cp := DecodeUTF8At(FPos, bl);
  Inc(FPos, bl);
  // Update line/column tracking.
  // After preprocessing, all newlines are U+000A.
  if cp = $000A then
  begin
    Inc(FLine);
    FColumn := 1;
  end
  else
    Inc(FColumn);
end;

function TCSSTokenizer.EncodeUTF8(ACodePoint: Cardinal): AnsiString;
begin
  if ACodePoint <= $7F then
    Result := Chr(ACodePoint)
  else if ACodePoint <= $7FF then
    Result := Chr($C0 or (ACodePoint shr 6))
            + Chr($80 or (ACodePoint and $3F))
  else if ACodePoint <= $FFFF then
    Result := Chr($E0 or (ACodePoint shr 12))
            + Chr($80 or ((ACodePoint shr 6) and $3F))
            + Chr($80 or (ACodePoint and $3F))
  else
    Result := Chr($F0 or (ACodePoint shr 18))
            + Chr($80 or ((ACodePoint shr 12) and $3F))
            + Chr($80 or ((ACodePoint shr 6) and $3F))
            + Chr($80 or (ACodePoint and $3F));
end;

// ============================================================
// Character predicates
// ============================================================

function TCSSTokenizer.IsWhitespace(cp: Cardinal): Boolean;
begin
  // After preprocessing, only TAB (09), LF (0A), SPACE (20) remain.
  Result := (cp = $09) or (cp = $0A) or (cp = $20);
end;

function TCSSTokenizer.IsDigit(cp: Cardinal): Boolean;
begin
  Result := (cp >= $30) and (cp <= $39);
end;

function TCSSTokenizer.IsHexDigit(cp: Cardinal): Boolean;
begin
  Result := IsDigit(cp)
         or ((cp >= $41) and (cp <= $46))  // A-F
         or ((cp >= $61) and (cp <= $66)); // a-f
end;

function TCSSTokenizer.IsAlpha(cp: Cardinal): Boolean;
begin
  Result := ((cp >= $41) and (cp <= $5A))  // A-Z
         or ((cp >= $61) and (cp <= $7A)); // a-z
end;

function TCSSTokenizer.IsNonASCII(cp: Cardinal): Boolean;
begin
  // Guard against the EOF sentinel ($FFFFFFFF).
  Result := (cp >= $0080) and (cp <= $10FFFF);
end;

function TCSSTokenizer.IsIdentStartCP(cp: Cardinal): Boolean;
begin
  // spec §4.2: letter | non-ASCII | U+005F (_)
  if cp > $10FFFF then Exit(False); // reject EOF sentinel
  Result := IsAlpha(cp) or IsNonASCII(cp) or (cp = $5F);
end;

function TCSSTokenizer.IsIdentCP(cp: Cardinal): Boolean;
begin
  // spec §4.2: ident-start | digit | U+002D (-)
  if cp > $10FFFF then Exit(False);
  Result := IsIdentStartCP(cp) or IsDigit(cp) or (cp = $2D);
end;

// ============================================================
// Three-code-point lookahead (spec §4.3.8-4.3.10)
// p is a byte position in FBuffer.
// ============================================================

function TCSSTokenizer.WouldStartValidEscape(p: Integer): Boolean;
// spec §4.3.8: first CP is '\', second CP is not a newline.
var
  cp1, cp2 : Cardinal;
  bl1      : Integer;
begin
  cp1 := DecodeUTF8At(p, bl1);
  if cp1 <> $5C then Exit(False);     // not backslash
  if bl1 = 0    then Exit(False);
  cp2 := DecodeUTF8At(p + bl1, bl1);
  Result := cp2 <> $0A;               // second CP is not LF (newline)
end;

function TCSSTokenizer.WouldStartIdentSequence(p: Integer): Boolean;
// spec §4.3.9
var
  cp1, cp2 : Cardinal;
  bl1, bl2 : Integer;
begin
  cp1 := DecodeUTF8At(p, bl1);
  if cp1 = $2D then // '-'
  begin
    cp2 := DecodeUTF8At(p + bl1, bl2);
    Result := IsIdentStartCP(cp2)
           or (cp2 = $2D)                         // '--'
           or WouldStartValidEscape(p + bl1);
  end
  else if IsIdentStartCP(cp1) then
    Result := True
  else if cp1 = $5C then // '\'
    Result := WouldStartValidEscape(p)
  else
    Result := False;
end;

function TCSSTokenizer.WouldStartNumber(p: Integer): Boolean;
// spec §4.3.10
var
  cp1, cp2, cp3 : Cardinal;
  bl1, bl2       : Integer;
begin
  cp1 := DecodeUTF8At(p, bl1);
  if (cp1 = $2B) or (cp1 = $2D) then // '+' or '-'
  begin
    cp2 := DecodeUTF8At(p + bl1, bl2);
    if IsDigit(cp2) then
      Result := True
    else if cp2 = $2E then // '.'
    begin
      cp3 := DecodeUTF8At(p + bl1 + bl2, bl2);
      Result := IsDigit(cp3);
    end
    else
      Result := False;
  end
  else if cp1 = $2E then // '.'
  begin
    cp2 := DecodeUTF8At(p + bl1, bl2);
    Result := IsDigit(cp2);
  end
  else
    Result := IsDigit(cp1);
end;

// ============================================================
// §4.3.2 — Consume comments
// ============================================================

procedure TCSSTokenizer.ConsumeComments();
begin
  while (CurrentCP() = $2F) and (PeekCP(1) = $2A) do  // '/' '*'
  begin
    AdvanceCP(); // consume '/'
    AdvanceCP(); // consume '*'
    // Consume everything until '*/' or EOF
    repeat
      if CurrentCP() = EOF_CP then Exit;   // parse error: EOF in comment
      if (CurrentCP() = $2A) and (PeekCP(1) = $2F) then  // '*/'
      begin
        AdvanceCP(); // consume '*'
        AdvanceCP(); // consume '/'
        Break;
      end;
      AdvanceCP();
    until False;
    // Loop back to check for another comment immediately following
  end;
end;

// ============================================================
// §4.3.11 — Consume an ident sequence
// ============================================================

function TCSSTokenizer.ConsumeIdentSequence(): AnsiString;
var
  cp : Cardinal;
begin
  Result := '';
  repeat
    cp := CurrentCP();
    if IsIdentCP(cp) then
    begin
      Result := Result + EncodeUTF8(cp);
      AdvanceCP();
    end
    else if WouldStartValidEscape(FPos) then
    begin
      AdvanceCP();                        // consume '\'
      Result := Result + EncodeUTF8(ConsumeEscapedCP());
    end
    else
      Break;
  until False;
end;

// ============================================================
// §4.3.7 — Consume an escaped code point
// '\' has already been consumed by the caller.
// ============================================================

function TCSSTokenizer.ConsumeEscapedCP(): Cardinal;
var
  cp      : Cardinal;
  hexStr  : AnsiString;
  hexVal  : Cardinal;
  count   : Integer;
  errCode : Integer;
begin
  cp := CurrentCP();
  if IsHexDigit(cp) then
  begin
    hexStr := '';
    count  := 0;
    while IsHexDigit(CurrentCP()) and (count < 6) do
    begin
      hexStr := hexStr + Chr(CurrentCP());
      AdvanceCP();
      Inc(count);
    end;
    // Optionally consume a single trailing whitespace (spec §4.3.7)
    if IsWhitespace(CurrentCP()) then
      AdvanceCP();
    Val('$' + hexStr, hexVal, errCode);
    if errCode <> 0 then hexVal := 0;
    // Reject zero, surrogates and values above U+10FFFF -> U+FFFD
    if (hexVal = 0)
       or ((hexVal >= $D800) and (hexVal <= $DFFF))
       or (hexVal > $10FFFF) then
      Result := $FFFD
    else
      Result := hexVal;
  end
  else if cp = EOF_CP then
    Result := $FFFD   // parse error
  else
  begin
    AdvanceCP();
    Result := cp;
  end;
end;

// ============================================================
// §4.3.12 — Consume a number
// ============================================================

function TCSSTokenizer.ConsumeNumber(out AValue: Double;
                                     out AFlag: TCSSNumberFlag): AnsiString;
var
  repr    : AnsiString;
  cp      : Cardinal;
  errCode : Integer;
  fs      : TFormatSettings;
begin
  repr  := '';
  AFlag := cnfInteger;

  // Step 3: optional sign
  cp := CurrentCP();
  if (cp = $2B) or (cp = $2D) then  // '+' or '-'
  begin
    repr := repr + Chr(cp);
    AdvanceCP();
  end;

  // Step 4: integer digits
  while IsDigit(CurrentCP()) do
  begin
    repr := repr + Chr(CurrentCP());
    AdvanceCP();
  end;

  // Step 5: decimal part
  if (CurrentCP() = $2E) and IsDigit(PeekCP(1)) then  // '.'
  begin
    repr  := repr + '.';
    AdvanceCP();
    AFlag := cnfNumber;
    while IsDigit(CurrentCP()) do
    begin
      repr := repr + Chr(CurrentCP());
      AdvanceCP();
    end;
  end;

  // Step 6: exponent
  cp := CurrentCP();
  if (cp = $45) or (cp = $65) then  // 'E' or 'e'
  begin
    cp := PeekCP(1);
    if IsDigit(cp) then
    begin
      repr  := repr + Chr(CurrentCP());  // E/e
      AdvanceCP();
      AFlag := cnfNumber;
      while IsDigit(CurrentCP()) do
      begin
        repr := repr + Chr(CurrentCP());
        AdvanceCP();
      end;
    end
    else if ((cp = $2B) or (cp = $2D)) and IsDigit(PeekCP(2)) then
    begin
      repr  := repr + Chr(CurrentCP());  // E/e
      AdvanceCP();
      repr  := repr + Chr(CurrentCP());  // sign
      AdvanceCP();
      AFlag := cnfNumber;
      while IsDigit(CurrentCP()) do
      begin
        repr := repr + Chr(CurrentCP());
        AdvanceCP();
      end;
    end;
  end;

  // Step 7: convert repr to a number (locale-independent, '.' as separator)
  fs                := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  AValue := StrToFloatDef(repr, 0, fs);

  Result := repr;
end;

// ============================================================
// §4.3.3 — Consume a numeric token
// ============================================================

procedure TCSSTokenizer.ConsumeNumericToken(const AStartPos: TCSSSourcePos);
var
  tok    : TCSSToken;
  repr   : AnsiString;
  numVal : Double;
  numFlg : TCSSNumberFlag;
begin
  repr := ConsumeNumber(numVal, numFlg);

  tok.NumericVal := numVal;
  tok.NumFlag    := numFlg;
  tok.Value      := repr;
  tok.HashFlag   := chfUnrestricted;
  tok.Pos        := AStartPos;

  if WouldStartIdentSequence(FPos) then
  begin
    tok.TokenType := cttDimension;
    tok.Unit_     := ConsumeIdentSequence();
  end
  else if CurrentCP() = $25 then  // '%'
  begin
    AdvanceCP();
    tok.TokenType := cttPercentage;
    tok.Unit_     := '';
  end
  else
  begin
    tok.TokenType := cttNumber;
    tok.Unit_     := '';
  end;

  Emit(tok);
end;

// ============================================================
// §4.3.4 — Consume an ident-like token
// ============================================================

procedure TCSSTokenizer.ConsumeIdentLikeToken(const AStartPos: TCSSSourcePos);
var
  tok      : TCSSToken;
  identStr : AnsiString;
  cp1, cp2 : Cardinal;
begin
  identStr := ConsumeIdentSequence();

  if (LowerCase(identStr) = 'url') and (CurrentCP() = $28) then  // 'url' + '('
  begin
    AdvanceCP(); // consume '('

    // Consume whitespace pairs (spec §4.3.4 step 2b):
    // "while next two input code points are whitespace, consume the next one"
    while IsWhitespace(CurrentCP()) and IsWhitespace(PeekCP(1)) do
      AdvanceCP();

    // Decide: function token or actual url token?
    cp1 := CurrentCP();
    cp2 := PeekCP(1);
    if (cp1 = $22) or (cp1 = $27)  // " or '
    or (IsWhitespace(cp1) and ((cp2 = $22) or (cp2 = $27))) then
    begin
      // Quoted url -> emit <function-token> and let the parser handle the string
      tok.TokenType  := cttFunction;
      tok.Value      := identStr;
      tok.NumericVal := 0;
      tok.NumFlag    := cnfInteger;
      tok.HashFlag   := chfUnrestricted;
      tok.Unit_      := '';
      tok.Pos        := AStartPos;
      Emit(tok);
    end
    else
      ConsumeUrlToken(AStartPos);
  end
  else if CurrentCP() = $28 then  // '(' - generic function
  begin
    AdvanceCP();
    tok.TokenType  := cttFunction;
    tok.Value      := identStr;
    tok.NumericVal := 0;
    tok.NumFlag    := cnfInteger;
    tok.HashFlag   := chfUnrestricted;
    tok.Unit_      := '';
    tok.Pos        := AStartPos;
    Emit(tok);
  end
  else
  begin
    tok.TokenType  := cttIdent;
    tok.Value      := identStr;
    tok.NumericVal := 0;
    tok.NumFlag    := cnfInteger;
    tok.HashFlag   := chfUnrestricted;
    tok.Unit_      := '';
    tok.Pos        := AStartPos;
    Emit(tok);
  end;
end;

// ============================================================
// §4.3.5 — Consume a string token
// Opening quote already consumed; AEndCP is the quote code point.
// ============================================================

procedure TCSSTokenizer.ConsumeStringToken(AEndCP: Cardinal;
                                           const AStartPos: TCSSSourcePos);
var
  tok       : TCSSToken;
  cp        : Cardinal;
  escapedCP : Cardinal;
begin
  tok.TokenType  := cttString;
  tok.Value      := '';
  tok.NumericVal := 0;
  tok.NumFlag    := cnfInteger;
  tok.HashFlag   := chfUnrestricted;
  tok.Unit_      := '';
  tok.Pos        := AStartPos;

  repeat
    cp := CurrentCP();
    if cp = AEndCP then
    begin
      AdvanceCP();    // consume closing quote
      Break;
    end
    else if cp = EOF_CP then
    begin
      // parse error - emit as a (truncated) string token and stop
      Break;
    end
    else if cp = $0A then  // newline (after preprocessing)
    begin
      // parse error - reconsume the newline; return <bad-string-token>
      tok.TokenType := cttBadString;
      Break;
    end
    else if cp = $5C then  // '\'
    begin
      AdvanceCP();  // consume '\'
      cp := CurrentCP();
      if cp = EOF_CP then
        // nothing (spec: "if EOF, do nothing")
      else if cp = $0A then
        AdvanceCP()  // escaped newline -> consume the LF, add nothing to value
      else
      begin
        escapedCP  := ConsumeEscapedCP();
        tok.Value  := tok.Value + EncodeUTF8(escapedCP);
      end;
    end
    else
    begin
      tok.Value := tok.Value + EncodeUTF8(cp);
      AdvanceCP();
    end;
  until False;

  Emit(tok);
end;

// ============================================================
// §4.3.6 — Consume a url token
// "url(" already consumed by ConsumeIdentLikeToken.
// ============================================================

procedure TCSSTokenizer.ConsumeUrlToken(const AStartPos: TCSSSourcePos);
var
  tok       : TCSSToken;
  cp        : Cardinal;
  escapedCP : Cardinal;
begin
  tok.TokenType  := cttUrl;
  tok.Value      := '';
  tok.NumericVal := 0;
  tok.NumFlag    := cnfInteger;
  tok.HashFlag   := chfUnrestricted;
  tok.Unit_      := '';
  tok.Pos        := AStartPos;

  // Step 2: consume leading whitespace
  while IsWhitespace(CurrentCP()) do AdvanceCP();

  // Step 3: main loop
  repeat
    cp := CurrentCP();
    if cp = $29 then  // ')'
    begin
      AdvanceCP();
      Break;
    end
    else if cp = EOF_CP then
    begin
      // parse error - return url token as-is (EOF)
      Break;
    end
    else if IsWhitespace(cp) then
    begin
      // Consume the whitespace block
      while IsWhitespace(CurrentCP()) do AdvanceCP();
      cp := CurrentCP();
      if (cp = $29) or (cp = EOF_CP) then
      begin
        if cp = $29 then AdvanceCP();
        Break;
      end;
      // Non-closing content after whitespace -> bad-url
      ConsumeRemnantsOfBadUrl();
      tok.TokenType := cttBadUrl;
      Break;
    end
    else if (cp = $22) or (cp = $27) or (cp = $28) then  // " ' (
    begin
      // parse error
      ConsumeRemnantsOfBadUrl();
      tok.TokenType := cttBadUrl;
      Break;
    end
    else if cp = $5C then  // '\'
    begin
      if WouldStartValidEscape(FPos) then
      begin
        AdvanceCP();  // consume '\'
        escapedCP := ConsumeEscapedCP();
        tok.Value := tok.Value + EncodeUTF8(escapedCP);
      end
      else
      begin
        // parse error
        ConsumeRemnantsOfBadUrl();
        tok.TokenType := cttBadUrl;
        Break;
      end;
    end
    else
    begin
      tok.Value := tok.Value + EncodeUTF8(cp);
      AdvanceCP();
    end;
  until False;

  Emit(tok);
end;

// ============================================================
// §4.3.14 — Consume remnants of a bad url
// ============================================================

procedure TCSSTokenizer.ConsumeRemnantsOfBadUrl();
begin
  repeat
    if (CurrentCP() = $29) or (CurrentCP() = EOF_CP) then  // ')' or EOF
    begin
      if CurrentCP() = $29 then AdvanceCP();
      Exit;
    end;
    if WouldStartValidEscape(FPos) then
    begin
      AdvanceCP();              // consume '\'
      ConsumeEscapedCP();       // consume and discard the escaped code point
    end
    else
      AdvanceCP();
  until False;
end;

// ============================================================
// Main token consumer - spec §4.3.1
// ============================================================

procedure TCSSTokenizer.ConsumeToken();
var
  cp       : Cardinal;
  apos     : TCSSSourcePos;
  tok      : TCSSToken;
  identStr : AnsiString;
begin
  ConsumeComments();

  apos := MakePos();
  cp   := CurrentCP();

  // EOF
  if cp = EOF_CP then
  begin
    EmitSimple(cttEOF, '', apos);
    FEOFEmitted := True;
    Exit;
  end;

  // Whitespace
  if IsWhitespace(cp) then
  begin
    while IsWhitespace(CurrentCP()) do AdvanceCP();
    EmitSimple(cttWhitespace, ' ', apos);
    Exit;
  end;

  // String delimiters  " '
  if (cp = $22) or (cp = $27) then
  begin
    AdvanceCP();  // consume opening quote
    ConsumeStringToken(cp, apos);
    Exit;
  end;

  // #
  if cp = $23 then
  begin
    AdvanceCP();  // consume '#'
    if IsIdentCP(CurrentCP()) or WouldStartValidEscape(FPos) then
    begin
      tok.TokenType  := cttHash;
      tok.NumericVal := 0;
      tok.NumFlag    := cnfInteger;
      tok.Unit_      := '';
      tok.Pos        := apos;
      if WouldStartIdentSequence(FPos) then
        tok.HashFlag := chfID
      else
        tok.HashFlag := chfUnrestricted;
      tok.Value := ConsumeIdentSequence();
      Emit(tok);
    end
    else
      EmitSimple(cttDelim, '#', apos);
    Exit;
  end;

  // ( )
  if cp = $28 then begin AdvanceCP(); EmitSimple(cttOpenParen,  '(', apos); Exit; end;
  if cp = $29 then begin AdvanceCP(); EmitSimple(cttCloseParen, ')', apos); Exit; end;

  // +
  if cp = $2B then
  begin
    if WouldStartNumber(FPos) then
      ConsumeNumericToken(apos)
    else
    begin
      AdvanceCP();
      EmitSimple(cttDelim, '+', apos);
    end;
    Exit;
  end;

  // ,
  if cp = $2C then begin AdvanceCP(); EmitSimple(cttComma, ',', apos); Exit; end;

  // -
  if cp = $2D then
  begin
    if WouldStartNumber(FPos) then
      ConsumeNumericToken(apos)
    else if (PeekCP(1) = $2D) and (PeekCP(2) = $3E) then  // '-->'
    begin
      AdvanceCP(); AdvanceCP(); AdvanceCP();
      EmitSimple(cttCDC, '-->', apos);
    end
    else if WouldStartIdentSequence(FPos) then
      ConsumeIdentLikeToken(apos)
    else
    begin
      AdvanceCP();
      EmitSimple(cttDelim, '-', apos);
    end;
    Exit;
  end;

  // .
  if cp = $2E then
  begin
    if WouldStartNumber(FPos) then
      ConsumeNumericToken(apos)
    else
    begin
      AdvanceCP();
      EmitSimple(cttDelim, '.', apos);
    end;
    Exit;
  end;

  // : ;
  if cp = $3A then begin AdvanceCP(); EmitSimple(cttColon,     ':', apos); Exit; end;
  if cp = $3B then begin AdvanceCP(); EmitSimple(cttSemicolon, ';', apos); Exit; end;

  // < (possibly <!--)
  if cp = $3C then
  begin
    if (PeekCP(1) = $21) and (PeekCP(2) = $2D) and (PeekCP(3) = $2D) then  // '<!--'
    begin
      AdvanceCP(); AdvanceCP(); AdvanceCP(); AdvanceCP();
      EmitSimple(cttCDO, '<!--', apos);
    end
    else
    begin
      AdvanceCP();
      EmitSimple(cttDelim, '<', apos);
    end;
    Exit;
  end;

  // @
  if cp = $40 then
  begin
    AdvanceCP();  // consume '@'
    if WouldStartIdentSequence(FPos) then
    begin
      identStr       := ConsumeIdentSequence();
      tok.TokenType  := cttAtKeyword;
      tok.Value      := identStr;
      tok.NumericVal := 0;
      tok.NumFlag    := cnfInteger;
      tok.HashFlag   := chfUnrestricted;
      tok.Unit_      := '';
      tok.Pos        := apos;
      Emit(tok);
    end
    else
      EmitSimple(cttDelim, '@', apos);
    Exit;
  end;

  // [ ]
  if cp = $5B then begin AdvanceCP(); EmitSimple(cttOpenSquare,  '[', apos); Exit; end;
  if cp = $5D then begin AdvanceCP(); EmitSimple(cttCloseSquare, ']', apos); Exit; end;

  // backslash
  if cp = $5C then
  begin
    if WouldStartValidEscape(FPos) then
      ConsumeIdentLikeToken(apos)
    else
    begin
      // parse error
      AdvanceCP();
      EmitSimple(cttDelim, '\', apos);
    end;
    Exit;
  end;

  // curly braces
  if cp = $7B then begin AdvanceCP(); EmitSimple(cttOpenCurly,  '{', apos); Exit; end;
  if cp = $7D then begin AdvanceCP(); EmitSimple(cttCloseCurly, '}', apos); Exit; end;

  // digit
  if IsDigit(cp) then
  begin
    ConsumeNumericToken(apos);
    Exit;
  end;

  // ident-start
  if IsIdentStartCP(cp) then
  begin
    ConsumeIdentLikeToken(apos);
    Exit;
  end;

  // anything else -> <delim-token>
  AdvanceCP();
  EmitSimple(cttDelim, EncodeUTF8(cp), apos);
end;

procedure TCSSTokenizer.ProcessBuffer();
begin
  FPos        := 1;
  FLine       := 1;
  FColumn     := 1;
  FEOFEmitted := False;

  repeat
    ConsumeToken();
  until FEOFEmitted;
end;

// ============================================================
// Emit helpers
// ============================================================

function TCSSTokenizer.MakePos(): TCSSSourcePos;
begin
  Result.Line   := FLine;
  Result.Column := FColumn;
end;

procedure TCSSTokenizer.Emit(const AToken: TCSSToken);
begin
  if FListener <> nil then
    FListener.OnToken(AToken);
end;

procedure TCSSTokenizer.EmitSimple(AType: TCSSTokenType;
                                   const AValue: AnsiString;
                                   const APos: TCSSSourcePos);
var
  tok : TCSSToken;
begin
  tok.TokenType  := AType;
  tok.Value      := AValue;
  tok.NumericVal := 0;
  tok.NumFlag    := cnfInteger;
  tok.HashFlag   := chfUnrestricted;
  tok.Unit_      := '';
  tok.Pos        := APos;
  Emit(tok);
end;

end.
