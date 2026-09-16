# XML Subsystem Guide

The `florialib` XML subsystem is a modular, zero-dependency, high-performance XML 1.0 parser and Document Object Model (DOM) engine written in Free Pascal (`{$mode objfpc}`). It is designed as the foundational markup layer for SVG vector graphics, declarative UI layouts, and structured data configuration.

```
Floria.XML.Types       (Tokens, token kinds, position tracking, entity encoding/decoding)
      ↓
Floria.XML.Tokenizer   (Streaming push/pull tokenizer for elements, attributes, text, CDATA, comments)
      ↓
Floria.XML.DOM         (W3C-compatible DOM tree: TXMLDocument, TXMLElement, TXMLTextNode, ICSSElement)
      ↓
Floria.XML.Parser      (Tree builder from strings, streams, and files with prolog & entity resolution)
```

---

## 1. Architecture Overview

| Unit | Role | Key Types |
|---|---|---|
| `Floria.XML.Types` | Token kinds, node types, source positions, entity encoders/decoders | `TXMLToken`, `TXMLPosition`, `XMLEncode`, `XMLDecode` |
| `Floria.XML.Tokenizer` | Streaming character-by-character scanner | `TXMLTokenizer` |
| `Floria.XML.DOM` | Hierarchical DOM nodes, attributes, navigation, and serialization | `TXMLNode`, `TXMLDocument`, `TXMLElement`, `TXMLAttribute` |
| `Floria.XML.Parser` | Document builder, nesting validation, and static helpers | `TXMLParser` |

---

## 2. Parsing XML

### Parse from String

```pascal
uses Floria.XML.DOM, Floria.XML.Parser;

var
  Doc: TXMLDocument;
  Svg: TXMLElement;
begin
  Doc := TXMLParser.ParseString(
    '<svg width="100" height="100" viewBox="0 0 100 100">' +
    '  <circle id="c1" cx="50" cy="50" r="40" fill="blue" />' +
    '</svg>');
  try
    Svg := Doc.DocumentElement;
    WriteLn('Root element: ', Svg.TagName);
    WriteLn('Width: ', Svg.GetAttribute('width'));
  finally
    Doc.Free();
  end;
end;
```

### Parse from File or Stream

```pascal
Doc := TXMLParser.ParseFile('/path/to/vector_icon.svg');
try
  // Work with Doc...
finally
  Doc.Free();
end;
```

---

## 3. DOM Tree Navigation & Queries

### Querying Elements by ID and Tag Name

```pascal
var
  Doc: TXMLDocument;
  Circle: TXMLElement;
  Paths: TObjectList;
begin
  Doc := TXMLParser.ParseString(SvgXml);
  try
    // Find by ID (#c1)
    Circle := Doc.FindElementById('c1');
    if Circle <> nil then
      WriteLn('Circle fill: ', Circle.GetAttribute('fill'));

    // Get all <path> elements
    Paths := Doc.GetElementsByTagName('path');
    try
      WriteLn('Total paths: ', Paths.Count);
    finally
      Paths.Free();
    end;
  finally
    Doc.Free();
  end;
end;
```

### Element Hierarchy Navigation

```pascal
var
  Child: TXMLElement;
begin
  Child := Root.GetFirstChildElement();
  while Child <> nil do
  begin
    WriteLn('Tag: ', Child.TagName, ' Local: ', Child.LocalName, ' Prefix: ', Child.Prefix);
    Child := Child.GetNextSiblingElement();
  end;
end;
```

---

## 4. Integration with `Floria.CSS`

`TXMLElement` implements the **`ICSSElement`** interface from `Floria.CSS.Cascade`. This enables any XML element tree (such as an SVG document) to be queried, matched, and styled by the Floria CSS cascade engine!

```pascal
uses
  Floria.XML.DOM, Floria.XML.Parser,
  Floria.CSS.Cascade, Floria.CSS.Properties;

var
  Doc: TXMLDocument;
  Rect: TXMLElement;
  Resolver: TCSSStyleResolver;
  Style: TCSSStyleBlock;
begin
  Doc := TXMLParser.ParseString('<svg><rect id="bg" class="icon-card" /></svg>');
  try
    Rect := Doc.FindElementById('bg');

    Resolver := TCSSStyleResolver.Create();
    try
      // Load CSS rules targeting the XML/SVG elements
      Resolver.AddCSS('rect.icon-card { background-color: #3b82f6; border-radius: 8px; }');

      // Resolve style for the XML node
      Style := Resolver.ResolveStyle(Rect as ICSSElement);
      try
        if Style.HasProperty(cpiBackgroundColor) then
          WriteLn('Resolved fill color: ', Style.GetDeclaration(cpiBackgroundColor).Value.Color.ToHex());
      finally
        Style.Free();
      end;
    finally
      Resolver.Free();
    end;
  finally
    Doc.Free();
  end;
end;
```

---

## 5. Serialization

Any DOM node or document can be serialized back to standards-compliant XML text:

```pascal
var
  XmlOutput: AnsiString;
begin
  // Save with XML declaration prolog
  XmlOutput := Doc.SaveToString(True);

  // Or save directly to file
  Doc.SaveToFile('/path/to/output.svg');
end;
```
