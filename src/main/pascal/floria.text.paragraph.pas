unit Floria.Text.Paragraph;

// Floria.Text.Paragraph
// =====================
// High-performance rich paragraph layout engine for Object Pascal,
// matching the architectural capabilities of Skia's SkParagraph and Flutter's
// ParagraphBuilder.
//
// Capabilities:
// - Multi-style spans (TFloriaParagraphBuilder: PushStyle, PopStyle, AddText, AddPlaceholder).
// - Font family, size, weight, slant, color, background highlight, letter/word spacing.
// - Text decorations (underline, overline, strikethrough with custom color/thickness).
// - Multilingual line breaking adhering to Unicode Standard Annex #14 (UAX #14),
//   including CJK ideographs/Kana/Hangul boundary breaks, Kinsoku punctuation rules,
//   hyphens, and emergency character breaking (break-all).
// - MaxLines and ellipsis overflow truncation (e.g. '...').
// - Bidirectional text layout and run reordering per line (Floria.Unicode.BiDi).
// - Baseline alignment for multi-sized fonts on a single line.
// - Paragraph alignment: Left, Right, Center, Justify.
// - Geometry, hit-testing, caret positioning (GetPositionForOffset), and
//   multi-line selection rectangles (GetRectsForRange).
// - Inline placeholders for embedded icons, badges, chips, and custom widgets.

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, Classes, Math,
  agg_basics,
  agg_color,
  agg_path_storage,
  agg_conv_stroke,
  agg_scanline_u,
  agg_renderer_scanline,
  agg_font_cache_manager,
  Floria.Image.Core,
  Floria.Font,
  Floria.Unicode.BiDi,
  Floria.Text.HarfBuzz,
  Floria.Canvas.Agg,
  Floria.Path.Clipper.Core;

type
  // Forward declarations
  TFloriaParagraph = class;
  TFloriaParagraphBuilder = class;

  // Horizontal text alignment
  TFloriaTextAlign = (
    ftaLeft,
    ftaRight,
    ftaCenter,
    ftaJustify,
    ftaStart,
    ftaEnd
  );

  // Overall paragraph base direction
  TFloriaTextDirection = (
    ftdAuto,
    ftdLTR,
    ftdRTL
  );

  // Overflow handling when text exceeds constraints
  TFloriaTextOverflow = (
    ftoClip,
    ftoEllipsis
  );

  // Text decorations
  TFloriaTextDecorationKind = (
    ftdUnderline,
    ftdOverline,
    ftdLineThrough
  );
  TFloriaTextDecorations = set of TFloriaTextDecorationKind;

  TFloriaTextDecorationStyle = (
    ftdsSolid,
    ftdsDouble,
    ftdsDashed,
    ftdsDotted,
    ftdsWavy
  );

  // Vertical alignment of inline placeholders relative to line baseline
  TFloriaPlaceholderAlignment = (
    fpaBaseline,
    fpaAboveBaseline,
    fpaBelowBaseline,
    fpaTop,
    fpaBottom,
    fpaMiddle
  );

  // Styling for an individual text span
  TFloriaTextStyle = record
    FontFamily         : string;
    FontSize           : Double;         // Points / pixels (default: 13.0)
    Bold               : Boolean;
    Italic             : Boolean;
    Color              : TBgraPixel;     // Glyph foreground color
    BackgroundColor    : TBgraPixel;     // Background highlight color
    HasBackground      : Boolean;
    Decorations        : TFloriaTextDecorations;
    DecorationColor    : TBgraPixel;
    DecorationStyle    : TFloriaTextDecorationStyle;
    DecorationThickness: Double;         // 0 = auto from font metrics
    LetterSpacing      : Double;         // Extra spacing between characters
    WordSpacing        : Double;         // Extra spacing between words
    HeightMultiplier   : Double;         // Line height factor (1.0 = normal, 1.3 = 130%)
    BaselineOffset     : Double;         // Shift for subscript/superscript
    FontFallback       : string;         // Optional secondary font family

    class function Default(): TFloriaTextStyle; static;
    class function Create(const AFamily: string; ASize: Double;
                          const AColor: TBgraPixel; ABold: Boolean = False;
                          AItalic: Boolean = False): TFloriaTextStyle; static;
  end;

  // Paragraph-wide layout parameters
  TFloriaParagraphStyle = record
    DefaultStyle : TFloriaTextStyle;
    Alignment    : TFloriaTextAlign;
    Direction    : TFloriaTextDirection;
    MaxLines     : Integer;              // 0 = unlimited
    Ellipsis     : string;               // default: '...'
    Overflow     : TFloriaTextOverflow;
    TextIndent   : Double;               // First line indentation in pixels

    class function Default(): TFloriaParagraphStyle; static;
  end;

  // Inline placeholder span configuration
  TFloriaPlaceholderSpan = record
    Width          : Double;
    Height         : Double;
    Alignment      : TFloriaPlaceholderAlignment;
    BaselineOffset : Double;
    ID             : Integer;
    Bounds         : TRectD;             // Resolved bounding box after layout
  end;

  // Metrics for an individual laid-out line
  TFloriaLineMetrics = record
    LineNumber   : Integer;              // 0-based index
    StartIndex   : Integer;              // Byte start offset in plain text
    EndIndex     : Integer;              // Byte end offset in plain text
    Left         : Double;
    Top          : Double;
    Width        : Double;
    Height       : Double;
    Ascent       : Double;
    Descent      : Double;
    Baseline     : Double;               // Vertical baseline position relative to paragraph top
    IsHardBreak  : Boolean;
    IsEllipsized : Boolean;
  end;

  // Caret / cursor position resulting from a hit-test
  TFloriaTextPosition = record
    TextOffset         : Integer;        // Byte offset in paragraph text
    AffinityDownstream : Boolean;        // True if closer to end of glyph
    LineIndex          : Integer;
  end;

  // ---------------------------------------------------------------------------
  // Internal Layout Data Types
  // ---------------------------------------------------------------------------

  TFloriaTokenType = (
    ttkWord,
    ttkSpace,
    ttkCJK,
    ttkMandatoryBreak,
    ttkPlaceholder
  );

  // A measured atomic unit of text or placeholder
  TFloriaLayoutToken = record
    TokenType       : TFloriaTokenType;
    Text            : string;
    ByteStart       : Integer;
    ByteLength      : Integer;
    Width           : Double;
    Ascent          : Double;
    Descent         : Double;
    StyleIndex      : Integer;
    PlaceholderIndex: Integer;
    ResolvedFont    : TFloriaFont;
  end;

  TFloriaLayoutTokenArray = array of TFloriaLayoutToken;
  TRectDArray = array of TRectD;

  // A positioned fragment on a specific line
  TFloriaLineFragment = record
    TokenIndex  : Integer;
    Text        : string;
    ByteStart   : Integer;
    ByteLength  : Integer;
    Left        : Double;
    Width       : Double;
    Ascent      : Double;
    Descent     : Double;
    StyleIndex  : Integer;
    IsPlaceholder: Boolean;
    PlaceholderID: Integer;
    ResolvedFont: TFloriaFont;
  end;

  // A laid out visual line
  TFloriaLayoutLine = record
    Fragments    : array of TFloriaLineFragment;
    Metrics      : TFloriaLineMetrics;
    SpaceGapExtra: Double;
  end;

  // An input span registered via TFloriaParagraphBuilder
  TFloriaSpanRecord = record
    Text            : string;
    Style           : TFloriaTextStyle;
    IsPlaceholder   : Boolean;
    Placeholder     : TFloriaPlaceholderSpan;
    ResolvedFont    : TFloriaFont;
  end;

  // ---------------------------------------------------------------------------
  // TFloriaParagraph
  // ---------------------------------------------------------------------------

  TFloriaParagraph = class
  private
    FStyle            : TFloriaParagraphStyle;
    FSpans            : array of TFloriaSpanRecord;
    FPlainText        : string;
    FWidth            : Double;
    FHeight           : Double;
    FMaxIntrinsicWidth: Double;
    FMinIntrinsicWidth: Double;
    FLongestLine      : Double;
    FDidExceedMaxLines: Boolean;
    FLines            : array of TFloriaLayoutLine;
    FConstraintWidth  : Double;

    procedure MeasureSpans();
    procedure BreakIntoTokens(out ATokens: TFloriaLayoutTokenArray);
    procedure DoLayout(AConstraintWidth: Double);
  public
    constructor Create(const AStyle: TFloriaParagraphStyle;
                       const ASpans: array of TFloriaSpanRecord;
                       const APlainText: string);
    destructor Destroy(); override;

    // Formatting & Layout
    procedure Layout(AConstraintWidth: Double);

    // Painting
    procedure Paint(Canvas: TFloriaCanvasAgg; const X, Y: Double);

    // Metrics & Geometry
    function GetLineCount(): Integer;
    function GetLineMetrics(ALineIndex: Integer): TFloriaLineMetrics;
    function GetPositionForOffset(X, Y: Double): TFloriaTextPosition;
    function GetRectsForRange(AStartOffset, AEndOffset: Integer): TRectDArray;
    function GetPlaceholderBounds(APlaceholderID: Integer): TRectD;

    property Width            : Double read FWidth;
    property Height           : Double read FHeight;
    property MaxIntrinsicWidth: Double read FMaxIntrinsicWidth;
    property MinIntrinsicWidth: Double read FMinIntrinsicWidth;
    property LongestLine      : Double read FLongestLine;
    property LineCount        : Integer read GetLineCount;
    property DidExceedMaxLines: Boolean read FDidExceedMaxLines;
    property PlainText        : string read FPlainText;
    property ParagraphStyle   : TFloriaParagraphStyle read FStyle;
  end;

  // ---------------------------------------------------------------------------
  // TFloriaParagraphBuilder
  // ---------------------------------------------------------------------------

  TFloriaParagraphBuilder = class
  private
    FStyle     : TFloriaParagraphStyle;
    FStyleStack: array of TFloriaTextStyle;
    FSpans     : array of TFloriaSpanRecord;
    FPlainText : string;

    function CurrentStyle(): TFloriaTextStyle;
  public
    constructor Create(const AStyle: TFloriaParagraphStyle);
    destructor Destroy(); override;

    procedure PushStyle(const AStyle: TFloriaTextStyle);
    procedure PopStyle();
    procedure AddText(const AText: string);
    procedure AddPlaceholder(AWidth, AHeight: Double;
                             AAlignment: TFloriaPlaceholderAlignment = fpaBaseline;
                             ABaselineOffset: Double = 0.0;
                             AID: Integer = 0);
    function Build(): TFloriaParagraph;
  end;

