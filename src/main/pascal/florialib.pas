{ This file was automatically created by Lazarus. Do not edit!
  This source is only used to compile and install the package.
 }

unit florialib;

{$warn 5023 off : no warning about unused units}
interface

uses
  Floria.CSS.AST, Floria.CSS.Parser, Floria.CSS.Tokenizer, Floria.CSS.Types, 
  Floria.X11.KeySym, Floria.XCB.Cursor, Floria.XCB.EWMH, Floria.XCB.ICCCM, 
  Floria.XCB.Keysyms, Floria.XCB, Floria.XCB.RandR, Floria.XCB.Render, 
  Floria.XCB.Shape, Floria.XCB.SHM, Floria.XCB.XFixes, LazarusPackageIntf;

implementation

procedure Register;
begin
end;

initialization
  RegisterPackage('florialib', @Register);
end.
