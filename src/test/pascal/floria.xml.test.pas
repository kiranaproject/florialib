unit Floria.XML.Test;

// Floria.XML.Test
// ===============
// Comprehensive test suite for the Floria XML subsystem:
//   - Entity encoding & decoding (&amp;, &#xHH;, &#NNN;)
//   - Tokenizer: tags, attributes, comments, CDATA, PIs, DOCTYPE
//   - DOM construction, hierarchy navigation, and serialization
//   - Elements querying by ID and TagName
//   - Integration with Floria.CSS (ICSSElement contract)
//   - Real-world SVG document parsing

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Contnrs, fpcunit, testregistry,
  Floria.XML.Types, Floria.XML.Tokenizer, Floria.XML.DOM, Floria.XML.Parser,
  Floria.CSS.Types, Floria.CSS.Values, Floria.CSS.Properties, Floria.CSS.Cascade;

type
  TXMLEntityTest = class(TTestCase)
  published
    procedure TestEncoding();
    procedure TestDecodingNamedEntities();
    procedure TestDecodingNumericEntities();
    procedure TestDecodingHexEntities();
  end;

  TXMLTokenizerTest = class(TTestCase)
  published
    procedure TestBasicElements();
    procedure TestAttributes();
    procedure TestSelfClosingTag();
    procedure TestComments();
    procedure TestCData();
    procedure TestProcessingInstruction();
    procedure TestDocType();
  end;

  TXMLDOMTest = class(TTestCase)
  published
    procedure TestNodeHierarchy();
    procedure TestAttributeOperations();
    procedure TestFindById();
    procedure TestGetElementsByTagName();
    procedure TestTextContent();
    procedure TestSerialization();
  end;

  TXMLParserTest = class(TTestCase)
  published
    procedure TestParseProlog();
    procedure TestParseNestedElements();
    procedure TestParseRealWorldSVG();
    procedure TestCSSCascadeIntegration();
  end;

implementation

// ── TXMLEntityTest ──────────────────────────────────────────────────────────

procedure TXMLEntityTest.TestEncoding();
begin
  AssertEquals('&lt;div class=&quot;main&quot;&gt;Tom &amp; Jerry&apos;s&lt;/div&gt;',
    XMLEncode('<div class="main">Tom & Jerry''s</div>'));
end;

procedure TXMLEntityTest.TestDecodingNamedEntities();
begin
  AssertEquals('<div class="main">Tom & Jerry''s</div>',
    XMLDecode('&lt;div class=&quot;main&quot;&gt;Tom &amp; Jerry&apos;s&lt;/div&gt;'));
end;

procedure TXMLEntityTest.TestDecodingNumericEntities();
begin
  AssertEquals('ABC', XMLDecode('&#65;&#66;&#67;'));
end;

procedure TXMLEntityTest.TestDecodingHexEntities();
begin
  AssertEquals('XYZ', XMLDecode('&#x58;&#x59;&#x5A;'));
end;

// ── TXMLTokenizerTest ───────────────────────────────────────────────────────

procedure TXMLTokenizerTest.TestBasicElements();
var
  Tokenizer: TXMLTokenizer;
  Tok: TXMLToken;
begin
  Tokenizer := TXMLTokenizer.Create('<root><child>Hello</child></root>');
  try
    Tok := Tokenizer.NextToken();
    AssertTrue('Start root', Tok.Kind = xtStartTag);
    AssertEquals('root', Tok.Name);

    Tok := Tokenizer.NextToken();
    AssertTrue('Start child', Tok.Kind = xtStartTag);
    AssertEquals('child', Tok.Name);

    Tok := Tokenizer.NextToken();
    AssertTrue('Text Hello', Tok.Kind = xtText);
    AssertEquals('Hello', Tok.Value);

    Tok := Tokenizer.NextToken();
    AssertTrue('End child', Tok.Kind = xtEndTag);
    AssertEquals('child', Tok.Name);

    Tok := Tokenizer.NextToken();
    AssertTrue('End root', Tok.Kind = xtEndTag);
    AssertEquals('root', Tok.Name);

    Tok := Tokenizer.NextToken();
    AssertTrue('EOF', Tok.Kind = xtEOF);
  finally
    Tokenizer.Free();
  end;
