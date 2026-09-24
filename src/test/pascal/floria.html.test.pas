unit Floria.HTML.Test;

// Floria.HTML.Test
// ================
// Comprehensive test suite for the Floria HTML subsystem:
//   - HTML entity encoding & decoding (named, numeric, hex, UTF-8)
//   - Tokenizer: tags, boolean/quoted/unquoted attributes, comments, DOCTYPE, raw text
//   - DOM construction, specialized elements, hierarchy, and serialization
//   - InnerHTML, OuterHTML, and InnerText manipulation via fragment parser
//   - Auto-closing elements: <p> on blocks, <li> in lists, <tr>/<td> in tables
//   - Implied <html>, <head>, and <body> element generation
//   - CSS Selectors: QuerySelector and QuerySelectorAll
//   - CSS Cascade styling integration via ICSSElement

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Contnrs, fpcunit, testregistry,
  Floria.XML.Types, Floria.XML.DOM,
  Floria.HTML.Types, Floria.HTML.DOM, Floria.HTML.Tokenizer, Floria.HTML.Parser,
  Floria.CSS.Types, Floria.CSS.Values, Floria.CSS.Properties, Floria.CSS.Cascade;

type
  THTMLEntityTest = class(TTestCase)
  published
    procedure TestEncoding();
    procedure TestDecodingNamedEntities();
    procedure TestDecodingNumericEntities();
    procedure TestDecodingHexEntities();
  end;

  THTMLTokenizerTest = class(TTestCase)
  published
    procedure TestDocType();
    procedure TestTagsAndAttributes();
    procedure TestVoidElements();
    procedure TestComments();
    procedure TestRawTextScript();
    procedure TestRawTextStyle();
  end;

  THTMLDOMTest = class(TTestCase)
  published
    procedure TestElementProperties();
    procedure TestSpecializedElements();
    procedure TestDocumentAccessors();
    procedure TestInnerHTMLAndFragmentParser();
    procedure TestInnerText();
  end;

  THTMLParserTest = class(TTestCase)
  published
    procedure TestImpliedDocumentStructure();
    procedure TestExplicitDocumentStructure();
    procedure TestAutoClosingParagraphs();
    procedure TestAutoClosingListItems();
    procedure TestAutoClosingTableCells();
    procedure TestQuerySelector();
    procedure TestQuerySelectorAll();
    procedure TestCSSCascadeIntegration();
  end;

implementation

// ── THTMLEntityTest ──────────────────────────────────────────────────────────

procedure THTMLEntityTest.TestEncoding();
begin
  AssertEquals('&lt;div class=&quot;box&quot;&gt;5 &amp; 10 &lt; 20&lt;/div&gt;',
    HTMLEncode('<div class="box">5 & 10 < 20</div>'));
end;

procedure THTMLEntityTest.TestDecodingNamedEntities();
begin
  AssertEquals('<div class="box">5 & 10 < 20 © €</div>',
    HTMLDecode('&lt;div class=&quot;box&quot;&gt;5 &amp; 10 &lt; 20 &copy; &euro;&lt;/div&gt;'));
end;

procedure THTMLEntityTest.TestDecodingNumericEntities();
begin
  AssertEquals('ABC', HTMLDecode('&#65;&#66;&#67;'));
end;

procedure THTMLEntityTest.TestDecodingHexEntities();
begin
  AssertEquals('XYZ', HTMLDecode('&#x58;&#x59;&#x5A;'));
end;

// ── THTMLTokenizerTest ───────────────────────────────────────────────────────

procedure THTMLTokenizerTest.TestDocType();
var
  Tokenizer: THTMLTokenizer;
  Tok: THTMLToken;
begin
  Tokenizer := THTMLTokenizer.Create('<!DOCTYPE html>');
  try
    Tok := Tokenizer.NextToken();
    AssertTrue('Is DocType', Tok.Kind = htDocType);
    AssertEquals('html', Tok.Name);
    AssertEquals('html', Tok.Value);
  finally
    Tokenizer.Free();
  end;
