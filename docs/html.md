# HTML Subsystem Guide

`Floria.HTML` is a pure Pascal HTML tokenizer, parser, and DOM. It is designed
for embedded UI use cases (rich labels, documentation panes, style sheets, and
HTML-to-widget trees), not as a full browser engine.

---

## 1. Architecture

```
HTML source / stream
        |
        v
Floria.HTML.Tokenizer   (tag, attribute, text, comment, doctype tokens)
        |
        v
Floria.HTML.Parser      (element tree construction, void elements, raw text)
        |
        v
Floria.HTML.DOM         (THTMLDocument / THTMLElement, extends Floria.XML.DOM)
        |
        v
CSS bridge              (THTMLElement implements ICSSElement via TXMLElement)
```

The DOM classes extend the XML DOM so HTML documents can participate in the
same CSS element contract used by [`Floria.CSS.Cascade`](../src/main/pascal/floria.css.cascade.pas).
That allows selectors, cascade resolution, and inherited styles to work on HTML
trees without a separate adapter.

---

## 2. Units

| Unit | Role |
|---|---|
| [`Floria.HTML.Types`](../src/main/pascal/floria.html.types.pas) | Token kinds, `THTMLToken`, `THTMLPosition`, attributes, `EHTMLException` |
| [`Floria.HTML.Tokenizer`](../src/main/pascal/floria.html.tokenizer.pas) | Streaming tokenizer with raw-text handling for `script`/`style` |
| [`Floria.HTML.Parser`](../src/main/pascal/floria.html.parser.pas) | `THTMLParser` tree construction and fragment parsing |
| [`Floria.HTML.DOM`](../src/main/pascal/floria.html.dom.pas) | `THTMLDocument`, `THTMLElement`, and typed element classes |

---

## 3. Parsing a document

```pascal
uses
  Floria.HTML.Parser,
  Floria.HTML.DOM;

var
  Doc: THTMLDocument;
  Body: THTMLElement;
  Title: THTMLElement;
begin
  Doc := THTMLParser.ParseString(
    '<html><body><h1 id="title">Hello</h1></body></html>');
  try
    Body := Doc.Body;
    Title := THTMLElement(Doc.FindElementById('title'));
    if (Body <> nil) and (Title <> nil) then
      WriteLn(Title.InnerText);
  finally
    Doc.Free();
  end;
end;
```

File and stream entry points are also available:

```pascal
Doc := THTMLParser.ParseFile('page.html');
Doc := THTMLParser.ParseStream(Stream);
```

---

## 4. Parsing fragments

Use fragment parsing when inserting HTML into an existing context (for example,
a rich-text widget):

```pascal
uses
  Classes, Contnrs,
  Floria.HTML.Parser,
  Floria.HTML.DOM;

var
  Nodes: TObjectList;
  Node: THTMLElement;
  I: Integer;
begin
  Nodes := THTMLParser.ParseFragment('<b>bold</b> and <i>italic</i>', nil);
  try
    for I := 0 to Nodes.Count - 1 do
    begin
      if Nodes[I] is THTMLElement then
      begin
        Node := THTMLElement(Nodes[I]);
        // Inspect or insert Node into an existing THTMLElement.
      end;
    end;
  finally
    Nodes.Free();
  end;
end;
```

`ParseHTMLFragment` is the procedural equivalent.

---

## 5. DOM capabilities

`THTMLElement` provides convenience properties for common attributes and DOM
operations:

- `Id`, `ClassName`, `Title`, `Hidden`, `Style`
- `InnerHTML`, `OuterHTML`, `InnerText`
- child/parent navigation inherited from `Floria.XML.DOM`
- typed subclasses:
  - `THTMLAnchorElement` (`Href`, `Target`)
  - `THTMLImageElement` (`Src`, `Alt`, `Width`, `Height`)
  - `THTMLInputElement` (`InputType`, `Value`, `Name`, `Checked`, `Disabled`, `Placeholder`)
  - `THTMLButtonElement` (`ButtonType`, `Disabled`)
  - `THTMLHeadingElement` (`Level`)
  - `THTMLTableElement`, `THTMLTableRowElement`, `THTMLTableCellElement`
  - `THTMLScriptElement`, `THTMLStyleElement`

Inspect [`floria.html.dom.pas`](../src/main/pascal/floria.html.dom.pas) for the
complete class set.

---

## 6. Scope and limitations

- No JavaScript execution and no browser layout engine.
- HTML parsing follows a practical subset of HTML5 tree construction; it is not
  a full WHATWG parser conformance implementation.
- CSS styling is available through the shared `ICSSElement` contract; layout
  (block/inline/flex/grid) is outside this subsystem.
- Malformed input is recovered where practical, but callers should expect
  `EHTMLException` for unrecoverable cases.

---

## 7. Tests

`src/test/pascal/floria.html.test.pas` covers tokenization, tree construction,
void elements, raw-text elements, attributes, entity decoding, fragment
parsing, and DOM navigation. Run it with the full suite:

```bash
pasbuild test -p pic
```
