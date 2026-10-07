unit Floria.Compression.Test;

// Floria.Compression.Test
// =======================
// Comprehensive unit tests for Floria.Compression.*:
//   - CRC32 and Adler32 checksums (standard test vectors)
//   - TBitReaderLSB, TBitReaderMSB, and TBitWriterLSB
//   - Canonical Huffman tree generation and decoding
//   - RFC 1951 Deflate and Inflate roundtrip across all compression levels
//   - RFC 1950 Zlib container compression and decompression
//   - RFC 1952 Gzip container compression and decompression

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Floria.Compression.CRC,
  Floria.Compression.BitStream,
  Floria.Compression.Huffman,
  Floria.Compression.Deflate,
  Floria.Compression.Zlib,
  Floria.Compression.Gzip;

type
  TFloriaCompressionTest = class(TTestCase)
  published
    // Checksum tests
    procedure TestCRC32TestVectors();
    procedure TestAdler32TestVectors();
    procedure TestChunkedChecksums();

    // Bitstream tests
    procedure TestBitStreamLSBRoundTrip();
    procedure TestBitStreamMSBReading();
    procedure TestBitReversal();

    // Huffman tests
    procedure TestCanonicalHuffmanTree();
    procedure TestFixedHuffmanTrees();

    // Deflate / Inflate tests
    procedure TestDeflateInflateEmpty();
    procedure TestDeflateInflateShortString();
    procedure TestDeflateInflateRepetitiveData();
    procedure TestDeflateInflateBinaryData();
    procedure TestDeflateStoredBlockLevelNone();
    procedure TestDeflateCompressionLevels();

    // Zlib container tests
    procedure TestZlibRoundTrip();
    procedure TestZlibHeaderValidation();
    procedure TestZlibStreamRoundTrip();

    // Gzip container tests
    procedure TestGzipDetection();
    procedure TestGzipRoundTrip();
    procedure TestGzipStreamRoundTrip();
  end;

implementation

// ---------------------------------------------------------------------------
// Checksum tests
// ---------------------------------------------------------------------------

procedure TFloriaCompressionTest.TestCRC32TestVectors();
var
  S: AnsiString;
  CRC: Cardinal;
begin
  // Empty data CRC is $00000000
  AssertEquals('CRC32 of empty is 0', Cardinal(0), CRC32(nil, 0));

  // Standard test vector: "123456789" -> $CBF43926
  S := '123456789';
  CRC := CRC32(PAnsiChar(S), Length(S));
  AssertEquals('CRC32("123456789")', Cardinal($CBF43926), CRC);
end;

procedure TFloriaCompressionTest.TestAdler32TestVectors();
var
  S: AnsiString;
  Adler: Cardinal;
begin
  // Empty data Adler32 is 1
  AssertEquals('Adler32 of empty is 1', Cardinal(1), Adler32(nil, 0));

  // Standard test vector: "123456789" -> $091E01DE
  S := '123456789';
  Adler := Adler32(PAnsiChar(S), Length(S));
  AssertEquals('Adler32("123456789")', Cardinal($091E01DE), Adler);

  // Test vector: "Wikipedia" -> $11E60398
  S := 'Wikipedia';
  Adler := Adler32(PAnsiChar(S), Length(S));
  AssertEquals('Adler32("Wikipedia")', Cardinal($11E60398), Adler);
end;

procedure TFloriaCompressionTest.TestChunkedChecksums();
var
  Data: array[0..9999] of Byte;
  I: Integer;
  FullCRC, ChunkedCRC: Cardinal;
  FullAdler, ChunkedAdler: Cardinal;