end;

procedure THTMLTokenizerTest.TestTagsAndAttributes();
var
  Tokenizer: THTMLTokenizer;
  Tok: THTMLToken;
begin
  Tokenizer := THTMLTokenizer.Create('<input type="text" name=''user'' data-id=123 disabled autofocus>');
  try
    Tok := Tokenizer.NextToken();
    AssertTrue('Is StartTag', Tok.Kind = htStartTag);
    AssertEquals('input', Tok.Name);
    AssertEquals('5 attributes', 5, Tok.AttributeCount());
    AssertEquals('type="text"', 'text', Tok.GetAttribute('type'));
    AssertEquals('name=''user''', 'user', Tok.GetAttribute('name'));
    AssertEquals('data-id=123', '123', Tok.GetAttribute('data-id'));
    AssertTrue('Has disabled', Tok.HasAttribute('disabled'));
    AssertTrue('Has autofocus', Tok.HasAttribute('autofocus'));
  finally
    Tokenizer.Free();
  end;
end;

procedure THTMLTokenizerTest.TestVoidElements();
var
  Tokenizer: THTMLTokenizer;
  Tok: THTMLToken;
begin
  Tokenizer := THTMLTokenizer.Create('<img src="pic.png" alt="photo"><br/>');
  try
    Tok := Tokenizer.NextToken();
    AssertTrue('Is img tag', Tok.Kind = htStartTag);
    AssertEquals('img', Tok.Name);
    AssertEquals('pic.png', Tok.GetAttribute('src'));

    Tok := Tokenizer.NextToken();
    AssertTrue('Is br self-closing', Tok.Kind = htSelfClosingTag);
    AssertEquals('br', Tok.Name);
  finally
    Tokenizer.Free();
  end;
end;

procedure THTMLTokenizerTest.TestComments();
var
  Tokenizer: THTMLTokenizer;
  Tok: THTMLToken;
begin
  Tokenizer := THTMLTokenizer.Create('<!-- Hello HTML5 World -->');
  try
    Tok := Tokenizer.NextToken();
    AssertTrue('Is comment', Tok.Kind = htComment);
    AssertEquals('Hello HTML5 World', Trim(Tok.Value));
  finally
    Tokenizer.Free();
  end;
end;

procedure THTMLTokenizerTest.TestRawTextScript();
var
  Tokenizer: THTMLTokenizer;
  Tok: THTMLToken;
begin
  Tokenizer := THTMLTokenizer.Create('<script type="text/javascript">if (x < 10) { alert("</notscript>"); }</script>');
  try
    Tok := Tokenizer.NextToken();
    AssertTrue('Is script start', Tok.Kind = htStartTag);
    AssertEquals('script', Tok.Name);

    Tokenizer.SwitchToRawText('script');

    Tok := Tokenizer.NextToken();
    AssertTrue('Is raw text', Tok.Kind = htRawText);
    AssertEquals('if (x < 10) { alert("</notscript>"); }', Tok.Value);

    Tok := Tokenizer.NextToken();
    AssertTrue('Is script end', Tok.Kind = htEndTag);
    AssertEquals('script', Tok.Name);
  finally
    Tokenizer.Free();
  end;
end;

procedure THTMLTokenizerTest.TestRawTextStyle();
var
  Tokenizer: THTMLTokenizer;
  Tok: THTMLToken;
begin
  Tokenizer := THTMLTokenizer.Create('<style>body > p { color: red; font-size: 14px; }</style>');
  try
    Tok := Tokenizer.NextToken();
    AssertTrue('Is style start', Tok.Kind = htStartTag);
    AssertEquals('style', Tok.Name);

    Tokenizer.SwitchToRawText('style');

    Tok := Tokenizer.NextToken();
    AssertTrue('Is raw text', Tok.Kind = htRawText);
    AssertEquals('body > p { color: red; font-size: 14px; }', Tok.Value);

    Tok := Tokenizer.NextToken();
    AssertTrue('Is style end', Tok.Kind = htEndTag);
    AssertEquals('style', Tok.Name);
  finally
    Tokenizer.Free();
  end;
