unit Floria.CSS.Types;

// Floria.CSS.Types
// ================
// Shared type definitions for the Floria CSS subsystem.
//
// Token types follow the W3C CSS Syntax Level 3 specification §4.2.
// Reference: https://www.w3.org/TR/css-syntax-3/#token-diagrams

{$mode objfpc}{$H+}

interface

type
  // All token types produced by the CSS Syntax Level 3 tokenizer (§4.2).
  // The cttBadString and cttBadUrl types signal parse errors but allow the
  // tokenizer to continue ("error recovery" per the spec).
  TCSSTokenType = (
    // Value tokens
    cttIdent,          // <ident-token>        e.g. color, --custom-prop
    cttFunction,       // <function-token>     e.g. rgb( url(
    cttAtKeyword,      // <at-keyword-token>   e.g. @media @charset
    cttHash,           // <hash-token>         e.g. #id #123
    cttString,         // <string-token>       e.g. "text" 'text'
    cttBadString,      // <bad-string-token>   parse error — newline inside string
    cttUrl,            // <url-token>          e.g. url(foo.png)
    cttBadUrl,         // <bad-url-token>      parse error — malformed url(...)
    cttDelim,          // <delim-token>        single unmatched code point
    cttNumber,         // <number-token>       e.g. 42  -1.5  3e10
    cttPercentage,     // <percentage-token>   e.g. 50%
    cttDimension,      // <dimension-token>    e.g. 10px  3.14em
    cttWhitespace,     // <whitespace-token>   one or more whitespace characters
    // HTML comment compatibility tokens
    cttCDO,            // <CDO-token>   <!--
    cttCDC,            // <CDC-token>   -->
    // Punctuation tokens
    cttColon,          // <colon-token>        :
    cttSemicolon,      // <semicolon-token>    ;
    cttComma,          // <comma-token>        ,
    cttOpenSquare,     // <[-token>            [
    cttCloseSquare,    // <]-token>            ]
    cttOpenParen,      // <(-token>            (
    cttCloseParen,     // <)-token>            )
    cttOpenCurly,      // <{-token>            {
    cttCloseCurly,     // <}-token>            }
    // End-of-stream token
    cttEOF             // <EOF-token>
  );

  // Source position inside the CSS text, 1-based. Stored in every token to
  // support accurate error reporting and source maps.
  TCSSSourcePos = record
    Line   : Integer;  // 1-based line number
    Column : Integer;  // 1-based column (in Unicode code points)
  end;

  // Type flag for <number-token> and <dimension-token> (spec §4.2).
  TCSSNumberFlag = (
    cnfInteger,   // the number was written without a decimal point or exponent
    cnfNumber     // the number has a decimal point or exponent
  );

  // Type flag for <hash-token> (spec §4.2).
  // chfID indicates the hash value is a valid CSS identifier.
  TCSSHashFlag = (
    chfID,            // value is a valid <ident-token> (e.g. #myId)
    chfUnrestricted   // value starts with a non-ident code point (e.g. #123)
  );

  // A single CSS token as produced by the tokenizer.
  // Fields not relevant to a given TokenType carry zero/empty/default values.
  TCSSToken = record
    TokenType  : TCSSTokenType;
    // Ident value, string content (escapes resolved), at-keyword name,
    // hash value, url content, delim char, or numeric repr for number tokens.
    Value      : AnsiString;
    // Numeric value for <number-token>, <percentage-token>, <dimension-token>.
    NumericVal : Double;
    // Integer vs. number distinction for <number-token> and <dimension-token>.
    NumFlag    : TCSSNumberFlag;
    // ID vs. unrestricted for <hash-token>.
    HashFlag   : TCSSHashFlag;
    // Unit identifier for <dimension-token> (e.g. 'px', 'em', 'rem').
    Unit_      : AnsiString;
    // Position of the first code point of this token in the source.
    Pos        : TCSSSourcePos;
  end;

  // ICSSTokenListener
  // Implement this interface and pass it to TCSSTokenizer to receive tokens.
  ICSSTokenListener = interface(IInterface)
    ['{3A7E9B2C-1F4D-4E8A-B6C5-0D2E4F7A9B1C}']
    procedure OnToken(const AToken: TCSSToken);
  end;

implementation

end.