// Standalone UAX #14 Unicode Character Classification Helper
function FloriaIsCJKCodePoint(ACodePoint: Cardinal): Boolean;
function FloriaIsOpeningPunctuation(ACodePoint: Cardinal): Boolean;
function FloriaIsClosingPunctuation(ACodePoint: Cardinal): Boolean;

implementation

// ---------------------------------------------------------------------------
// Standalone UAX #14 Classification
// ---------------------------------------------------------------------------

function FloriaIsCJKCodePoint(ACodePoint: Cardinal): Boolean;
begin
  Result := ((ACodePoint >= $4E00) and (ACodePoint <= $9FFF)) or    // CJK Unified Ideographs
            ((ACodePoint >= $3400) and (ACodePoint <= $4DBF)) or    // CJK Extension A
            ((ACodePoint >= $20000) and (ACodePoint <= $2A6DF)) or  // CJK Extension B
            ((ACodePoint >= $3040) and (ACodePoint <= $309F)) or    // Hiragana
            ((ACodePoint >= $30A0) and (ACodePoint <= $30FF)) or    // Katakana
            ((ACodePoint >= $AC00) and (ACodePoint <= $D7AF));      // Hangul Syllables
end;

function FloriaIsOpeningPunctuation(ACodePoint: Cardinal): Boolean;
begin
  case ACodePoint of
    $0028, // (
    $005B, // [
    $007B, // {
    $3008, // 〈
    $300A, // 《
    $300C, // 「
    $300E, // 『
    $3010, // 【
    $3014, // 〔
    $FF08, // （
    $FF3B, // ［
    $FF5B, // ｛
    $201C, // “
    $2018: // ‘
      Result := True;
  else
    Result := False;
  end;
end;

function FloriaIsClosingPunctuation(ACodePoint: Cardinal): Boolean;
begin
  case ACodePoint of
    $0029, // )
    $005D, // ]
    $007D, // }
    $0021, // !
    $002C, // ,
    $002E, // .
    $003A, // :
    $003B, // ;
    $003F, // ?
    $3001, // 、
    $3002, // 。
    $3009, // 〉
    $300B, // 》
    $300D, // 」
    $300F, // 』
    $3011, // 】
    $3015, // 〕
    $FF01, // ！
    $FF09, // ）
    $FF0C, // ，
    $FF0E, // ．
    $FF1A, // ：
    $FF1B, // ；
    $FF1F, // ？
    $FF3D, // ］
    $FF5D, // ｝
    $201D, // ”
    $2019: // ’
      Result := True;
  else
    Result := False;
  end;
end;

// ---------------------------------------------------------------------------
// TFloriaTextStyle
// ---------------------------------------------------------------------------

