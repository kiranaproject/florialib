program TestRunner;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, fpcunit, testregistry, consoletestrunner,
  { Register all test suites }
  Floria.CSS.Tokenizer.Test,
  Floria.CSS.Parser.Test,
  Floria.CSS.Values.Test,
  Floria.CSS.Properties.Test,
  Floria.CSS.Selectors.Test,
  Floria.CSS.Cascade.Test,
  Floria.XCB.Test,
  Floria.XCB.WM.Test,
  Floria.XML.Test,
  Floria.SVG.Test,
  Floria.HTML.Test,
  Floria.Image.Test,
  Floria.Image.Blur.Test,
  Floria.Canvas.Agg.Test,
  Floria.Unicode.BiDi.Test,
  Floria.Text.HarfBuzz.Test;

var
  Application: TTestRunner;

begin
  Application := TTestRunner.Create(nil);
  try
    Application.Initialize();
    Application.Run();
  finally
    Application.Free();
  end;
end.