end;

// ── THTMLDOMTest ─────────────────────────────────────────────────────────────

procedure THTMLDOMTest.TestElementProperties();
var
  Elem: THTMLElement;
begin
  Elem := THTMLElement.Create('div');
  try
    Elem.Id := 'card-1';
    Elem.ClassName := 'card primary active';
    Elem.Title := 'Card Tooltip';
    Elem.Hidden := True;
    Elem.Style := 'padding: 10px; margin: 5px;';

    AssertEquals('card-1', Elem.Id);
    AssertEquals('card primary active', Elem.ClassName);
    AssertEquals('Card Tooltip', Elem.Title);
    AssertTrue('Is Hidden', Elem.Hidden);
    AssertEquals('padding: 10px; margin: 5px;', Elem.Style);

    AssertTrue('Has card class', Elem.HasClass('card'));
    AssertTrue('Has primary class', Elem.HasClass('primary'));
    AssertTrue('Has active class', Elem.HasClass('active'));
    AssertFalse('Has missing class', Elem.HasClass('missing'));
  finally
    Elem.Free();
  end;
end;

procedure THTMLDOMTest.TestSpecializedElements();
var
  A    : THTMLAnchorElement;
  Img  : THTMLImageElement;
  Inp  : THTMLInputElement;
  Btn  : THTMLButtonElement;
  H    : THTMLHeadingElement;
  Tbl  : THTMLTableElement;
  Tr   : THTMLTableRowElement;
  Td   : THTMLTableCellElement;
  Rows : TObjectList;
  Cells: TObjectList;
begin
  A := THTMLAnchorElement.Create('a');
  try
    A.Href := 'https://example.com';
    A.Target := '_blank';
    AssertEquals('https://example.com', A.Href);
    AssertEquals('_blank', A.Target);
  finally
    A.Free();
  end;

  Img := THTMLImageElement.Create('img');
  try
    Img.Src := 'logo.png';
    Img.Alt := 'Floria Logo';
    Img.Width := 200;
    Img.Height := 50;
    AssertEquals('logo.png', Img.Src);
    AssertEquals('Floria Logo', Img.Alt);
    AssertEquals(200, Img.Width);
    AssertEquals(50, Img.Height);
  finally
    Img.Free();
  end;

  Inp := THTMLInputElement.Create('input');
  try
    Inp.InputType := 'checkbox';
    Inp.Name := 'remember';
    Inp.Checked := True;
    Inp.Disabled := False;
    Inp.Value := '1';
    AssertEquals('checkbox', Inp.InputType);
    AssertEquals('remember', Inp.Name);
    AssertTrue('Checked', Inp.Checked);
    AssertFalse('Not disabled', Inp.Disabled);
    AssertEquals('1', Inp.Value);
  finally
    Inp.Free();
  end;

  Btn := THTMLButtonElement.Create('button');
  try
    Btn.ButtonType := 'button';
    Btn.Disabled := True;
    AssertEquals('button', Btn.ButtonType);
    AssertTrue('Disabled', Btn.Disabled);
  finally
    Btn.Free();
  end;

  H := THTMLHeadingElement.Create('h2', 2);
  try
    AssertEquals('h2', H.TagName);
    AssertEquals(2, H.Level);
  finally
    H.Free();
  end;

  Tbl := THTMLTableElement.Create('table');
  try
    Tr := THTMLTableRowElement.Create('tr');
    Tbl.AppendChild(Tr);
    Td := THTMLTableCellElement.Create('td');
    Td.ColSpan := 2;
    Td.RowSpan := 1;
    Tr.AppendChild(Td);

    Rows := Tbl.GetRows();
    try
      AssertEquals('1 row', 1, Rows.Count);
    finally
      Rows.Free();
    end;

    Cells := Tr.GetCells();
    try
      AssertEquals('1 cell', 1, Cells.Count);
    finally
      Cells.Free();
    end;

    AssertEquals(2, Td.ColSpan);
    AssertEquals(1, Td.RowSpan);
    AssertEquals(0, Tr.GetRowIndex());
    AssertEquals(0, Td.GetCellIndex());
  finally
    Tbl.Free();
  end;