begin
  for I := 0 to High(Data) do
    Data[I] := Byte(I mod 251);

  FullCRC := CRC32(@Data[0], Length(Data));
  ChunkedCRC := UpdateCRC32(0, @Data[0], 5000);
  ChunkedCRC := UpdateCRC32(ChunkedCRC, @Data[5000], 5000);
  AssertEquals('Chunked CRC matches full CRC', FullCRC, ChunkedCRC);

  FullAdler := Adler32(@Data[0], Length(Data));
  ChunkedAdler := UpdateAdler32(1, @Data[0], 5000);
  ChunkedAdler := UpdateAdler32(ChunkedAdler, @Data[5000], 5000);
  AssertEquals('Chunked Adler matches full Adler', FullAdler, ChunkedAdler);
end;

// ---------------------------------------------------------------------------
// Bitstream tests
// ---------------------------------------------------------------------------

procedure TFloriaCompressionTest.TestBitStreamLSBRoundTrip();
var
  BW: TBitWriterLSB;
  BR: TBitReaderLSB;
  Bytes: TBytes;
begin
  BW.Init();
  try
    BW.WriteBits(5, 3);    // 101_2
    BW.WriteBits(12, 4);   // 1100_2
    BW.WriteBit(1);        // 1_2 (total 8 bits = 1 byte)
    BW.WriteBits($A5, 8);  // 10100101_2
    BW.WriteBits(7, 3);    // 111_2
    Bytes := BW.ToBytes();
  finally
    BW.Done();
  end;

  BR.Init(@Bytes[0], Length(Bytes));
  AssertEquals('Read 3 bits', 5, BR.ReadBits(3));
  AssertEquals('Read 4 bits', 12, BR.ReadBits(4));
  AssertEquals('Read 1 bit', 1, BR.ReadBit());
  AssertEquals('Read 8 bits', $A5, BR.ReadBits(8));
  AssertEquals('Read 3 bits', 7, BR.ReadBits(3));
end;

procedure TFloriaCompressionTest.TestBitStreamMSBReading();
var
  Data: array[0..1] of Byte;
  BR: TBitReaderMSB;
begin
  Data[0] := %10110000;
  Data[1] := %11110001;

  BR.Init(@Data[0], 2);
  AssertEquals('Read top 4 bits', %1011, BR.ReadBits(4));
  AssertEquals('Read next 4 bits', %0000, BR.ReadBits(4));
  AssertEquals('Read next 8 bits', %11110001, BR.ReadBits(8));
end;

procedure TFloriaCompressionTest.TestBitReversal();
begin
  AssertEquals('Reverse 3 bits: 100 -> 001', Cardinal(1), ReverseBits(4, 3));
  AssertEquals('Reverse 4 bits: 1100 -> 0011', Cardinal(3), ReverseBits(12, 4));
  AssertEquals('Reverse 8 bits: $80 -> $01', Cardinal(1), ReverseBits($80, 8));
  AssertEquals('Reverse 8 bits: $01 -> $80', Cardinal($80), ReverseBits($01, 8));
end;

// ---------------------------------------------------------------------------
// Huffman tests
// ---------------------------------------------------------------------------

procedure TFloriaCompressionTest.TestCanonicalHuffmanTree();
var
  Tree: THuffmanTree;
  Lengths: array[0..3] of Integer;
  BW: TBitWriterLSB;
  BR: TBitReaderLSB;
  Bytes: TBytes;
  Sym: Integer;
begin
  // 4 symbols with lengths: A=1, B=2, C=3, D=3
  Lengths[0] := 1;
  Lengths[1] := 2;
  Lengths[2] := 3;
  Lengths[3] := 3;

  Tree.Build(Lengths, 4);

  // Encode symbols 0, 1, 2, 3
  BW.Init();
  try
    BW.WriteBits(Tree.Codes[0], Tree.Lengths[0]);
    BW.WriteBits(Tree.Codes[1], Tree.Lengths[1]);
    BW.WriteBits(Tree.Codes[2], Tree.Lengths[2]);
    BW.WriteBits(Tree.Codes[3], Tree.Lengths[3]);
    Bytes := BW.ToBytes();
  finally
    BW.Done();
  end;

  // Decode back
  BR.Init(@Bytes[0], Length(Bytes));
  Sym := Tree.DecodeLSB(BR);
  AssertEquals('Decoded symbol 0', 0, Sym);
  Sym := Tree.DecodeLSB(BR);
  AssertEquals('Decoded symbol 1', 1, Sym);
  Sym := Tree.DecodeLSB(BR);
  AssertEquals('Decoded symbol 2', 2, Sym);
  Sym := Tree.DecodeLSB(BR);
  AssertEquals('Decoded symbol 3', 3, Sym);
