unit Floria.Path.Golden.Data;

// Floria.Path.Golden.Data
// =======================
// GENERATED FILE - do not edit by hand.
//
// Frozen expected results for the path-engine regression corpus, captured
// from the reference implementation (clipper2) before it was removed.
// Regenerate with tools/pathgolden while a reference backend still exists.
//
// Each row records the total absolute area and the bounds of the result.
// Area is the primary invariant. Bounds are only meaningful when area is
// non-zero, and catch translated or clipped geometry that happens to
// preserve area.
//
// ContourCount is recorded for diagnostics but is NOT asserted: backends
// may legitimately differ in how they split zero-area remnants, and the
// reference engine sometimes returns a degenerate contour where a
// first-party engine returns none.

{$mode objfpc}{$H+}

interface

type
  TGoldenResult = record
    Name        : string;
    Area        : Double;
    ContourCount: Integer;
    Left        : Double;
    Top         : Double;
    Right       : Double;
    Bottom      : Double;
  end;

const
  GOLDEN_COUNT = 33;

// Returns the recorded result for AName. Raises if the name is unknown, so a
// renamed or removed corpus case fails loudly instead of silently skipping.
function GoldenResult(const AName: string): TGoldenResult;

implementation

uses
  SysUtils,
  Floria.Path.Engine;

const
  GOLDEN: array[0..GOLDEN_COUNT - 1] of TGoldenResult = (
    (Name: 'bool.union.overlap'; Area: 15000.0; ContourCount: 1; Left: 0.0; Top: 0.0; Right: 150.0; Bottom: 100.0),
    (Name: 'bool.difference.overlap'; Area: 5000.0; ContourCount: 1; Left: 0.0; Top: 0.0; Right: 50.0; Bottom: 100.0),
    (Name: 'bool.intersect.overlap'; Area: 5000.0; ContourCount: 1; Left: 50.0; Top: 0.0; Right: 100.0; Bottom: 100.0),
    (Name: 'bool.xor.overlap'; Area: 10000.0; ContourCount: 2; Left: 0.0; Top: 0.0; Right: 150.0; Bottom: 100.0),
    (Name: 'bool.union.disjoint'; Area: 20000.0; ContourCount: 2; Left: 0.0; Top: 0.0; Right: 300.0; Bottom: 100.0),
    (Name: 'bool.intersect.disjoint'; Area: 0.0; ContourCount: 0; Left: 0.0; Top: 0.0; Right: 0.0; Bottom: 0.0),
    (Name: 'bool.union.nested'; Area: 10000.0; ContourCount: 1; Left: 0.0; Top: 0.0; Right: 100.0; Bottom: 100.0),
    (Name: 'bool.difference.nested'; Area: 7500.0; ContourCount: 2; Left: 0.0; Top: 0.0; Right: 100.0; Bottom: 100.0),
    (Name: 'bool.intersect.nested'; Area: 2500.0; ContourCount: 1; Left: 25.0; Top: 25.0; Right: 75.0; Bottom: 75.0),
    (Name: 'bool.union.identical'; Area: 10000.0; ContourCount: 1; Left: 0.0; Top: 0.0; Right: 100.0; Bottom: 100.0),
    (Name: 'bool.intersect.identical'; Area: 10000.0; ContourCount: 1; Left: 0.0; Top: 0.0; Right: 100.0; Bottom: 100.0),
    (Name: 'bool.difference.identical'; Area: 0.0; ContourCount: 0; Left: 0.0; Top: 0.0; Right: 0.0; Bottom: 0.0),
    (Name: 'bool.union.triangle-square'; Area: 6250.0; ContourCount: 1; Left: 0.0; Top: 0.0; Right: 100.0; Bottom: 100.0),
    (Name: 'bool.intersect.triangle-square'; Area: 3750.0; ContourCount: 1; Left: 0.0; Top: 0.0; Right: 100.0; Bottom: 50.0),
    (Name: 'bool.difference.triangle-square'; Area: 1250.0; ContourCount: 1; Left: 25.0; Top: 50.0; Right: 75.0; Bottom: 100.0),
    (Name: 'bool.xor.triangle-square'; Area: 2500.0; ContourCount: 3; Left: 0.0; Top: 0.0; Right: 100.0; Bottom: 100.0),
    (Name: 'bool.union.collinear'; Area: 20000.0; ContourCount: 1; Left: 0.0; Top: 0.0; Right: 200.0; Bottom: 100.0),
    (Name: 'bool.union.corner-touch'; Area: 20000.0; ContourCount: 2; Left: 0.0; Top: 0.0; Right: 200.0; Bottom: 200.0),
    (Name: 'bool.intersect.corner-touch'; Area: 0.0; ContourCount: 0; Left: 0.0; Top: 0.0; Right: 0.0; Bottom: 0.0),
    (Name: 'bool.selfunion.nonzero'; Area: 10000.0; ContourCount: 1; Left: 0.0; Top: 0.0; Right: 100.0; Bottom: 100.0),
    (Name: 'bool.selfunion.evenodd'; Area: 7500.0; ContourCount: 2; Left: 0.0; Top: 0.0; Right: 100.0; Bottom: 100.0),
    (Name: 'offset.inflate.miter'; Area: 12100.0; ContourCount: 1; Left: -5.0; Top: -5.0; Right: 105.0; Bottom: 105.0),
    (Name: 'offset.inflate.bevel'; Area: 12050.0; ContourCount: 1; Left: -5.0; Top: -5.0; Right: 105.0; Bottom: 105.0),
    (Name: 'offset.inflate.square'; Area: 12082.8302; ContourCount: 1; Left: -5.0; Top: -5.0; Right: 105.0; Bottom: 105.0),
    (Name: 'offset.inflate.round'; Area: 12078.292; ContourCount: 1; Left: -5.0; Top: -5.0; Right: 105.0; Bottom: 105.0),
    (Name: 'offset.deflate.miter'; Area: 6400.0; ContourCount: 1; Left: 10.0; Top: 10.0; Right: 90.0; Bottom: 90.0),
    (Name: 'offset.deflate.deep'; Area: 2500.0; ContourCount: 1; Left: 25.0; Top: 25.0; Right: 75.0; Bottom: 75.0),
    (Name: 'offset.deflate.collapse'; Area: 0.0; ContourCount: 0; Left: 0.0; Top: 0.0; Right: 0.0; Bottom: 0.0),
    (Name: 'offset.stroke.butt'; Area: 1000.0; ContourCount: 1; Left: 0.0; Top: -5.0; Right: 100.0; Bottom: 5.0),
    (Name: 'offset.stroke.square'; Area: 1100.0; ContourCount: 1; Left: -5.0; Top: -5.0; Right: 105.0; Bottom: 5.0),
    (Name: 'offset.stroke.round'; Area: 1078.3022; ContourCount: 1; Left: -4.99; Top: -5.0; Right: 104.99; Bottom: 5.0),
    (Name: 'simplify.closed-collinear'; Area: 5000.0; ContourCount: 1; Left: 0.0; Top: 0.0; Right: 100.0; Bottom: 50.0),
    (Name: 'simplify.open-line'; Area: 0.0; ContourCount: 0; Left: 0.0; Top: 0.0; Right: 0.0; Bottom: 0.0)
  );

function GoldenResult(const AName: string): TGoldenResult;
var
  I: Integer;
begin
  for I := 0 to High(GOLDEN) do
    if GOLDEN[I].Name = AName then
      Exit(GOLDEN[I]);

  raise EPathEngineError.CreateFmt('no golden result recorded for "%s"', [AName]);
end;

end.