end;

procedure THTMLDOMTest.TestDocumentAccessors();
var
  Doc: THTMLDocument;
begin
  Doc := THTMLDocument.Create();
  try
    Doc.Title := 'Floria Test Page';
    AssertEquals('Floria Test Page', Doc.Title);
    AssertNotNull('Head is created', Doc.Head);
    AssertNotNull('DocumentElement is html', Doc.DocumentElement);
    AssertEquals('html', Doc.DocumentElement.TagName);
    AssertEquals('head', Doc.Head.TagName);
  finally
    Doc.Free();
  end;
end;

procedure THTMLDOMTest.TestInnerHTMLAndFragmentParser();
var
  DivElem: THTMLElement;
begin
  DivElem := THTMLElement.Create('div');
  try
    DivElem.InnerHTML := '<h1>Title</h1><p>Description with <b>bold</b> text</p>';

    AssertEquals('Child count', 2, DivElem.ChildCount);
    AssertEquals('First is h1', 'h1', THTMLElement(DivElem.Children[0]).TagName);
    AssertEquals('Second is p', 'p', THTMLElement(DivElem.Children[1]).TagName);
    AssertEquals('h1 text', 'Title', THTMLElement(DivElem.Children[0]).InnerText);

    AssertTrue('Contains bold', Pos('<b>bold</b>', DivElem.InnerHTML) > 0);
  finally
    DivElem.Free();
  end;
end;

procedure THTMLDOMTest.TestInnerText();
var
  DivElem: THTMLElement;
begin
  DivElem := THTMLElement.Create('div');
  try
    DivElem.InnerHTML := '<p>Hello <span>World</span></p>';
    AssertEquals('Hello World', DivElem.InnerText);

    DivElem.InnerText := 'New Plain Text';
    AssertEquals('New Plain Text', DivElem.InnerText);
    AssertEquals('New Plain Text', DivElem.InnerHTML);
  finally
    DivElem.Free();
  end;
end;

// ── THTMLParserTest ──────────────────────────────────────────────────────────

procedure THTMLParserTest.TestImpliedDocumentStructure();
var
  Doc: THTMLDocument;
begin
  Doc := THTMLParser.ParseString('<h1>Hello World</h1><p>Welcome to Floria</p>');
  try
    AssertNotNull('Doc DocumentElement', Doc.DocumentElement);
    AssertEquals('html', Doc.DocumentElement.TagName);
    AssertNotNull('Doc Head', Doc.Head);
    AssertNotNull('Doc Body', Doc.Body);
    AssertEquals('Body has 2 children', 2, Doc.Body.ChildCount);
    AssertEquals('h1', THTMLElement(Doc.Body.Children[0]).TagName);
    AssertEquals('p', THTMLElement(Doc.Body.Children[1]).TagName);
  finally
    Doc.Free();
  end;
end;

procedure THTMLParserTest.TestExplicitDocumentStructure();
var
  HTML: AnsiString;
  Doc: THTMLDocument;
begin
  HTML := '<!DOCTYPE html>' +
          '<html lang="en">' +
          '<head><title>Full Document</title><meta charset="utf-8"></head>' +
          '<body><div id="main">Content</div></body>' +
          '</html>';

  Doc := THTMLParser.ParseString(HTML);
  try
    AssertEquals('<!DOCTYPE html>', Trim(Doc.DocTypeStr));
    AssertEquals('en', Doc.DocumentElement.GetAttribute('lang'));
    AssertEquals('Full Document', Doc.Title);
    AssertNotNull('Has Body', Doc.Body);

    AssertNotNull('GetElementById main', Doc.GetElementById('main'));
    AssertEquals('Content', Doc.GetElementById('main').InnerText);
  finally
    Doc.Free();
  end;