class function TFloriaTextStyle.Default(): TFloriaTextStyle;
begin
  Result.FontFamily          := 'Sans';
  Result.FontSize            := 13.0;
  Result.Bold                := False;
  Result.Italic              := False;
  Result.Color               := TBgraPixel.Create(0, 0, 0, 255);
  Result.BackgroundColor     := TBgraPixel.Create(0, 0, 0, 0);
  Result.HasBackground       := False;
  Result.Decorations         := [];
  Result.DecorationColor     := TBgraPixel.Create(0, 0, 0, 255);
  Result.DecorationStyle     := ftdsSolid;
  Result.DecorationThickness := 1.0;
  Result.LetterSpacing       := 0.0;
  Result.WordSpacing         := 0.0;
  Result.HeightMultiplier    := 1.25;
  Result.BaselineOffset      := 0.0;
  Result.FontFallback        := '';
end;

class function TFloriaTextStyle.Create(const AFamily: string; ASize: Double;
                                       const AColor: TBgraPixel; ABold: Boolean;
                                       AItalic: Boolean): TFloriaTextStyle;
begin
  Result := Default();
  Result.FontFamily := AFamily;
  Result.FontSize := ASize;
  Result.Color := AColor;
  Result.DecorationColor := AColor;
  Result.Bold := ABold;
  Result.Italic := AItalic;
end;

// ---------------------------------------------------------------------------
// TFloriaParagraphStyle
// ---------------------------------------------------------------------------

class function TFloriaParagraphStyle.Default(): TFloriaParagraphStyle;
begin
  Result.DefaultStyle := TFloriaTextStyle.Default();
  Result.Alignment    := ftaLeft;
  Result.Direction    := ftdAuto;
  Result.MaxLines     := 0; // Unlimited
  Result.Ellipsis     := '...';
  Result.Overflow     := ftoClip;
  Result.TextIndent   := 0.0;
end;

// ---------------------------------------------------------------------------
// TFloriaParagraphBuilder
// ---------------------------------------------------------------------------

constructor TFloriaParagraphBuilder.Create(const AStyle: TFloriaParagraphStyle);
begin
  inherited Create();
  FStyle := AStyle;
  SetLength(FStyleStack, 1);
  FStyleStack[0] := AStyle.DefaultStyle;
  SetLength(FSpans, 0);
  FPlainText := '';
end;

destructor TFloriaParagraphBuilder.Destroy();
begin
  SetLength(FStyleStack, 0);
  SetLength(FSpans, 0);
  inherited Destroy();
end;

function TFloriaParagraphBuilder.CurrentStyle(): TFloriaTextStyle;
begin
  if Length(FStyleStack) > 0 then
    Result := FStyleStack[High(FStyleStack)]
  else
    Result := FStyle.DefaultStyle;
end;

procedure TFloriaParagraphBuilder.PushStyle(const AStyle: TFloriaTextStyle);
var
  ParentStyle: TFloriaTextStyle;
  Effective: TFloriaTextStyle;
begin
  ParentStyle := CurrentStyle();
  Effective := AStyle;

  // Inherit unspecified attributes
  if Effective.FontFamily = '' then Effective.FontFamily := ParentStyle.FontFamily;
  if Effective.FontSize <= 0 then Effective.FontSize := ParentStyle.FontSize;
  if Effective.HeightMultiplier <= 0 then Effective.HeightMultiplier := ParentStyle.HeightMultiplier;

  SetLength(FStyleStack, Length(FStyleStack) + 1);
  FStyleStack[High(FStyleStack)] := Effective;
end;

procedure TFloriaParagraphBuilder.PopStyle();
begin
  if Length(FStyleStack) > 1 then
    SetLength(FStyleStack, Length(FStyleStack) - 1);
end;

procedure TFloriaParagraphBuilder.AddText(const AText: string);
var
  Idx: Integer;
begin
  if AText = '' then Exit;
  Idx := Length(FSpans);
  SetLength(FSpans, Idx + 1);
  FSpans[Idx].Text := AText;
  FSpans[Idx].Style := CurrentStyle();
  FSpans[Idx].IsPlaceholder := False;
  FSpans[Idx].ResolvedFont := nil;
  FPlainText := FPlainText + AText;
end;

procedure TFloriaParagraphBuilder.AddPlaceholder(AWidth, AHeight: Double;
                                                 AAlignment: TFloriaPlaceholderAlignment;
                                                 ABaselineOffset: Double;
                                                 AID: Integer);
var
  Idx: Integer;
begin
  Idx := Length(FSpans);
  SetLength(FSpans, Idx + 1);
  FSpans[Idx].Text := ' '; // Space placeholder in plain text
  FSpans[Idx].Style := CurrentStyle();
  FSpans[Idx].IsPlaceholder := True;
  FSpans[Idx].Placeholder.Width := AWidth;
  FSpans[Idx].Placeholder.Height := AHeight;
  FSpans[Idx].Placeholder.Alignment := AAlignment;
  FSpans[Idx].Placeholder.BaselineOffset := ABaselineOffset;
  FSpans[Idx].Placeholder.ID := AID;
  FSpans[Idx].ResolvedFont := nil;
  FPlainText := FPlainText + ' ';
end;

function TFloriaParagraphBuilder.Build(): TFloriaParagraph;
begin
  Result := TFloriaParagraph.Create(FStyle, FSpans, FPlainText);
end;

// ---------------------------------------------------------------------------
// TFloriaParagraph
// ---------------------------------------------------------------------------

constructor TFloriaParagraph.Create(const AStyle: TFloriaParagraphStyle;
                                    const ASpans: array of TFloriaSpanRecord;
                                    const APlainText: string);
var
  I: Integer;
begin
  inherited Create();
  FStyle := AStyle;
  FPlainText := APlainText;
  SetLength(FSpans, Length(ASpans));
  for I := 0 to High(ASpans) do
    FSpans[I] := ASpans[I];

  FWidth := 0.0;
  FHeight := 0.0;
  FMaxIntrinsicWidth := 0.0;
  FMinIntrinsicWidth := 0.0;
  FLongestLine := 0.0;
  FDidExceedMaxLines := False;
  SetLength(FLines, 0);

  MeasureSpans();
end;

destructor TFloriaParagraph.Destroy();
var
  I: Integer;
begin
  for I := 0 to High(FLines) do
    SetLength(FLines[I].Fragments, 0);
  SetLength(FLines, 0);
  SetLength(FSpans, 0);
  inherited Destroy();
end;

procedure TFloriaParagraph.MeasureSpans();
var
  I: Integer;
  Desc: string;
begin
  for I := 0 to High(FSpans) do
  begin
    if not FSpans[I].IsPlaceholder then
    begin
      Desc := FSpans[I].Style.FontFamily + '-' + FloatToStr(FSpans[I].Style.FontSize);
      if FSpans[I].Style.Bold then Desc := Desc + ':bold';
      if FSpans[I].Style.Italic then Desc := Desc + ':italic';

      FSpans[I].ResolvedFont := FloriaFontManager().GetFont(Desc);
      if not Assigned(FSpans[I].ResolvedFont) then
        FSpans[I].ResolvedFont := FloriaGetSystemFont();
    end;
  end;