end;

procedure TFloriaCompressionTest.TestFixedHuffmanTrees();
var
  LitTree, DistTree: THuffmanTree;
begin
  LitTree := GetFixedLiteralTree();
  DistTree := GetFixedDistanceTree();

  AssertEquals('Lit tree symbol 0 length', 8, LitTree.Lengths[0]);
  AssertEquals('Lit tree symbol 144 length', 9, LitTree.Lengths[144]);
  AssertEquals('Lit tree symbol 256 length', 7, LitTree.Lengths[256]);
  AssertEquals('Lit tree symbol 280 length', 8, LitTree.Lengths[280]);

  AssertEquals('Dist tree symbol 0 length', 5, DistTree.Lengths[0]);
  AssertEquals('Dist tree symbol 31 length', 5, DistTree.Lengths[31]);
end;

// ---------------------------------------------------------------------------
// Deflate / Inflate tests
// ---------------------------------------------------------------------------

procedure TFloriaCompressionTest.TestDeflateInflateEmpty();
var
  Compressed, Decompressed: TBytes;
begin
  Compressed := Deflate(nil, 0);
  AssertTrue('Empty deflate produces valid block', Length(Compressed) > 0);

  Decompressed := Inflate(@Compressed[0], Length(Compressed));
  AssertEquals('Empty decompressed length is 0', 0, Length(Decompressed));
end;

procedure TFloriaCompressionTest.TestDeflateInflateShortString();
var
  Original: AnsiString;
  Compressed, Decompressed: TBytes;
  ResultStr: AnsiString;
begin
  Original := 'Hello, Floria Graphics Engine!';
  Compressed := Deflate(PAnsiChar(Original), Length(Original), fclDefault);
  Decompressed := Inflate(@Compressed[0], Length(Compressed));

  SetString(ResultStr, PAnsiChar(@Decompressed[0]), Length(Decompressed));
  AssertEquals('Decompressed string matches original', string(Original), string(ResultStr));
end;

procedure TFloriaCompressionTest.TestDeflateInflateRepetitiveData();
var
  RepPattern: AnsiString;
  InputData: AnsiString;
  Compressed, Decompressed: TBytes;
  I: Integer;
begin
  RepPattern := 'Pure Object Pascal Floria Graphics Pipeline WebRender Impeller Skia Parity. ';
  InputData := '';
  for I := 1 to 50 do
    InputData := InputData + RepPattern;

  Compressed := Deflate(PAnsiChar(InputData), Length(InputData), fclDefault);

  // Highly repetitive data should achieve significant compression (< 25% of original size)
  AssertTrue(Format('Repetitive data compressed: %d bytes -> %d bytes', [Length(InputData), Length(Compressed)]),
    Length(Compressed) < (Length(InputData) div 4));

  Decompressed := Inflate(@Compressed[0], Length(Compressed));
  AssertEquals('Decompressed size matches', Length(InputData), Length(Decompressed));
  AssertTrue('Decompressed bytes match original',
    CompareMem(PAnsiChar(InputData), @Decompressed[0], Length(InputData)));
end;

procedure TFloriaCompressionTest.TestDeflateInflateBinaryData();
var
  Data: array[0..4095] of Byte;
  I: Integer;
  Compressed, Decompressed: TBytes;