end;

procedure THTMLParserTest.TestAutoClosingParagraphs();
var
  Doc: THTMLDocument;
  P1, P2, DivElem: THTMLElement;
begin
  Doc := THTMLParser.ParseString('<p>Paragraph 1<p>Paragraph 2<div>Block element</div>');
  try
    // The second <p> should auto-close the first <p>.
    // The <div> should auto-close the second <p>.
    // All three should be sibling elements under <body>!
    AssertEquals('3 children in body', 3, Doc.Body.ChildCount);

    P1 := THTMLElement(Doc.Body.Children[0]);
    P2 := THTMLElement(Doc.Body.Children[1]);
    DivElem := THTMLElement(Doc.Body.Children[2]);

    AssertEquals('p', P1.TagName);
    AssertEquals('Paragraph 1', P1.InnerText);

    AssertEquals('p', P2.TagName);
    AssertEquals('Paragraph 2', P2.InnerText);

    AssertEquals('div', DivElem.TagName);
    AssertEquals('Block element', DivElem.InnerText);
  finally
    Doc.Free();
  end;
end;

procedure THTMLParserTest.TestAutoClosingListItems();
var
  Doc: THTMLDocument;
  Ul: THTMLElement;
begin
  Doc := THTMLParser.ParseString('<ul><li>Alpha<li>Beta<li>Gamma</ul>');
  try
    Ul := THTMLElement(Doc.Body.Children[0]);
    AssertEquals('ul', Ul.TagName);
    AssertEquals('3 list items', 3, Ul.ChildCount);
    AssertEquals('Alpha', THTMLElement(Ul.Children[0]).InnerText);
    AssertEquals('Beta', THTMLElement(Ul.Children[1]).InnerText);
    AssertEquals('Gamma', THTMLElement(Ul.Children[2]).InnerText);
  finally
    Doc.Free();
  end;
end;

procedure THTMLParserTest.TestAutoClosingTableCells();
var
  Doc: THTMLDocument;
  Tbl: THTMLTableElement;
  Rows: TObjectList;
  Tr1, Tr2: THTMLTableRowElement;
  Cells1, Cells2: TObjectList;
begin
  Doc := THTMLParser.ParseString('<table><tr><td>R1C1<td>R1C2<tr><td>R2C1<td>R2C2</table>');
  try
    Tbl := THTMLTableElement(Doc.Body.Children[0]);
    AssertEquals('table', Tbl.TagName);

    Rows := Tbl.GetRows();
    try
      AssertEquals('2 rows', 2, Rows.Count);
      Tr1 := THTMLTableRowElement(Rows[0]);
      Tr2 := THTMLTableRowElement(Rows[1]);

      Cells1 := Tr1.GetCells();
      try
        AssertEquals('Row 1 has 2 cells', 2, Cells1.Count);
        AssertEquals('R1C1', THTMLElement(Cells1[0]).InnerText);
        AssertEquals('R1C2', THTMLElement(Cells1[1]).InnerText);
      finally
        Cells1.Free();
      end;

      Cells2 := Tr2.GetCells();
      try
        AssertEquals('Row 2 has 2 cells', 2, Cells2.Count);
        AssertEquals('R2C1', THTMLElement(Cells2[0]).InnerText);
        AssertEquals('R2C2', THTMLElement(Cells2[1]).InnerText);
      finally
        Cells2.Free();
      end;
    finally
      Rows.Free();
    end;
  finally
    Doc.Free();
  end;
end;

procedure THTMLParserTest.TestQuerySelector();
var
  HTML: AnsiString;
  Doc: THTMLDocument;
  Target: THTMLElement;