end;

procedure TXMLTokenizerTest.TestAttributes();
var
  Tokenizer: TXMLTokenizer;
  Tok: TXMLToken;
begin
  Tokenizer := TXMLTokenizer.Create('<button id="btn1" class=''btn primary'' disabled>');
  try
    Tok := Tokenizer.NextToken();
    AssertTrue('Start button', Tok.Kind = xtStartTag);
    AssertEquals('button', Tok.Name);
    AssertEquals(3, Tok.AttributeCount());
    AssertEquals('btn1', Tok.GetAttribute('id'));
    AssertEquals('btn primary', Tok.GetAttribute('class'));
    AssertTrue('Has disabled', Tok.HasAttribute('disabled'));
  finally
    Tokenizer.Free();
  end;
end;

procedure TXMLTokenizerTest.TestSelfClosingTag();
var
  Tokenizer: TXMLTokenizer;
  Tok: TXMLToken;
begin
  Tokenizer := TXMLTokenizer.Create('<path d="M 0 0 L 10 10 Z" fill="red" />');
  try
    Tok := Tokenizer.NextToken();
    AssertTrue('Empty element tag', Tok.Kind = xtEmptyElementTag);
    AssertEquals('path', Tok.Name);
    AssertEquals('M 0 0 L 10 10 Z', Tok.GetAttribute('d'));
    AssertEquals('red', Tok.GetAttribute('fill'));
  finally
    Tokenizer.Free();
  end;
end;

procedure TXMLTokenizerTest.TestComments();
var
  Tokenizer: TXMLTokenizer;
  Tok: TXMLToken;
begin
  Tokenizer := TXMLTokenizer.Create('<!-- Multi-line' + LineEnding + 'comment test --><tag/>');
  try
    Tok := Tokenizer.NextToken();
    AssertTrue('Comment', Tok.Kind = xtComment);
    AssertTrue('Contains text', Pos('Multi-line', Tok.Value) > 0);

    Tok := Tokenizer.NextToken();
    AssertTrue('Empty tag', Tok.Kind = xtEmptyElementTag);
    AssertEquals('tag', Tok.Name);
  finally
    Tokenizer.Free();
  end;
end;

procedure TXMLTokenizerTest.TestCData();
var
  Tokenizer: TXMLTokenizer;
  Tok: TXMLToken;
begin
  Tokenizer := TXMLTokenizer.Create('<![CDATA[function test() { return 1 < 2 && 3 > 2; }]]>');
  try
    Tok := Tokenizer.NextToken();
    AssertTrue('CDATA token', Tok.Kind = xtCData);
    AssertEquals('function test() { return 1 < 2 && 3 > 2; }', Tok.Value);
  finally
    Tokenizer.Free();
  end;
end;

procedure TXMLTokenizerTest.TestProcessingInstruction();
var
  Tokenizer: TXMLTokenizer;
  Tok: TXMLToken;
begin
  Tokenizer := TXMLTokenizer.Create('<?xml-stylesheet type="text/css" href="style.css"?>');
  try
    Tok := Tokenizer.NextToken();
    AssertTrue('PI token', Tok.Kind = xtProcessingInstruction);
    AssertEquals('xml-stylesheet', Tok.Name);
    AssertTrue('PI data', Pos('href="style.css"', Tok.Value) > 0);
  finally
    Tokenizer.Free();
  end;
end;

procedure TXMLTokenizerTest.TestDocType();
var
  Tokenizer: TXMLTokenizer;
  Tok: TXMLToken;
begin
  Tokenizer := TXMLTokenizer.Create('<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">');
  try
    Tok := Tokenizer.NextToken();
    AssertTrue('DocType token', Tok.Kind = xtDocType);
    AssertEquals('svg', Tok.Name);
  finally
    Tokenizer.Free();
  end;
