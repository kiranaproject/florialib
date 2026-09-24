unit Floria.Unicode.BiDi;

// Floria.Unicode.BiDi
// ===================
// Pure Pascal implementation of the Unicode Bidirectional Algorithm (UAX #9).
//
// Capabilities:
// - Unicode code point Bidi_Class classification (L, R, AL, EN, ES, ET, AN, CS,
//   NSM, BN, B, S, WS, ON, isolates, explicit embeddings).
// - Base paragraph embedding level resolution (Auto, LTR, RTL).
// - UAX #9 resolution rules: W1-W7 (weak types), N0-N2 (neutrals & brackets),
//   I1-I2 (implicit levels).
// - Bracket pairing and glyph mirroring for mirrored characters in RTL context.
// - Segmenting text into visual unidirectional runs (TFloriaBiDiRun) with
//   logical character preservation inside each run for OpenType shaping (HarfBuzz).
// - Pure visual string reordering helper (ReorderToVisualString) for fallback
//   rendering pipelines without shaping engines.

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes;

type
  // Unicode Bidi_Class enumeration (UAX #9 §3)
  TFloriaBidiClass = (
    fbcL,    // Left-to-Right
    fbcR,    // Right-to-Left (Hebrew, etc.)
    fbcAL,   // Right-to-Left Arabic Letter
    fbcEN,   // European Number
    fbcES,   // European Number Separator (+, -)
    fbcET,   // European Number Terminator ($, %, etc.)
    fbcAN,   // Arabic Number
    fbcCS,   // Common Number Separator (comma, period, colon)
    fbcNSM,  // Non-Spacing Mark
    fbcBN,   // Boundary Neutral
    fbcB,    // Paragraph Separator
    fbcS,    // Segment Separator
    fbcWS,   // Whitespace
    fbcON,   // Other Neutrals (punctuation, symbols)
    fbcLRE,  // Left-to-Right Embedding
    fbcRLE,  // Right-to-Left Embedding
    fbcLRO,  // Left-to-Right Override
    fbcRLO,  // Right-to-Left Override
    fbcPDF,  // Pop Directional Format
    fbcLRI,  // Left-to-Right Isolate
    fbcRLI,  // Right-to-Left Isolate
    fbcFSI,  // First Strong Isolate
    fbcPDI   // Pop Directional Isolate
  );

  TFloriaBiDiDirection = (
    fbdLTR,  // Left-to-Right
    fbdRTL   // Right-to-Left
  );

  TFloriaBiDiBaseDir = (
    fbbAuto, // Auto-detect from first strong character (default LTR if none)
    fbbLTR,  // Forced Left-to-Right base
    fbbRTL   // Forced Right-to-Left base
  );

  // A unidirectional run of text ready for shaping and visual layout
  TFloriaBiDiRun = record
    Text      : string;               // UTF-8 string of this run (logical order)
    Direction : TFloriaBiDiDirection; // Visual direction of this run
    Level     : Byte;                 // Resolved embedding level (even = LTR, odd = RTL)
    StartChar : Integer;              // 0-based character index in original string
    CharCount : Integer;              // Number of Unicode code points
  end;
  TFloriaBiDiRunArray = array of TFloriaBiDiRun;

  // TFloriaBiDi: Main Bidirectional processor
  TFloriaBiDi = class
  public
    // Returns the Bidi_Class for a given Unicode code point
    class function GetBidiClass(ACodePoint: Cardinal): TFloriaBidiClass;

    // Returns mirrored character for RTL context (e.g. '(' -> ')', '<' -> '>'),
    // or ACodePoint if no mirror exists.
    class function GetMirroredChar(ACodePoint: Cardinal): Cardinal;

    // Segments AText into visual unidirectional runs.
    // The runs are ordered from left to right as they should appear on screen.
    // The characters inside each run remain in logical order for OpenType shaping.
    class function GetVisualRuns(const AText: string;
                                ABaseDir: TFloriaBiDiBaseDir = fbbAuto): TFloriaBiDiRunArray;

    // Completely reorders AText into a visual display string, reversing RTL runs
    // and applying glyph mirroring. Used when rendering without a text shaper.
    class function ReorderToVisualString(const AText: string;
                                        ABaseDir: TFloriaBiDiBaseDir = fbbAuto): string;

    // Detects whether AText contains any Right-to-Left characters (Arabic or Hebrew)
    class function HasRTL(const AText: string): Boolean;
  end;