begin
  for I := 0 to High(Data) do
    Data[I] := Byte((I * 17 + 31) and $FF);

  Compressed := Deflate(@Data[0], Length(Data), fclDefault);
  Decompressed := Inflate(@Compressed[0], Length(Compressed));

  AssertEquals('Binary decompressed length', Length(Data), Length(Decompressed));
  AssertTrue('Binary content matches', CompareMem(@Data[0], @Decompressed[0], Length(Data)));
end;

procedure TFloriaCompressionTest.TestDeflateStoredBlockLevelNone();
var
  Data: array[0..255] of Byte;
  I: Integer;
  Compressed, Decompressed: TBytes;
begin
  for I := 0 to High(Data) do Data[I] := Byte(I);

  Compressed := Deflate(@Data[0], Length(Data), fclNone);
  Decompressed := Inflate(@Compressed[0], Length(Compressed));

  AssertEquals('Stored block decompressed length', Length(Data), Length(Decompressed));
  AssertTrue('Stored block content matches', CompareMem(@Data[0], @Decompressed[0], Length(Data)));
end;

procedure TFloriaCompressionTest.TestDeflateCompressionLevels();
var
  Original: AnsiString;
  CompFast, CompDef, CompMax: TBytes;
  DecFast, DecDef, DecMax: TBytes;
  I: Integer;
begin
  Original := '';
  for I := 1 to 100 do
    Original := Original + Format('Line %d: The quick brown fox jumps over the lazy dog. ', [I]);

  CompFast := Deflate(PAnsiChar(Original), Length(Original), fclFast);
  CompDef := Deflate(PAnsiChar(Original), Length(Original), fclDefault);
  CompMax := Deflate(PAnsiChar(Original), Length(Original), fclMax);

  AssertTrue('Fast produces compressed output', Length(CompFast) < Length(Original));
  AssertTrue('Default produces compressed output', Length(CompDef) < Length(Original));
  AssertTrue('Max produces compressed output', Length(CompMax) < Length(Original));

  DecFast := Inflate(@CompFast[0], Length(CompFast));
  DecDef := Inflate(@CompDef[0], Length(CompDef));
  DecMax := Inflate(@CompMax[0], Length(CompMax));

  AssertTrue('DecFast matches', CompareMem(PAnsiChar(Original), @DecFast[0], Length(Original)));
  AssertTrue('DecDef matches', CompareMem(PAnsiChar(Original), @DecDef[0], Length(Original)));
  AssertTrue('DecMax matches', CompareMem(PAnsiChar(Original), @DecMax[0], Length(Original)));
end;

// ---------------------------------------------------------------------------
// Zlib container tests
// ---------------------------------------------------------------------------

procedure TFloriaCompressionTest.TestZlibRoundTrip();
var
  Data: AnsiString;
  Compressed, Decompressed: TBytes;
begin
  Data := 'Testing RFC 1950 Zlib container with Floria.Compression.Zlib!';
  Compressed := ZlibCompress(PAnsiChar(Data), Length(Data), fclDefault);

  // Check CMF ($78) and FLG checksum
  AssertEquals('Zlib CMF is $78', Byte($78), Compressed[0]);
  AssertTrue('Zlib header checksum (CMF*256 + FLG) mod 31 = 0',
    ((Integer(Compressed[0]) * 256 + Integer(Compressed[1])) mod 31) = 0);

  Decompressed := ZlibDecompress(@Compressed[0], Length(Compressed));
  AssertEquals('Zlib decompressed length', Length(Data), Length(Decompressed));
  AssertTrue('Zlib decompressed content matches',
    CompareMem(PAnsiChar(Data), @Decompressed[0], Length(Data)));
end;

procedure TFloriaCompressionTest.TestZlibHeaderValidation();
var
  BogusData: array[0..7] of Byte;
  Caught: Boolean;