end;

// ── TXMLDOMTest ─────────────────────────────────────────────────────────────

procedure TXMLDOMTest.TestNodeHierarchy();
var
  Doc: TXMLDocument;
  Root, C1, C2: TXMLElement;
begin
  Doc := TXMLDocument.Create();
  try
    Root := Doc.CreateElement('root');
    Doc.DocumentElement := Root;

    C1 := Doc.CreateElement('child1');
    C2 := Doc.CreateElement('child2');

    Root.AppendChild(C1);
    Root.AppendChild(C2);

    AssertEquals(2, Root.ChildCount);
    AssertTrue('FirstChild is C1', Root.FirstChild = C1);
    AssertTrue('LastChild is C2', Root.LastChild = C2);
    AssertTrue('C1 Next is C2', C1.NextSibling = C2);
    AssertTrue('C2 Prev is C1', C2.PreviousSibling = C1);
    AssertTrue('C1 Parent is Root', C1.Parent = Root);

    Root.RemoveChild(C1);
    AssertEquals(1, Root.ChildCount);
    AssertTrue('FirstChild is now C2', Root.FirstChild = C2);
    C1.Free();
  finally
    Doc.Free();
  end;
end;

procedure TXMLDOMTest.TestAttributeOperations();
var
  Elem: TXMLElement;
begin
  Elem := TXMLElement.Create('svg:path');
  try
    AssertEquals('svg', Elem.Prefix);
    AssertEquals('path', Elem.LocalName);

    Elem.SetAttribute('d', 'M 0 0');
    Elem.SetAttribute('fill', 'blue');
    Elem.SetAttribute('xmlns:svg', 'http://www.w3.org/2000/svg');

    AssertEquals(3, Elem.AttributeCount);
    AssertTrue('Has d', Elem.HasAttribute('d'));
    AssertEquals('M 0 0', Elem.GetAttribute('d'));
    AssertEquals('blue', Elem.GetAttribute('fill'));

    // Overwrite attribute
    Elem.SetAttribute('fill', 'green');
    AssertEquals(3, Elem.AttributeCount);
    AssertEquals('green', Elem.GetAttribute('fill'));

    // Remove attribute
    Elem.RemoveAttribute('fill');
    AssertEquals(2, Elem.AttributeCount);
    AssertFalse('fill removed', Elem.HasAttribute('fill'));
  finally
    Elem.Free();
  end;
end;

procedure TXMLDOMTest.TestFindById();
var
  Doc: TXMLDocument;
  Root, Section, Target: TXMLElement;
begin
  Doc := TXMLDocument.Create();
  try
    Root := Doc.CreateElement('div');
    Doc.DocumentElement := Root;

    Section := Doc.CreateElement('section');
    Root.AppendChild(Section);

    Target := Doc.CreateElement('button');
    Target.SetAttribute('id', 'submit-btn');
    Section.AppendChild(Target);

    AssertTrue('FindElementById finds target', Doc.FindElementById('submit-btn') = Target);
    AssertNull('Non-existent returns nil', Doc.FindElementById('missing-id'));
  finally
    Doc.Free();
  end;
end;

procedure TXMLDOMTest.TestGetElementsByTagName();
var
  Doc: TXMLDocument;
  Root, P1, P2, Div1: TXMLElement;
  List: TObjectList;
begin
  Doc := TXMLDocument.Create();
  try
    Root := Doc.CreateElement('main');
    Doc.DocumentElement := Root;

    P1 := Doc.CreateElement('p');
    Div1 := Doc.CreateElement('div');
    P2 := Doc.CreateElement('p');

    Root.AppendChild(P1);
    Root.AppendChild(Div1);
    Div1.AppendChild(P2);

    List := Doc.GetElementsByTagName('p');
    try
      AssertEquals(2, List.Count);
      AssertTrue('Contains P1', List.IndexOf(P1) >= 0);
      AssertTrue('Contains P2', List.IndexOf(P2) >= 0);
    finally
      List.Free();
    end;
  finally
    Doc.Free();
  end;