begin
  HTML := '<div class="container">' +
          '  <header><h1 class="title">My App</h1></header>' +
          '  <main><section id="about"><p class="highlight">Hello World</p></section></main>' +
          '</div>';

  Doc := THTMLParser.ParseString(HTML);
  try
    Target := Doc.QuerySelector('header h1.title');
    AssertNotNull('Found header h1.title', Target);
    AssertEquals('My App', Target.InnerText);

    Target := Doc.QuerySelector('#about > p.highlight');
    AssertNotNull('Found #about > p.highlight', Target);
    AssertEquals('Hello World', Target.InnerText);

    Target := Doc.QuerySelector('.non-existent');
    AssertNull('Non-existent is nil', Target);
  finally
    Doc.Free();
  end;
end;

procedure THTMLParserTest.TestQuerySelectorAll();
var
  HTML: AnsiString;
  Doc: THTMLDocument;
  List: TObjectList;
begin
  HTML := '<ul class="nav">' +
          '  <li class="item active"><a href="#1">One</a></li>' +
          '  <li class="item"><a href="#2">Two</a></li>' +
          '  <li class="item active"><a href="#3">Three</a></li>' +
          '</ul>';

  Doc := THTMLParser.ParseString(HTML);
  try
    List := Doc.QuerySelectorAll('li.item.active');
    try
      AssertEquals('Found 2 active items', 2, List.Count);
      AssertEquals('One', THTMLElement(List[0]).InnerText);
      AssertEquals('Three', THTMLElement(List[1]).InnerText);
    finally
      List.Free();
    end;

    List := Doc.QuerySelectorAll('li a[href]');
    try
      AssertEquals('Found 3 links', 3, List.Count);
    finally
      List.Free();
    end;
  finally
    Doc.Free();
  end;
end;

procedure THTMLParserTest.TestCSSCascadeIntegration();
var
  HTML, CSS: AnsiString;
  Doc: THTMLDocument;
  H1Elem: THTMLElement;
  Resolver: TCSSStyleResolver;
  Resolved: TCSSStyleBlock;
begin
  HTML := '<html><head><title>Test</title></head>' +
          '<body>' +
          '  <h1 id="headline" class="title important">Styled Heading</h1>' +
          '</body></html>';

  CSS := 'h1 { color: #0000ff; }' + LineEnding +
         '.important { color: #ff0000; }' + LineEnding +
         '#headline { font-weight: bold; font-size: 24px; }';

  Doc := THTMLParser.ParseString(HTML);
  try
    H1Elem := Doc.GetElementById('headline');
    AssertNotNull('Found headline', H1Elem);

    // Verify ICSSElement contract
    AssertEquals('h1', (H1Elem as ICSSElement).GetTagName());
    AssertEquals('headline', (H1Elem as ICSSElement).GetId());
    AssertTrue('Has title class', (H1Elem as ICSSElement).HasClass('title'));
    AssertTrue('Has important class', (H1Elem as ICSSElement).HasClass('important'));

    Resolver := TCSSStyleResolver.Create();
    try
      Resolver.AddCSS(CSS);
      Resolved := Resolver.ResolveStyle(H1Elem as ICSSElement);
      try
        AssertTrue('Has color', Resolved.HasProperty(cpiColor));
        // .important (#ff0000) wins over h1 (#0000ff)
        AssertEquals('R = $FF', Byte($FF), Resolved.GetDeclaration(cpiColor).Value.Color.R);
        AssertEquals('G = $00', Byte($00), Resolved.GetDeclaration(cpiColor).Value.Color.G);
        AssertEquals('B = $00', Byte($00), Resolved.GetDeclaration(cpiColor).Value.Color.B);
        AssertTrue('Has font-weight', Resolved.HasProperty(cpiFontWeight));
        AssertTrue('Has font-size', Resolved.HasProperty(cpiFontSize));
        AssertEquals('Font size 24px', 24.0, Resolved.GetDeclaration(cpiFontSize).Value.Length.ToPixels());
      finally
        Resolved.Free();
      end;
    finally
      Resolver.Free();
    end;
  finally
    Doc.Free();
  end;
end;

initialization
  RegisterTest(THTMLEntityTest);
  RegisterTest(THTMLTokenizerTest);
  RegisterTest(THTMLDOMTest);
  RegisterTest(THTMLParserTest);

end.