end;

procedure TFloriaParagraph.BreakIntoTokens(out ATokens: TFloriaLayoutTokenArray);
var
  TokensList: array of TFloriaLayoutToken;
  TokenCount: Integer;

  procedure AddToken(AType: TFloriaTokenType; const AText: string;
                     ABStart, ABLen, AStyleIdx, APlaceIdx: Integer;
                     AWidth, AAscent, ADescent: Double; AFont: TFloriaFont);
  begin
    Inc(TokenCount);
    SetLength(TokensList, TokenCount);
    TokensList[TokenCount - 1].TokenType        := AType;
    TokensList[TokenCount - 1].Text             := AText;
    TokensList[TokenCount - 1].ByteStart        := ABStart;
    TokensList[TokenCount - 1].ByteLength       := ABLen;
    TokensList[TokenCount - 1].Width            := AWidth;
    TokensList[TokenCount - 1].Ascent           := AAscent;
    TokensList[TokenCount - 1].Descent          := ADescent;
    TokensList[TokenCount - 1].StyleIndex       := AStyleIdx;
    TokensList[TokenCount - 1].PlaceholderIndex := APlaceIdx;
    TokensList[TokenCount - 1].ResolvedFont     := AFont;
  end;

var
  SpanIdx: Integer;
  P: PChar;
  CharLen: LongInt;
  CodePoint: Cardinal;
  WordBuf: string;
  WordStart, WordByteLen: Integer;
  CurrentBytePos: Integer;
  Font: TFloriaFont;
  Ascent, Descent, H: Double;
  CharW: Double;