end;

procedure TXMLDOMTest.TestTextContent();
var
  Doc: TXMLDocument;
  Root, P: TXMLElement;
begin
  Doc := TXMLDocument.Create();
  try
    Root := Doc.CreateElement('div');
    Doc.DocumentElement := Root;

    P := Doc.CreateElement('p');
    P.AppendChild(Doc.CreateTextNode('Hello '));
    P.AppendChild(Doc.CreateTextNode('World!'));
    Root.AppendChild(P);

    AssertEquals('Hello World!', Root.TextContent);
  finally
    Doc.Free();
  end;
end;

procedure TXMLDOMTest.TestSerialization();
var
  Doc: TXMLDocument;
  Root, Rect: TXMLElement;
  XmlStr: AnsiString;
begin
  Doc := TXMLDocument.Create();
  try
    Root := Doc.CreateElement('svg');
    Root.SetAttribute('width', '100');
    Doc.DocumentElement := Root;

    Rect := Doc.CreateElement('rect');
    Rect.SetAttribute('fill', 'red');
    Root.AppendChild(Rect);

    XmlStr := Doc.SaveToString(True);
    AssertTrue('Prolog present', Pos('<?xml', XmlStr) = 1);
    AssertTrue('Root present', Pos('<svg width="100">', XmlStr) > 0);
    AssertTrue('Rect present', Pos('<rect fill="red" />', XmlStr) > 0);
    AssertTrue('Closing svg', Pos('</svg>', XmlStr) > 0);
  finally
    Doc.Free();
  end;
end;

// ── TXMLParserTest ──────────────────────────────────────────────────────────

procedure TXMLParserTest.TestParseProlog();
var
  Doc: TXMLDocument;
begin
  Doc := TXMLParser.ParseString('<?xml version="1.1" encoding="ISO-8859-1" standalone="yes"?><test/>');
  try
    AssertEquals('1.1', Doc.Version);
    AssertEquals('ISO-8859-1', Doc.Encoding);
    AssertEquals('yes', Doc.Standalone);
    AssertNotNull('Root exists', Doc.DocumentElement);
    AssertEquals('test', Doc.DocumentElement.TagName);
  finally
    Doc.Free();
  end;
end;

procedure TXMLParserTest.TestParseNestedElements();
var
  Doc: TXMLDocument;
  Root, Item: TXMLElement;
begin
  Doc := TXMLParser.ParseString(
    '<catalog>' +
    '  <item id="1"><name>Keyboard</name><price>49.99</price></item>' +
    '  <item id="2"><name>Mouse</name><price>19.99</price></item>' +
    '</catalog>');
  try
    Root := Doc.DocumentElement;
    AssertNotNull('Root exists', Root);
    AssertEquals('catalog', Root.TagName);

    Item := Doc.FindElementById('2');
    AssertNotNull('Found item 2', Item);
    AssertEquals('item', Item.TagName);
    AssertEquals('Mouse19.99', Item.TextContent);
  finally
    Doc.Free();
  end;
end;

procedure TXMLParserTest.TestParseRealWorldSVG();
var
  SvgXml: AnsiString;
  Doc: TXMLDocument;
  Svg, Circle, Path: TXMLElement;
  Stops: TObjectList;