begin
  // Corrupt header checksum
  BogusData[0] := $78;
  BogusData[1] := $99; // Invalid FLG checksum
  FillChar(BogusData[2], 6, 0);

  Caught := False;
  try
    ZlibDecompress(@BogusData[0], 8);
  except
    Caught := True;
  end;
  AssertTrue('Invalid Zlib header throws exception', Caught);
end;

procedure TFloriaCompressionTest.TestZlibStreamRoundTrip();
var
  InStream, CompStream, OutStream: TMemoryStream;
  TestData: AnsiString;
  ResultData: AnsiString;
begin
  TestData := 'Stream-based Zlib compression test payload with multiple repeated words words words.';
  InStream := TMemoryStream.Create();
  CompStream := TMemoryStream.Create();
  OutStream := TMemoryStream.Create();
  try
    InStream.WriteBuffer(PAnsiChar(TestData)^, Length(TestData));
    InStream.Position := 0;

    ZlibCompressStream(InStream, CompStream);
    CompStream.Position := 0;

    ZlibDecompressStream(CompStream, OutStream);

    SetLength(ResultData, OutStream.Size);
    if OutStream.Size > 0 then
      Move(OutStream.Memory^, ResultData[1], OutStream.Size);

    AssertEquals('Stream Zlib result matches', string(TestData), string(ResultData));
  finally
    InStream.Free();
    CompStream.Free();
    OutStream.Free();
  end;
end;

// ---------------------------------------------------------------------------
// Gzip container tests
// ---------------------------------------------------------------------------

procedure TFloriaCompressionTest.TestGzipDetection();
var
  Data: AnsiString;
  GzBytes: TBytes;
begin
  Data := 'Sample XML content <svg width="100" height="100"></svg>';
  GzBytes := GzipCompress(PAnsiChar(Data), Length(Data));

  AssertTrue('IsGzip detects valid Gzip buffer', IsGzip(@GzBytes[0], Length(GzBytes)));
  AssertFalse('IsGzip rejects raw text', IsGzip(PAnsiChar(Data), Length(Data)));
end;

procedure TFloriaCompressionTest.TestGzipRoundTrip();
var
  Original: AnsiString;
  Compressed, Decompressed: TBytes;
begin
  Original := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><circle cx="50" cy="50" r="40"/></svg>';
  Compressed := GzipCompress(PAnsiChar(Original), Length(Original), fclDefault);

  AssertTrue('Gzip compressed has valid header', IsGzip(@Compressed[0], Length(Compressed)));

  Decompressed := GzipDecompress(@Compressed[0], Length(Compressed));
  AssertEquals('Gzip decompressed size matches', Length(Original), Length(Decompressed));
  AssertTrue('Gzip decompressed content matches',
    CompareMem(PAnsiChar(Original), @Decompressed[0], Length(Original)));
end;

procedure TFloriaCompressionTest.TestGzipStreamRoundTrip();
var
  InStream, CompStream, OutStream: TMemoryStream;
  TestData: AnsiString;
  ResultData: AnsiString;
begin
  TestData := '<svg><rect x="0" y="0" width="200" height="100" fill="red"/></svg>';
  InStream := TMemoryStream.Create();
  CompStream := TMemoryStream.Create();
  OutStream := TMemoryStream.Create();
  try
    InStream.WriteBuffer(PAnsiChar(TestData)^, Length(TestData));
    InStream.Position := 0;

    GzipCompressStream(InStream, CompStream);
    CompStream.Position := 0;

    AssertTrue('IsGzipStream detects stream', IsGzipStream(CompStream));

    GzipDecompressStream(CompStream, OutStream);

    SetLength(ResultData, OutStream.Size);
    if OutStream.Size > 0 then
      Move(OutStream.Memory^, ResultData[1], OutStream.Size);

    AssertEquals('Stream Gzip result matches', string(TestData), string(ResultData));
  finally
    InStream.Free();
    CompStream.Free();
    OutStream.Free();
  end;
end;

initialization
  RegisterTest(TFloriaCompressionTest);

end.