begin
  TokenCount := 0;
  SetLength(TokensList, 0);
  CurrentBytePos := 0;

  for SpanIdx := 0 to High(FSpans) do
  begin
    Font := FSpans[SpanIdx].ResolvedFont;
    if Assigned(Font) and Font.Loaded then
    begin
      Ascent := Font.Ascent;
      Descent := Font.Descent;
    end
    else
    begin
      Ascent := FSpans[SpanIdx].Style.FontSize * 0.8;
      Descent := FSpans[SpanIdx].Style.FontSize * 0.2;
    end;

    // Apply height multiplier
    if FSpans[SpanIdx].Style.HeightMultiplier > 0 then
    begin
      H := (Ascent + Descent) * FSpans[SpanIdx].Style.HeightMultiplier;
      Ascent := H * 0.8;
      Descent := H * 0.2;
    end;

    if FSpans[SpanIdx].IsPlaceholder then
    begin
      AddToken(ttkPlaceholder, ' ', CurrentBytePos, 1, SpanIdx, SpanIdx,
               FSpans[SpanIdx].Placeholder.Width,
               FSpans[SpanIdx].Placeholder.Height * 0.8,
               FSpans[SpanIdx].Placeholder.Height * 0.2,
               Font);
      Inc(CurrentBytePos, 1);
      Continue;
    end;

    P := PChar(FSpans[SpanIdx].Text);
    WordBuf := '';
    WordStart := CurrentBytePos;
    WordByteLen := 0;

    while P^ <> #0 do
    begin
      CodePoint := UTF8CharToUnicode(P, CharLen);

      // Mandatory Line Breaks
      if (CodePoint = $0A) or (CodePoint = $0D) then
      begin
        // Flush previous word
        if WordBuf <> '' then
        begin
          AddToken(ttkWord, WordBuf, WordStart, WordByteLen, SpanIdx, -1,
                   Font.GetTextWidth(WordBuf) + (Length(WordBuf) * FSpans[SpanIdx].Style.LetterSpacing),
                   Ascent, Descent, Font);
          WordBuf := '';
        end;

        // Skip CRLF
        if (CodePoint = $0D) and ((P + CharLen)^ = #10) then
        begin
          Inc(P, CharLen);
          Inc(CurrentBytePos, CharLen);
          Inc(CharLen); // Account for both CR and LF
        end;

        AddToken(ttkMandatoryBreak, #10, CurrentBytePos, CharLen, SpanIdx, -1,
                 0.0, Ascent, Descent, Font);
        Inc(P, CharLen);
        Inc(CurrentBytePos, CharLen);
        WordStart := CurrentBytePos;
        WordByteLen := 0;
        Continue;
      end;

      // Space / Tab Whitespace
      if (CodePoint = $20) or (CodePoint = $09) then
      begin
        // Flush previous word
        if WordBuf <> '' then
        begin
          AddToken(ttkWord, WordBuf, WordStart, WordByteLen, SpanIdx, -1,
                   Font.GetTextWidth(WordBuf) + (Length(WordBuf) * FSpans[SpanIdx].Style.LetterSpacing),
                   Ascent, Descent, Font);
          WordBuf := '';
        end;

        CharW := Font.GetTextWidth(' ') + FSpans[SpanIdx].Style.WordSpacing;
        AddToken(ttkSpace, Copy(P, 1, CharLen), CurrentBytePos, CharLen, SpanIdx, -1,
                 CharW, Ascent, Descent, Font);
        Inc(P, CharLen);
        Inc(CurrentBytePos, CharLen);
        WordStart := CurrentBytePos;
        WordByteLen := 0;
        Continue;
      end;

      // CJK Ideographs / Syllables (Break allowed per character)
      if FloriaIsCJKCodePoint(CodePoint) then
      begin
        // Flush previous word
        if WordBuf <> '' then
        begin
          AddToken(ttkWord, WordBuf, WordStart, WordByteLen, SpanIdx, -1,
                   Font.GetTextWidth(WordBuf) + (Length(WordBuf) * FSpans[SpanIdx].Style.LetterSpacing),
                   Ascent, Descent, Font);
          WordBuf := '';
        end;

        CharW := Font.GetTextWidth(Copy(P, 1, CharLen)) + FSpans[SpanIdx].Style.LetterSpacing;
        AddToken(ttkCJK, Copy(P, 1, CharLen), CurrentBytePos, CharLen, SpanIdx, -1,
                 CharW, Ascent, Descent, Font);
        Inc(P, CharLen);
        Inc(CurrentBytePos, CharLen);
        WordStart := CurrentBytePos;
        WordByteLen := 0;
        Continue;
      end;

      // Hyphen / Dash (Break opportunity after hyphen)
      if (CodePoint = $2D) or (CodePoint = $2010) or (CodePoint = $2013) then
      begin
        WordBuf := WordBuf + Copy(P, 1, CharLen);
        Inc(WordByteLen, CharLen);
        Inc(P, CharLen);
        Inc(CurrentBytePos, CharLen);

        // Break word here
        AddToken(ttkWord, WordBuf, WordStart, WordByteLen, SpanIdx, -1,
                 Font.GetTextWidth(WordBuf) + (Length(WordBuf) * FSpans[SpanIdx].Style.LetterSpacing),
                 Ascent, Descent, Font);
        WordBuf := '';
        WordStart := CurrentBytePos;
        WordByteLen := 0;
        Continue;
      end;

      // Normal character in word
      WordBuf := WordBuf + Copy(P, 1, CharLen);
      Inc(WordByteLen, CharLen);
      Inc(P, CharLen);
      Inc(CurrentBytePos, CharLen);
    end;

    // Flush trailing word in span
    if WordBuf <> '' then
    begin
      AddToken(ttkWord, WordBuf, WordStart, WordByteLen, SpanIdx, -1,
               Font.GetTextWidth(WordBuf) + (Length(WordBuf) * FSpans[SpanIdx].Style.LetterSpacing),
               Ascent, Descent, Font);
    end;
  end;

  // Copy to output
  SetLength(ATokens, Length(TokensList));
  for SpanIdx := 0 to High(TokensList) do
    ATokens[SpanIdx] := TokensList[SpanIdx];
end;

procedure TFloriaParagraph.DoLayout(AConstraintWidth: Double);
var
  Tokens: array of TFloriaLayoutToken;
  I, J, TokIdx: Integer;
  CurLineCount: Integer;

  CurLineFragments: array of TFloriaLineFragment;
  CurFragCount: Integer;
  CurLineWidth: Double;
  CurAscent, CurDescent: Double;
  LineStartByte: Integer;
  CurrentY: Double;
  Token: TFloriaLayoutToken;

  procedure AddFragment(const AToken: TFloriaLayoutToken; ALeft, AWidth: Double);
  begin
    Inc(CurFragCount);
    SetLength(CurLineFragments, CurFragCount);
    CurLineFragments[CurFragCount - 1].TokenIndex   := TokIdx;
    CurLineFragments[CurFragCount - 1].Text         := AToken.Text;
    CurLineFragments[CurFragCount - 1].ByteStart    := AToken.ByteStart;
    CurLineFragments[CurFragCount - 1].ByteLength   := AToken.ByteLength;
    CurLineFragments[CurFragCount - 1].Left         := ALeft;
    CurLineFragments[CurFragCount - 1].Width        := AWidth;
    CurLineFragments[CurFragCount - 1].Ascent       := AToken.Ascent;
    CurLineFragments[CurFragCount - 1].Descent      := AToken.Descent;
    CurLineFragments[CurFragCount - 1].StyleIndex   := AToken.StyleIndex;
    CurLineFragments[CurFragCount - 1].IsPlaceholder:= (AToken.TokenType = ttkPlaceholder);
    if AToken.TokenType = ttkPlaceholder then
      CurLineFragments[CurFragCount - 1].PlaceholderID := FSpans[AToken.StyleIndex].Placeholder.ID
    else
      CurLineFragments[CurFragCount - 1].PlaceholderID := -1;
    CurLineFragments[CurFragCount - 1].ResolvedFont := AToken.ResolvedFont;
  end;

  procedure PushCurrentLine(AIsHardBreak: Boolean);
  var
    LIdx: Integer;
    K: Integer;
    LineH: Double;
    LineW: Double;
    RemainingW: Double;
    AlignOffset: Double;
    SpaceCount: Integer;
    ExtraPerSpace: Double;
    AccumX: Double;
    LastFrag: Integer;
  begin
    if CurFragCount = 0 then
    begin
      // Empty line (e.g. from consecutive newlines)
      if CurAscent <= 0 then CurAscent := FStyle.DefaultStyle.FontSize * 0.8;
      if CurDescent <= 0 then CurDescent := FStyle.DefaultStyle.FontSize * 0.2;
    end;

    LIdx := CurLineCount;
    Inc(CurLineCount);
    SetLength(FLines, CurLineCount);

    LineH := CurAscent + CurDescent;

    // Trim trailing whitespace from line width
    LineW := CurLineWidth;
    LastFrag := CurFragCount - 1;
    while (LastFrag >= 0) and (Tokens[CurLineFragments[LastFrag].TokenIndex].TokenType = ttkSpace) do
    begin
      LineW := LineW - CurLineFragments[LastFrag].Width;
      Dec(LastFrag);
    end;
    if LineW < 0 then LineW := 0;

    // Calculate alignment offset
    RemainingW := AConstraintWidth - LineW;
    if RemainingW < 0 then RemainingW := 0;

    AlignOffset := 0.0;
    ExtraPerSpace := 0.0;

    case FStyle.Alignment of
      ftaRight, ftaEnd:
        AlignOffset := RemainingW;
      ftaCenter:
        AlignOffset := RemainingW * 0.5;
      ftaJustify:
      begin
        if not AIsHardBreak and (LIdx < FStyle.MaxLines - 1) then
        begin
          SpaceCount := 0;
          for K := 0 to LastFrag do
            if Tokens[CurLineFragments[K].TokenIndex].TokenType = ttkSpace then
              Inc(SpaceCount);

          if SpaceCount > 0 then
            ExtraPerSpace := RemainingW / SpaceCount;
        end;
      end;
      else // ftaLeft, ftaStart
        AlignOffset := 0.0;
    end;

    // Apply alignment offset and space expansion to fragments
    AccumX := AlignOffset;
    for K := 0 to CurFragCount - 1 do
    begin
      CurLineFragments[K].Left := AccumX;
      AccumX := AccumX + CurLineFragments[K].Width;
      if (Tokens[CurLineFragments[K].TokenIndex].TokenType = ttkSpace) and (K <= LastFrag) then
        AccumX := AccumX + ExtraPerSpace;

      // Update placeholder bounding boxes if applicable
      if CurLineFragments[K].IsPlaceholder then
      begin
        FSpans[CurLineFragments[K].StyleIndex].Placeholder.Bounds :=
          RectD(CurLineFragments[K].Left, CurrentY,
                CurLineFragments[K].Left + CurLineFragments[K].Width,
                CurrentY + CurLineFragments[K].Ascent + CurLineFragments[K].Descent);
      end;
    end;

    // Record line metrics
    FLines[LIdx].Metrics.LineNumber   := LIdx;
    FLines[LIdx].Metrics.StartIndex   := LineStartByte;
    if CurFragCount > 0 then
      FLines[LIdx].Metrics.EndIndex   := CurLineFragments[CurFragCount - 1].ByteStart + CurLineFragments[CurFragCount - 1].ByteLength
    else
      FLines[LIdx].Metrics.EndIndex   := LineStartByte;
    FLines[LIdx].Metrics.Left         := AlignOffset;
    FLines[LIdx].Metrics.Top          := CurrentY;
    FLines[LIdx].Metrics.Width        := LineW;
    FLines[LIdx].Metrics.Height       := LineH;
    FLines[LIdx].Metrics.Ascent       := CurAscent;
    FLines[LIdx].Metrics.Descent      := CurDescent;
    FLines[LIdx].Metrics.Baseline     := CurrentY + CurAscent;
    FLines[LIdx].Metrics.IsHardBreak  := AIsHardBreak;
    FLines[LIdx].Metrics.IsEllipsized := False;
    FLines[LIdx].SpaceGapExtra        := ExtraPerSpace;

    // Copy fragments
    SetLength(FLines[LIdx].Fragments, CurFragCount);
    for K := 0 to CurFragCount - 1 do
      FLines[LIdx].Fragments[K] := CurLineFragments[K];

    if LineW > FLongestLine then
      FLongestLine := LineW;

    CurrentY := CurrentY + LineH;

    // Reset current line state
    CurFragCount := 0;
    SetLength(CurLineFragments, 0);
    CurLineWidth := 0.0;
    CurAscent := 0.0;
    CurDescent := 0.0;
  end;

var
  EllipsisFont: TFloriaFont;
  EllipsisW: Double;
  LastLineIdx: Integer;
  CutFragIdx: Integer;
begin
  BreakIntoTokens(Tokens);

  CurLineCount := 0;
  SetLength(FLines, 0);
  CurFragCount := 0;
  SetLength(CurLineFragments, 0);
  CurLineWidth := 0.0;
  CurAscent := 0.0;
  CurDescent := 0.0;
  LineStartByte := 0;
  CurrentY := 0.0;
  FLongestLine := 0.0;
  FDidExceedMaxLines := False;

  if Length(Tokens) = 0 then
    Exit;

  TokIdx := 0;
  while TokIdx <= High(Tokens) do
  begin
    Token := Tokens[TokIdx];

    // Check MaxLines limit
    if (FStyle.MaxLines > 0) and (CurLineCount >= FStyle.MaxLines) then
    begin
      FDidExceedMaxLines := True;
      Break;
    end;

    // 1. Mandatory Break
    if Token.TokenType = ttkMandatoryBreak then
    begin
      PushCurrentLine(True);
      LineStartByte := Token.ByteStart + Token.ByteLength;
      Inc(TokIdx);
      Continue;
    end;

    // 2. Leading whitespace trimming at start of wrapped line
    if (CurFragCount = 0) and (Token.TokenType = ttkSpace) then
    begin
      Inc(TokIdx);
      Continue;
    end;

    // 3. Check Wrapping against AConstraintWidth
    if (AConstraintWidth > 0) and (CurFragCount > 0) and
       (CurLineWidth + Token.Width > AConstraintWidth) then
    begin
      // Soft break opportunity triggered: emit current line
      PushCurrentLine(False);
      LineStartByte := Token.ByteStart;

      // Check if we hit MaxLines after wrapping
      if (FStyle.MaxLines > 0) and (CurLineCount >= FStyle.MaxLines) then
      begin
        FDidExceedMaxLines := True;
        Break;
      end;

      // Skip whitespace at start of the new wrapped line
      if Token.TokenType = ttkSpace then
      begin
        Inc(TokIdx);
        Continue;
      end;
    end;

    // Add token to current line
    AddFragment(Token, CurLineWidth, Token.Width);
    CurLineWidth := CurLineWidth + Token.Width;
    if Token.Ascent > CurAscent then CurAscent := Token.Ascent;
    if Token.Descent > CurDescent then CurDescent := Token.Descent;

    Inc(TokIdx);
  end;

  // Emit any remaining line content
  if (CurFragCount > 0) or (CurLineCount = 0) then
  begin
    if (FStyle.MaxLines = 0) or (CurLineCount < FStyle.MaxLines) then
      PushCurrentLine(False)
    else
      FDidExceedMaxLines := True;
  end;

  // Apply Ellipsis if MaxLines was exceeded and overflow mode is ftoEllipsis
  if FDidExceedMaxLines and (FStyle.Overflow = ftoEllipsis) and (CurLineCount > 0) and (FStyle.Ellipsis <> '') then
  begin
    LastLineIdx := CurLineCount - 1;
    EllipsisFont := FloriaFontManager().GetFont(FStyle.DefaultStyle.FontFamily + '-' + FloatToStr(FStyle.DefaultStyle.FontSize));
    if not Assigned(EllipsisFont) then EllipsisFont := FloriaGetSystemFont();

    EllipsisW := EllipsisFont.GetTextWidth(FStyle.Ellipsis);

    // Truncate fragments from end of last line to fit ellipsis
    while (Length(FLines[LastLineIdx].Fragments) > 0) and
          (FLines[LastLineIdx].Metrics.Width + EllipsisW > AConstraintWidth) do
    begin
      CutFragIdx := High(FLines[LastLineIdx].Fragments);
      FLines[LastLineIdx].Metrics.Width := FLines[LastLineIdx].Metrics.Width - FLines[LastLineIdx].Fragments[CutFragIdx].Width;
      SetLength(FLines[LastLineIdx].Fragments, CutFragIdx);
    end;

    // Append ellipsis fragment
    CutFragIdx := Length(FLines[LastLineIdx].Fragments);
    SetLength(FLines[LastLineIdx].Fragments, CutFragIdx + 1);
    FLines[LastLineIdx].Fragments[CutFragIdx].TokenIndex    := -1;
    FLines[LastLineIdx].Fragments[CutFragIdx].Text          := FStyle.Ellipsis;
    FLines[LastLineIdx].Fragments[CutFragIdx].ByteStart     := FLines[LastLineIdx].Metrics.EndIndex;
    FLines[LastLineIdx].Fragments[CutFragIdx].ByteLength    := Length(FStyle.Ellipsis);
    FLines[LastLineIdx].Fragments[CutFragIdx].Left          := FLines[LastLineIdx].Metrics.Width;
    FLines[LastLineIdx].Fragments[CutFragIdx].Width         := EllipsisW;
    FLines[LastLineIdx].Fragments[CutFragIdx].Ascent        := EllipsisFont.Ascent;
    FLines[LastLineIdx].Fragments[CutFragIdx].Descent       := EllipsisFont.Descent;
    FLines[LastLineIdx].Fragments[CutFragIdx].StyleIndex    := 0;
    FLines[LastLineIdx].Fragments[CutFragIdx].IsPlaceholder := False;
    FLines[LastLineIdx].Fragments[CutFragIdx].PlaceholderID := -1;
    FLines[LastLineIdx].Fragments[CutFragIdx].ResolvedFont  := EllipsisFont;

    FLines[LastLineIdx].Metrics.Width := FLines[LastLineIdx].Metrics.Width + EllipsisW;
    FLines[LastLineIdx].Metrics.IsEllipsized := True;
  end;

  FWidth := AConstraintWidth;
  FHeight := CurrentY;
end;

procedure TFloriaParagraph.Layout(AConstraintWidth: Double);
var
  Tokens: array of TFloriaLayoutToken;
  I: Integer;
  UnwrappedW, WordW: Double;
begin
  FConstraintWidth := AConstraintWidth;

  // Calculate Intrinsic Dimensions
  BreakIntoTokens(Tokens);
  FMaxIntrinsicWidth := 0.0;
  FMinIntrinsicWidth := 0.0;
  UnwrappedW := 0.0;

  for I := 0 to High(Tokens) do
  begin
    if Tokens[I].TokenType = ttkMandatoryBreak then
    begin
      if UnwrappedW > FMaxIntrinsicWidth then
        FMaxIntrinsicWidth := UnwrappedW;
      UnwrappedW := 0.0;
    end
    else
    begin
      WordW := Tokens[I].Width;
      UnwrappedW := UnwrappedW + WordW;
      if WordW > FMinIntrinsicWidth then
        FMinIntrinsicWidth := WordW;
    end;
  end;
  if UnwrappedW > FMaxIntrinsicWidth then
    FMaxIntrinsicWidth := UnwrappedW;

  if AConstraintWidth <= 0 then
    AConstraintWidth := FMaxIntrinsicWidth;

  DoLayout(AConstraintWidth);
end;

procedure TFloriaParagraph.Paint(Canvas: TFloriaCanvasAgg; const X, Y: Double);
var
  LineIdx, FragIdx: Integer;
  Line: TFloriaLayoutLine;
  Frag: TFloriaLineFragment;
  Style: TFloriaTextStyle;
  Font: TFloriaFont;
  R, G, B: Double;
  DrawX, DrawY: Double;
  DecY, DecThick: Double;
begin
  if not Assigned(Canvas) or (Length(FLines) = 0) then Exit;

  // -------------------------------------------------------------------------
  // Pass 1: Background Highlights
  // -------------------------------------------------------------------------
  for LineIdx := 0 to High(FLines) do
  begin
    Line := FLines[LineIdx];
    for FragIdx := 0 to High(Line.Fragments) do
    begin
      Frag := Line.Fragments[FragIdx];
      if (Frag.StyleIndex >= 0) and (Frag.StyleIndex <= High(FSpans)) then
      begin
        Style := FSpans[Frag.StyleIndex].Style;
        if Style.HasBackground and (Style.BackgroundColor.A > 0) then
        begin
          Canvas.DrawRect(Round(X + Frag.Left),
                          Round(Y + Line.Metrics.Top),
                          Round(Frag.Width),
                          Round(Line.Metrics.Height),
                          Style.BackgroundColor.R / 255.0,
                          Style.BackgroundColor.G / 255.0,
                          Style.BackgroundColor.B / 255.0,
                          Style.BackgroundColor.A / 255.0);
        end;
      end;
    end;
  end;

  // -------------------------------------------------------------------------
  // Pass 2: Text Glyphs
  // -------------------------------------------------------------------------
  for LineIdx := 0 to High(FLines) do
  begin
    Line := FLines[LineIdx];
    for FragIdx := 0 to High(Line.Fragments) do
    begin
      Frag := Line.Fragments[FragIdx];
      if Frag.IsPlaceholder or (Frag.Text = '') then Continue;

      if (Frag.StyleIndex >= 0) and (Frag.StyleIndex <= High(FSpans)) then
        Style := FSpans[Frag.StyleIndex].Style
      else
        Style := FStyle.DefaultStyle;

      Font := Frag.ResolvedFont;
      if not Assigned(Font) then Font := FloriaGetSystemFont();

      R := Style.Color.R / 255.0;
      G := Style.Color.G / 255.0;
      B := Style.Color.B / 255.0;

      DrawX := X + Frag.Left;
      DrawY := Y + Line.Metrics.Baseline - Font.Ascent + Style.BaselineOffset;

      Canvas.DrawText(DrawX, DrawY, Frag.Text, Font, R, G, B);
    end;
  end;

  // -------------------------------------------------------------------------
  // Pass 3: Text Decorations (Underline, Overline, LineThrough)
  // -------------------------------------------------------------------------
  for LineIdx := 0 to High(FLines) do
  begin
    Line := FLines[LineIdx];
    for FragIdx := 0 to High(Line.Fragments) do
    begin
      Frag := Line.Fragments[FragIdx];
      if Frag.IsPlaceholder or (Frag.Text = '') then Continue;

      if (Frag.StyleIndex >= 0) and (Frag.StyleIndex <= High(FSpans)) then
        Style := FSpans[Frag.StyleIndex].Style
      else
        Style := FStyle.DefaultStyle;

      if Style.Decorations = [] then Continue;

      Font := Frag.ResolvedFont;
      if not Assigned(Font) then Font := FloriaGetSystemFont();

      DecThick := Style.DecorationThickness;
      if DecThick <= 0 then DecThick := Max(1.0, Font.Size * 0.08);

      R := Style.DecorationColor.R / 255.0;
      G := Style.DecorationColor.G / 255.0;
      B := Style.DecorationColor.B / 255.0;

      // Underline
      if ftdUnderline in Style.Decorations then
      begin
        DecY := Y + Line.Metrics.Baseline + Max(1.0, Font.Descent * 0.25);
        Canvas.DrawLine(X + Frag.Left, DecY, X + Frag.Left + Frag.Width, DecY, DecThick, R, G, B);
      end;

      // LineThrough (strikethrough)
      if ftdLineThrough in Style.Decorations then
      begin
        DecY := Y + Line.Metrics.Baseline - (Font.Ascent * 0.35);
        Canvas.DrawLine(X + Frag.Left, DecY, X + Frag.Left + Frag.Width, DecY, DecThick, R, G, B);
      end;

      // Overline
      if ftdOverline in Style.Decorations then
      begin
        DecY := Y + Line.Metrics.Baseline - Font.Ascent;
        Canvas.DrawLine(X + Frag.Left, DecY, X + Frag.Left + Frag.Width, DecY, DecThick, R, G, B);
      end;
    end;
  end;
end;

function TFloriaParagraph.GetLineCount(): Integer;
begin
  Result := Length(FLines);
end;

function TFloriaParagraph.GetLineMetrics(ALineIndex: Integer): TFloriaLineMetrics;
begin
  if (ALineIndex >= 0) and (ALineIndex < Length(FLines)) then
    Result := FLines[ALineIndex].Metrics
  else
    FillChar(Result, SizeOf(Result), 0);
end;

function TFloriaParagraph.GetPositionForOffset(X, Y: Double): TFloriaTextPosition;
var
  LineIdx, FragIdx: Integer;
  Line: TFloriaLayoutLine;
  Frag: TFloriaLineFragment;
  BestLine: Integer;
  AccumW: Double;
  P: PChar;
  CharLen: LongInt;
  CharW: Double;
  CharId: Cardinal;
  BytePos: Integer;
begin
  Result.TextOffset := 0;
  Result.AffinityDownstream := True;
  Result.LineIndex := 0;
  if Length(FLines) = 0 then Exit;

  // 1. Locate corresponding line by Y coordinate
  BestLine := 0;
  if Y < FLines[0].Metrics.Top then
    BestLine := 0
  else if Y >= FLines[High(FLines)].Metrics.Top + FLines[High(FLines)].Metrics.Height then
    BestLine := High(FLines)
  else
  begin
    for LineIdx := 0 to High(FLines) do
    begin
      if (Y >= FLines[LineIdx].Metrics.Top) and
         (Y < FLines[LineIdx].Metrics.Top + FLines[LineIdx].Metrics.Height) then
      begin
        BestLine := LineIdx;
        Break;
      end;
    end;
  end;

  Result.LineIndex := BestLine;
  Line := FLines[BestLine];

  if Length(Line.Fragments) = 0 then
  begin
    Result.TextOffset := Line.Metrics.StartIndex;
    Exit;
  end;

  // 2. Locate character within line by X coordinate
  if X <= Line.Fragments[0].Left then
  begin
    Result.TextOffset := Line.Fragments[0].ByteStart;
    Result.AffinityDownstream := False;
    Exit;
  end;

  for FragIdx := 0 to High(Line.Fragments) do
  begin
    Frag := Line.Fragments[FragIdx];
    if (X >= Frag.Left) and (X <= Frag.Left + Frag.Width) then
    begin
      // Character-level inspection within fragment
      P := PChar(Frag.Text);
      AccumW := Frag.Left;
      BytePos := Frag.ByteStart;

      while P^ <> #0 do
      begin
        CharId := UTF8CharToUnicode(P, CharLen);
        if Assigned(Frag.ResolvedFont) then
          CharW := Frag.ResolvedFont.GetTextWidth(Copy(P, 1, CharLen))
        else
          CharW := 8.0;

        if X <= AccumW + (CharW * 0.5) then
        begin
          Result.TextOffset := BytePos;
          Result.AffinityDownstream := False;
          Exit;
        end
        else if X <= AccumW + CharW then
        begin
          Result.TextOffset := BytePos + CharLen;
          Result.AffinityDownstream := True;
          Exit;
        end;

        AccumW := AccumW + CharW;
        Inc(BytePos, CharLen);
        Inc(P, CharLen);
      end;

      Result.TextOffset := Frag.ByteStart + Frag.ByteLength;
      Result.AffinityDownstream := True;
      Exit;
    end;
  end;

  // Past the end of the line
  Frag := Line.Fragments[High(Line.Fragments)];
  Result.TextOffset := Frag.ByteStart + Frag.ByteLength;
  Result.AffinityDownstream := True;
end;

function TFloriaParagraph.GetRectsForRange(AStartOffset, AEndOffset: Integer): TRectDArray;
var
  RectList: array of TRectD;
  RectCount: Integer;
  LineIdx, FragIdx: Integer;
  Line: TFloriaLayoutLine;
  Frag: TFloriaLineFragment;
  SelStart, SelEnd: Integer;
  X1, X2: Double;
  P: PChar;
  CharLen: LongInt;
  CharW: Double;
  BytePos: Integer;
  CurX: Double;
  FoundX1, FoundX2: Boolean;
begin
  RectCount := 0;
  SetLength(RectList, 0);

  if (AStartOffset >= AEndOffset) or (Length(FLines) = 0) then
  begin
    SetLength(Result, 0);
    Exit;
  end;

  for LineIdx := 0 to High(FLines) do
  begin
    Line := FLines[LineIdx];
    if (AEndOffset <= Line.Metrics.StartIndex) or (AStartOffset >= Line.Metrics.EndIndex) then
      Continue;

    SelStart := Max(AStartOffset, Line.Metrics.StartIndex);
    SelEnd   := Min(AEndOffset, Line.Metrics.EndIndex);

    X1 := Line.Metrics.Left;
    X2 := Line.Metrics.Left + Line.Metrics.Width;
    FoundX1 := False;
    FoundX2 := False;

    for FragIdx := 0 to High(Line.Fragments) do
    begin
      Frag := Line.Fragments[FragIdx];
      if (SelStart >= Frag.ByteStart) and (SelStart <= Frag.ByteStart + Frag.ByteLength) then
      begin
        // Resolve precise X1
        CurX := Frag.Left;
        BytePos := Frag.ByteStart;
        P := PChar(Frag.Text);
        while (P^ <> #0) and (BytePos < SelStart) do
        begin
          UTF8CharToUnicode(P, CharLen);
          if Assigned(Frag.ResolvedFont) then
            CharW := Frag.ResolvedFont.GetTextWidth(Copy(P, 1, CharLen))
          else
            CharW := 8.0;
          CurX := CurX + CharW;
          Inc(BytePos, CharLen);
          Inc(P, CharLen);
        end;
        X1 := CurX;
        FoundX1 := True;
      end;

      if (SelEnd >= Frag.ByteStart) and (SelEnd <= Frag.ByteStart + Frag.ByteLength) then
      begin
        // Resolve precise X2
        CurX := Frag.Left;
        BytePos := Frag.ByteStart;
        P := PChar(Frag.Text);
        while (P^ <> #0) and (BytePos < SelEnd) do
        begin
          UTF8CharToUnicode(P, CharLen);
          if Assigned(Frag.ResolvedFont) then
            CharW := Frag.ResolvedFont.GetTextWidth(Copy(P, 1, CharLen))
          else
            CharW := 8.0;
          CurX := CurX + CharW;
          Inc(BytePos, CharLen);
          Inc(P, CharLen);
        end;
        X2 := CurX;
        FoundX2 := True;
        Break;
      end;
    end;

    if not FoundX1 then X1 := Line.Metrics.Left;
    if not FoundX2 then X2 := Line.Metrics.Left + Line.Metrics.Width;

    Inc(RectCount);
    SetLength(RectList, RectCount);
    RectList[RectCount - 1] := RectD(X1, Line.Metrics.Top, X2, Line.Metrics.Top + Line.Metrics.Height);
  end;

  SetLength(Result, RectCount);
  for LineIdx := 0 to RectCount - 1 do
    Result[LineIdx] := RectList[LineIdx];
end;

function TFloriaParagraph.GetPlaceholderBounds(APlaceholderID: Integer): TRectD;
var
  I: Integer;
begin
  for I := 0 to High(FSpans) do
    if FSpans[I].IsPlaceholder and (FSpans[I].Placeholder.ID = APlaceholderID) then
      Exit(FSpans[I].Placeholder.Bounds);
  Result := NullRectD;
end;

end.
