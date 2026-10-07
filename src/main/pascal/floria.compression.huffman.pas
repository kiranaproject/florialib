unit Floria.Compression.Huffman;

// Floria.Compression.Huffman
// ==========================
// Canonical Huffman tree construction, decoding, and encoding tables.
// Conforms to RFC 1951 canonical Huffman code generation rules.

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils,
  Floria.Compression.BitStream;

const
  MAX_BITS    = 16;
  MAX_SYMBOLS = 320;

type
  THuffmanTree = record
    Counts : array[0..MAX_BITS] of Integer;
    Symbols: array[0..MAX_SYMBOLS] of Integer;
    Offsets: array[0..MAX_BITS] of Integer;
    Codes  : array[0..MAX_SYMBOLS] of Word; // Bit-reversed codes for LSB writing
    Lengths: array[0..MAX_SYMBOLS] of Byte;
    procedure Build(const BitLengths: array of Integer; const Count: Integer);
    function DecodeLSB(var BR: TBitReaderLSB): Integer;
    function DecodeMSB(var BR: TBitReaderMSB): Integer;
  end;

// Precomputed RFC 1951 Fixed Huffman Trees
function GetFixedLiteralTree(): THuffmanTree;
function GetFixedDistanceTree(): THuffmanTree;

implementation

procedure THuffmanTree.Build(const BitLengths: array of Integer; const Count: Integer);
var
  I, Len, Code: Integer;
  CodeCount: array[0..MAX_BITS] of Integer;
  NextCode: array[0..MAX_BITS] of Integer;
begin
  FillChar(Counts, SizeOf(Counts), 0);
  FillChar(Symbols, SizeOf(Symbols), 0);
  FillChar(Offsets, SizeOf(Offsets), 0);
  FillChar(Codes, SizeOf(Codes), 0);
  FillChar(Lengths, SizeOf(Lengths), 0);
  FillChar(CodeCount, SizeOf(CodeCount), 0);

  // 1. Count number of codes for each bit length
  for I := 0 to Count - 1 do
  begin
    Len := BitLengths[I];
    if (Len > 0) and (Len <= MAX_BITS) then
    begin
      Inc(CodeCount[Len]);
      Lengths[I] := Byte(Len);
    end;
  end;

  // 2. Offsets for symbol mapping
  Offsets[1] := 0;
  for I := 1 to MAX_BITS - 1 do
    Offsets[I + 1] := Offsets[I] + CodeCount[I];

  for I := 0 to Count - 1 do
  begin
    Len := BitLengths[I];
    if (Len > 0) and (Len <= MAX_BITS) then
    begin
      Symbols[Offsets[Len]] := I;
      Inc(Offsets[Len]);
    end;
  end;

  // 3. Rebuild offsets for fast decoding
  Offsets[0] := 0;
  for I := 1 to MAX_BITS do
  begin
    Counts[I] := CodeCount[I];
    Offsets[I] := Offsets[I - 1] + CodeCount[I - 1];
  end;

  // 4. Generate canonical codes for encoding (RFC 1951 Section 3.2.2)
  Code := 0;
  NextCode[0] := 0;
  for Len := 1 to MAX_BITS do
  begin
    Code := (Code + CodeCount[Len - 1]) shl 1;
    NextCode[Len] := Code;
  end;

  for I := 0 to Count - 1 do
  begin
    Len := BitLengths[I];
    if Len > 0 then
    begin
      // Store bit-reversed code for instant emission into LSB-first bitstream
      Codes[I] := Word(ReverseBits(Cardinal(NextCode[Len]), Len));
      Inc(NextCode[Len]);
    end;
  end;
end;

function THuffmanTree.DecodeLSB(var BR: TBitReaderLSB): Integer;
var
  Code: Integer;
  Len: Integer;
  Count: Integer;
begin
  Code := 0;
  for Len := 1 to MAX_BITS do
  begin
    Code := (Code shl 1) or BR.ReadBits(1);
    Count := Counts[Len];
    if Code < Count then
    begin
      Result := Symbols[Offsets[Len] + Code];
      Exit;
    end;
    Code := Code - Count;
  end;
  Result := -1; // Decode error
end;

function THuffmanTree.DecodeMSB(var BR: TBitReaderMSB): Integer;
var
  Code: Integer;
  Len: Integer;
  Count: Integer;
begin
  Code := 0;
  for Len := 1 to MAX_BITS do
  begin
    Code := (Code shl 1) or BR.ReadBits(1);
    Count := Counts[Len];
    if Code < Count then
    begin
      Result := Symbols[Offsets[Len] + Code];
      Exit;
    end;
    Code := Code - Count;
  end;
  Result := -1; // Decode error
end;

var
  GFixedLitReady: Boolean = False;
  GFixedLitTree : THuffmanTree;
  GFixedDistReady: Boolean = False;
  GFixedDistTree : THuffmanTree;

function GetFixedLiteralTree(): THuffmanTree;
var
  Lengths: array[0..287] of Integer;
  I: Integer;
begin
  if not GFixedLitReady then
  begin
    for I := 0 to 143 do Lengths[I] := 8;
    for I := 144 to 255 do Lengths[I] := 9;
    for I := 256 to 279 do Lengths[I] := 7;
    for I := 280 to 287 do Lengths[I] := 8;
    GFixedLitTree.Build(Lengths, 288);
    GFixedLitReady := True;
  end;
  Result := GFixedLitTree;
end;

function GetFixedDistanceTree(): THuffmanTree;
var
  Lengths: array[0..31] of Integer;
  I: Integer;
begin
  if not GFixedDistReady then
  begin
    for I := 0 to 31 do Lengths[I] := 5;
    GFixedDistTree.Build(Lengths, 32);
    GFixedDistReady := True;
  end;
  Result := GFixedDistTree;
end;

end.