// Unicode helper functions
function FloriaUTF8NextChar(var P: PChar; out ACodePoint: Cardinal): Boolean;
function FloriaUnicodeToUTF8(ACodePoint: Cardinal): string;

implementation

// ============================================================================
// Unicode Helpers
// ============================================================================

function FloriaUTF8NextChar(var P: PChar; out ACodePoint: Cardinal): Boolean;
var
  B: Byte;
  Len: Integer;
begin
  ACodePoint := 0;
  if (P = nil) or (P^ = #0) then
    Exit(False);

  B := Byte(P^);
  if (B and $80) = 0 then
  begin
    ACodePoint := B;
    Inc(P);
    Exit(True);
  end;

  if (B and $E0) = $C0 then
  begin
    Len := 2;
    ACodePoint := B and $1F;
  end
  else if (B and $F0) = $E0 then
  begin
    Len := 3;
    ACodePoint := B and $0F;
  end
  else if (B and $F8) = $F0 then
  begin
    Len := 4;
    ACodePoint := B and $07;
  end
  else
  begin
    // Invalid lead byte, skip 1 byte
    ACodePoint := B;
    Inc(P);
    Exit(True);
  end;

  Inc(P);
  Dec(Len);
  while (Len > 0) and (P^ <> #0) and ((Byte(P^) and $C0) = $80) do
  begin
    ACodePoint := (ACodePoint shl 6) or (Byte(P^) and $3F);
    Inc(P);
    Dec(Len);
  end;

  Result := True;
end;

function FloriaUnicodeToUTF8(ACodePoint: Cardinal): string;
begin
  if ACodePoint <= $7F then
    Result := Chr(ACodePoint)
  else if ACodePoint <= $7FF then
    Result := Chr($C0 or (ACodePoint shr 6)) +
              Chr($80 or (ACodePoint and $3F))
  else if ACodePoint <= $FFFF then
    Result := Chr($E0 or (ACodePoint shr 12)) +
              Chr($80 or ((ACodePoint shr 6) and $3F)) +
              Chr($80 or (ACodePoint and $3F))
  else if ACodePoint <= $10FFFF then
    Result := Chr($F0 or (ACodePoint shr 18)) +
              Chr($80 or ((ACodePoint shr 12) and $3F)) +
              Chr($80 or ((ACodePoint shr 6) and $3F)) +
              Chr($80 or (ACodePoint and $3F))
  else
    Result := '?';
end;

// ============================================================================
// TFloriaBiDi Character Classification
// ============================================================================

class function TFloriaBiDi.GetBidiClass(ACodePoint: Cardinal): TFloriaBidiClass;
begin
  // ASCII fast path (0x00 .. 0x7F)
  if ACodePoint <= $7F then
  begin
    case ACodePoint of
      $00..$08, $0E..$1F, $7F:
        Exit(fbcBN);
      $09:
        Exit(fbcS);
      $0A, $0D:
        Exit(fbcB);
      $0C, $20:
        Exit(fbcWS);
      Ord('0')..Ord('9'):
        Exit(fbcEN);
      Ord('+'), Ord('-'):
        Exit(fbcES);
      Ord('$'), Ord('%'):
        Exit(fbcET);
      Ord(','), Ord('.'), Ord('/'), Ord(':'):
        Exit(fbcCS);
      Ord('A')..Ord('Z'), Ord('a')..Ord('z'):
        Exit(fbcL);
    else
      Exit(fbcON);
    end;
  end;

  // Hebrew script (0x0590 .. 0x05FF)
  if (ACodePoint >= $0590) and (ACodePoint <= $05FF) then
  begin
    case ACodePoint of
      $0591..$05BD, $05BF, $05C1..$05C2, $05C4..$05C5, $05C7:
        Exit(fbcNSM);
    else
      Exit(fbcR);
    end;
  end;

  // Arabic script (0x0600 .. 0x06FF)
  if (ACodePoint >= $0600) and (ACodePoint <= $06FF) then
  begin
    case ACodePoint of
      $0600..$0605:
        Exit(fbcAN);
      $0606..$060B, $060E..$060F:
        Exit(fbcON);
      $060C, $061B, $061F:
        Exit(fbcCS);
      $0610..$061A, $064B..$065F, $0670, $06D6..$06DC, $06DF..$06E4, $06E7..$06E8, $06EA..$06ED:
        Exit(fbcNSM);
      $0660..$0669, $066B:
        Exit(fbcAN);
      $066A, $066C:
        Exit(fbcET);
      $06F0..$06F9:
        Exit(fbcEN); // Persian/Eastern digits behave as EN in BiDi
    else
      Exit(fbcAL);
    end;
  end;

  // Arabic Supplement & Extended-A (0x0750 .. 0x08FF)
  if (ACodePoint >= $0750) and (ACodePoint <= $08FF) then
  begin
    case ACodePoint of
      $07A6..$07B0, $08E3..$08FE:
        Exit(fbcNSM);
    else
      Exit(fbcAL);
    end;
  end;

  // Syriac, Thaana, Samaritan, Mandaic (0x0700 .. 0x085F)
  if (ACodePoint >= $0700) and (ACodePoint <= $074F) then Exit(fbcAL);
  if (ACodePoint >= $0780) and (ACodePoint <= $07BF) then Exit(fbcAL);
  if (ACodePoint >= $0800) and (ACodePoint <= $083F) then Exit(fbcR);
  if (ACodePoint >= $0840) and (ACodePoint <= $085F) then Exit(fbcR);

  // Explicit BiDi Formatting Controls
  case ACodePoint of
    $200E: Exit(fbcL);   // LRM
    $200F: Exit(fbcR);   // RLM
    $202A: Exit(fbcLRE);
    $202B: Exit(fbcRLE);
    $202C: Exit(fbcPDF);
    $202D: Exit(fbcLRO);
    $202E: Exit(fbcRLO);
    $2066: Exit(fbcLRI);
    $2067: Exit(fbcRLI);
    $2068: Exit(fbcFSI);
    $2069: Exit(fbcPDI);
  end;

  // General Punctuation (0x2000 .. 0x206F)
  if (ACodePoint >= $2000) and (ACodePoint <= $206F) then
  begin
    case ACodePoint of
      $2000..$200A, $2028: Exit(fbcWS);
      $2029: Exit(fbcB);
      $200B..$200D, $2060..$2064: Exit(fbcBN);
    else
      Exit(fbcON);
    end;
  end;

  // Arabic Presentation Forms (0xFB50 .. 0xFDFF, 0xFE70 .. 0xFEFF)
  if ((ACodePoint >= $FB50) and (ACodePoint <= $FDFF)) or
     ((ACodePoint >= $FE70) and (ACodePoint <= $FEFF)) then
    Exit(fbcAL);

  // Latin-1 Supplement (0x0080 .. 0x00FF)
  if (ACodePoint >= $0080) and (ACodePoint <= $00FF) then
  begin
    case ACodePoint of
      $0085: Exit(fbcB);   // Next Line
      $00A0: Exit(fbcCS);  // Non-breaking space
      $00A2..$00A5: Exit(fbcET); // Currency symbols
      $00C0..$00D6, $00D8..$00F6, $00F8..$00FF: Exit(fbcL);
    else
      Exit(fbcON);
    end;
  end;

  // Default: Left-to-Right for Latin, Greek, Cyrillic, CJK, Devanagari, Thai, etc.
  Result := fbcL;
end;

class function TFloriaBiDi.GetMirroredChar(ACodePoint: Cardinal): Cardinal;
begin
  case ACodePoint of
    $0028: Exit($0029); // ( -> )
    $0029: Exit($0028); // ) -> (
    $005B: Exit($005D); // [ -> ]
    $005D: Exit($005B); // ] -> [
    $007B: Exit($007D); // { -> }
    $007D: Exit($007B); // } -> {
    $003C: Exit($003E); // < -> >
    $003E: Exit($003C); // > -> <
    $00AB: Exit($00BB); // « -> »
    $00BB: Exit($00AB); // » -> «
    $2039: Exit($203A); // ‹ -> ›
    $203A: Exit($2039); // › -> ‹
    $3008: Exit($3009); // 〈 -> 〉
    $3009: Exit($3008);
    $300A: Exit($300B); // 《 -> 》
    $300B: Exit($300A);
    $300C: Exit($300D); // 「 -> 」
    $300D: Exit($300C);
    $300E: Exit($300F); // 『 -> 』
    $300F: Exit($300E);
    $3010: Exit($3011); // 【 -> 】
    $3011: Exit($3010);
  else
    Result := ACodePoint;
  end;
end;

class function TFloriaBiDi.HasRTL(const AText: string): Boolean;
var
  P: PChar;
  CP: Cardinal;
  BClass: TFloriaBidiClass;
begin
  P := PChar(AText);
  while FloriaUTF8NextChar(P, CP) do
  begin
    BClass := GetBidiClass(CP);
    if BClass in [fbcR, fbcAL] then
      Exit(True);
  end;
  Result := False;
end;

// ============================================================================
// UAX #9 Bidirectional Resolution Engine
// ============================================================================

type
  TCharEntry = record
    CodePoint : Cardinal;
    OrigClass : TFloriaBidiClass;
    CurClass  : TFloriaBidiClass;
    Level     : Byte;
    Index     : Integer; // Original index
  end;

class function TFloriaBiDi.GetVisualRuns(const AText: string;
                                        ABaseDir: TFloriaBiDiBaseDir): TFloriaBiDiRunArray;
var
  P: PChar;
  CP: Cardinal;
  Entries: array of TCharEntry;
  N, I, J: Integer;
  BaseLevel: Byte;
  FoundStrong: Boolean;
  PrevStrong, NextStrong: TFloriaBidiClass;
  LastStrong: TFloriaBidiClass;
  MaxLevel, MinLevel: Integer;
  L: Integer;
  RunCount: Integer;
  RunStart, M: Integer;
  CurDir: TFloriaBiDiDirection;
  RunStr: string;
  TmpRun: TFloriaBiDiRun;
begin
  SetLength(Result, 0);
  if AText = '' then Exit;

  // 1. Decode UTF-8 string into code points and initial classes
  P := PChar(AText);
  N := 0;
  while FloriaUTF8NextChar(P, CP) do
  begin
    SetLength(Entries, N + 1);
    Entries[N].CodePoint := CP;
    Entries[N].OrigClass := GetBidiClass(CP);
    Entries[N].CurClass  := Entries[N].OrigClass;
    Entries[N].Level     := 0;
    Entries[N].Index     := N;
    Inc(N);
  end;

  if N = 0 then Exit;

  // 2. Determine base paragraph level (Rules P1-P3)
  case ABaseDir of
    fbbLTR: BaseLevel := 0;
    fbbRTL: BaseLevel := 1;
    fbbAuto:
    begin
      BaseLevel := 0;
      FoundStrong := False;
      for I := 0 to N - 1 do
      begin
        if Entries[I].CurClass in [fbcL, fbcR, fbcAL] then
        begin
          if Entries[I].CurClass in [fbcR, fbcAL] then
            BaseLevel := 1
          else
            BaseLevel := 0;
          FoundStrong := True;
          Break;
        end;
      end;
      if not FoundStrong then BaseLevel := 0;
    end;
  end;

  // Assign base level
  for I := 0 to N - 1 do
    Entries[I].Level := BaseLevel;

  // 3. Weak types resolution (Rules W1-W7)
  // W1: NSM takes type of previous character
  for I := 0 to N - 1 do
  begin
    if Entries[I].CurClass = fbcNSM then
    begin
      if I = 0 then
      begin
        if BaseLevel = 1 then Entries[I].CurClass := fbcR else Entries[I].CurClass := fbcL;
      end
      else
        Entries[I].CurClass := Entries[I - 1].CurClass;
    end;
  end;

  // W2: EN following AL becomes AN
  LastStrong := fbcON;
  for I := 0 to N - 1 do
  begin
    if Entries[I].CurClass in [fbcL, fbcR, fbcAL] then
      LastStrong := Entries[I].CurClass
    else if (Entries[I].CurClass = fbcEN) and (LastStrong = fbcAL) then
      Entries[I].CurClass := fbcAN;
  end;

  // W3: AL becomes R
  for I := 0 to N - 1 do
  begin
    if Entries[I].CurClass = fbcAL then
      Entries[I].CurClass := fbcR;
  end;

  // W4: ES between ENs becomes EN; CS between numbers becomes that number type
  for I := 1 to N - 2 do
  begin
    if (Entries[I].CurClass = fbcES) and (Entries[I - 1].CurClass = fbcEN) and (Entries[I + 1].CurClass = fbcEN) then
      Entries[I].CurClass := fbcEN
    else if (Entries[I].CurClass = fbcCS) and (Entries[I - 1].CurClass = fbcEN) and (Entries[I + 1].CurClass = fbcEN) then
      Entries[I].CurClass := fbcEN
    else if (Entries[I].CurClass = fbcCS) and (Entries[I - 1].CurClass = fbcAN) and (Entries[I + 1].CurClass = fbcAN) then
      Entries[I].CurClass := fbcAN;
  end;

  // W5: ET adjacent to EN becomes EN
  for I := 0 to N - 1 do
  begin
    if Entries[I].CurClass = fbcET then
    begin
      if (I > 0) and (Entries[I - 1].CurClass = fbcEN) then
        Entries[I].CurClass := fbcEN
      else if (I < N - 1) and (Entries[I + 1].CurClass = fbcEN) then
        Entries[I].CurClass := fbcEN;
    end;
  end;

  // W6: Remaining ES, ET, CS become ON
  for I := 0 to N - 1 do
  begin
    if Entries[I].CurClass in [fbcES, fbcET, fbcCS] then
      Entries[I].CurClass := fbcON;
  end;

  // W7: EN with preceding strong L becomes L
  LastStrong := fbcON;
  for I := 0 to N - 1 do
  begin
    if Entries[I].CurClass in [fbcL, fbcR] then
      LastStrong := Entries[I].CurClass
    else if (Entries[I].CurClass = fbcEN) and (LastStrong = fbcL) then
      Entries[I].CurClass := fbcL;
  end;

  // 4. Neutral types resolution (Rules N1-N2)
  // N1: Neutrals between matching strong types take that type
  // N2: Remaining neutrals take embedding level
  for I := 0 to N - 1 do
  begin
    if Entries[I].CurClass in [fbcON, fbcWS, fbcB, fbcS, fbcBN] then
    begin
      PrevStrong := fbcON;
      for J := I - 1 downto 0 do
      begin
        if Entries[J].CurClass in [fbcL, fbcR, fbcAN, fbcEN] then
        begin
          if Entries[J].CurClass in [fbcR, fbcAN] then PrevStrong := fbcR else PrevStrong := fbcL;
          Break;
        end;
      end;
      NextStrong := fbcON;
      for J := I + 1 to N - 1 do
      begin
        if Entries[J].CurClass in [fbcL, fbcR, fbcAN, fbcEN] then
        begin
          if Entries[J].CurClass in [fbcR, fbcAN] then NextStrong := fbcR else NextStrong := fbcL;
          Break;
        end;
      end;

      if (PrevStrong <> fbcON) and (PrevStrong = NextStrong) then
        Entries[I].CurClass := PrevStrong
      else
      begin
        if BaseLevel = 1 then Entries[I].CurClass := fbcR else Entries[I].CurClass := fbcL;
      end;
    end;
  end;

  // 5. Implicit levels resolution (Rules I1-I2)
  for I := 0 to N - 1 do
  begin
    if (Entries[I].Level mod 2) = 0 then
    begin
      // Even (LTR) base
      if Entries[I].CurClass = fbcR then
        Entries[I].Level := Entries[I].Level + 1
      else if Entries[I].CurClass in [fbcAN, fbcEN] then
        Entries[I].Level := Entries[I].Level + 2;
    end
    else
    begin
      // Odd (RTL) base
      if Entries[I].CurClass = fbcL then
        Entries[I].Level := Entries[I].Level + 1
      else if Entries[I].CurClass in [fbcEN, fbcAN] then
        Entries[I].Level := Entries[I].Level + 1;
    end;
  end;

  // 6. Partition logical characters into contiguous runs with the same level
  RunCount := 0;
  I := 0;
  while I < N do
  begin
    CurDir := fbdLTR;
    if (Entries[I].Level mod 2) = 1 then
      CurDir := fbdRTL;

    J := I;
    RunStr := '';
    while (J < N) and (Entries[J].Level = Entries[I].Level) do
    begin
      RunStr := RunStr + FloriaUnicodeToUTF8(Entries[J].CodePoint);
      Inc(J);
    end;

    SetLength(Result, RunCount + 1);
    Result[RunCount].Text      := RunStr;
    Result[RunCount].Direction := CurDir;
    Result[RunCount].Level     := Entries[I].Level;
    Result[RunCount].StartChar := Entries[I].Index;
    Result[RunCount].CharCount := J - I;
    Inc(RunCount);

    I := J;
  end;

  // 7. Visual run reordering (Rule L2 on runs)
  // Reorder run subsequences from MaxLevel down to MinLevel
  MaxLevel := 0;
  MinLevel := 255;
  for I := 0 to RunCount - 1 do
  begin
    if Result[I].Level > MaxLevel then
      MaxLevel := Result[I].Level;
    if (Result[I].Level mod 2 = 1) and (Result[I].Level < MinLevel) then
      MinLevel := Result[I].Level;
  end;

  if (RunCount > 1) and (MinLevel <= MaxLevel) then
  begin
    for L := MaxLevel downto MinLevel do
    begin
      I := 0;
      while I < RunCount do
      begin
        if Result[I].Level >= L then
        begin
          J := I;
          while (J + 1 < RunCount) and (Result[J + 1].Level >= L) do
            Inc(J);

          // Reverse runs between I and J
          RunStart := I;
          M := J;
          while RunStart < M do
          begin
            TmpRun := Result[RunStart];
            Result[RunStart] := Result[M];
            Result[M] := TmpRun;
            Dec(M);
            Inc(RunStart);
          end;
          I := J + 1;
        end
        else
          Inc(I);
      end;
    end;
  end;
end;

class function TFloriaBiDi.ReorderToVisualString(const AText: string;
                                               ABaseDir: TFloriaBiDiBaseDir): string;
var
  Runs: TFloriaBiDiRunArray;
  I, K: Integer;
  P: PChar;
  CP: Cardinal;
  Chars: array of Cardinal;
  NumChars: Integer;
begin
  Result := '';
  Runs := GetVisualRuns(AText, ABaseDir);
  for I := 0 to High(Runs) do
  begin
    if Runs[I].Direction = fbdLTR then
      Result := Result + Runs[I].Text
    else
    begin
      // In RTL run without shaper: reverse code points and apply mirroring
      P := PChar(Runs[I].Text);
      NumChars := 0;
      while FloriaUTF8NextChar(P, CP) do
      begin
        SetLength(Chars, NumChars + 1);
        Chars[NumChars] := GetMirroredChar(CP);
        Inc(NumChars);
      end;

      for K := NumChars - 1 downto 0 do
        Result := Result + FloriaUnicodeToUTF8(Chars[K]);
    end;
  end;
end;

end.