begin
  SvgXml :=
    '<?xml version="1.0" encoding="UTF-8"?>' + LineEnding +
    '<svg width="200" height="200" viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">' + LineEnding +
    '  <!-- Main gradient def -->' + LineEnding +
    '  <defs>' + LineEnding +
    '    <linearGradient id="grad1" x1="0%" y1="0%" x2="100%" y2="100%">' + LineEnding +
    '      <stop offset="0%" stop-color="#ffff00" />' + LineEnding +
    '      <stop offset="100%" stop-color="#ff0000" />' + LineEnding +
    '    </linearGradient>' + LineEnding +
    '  </defs>' + LineEnding +
    '  <circle id="c1" cx="50" cy="50" r="40" stroke="green" stroke-width="4" fill="yellow" />' + LineEnding +
    '  <path id="p1" d="M 10 80 Q 52.5 10, 95 80 T 180 80" fill="none" stroke="black" />' + LineEnding +
    '</svg>';

  Doc := TXMLParser.ParseString(SvgXml);
  try
    Svg := Doc.DocumentElement;
    AssertNotNull('SVG root exists', Svg);
    AssertEquals('svg', Svg.TagName);
    AssertEquals('200', Svg.GetAttribute('width'));
    AssertEquals('200', Svg.GetAttribute('height'));
    AssertEquals('0 0 100 100', Svg.GetAttribute('viewBox'));

    Circle := Doc.FindElementById('c1');
    AssertNotNull('Circle c1 found', Circle);
    AssertEquals('circle', Circle.TagName);
    AssertEquals('40', Circle.GetAttribute('r'));
    AssertEquals('green', Circle.GetAttribute('stroke'));

    Path := Doc.FindElementById('p1');
    AssertNotNull('Path p1 found', Path);
    AssertEquals('M 10 80 Q 52.5 10, 95 80 T 180 80', Path.GetAttribute('d'));

    Stops := Doc.GetElementsByTagName('stop');
    try
      AssertEquals(2, Stops.Count);
    finally
      Stops.Free();
    end;
  finally
    Doc.Free();
  end;
end;

procedure TXMLParserTest.TestCSSCascadeIntegration();
var
  Doc: TXMLDocument;
  Rect: TXMLElement;
  Resolver: TCSSStyleResolver;
  Css: AnsiString;
  Resolved: TCSSStyleBlock;
begin
  // Verifies that TXMLElement implements ICSSElement and can be styled by Floria.CSS
  Doc := TXMLParser.ParseString(
    '<svg>' +
    '  <rect id="card-bg" class="icon-shape primary" />' +
    '</svg>');
  try
    Rect := Doc.FindElementById('card-bg');
    AssertNotNull('Rect exists', Rect);

    // Verify ICSSElement contract
    AssertEquals('rect', (Rect as ICSSElement).GetTagName());
    AssertEquals('card-bg', (Rect as ICSSElement).GetId());
    AssertTrue('Has class icon-shape', (Rect as ICSSElement).HasClass('icon-shape'));
    AssertTrue('Has class primary', (Rect as ICSSElement).HasClass('primary'));
    AssertFalse('Does not have danger', (Rect as ICSSElement).HasClass('danger'));

    // Apply Floria.CSS styling to the XML element
    Resolver := TCSSStyleResolver.Create();
    try
      Css := 'rect { background-color: #111111; }' + LineEnding +
             'rect.icon-shape { background-color: #222222; }' + LineEnding +
             '#card-bg.primary { background-color: #3b82f6; border-radius: 8px; }';
      Resolver.AddCSS(Css);

      Resolved := Resolver.ResolveStyle(Rect as ICSSElement);
      try
        AssertTrue('Has bg color', Resolved.HasProperty(cpiBackgroundColor));
        // Winning selector #card-bg.primary should give #3b82f6
        AssertEquals('R = $3B', Byte($3B), Resolved.GetDeclaration(cpiBackgroundColor).Value.Color.R);
        AssertEquals('G = $82', Byte($82), Resolved.GetDeclaration(cpiBackgroundColor).Value.Color.G);
        AssertEquals('B = $F6', Byte($F6), Resolved.GetDeclaration(cpiBackgroundColor).Value.Color.B);
        AssertTrue('Has border radius', Resolved.HasProperty(cpiBorderTopLeftRadius));
        AssertEquals('Radius 8px', 8.0, Resolved.GetDeclaration(cpiBorderTopLeftRadius).Value.Length.ToPixels());
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
  RegisterTest(TXMLEntityTest);
  RegisterTest(TXMLTokenizerTest);
  RegisterTest(TXMLDOMTest);
  RegisterTest(TXMLParserTest);

end.
