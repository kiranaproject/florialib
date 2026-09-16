unit Floria.CSS.AST;

(*
  Floria.CSS.AST
  ==============
  Abstract Syntax Tree (AST) node definitions for the Floria CSS parser.

  Follows the structural types defined by W3C CSS Syntax Level 3 §5:
    https://www.w3.org/TR/css-syntax-3/#parsing

  Ownership model
  ---------------
  Every TObjectList field is created with FreeObjects = True, so freeing the
  parent node automatically frees all descendants. Each node should be owned
  by exactly one parent; never add the same node instance to two lists.

  Node hierarchy
  --------------
    TCSSNode (base)
    +-- TCSSPreservedToken   - wraps one TCSSToken unchanged
    +-- TCSSSimpleBlock      - { }, [ ], or ( ) with a list of component values
    +-- TCSSFunctionBlock    - funcname( component-values )
    +-- TCSSDeclaration      - name: value [!important]
    +-- TCSSQualifiedRule    - selector-prelude { declarations }
    +-- TCSSAtRule           - @keyword prelude [; | { block }]
    +-- TCSSStylesheet       - top-level list of rules
*)

{$mode objfpc}{$H+}

interface

uses
  Classes, Contnrs, SysUtils, Floria.CSS.Types;

type
  // Discriminator for fast node-type dispatch without casting.
  TCSSNodeType = (
    cntStylesheet,       // TCSSStylesheet
    cntQualifiedRule,    // TCSSQualifiedRule
    cntAtRule,           // TCSSAtRule
    cntDeclaration,      // TCSSDeclaration
    cntPreservedToken,   // TCSSPreservedToken
    cntSimpleBlock,      // TCSSSimpleBlock
    cntFunction          // TCSSFunctionBlock
  );

  // Base class for every node in the CSS AST.
  TCSSNode = class(TObject)
  public
    NodeType : TCSSNodeType;
    constructor Create(ANodeType: TCSSNodeType);
  end;

  // A preserved token - a single CSS token stored verbatim.
  // Used for tokens that form component values but are not simple blocks or
  // function calls (spec section 5 "preserved tokens").
  TCSSPreservedToken = class(TCSSNode)
  public
    Token : TCSSToken;
    constructor Create(const AToken: TCSSToken);
  end;

  // A simple block: one of curly-brace, square-bracket, or paren blocks with contents.
  // AssocToken is the opening token (cttOpenCurly / cttOpenSquare / cttOpenParen).
  // Children is a list of TCSSNode (component values inside the block).
  TCSSSimpleBlock = class(TCSSNode)
  public
    AssocToken : TCSSToken;
    Children   : TObjectList;   // owns its children
    constructor Create(const AAssocToken: TCSSToken);
    destructor  Destroy(); override;
  end;

  // A CSS function value: name followed by a parenthesised list of component values.
  // Children is a list of TCSSNode (the component values inside the parens).
  TCSSFunctionBlock = class(TCSSNode)
  public
    Name     : AnsiString;
    Children : TObjectList;   // owns its children
    constructor Create(const AName: AnsiString);
    destructor  Destroy(); override;
  end;

  // A CSS declaration: property-name : value [!important].
  // Value is a list of TCSSNode (component values; whitespace stripped from both ends).
  // Important is True when the !important annotation is present.
  TCSSDeclaration = class(TCSSNode)
  public
    Name      : AnsiString;
    Value     : TObjectList;   // owns its children (component values)
    Important : Boolean;
    constructor Create(const AName: AnsiString);
    destructor  Destroy(); override;
  end;

  // A CSS qualified rule: selector prelude followed by a declarations block.
  // Prelude contains the raw component values of the selector (including whitespace).
  // Declarations contains TCSSDeclaration objects (and possibly TCSSAtRule objects
  // when a nested at-rule appears inside a declaration block).
  TCSSQualifiedRule = class(TCSSNode)
  public
    Prelude      : TObjectList;   // component values for the selector; owns children
    Declarations : TObjectList;   // TCSSDeclaration / TCSSAtRule; owns children
    constructor Create();
    destructor  Destroy(); override;
  end;

  // A CSS at-rule: @keyword prelude [;] or @keyword prelude [block].
  // Name is the keyword without the leading '@'.
  // Prelude contains the raw component values between the keyword and the
  // ';' or opening brace. Block is nil when the at-rule ends with ';'.
  TCSSAtRule = class(TCSSNode)
  public
    Name    : AnsiString;
    Prelude : TObjectList;     // component values; owns children
    Block   : TCSSSimpleBlock; // nil if no block; owned by this node
    constructor Create(const AName: AnsiString);
    destructor  Destroy(); override;
  end;

  // The top-level stylesheet node.
  // Rules contains a mix of TCSSQualifiedRule and TCSSAtRule objects.
  TCSSStylesheet = class(TCSSNode)
  public
    Rules : TObjectList;   // owns its children
    constructor Create();
    destructor  Destroy(); override;
  end;

implementation

// TCSSNode

constructor TCSSNode.Create(ANodeType: TCSSNodeType);
begin
  inherited Create();
  NodeType := ANodeType;
end;

// TCSSPreservedToken

constructor TCSSPreservedToken.Create(const AToken: TCSSToken);
begin
  inherited Create(cntPreservedToken);
  Token := AToken;
end;

// TCSSSimpleBlock

constructor TCSSSimpleBlock.Create(const AAssocToken: TCSSToken);
begin
  inherited Create(cntSimpleBlock);
  AssocToken := AAssocToken;
  Children   := TObjectList.Create(True); // owns children
end;

destructor TCSSSimpleBlock.Destroy();
begin
  Children.Free();
  inherited Destroy();
end;

// TCSSFunctionBlock

constructor TCSSFunctionBlock.Create(const AName: AnsiString);
begin
  inherited Create(cntFunction);
  Name     := AName;
  Children := TObjectList.Create(True);
end;

destructor TCSSFunctionBlock.Destroy();
begin
  Children.Free();
  inherited Destroy();
end;

// TCSSDeclaration

constructor TCSSDeclaration.Create(const AName: AnsiString);
begin
  inherited Create(cntDeclaration);
  Name      := AName;
  Value     := TObjectList.Create(True);
  Important := False;
end;

destructor TCSSDeclaration.Destroy();
begin
  Value.Free();
  inherited Destroy();
end;

// TCSSQualifiedRule

constructor TCSSQualifiedRule.Create();
begin
  inherited Create(cntQualifiedRule);
  Prelude      := TObjectList.Create(True);
  Declarations := nil;   // assigned by the parser
end;

destructor TCSSQualifiedRule.Destroy();
begin
  Prelude.Free();
  Declarations.Free();   // nil-safe
  inherited Destroy();
end;

// TCSSAtRule

constructor TCSSAtRule.Create(const AName: AnsiString);
begin
  inherited Create(cntAtRule);
  Name    := AName;
  Prelude := TObjectList.Create(True);
  Block   := nil;
end;

destructor TCSSAtRule.Destroy();
begin
  Prelude.Free();
  Block.Free();   // nil-safe
  inherited Destroy();
end;

// TCSSStylesheet

constructor TCSSStylesheet.Create();
begin
  inherited Create(cntStylesheet);
  Rules := TObjectList.Create(True);
end;

destructor TCSSStylesheet.Destroy();
begin
  Rules.Free();
  inherited Destroy();
end;


end.
