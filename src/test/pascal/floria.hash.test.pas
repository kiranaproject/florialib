unit Floria.Hash.Test;

// Floria.Hash.Test
// ================
// Comprehensive unit tests for Floria.Hash.*:
//   - CRC32, CRC16, CRC64 standard test vectors and chunking
//   - Adler32 RFC 1950 test vectors
//   - FNV-1a 32-bit and 64-bit standard test vectors
//   - MurmurHash3 32-bit and 128-bit consistency, avalanche, and tail processing

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Floria.Hash.CRC,
  Floria.Hash.Adler,
  Floria.Hash.FNV,
  Floria.Hash.Murmur;

type
  TFloriaHashTest = class(TTestCase)
  published
    // CRC tests
    procedure TestCRC32TestVectors();
    procedure TestCRC16TestVectors();
    procedure TestCRC64TestVectors();
    procedure TestCRCChunking();

    // Adler tests
    procedure TestAdler32TestVectors();
    procedure TestAdler32Chunking();

    // FNV-1a tests
    procedure TestFNV1a_32TestVectors();
    procedure TestFNV1a_64TestVectors();
    procedure TestFNV1aStringOverloads();

    // MurmurHash3 tests
    procedure TestMurmurHash3_32Basics();
    procedure TestMurmurHash3_32TailHandling();
    procedure TestMurmurHash3_128Basics();
    procedure TestMurmurHash3_64Basics();
    procedure TestMurmurHash3Avalanche();
  end;

implementation

// ---------------------------------------------------------------------------
// CRC tests
// ---------------------------------------------------------------------------

procedure TFloriaHashTest.TestCRC32TestVectors();
var
  S: AnsiString;
begin
  AssertEquals('CRC32 empty is 0', Cardinal(0), CRC32(nil, 0));
  AssertEquals('CRC32Str empty is 0', Cardinal(0), CRC32Str(''));

  S := '123456789';
  AssertEquals('CRC32("123456789")', Cardinal($CBF43926), CRC32(PAnsiChar(S), Length(S)));
  AssertEquals('CRC32Str("123456789")', Cardinal($CBF43926), CRC32Str(S));
end;

procedure TFloriaHashTest.TestCRC16TestVectors();
var
  S: AnsiString;
  C16: Word;
begin
  AssertEquals('CRC16 empty is 0', Word(0), CRC16(nil, 0));

  S := '123456789';
  C16 := CRC16(PAnsiChar(S), Length(S));
  AssertTrue('CRC16 non-zero on test vector', C16 <> 0);
  AssertEquals('CRC16("123456789")', Word($BB3D), C16);
end;

procedure TFloriaHashTest.TestCRC64TestVectors();
var
  S: AnsiString;
  C64: QWord;
begin
  AssertEquals('CRC64 empty is 0', QWord(0), CRC64(nil, 0));

  S := '123456789';
  C64 := CRC64(PAnsiChar(S), Length(S));
  AssertEquals('CRC64 ECMA-182 ("123456789")', QWord($995DC9BBDF1939FA), C64);
end;

procedure TFloriaHashTest.TestCRCChunking();
var
  Data: array[0..999] of Byte;
  I: Integer;
  FullCRC32, ChunkedCRC32: Cardinal;
  FullCRC64, ChunkedCRC64: QWord;
begin
  for I := 0 to High(Data) do Data[I] := Byte(I mod 253);

  FullCRC32 := CRC32(@Data[0], Length(Data));
  ChunkedCRC32 := UpdateCRC32(0, @Data[0], 500);
  ChunkedCRC32 := UpdateCRC32(ChunkedCRC32, @Data[500], 500);
  AssertEquals('CRC32 chunking matches full', FullCRC32, ChunkedCRC32);

  FullCRC64 := CRC64(@Data[0], Length(Data));
  ChunkedCRC64 := UpdateCRC64(0, @Data[0], 500);
  ChunkedCRC64 := UpdateCRC64(ChunkedCRC64, @Data[500], 500);
  AssertEquals('CRC64 chunking matches full', FullCRC64, ChunkedCRC64);
end;

// ---------------------------------------------------------------------------
// Adler tests
// ---------------------------------------------------------------------------

procedure TFloriaHashTest.TestAdler32TestVectors();
var
  S: AnsiString;
begin
  AssertEquals('Adler32 empty is 1', Cardinal(1), Adler32(nil, 0));
  AssertEquals('Adler32Str empty is 1', Cardinal(1), Adler32Str(''));

  S := '123456789';
  AssertEquals('Adler32("123456789")', Cardinal($091E01DE), Adler32(PAnsiChar(S), Length(S)));
  AssertEquals('Adler32Str("123456789")', Cardinal($091E01DE), Adler32Str(S));

  S := 'Wikipedia';
  AssertEquals('Adler32("Wikipedia")', Cardinal($11E60398), Adler32(PAnsiChar(S), Length(S)));
end;

procedure TFloriaHashTest.TestAdler32Chunking();
var
  Data: array[0..999] of Byte;
  I: Integer;
  FullAdler, ChunkedAdler: Cardinal;
begin
  for I := 0 to High(Data) do Data[I] := Byte(I mod 251);

  FullAdler := Adler32(@Data[0], Length(Data));
  ChunkedAdler := UpdateAdler32(1, @Data[0], 500);
  ChunkedAdler := UpdateAdler32(ChunkedAdler, @Data[500], 500);
  AssertEquals('Adler32 chunking matches full', FullAdler, ChunkedAdler);
end;

// ---------------------------------------------------------------------------
// FNV-1a tests
// ---------------------------------------------------------------------------

procedure TFloriaHashTest.TestFNV1a_32TestVectors();
var
  S: AnsiString;
begin
  // FNV-1a standard test vectors
  AssertEquals('FNV-1a 32 empty', FNV1A_32_INIT, FNV1a_32(nil, 0));
  AssertEquals('FNV-1a 32 empty string', FNV1A_32_INIT, FNV1a_32Str(''));

  S := 'a';
  AssertEquals('FNV-1a 32 ("a")', Cardinal($E40C292C), FNV1a_32Str(S));

  S := 'foobar';
  AssertEquals('FNV-1a 32 ("foobar")', Cardinal($BF9CF968), FNV1a_32Str(S));
end;

procedure TFloriaHashTest.TestFNV1a_64TestVectors();
var
  S: AnsiString;
begin
  // FNV-1a 64-bit standard test vectors
  AssertEquals('FNV-1a 64 empty', FNV1A_64_INIT, FNV1a_64(nil, 0));
  AssertEquals('FNV-1a 64 empty string', FNV1A_64_INIT, FNV1a_64Str(''));

  S := 'a';
  AssertEquals('FNV-1a 64 ("a")', QWord($AF63DC4C8601EC8C), FNV1a_64Str(S));

  S := 'foobar';
  AssertEquals('FNV-1a 64 ("foobar")', QWord($85944171F73967E8), FNV1a_64Str(S));
end;

procedure TFloriaHashTest.TestFNV1aStringOverloads();
var
  H1, H2: Cardinal;
  Q1, Q2: QWord;
begin
  // Distinct strings produce distinct hashes
  H1 := FNV1a_32Str('background-color');
  H2 := FNV1a_32Str('border-radius');
  AssertTrue('Different CSS properties have different 32-bit hashes', H1 <> H2);

  Q1 := FNV1a_64Str('background-color');
  Q2 := FNV1a_64Str('border-radius');
  AssertTrue('Different CSS properties have different 64-bit hashes', Q1 <> Q2);
end;

// ---------------------------------------------------------------------------
// MurmurHash3 tests
// ---------------------------------------------------------------------------

procedure TFloriaHashTest.TestMurmurHash3_32Basics();
var
  H1, H2: Cardinal;
begin
  H1 := MurmurHash3_32Str('The quick brown fox jumps over the lazy dog', 0);
  H2 := MurmurHash3_32Str('The quick brown fox jumps over the lazy dog', 1);

  AssertTrue('MurmurHash3 non-zero', H1 <> 0);
  AssertTrue('Different seeds produce different hashes', H1 <> H2);

  // Reproducibility
  AssertEquals('MurmurHash3 deterministic', H1, MurmurHash3_32Str('The quick brown fox jumps over the lazy dog', 0));
end;

procedure TFloriaHashTest.TestMurmurHash3_32TailHandling();
var
  H1, H2, H3, H4: Cardinal;
begin
  // Test lengths with 1, 2, 3, 4 bytes to exercise tail branches
  H1 := MurmurHash3_32Str('A');
  H2 := MurmurHash3_32Str('AB');
  H3 := MurmurHash3_32Str('ABC');
  H4 := MurmurHash3_32Str('ABCD');

  AssertTrue('Tail 1 non-zero', H1 <> 0);
  AssertTrue('Tail 2 non-zero', H2 <> 0);
  AssertTrue('Tail 3 non-zero', H3 <> 0);
  AssertTrue('Tail 4 non-zero', H4 <> 0);

  AssertTrue('All tail hashes distinct (1 vs 2)', H1 <> H2);
  AssertTrue('All tail hashes distinct (2 vs 3)', H2 <> H3);
  AssertTrue('All tail hashes distinct (3 vs 4)', H3 <> H4);
end;

procedure TFloriaHashTest.TestMurmurHash3_128Basics();
var
  H: THash128;
  HexStr: string;
begin
  H := MurmurHash3_128Str('Floria Toolkit Skia-Parity Vector Engine', 42);
  AssertTrue('128-bit hash Low non-zero', H.Low <> 0);
  AssertTrue('128-bit hash High non-zero', H.High <> 0);

  HexStr := H.ToString();
  AssertEquals('128-bit hex string length is 32 chars', 32, Length(HexStr));
end;

procedure TFloriaHashTest.TestMurmurHash3_64Basics();
var
  H1, H2: QWord;
begin
  H1 := MurmurHash3_64Str('widget.button.normal');
  H2 := MurmurHash3_64Str('widget.button.pressed');

  AssertTrue('64-bit hash non-zero', H1 <> 0);
  AssertTrue('Different states produce different 64-bit hashes', H1 <> H2);
end;

procedure TFloriaHashTest.TestMurmurHash3Avalanche();
var
  H1, H2: Cardinal;
  DiffBits, DiffCount, I: Integer;
begin
  // Flipping a single character in the input should flip many bits in the 32-bit hash
  H1 := MurmurHash3_32Str('SampleStringA');
  H2 := MurmurHash3_32Str('SampleStringB');

  DiffBits := Integer(H1 xor H2);
  DiffCount := 0;
  for I := 0 to 31 do
    if (DiffBits and (1 shl I)) <> 0 then
      Inc(DiffCount);

  // Good avalanche typically flips 10 to 22 bits out of 32
  AssertTrue(Format('Avalanche flips at least 8 bits: got %d', [DiffCount]), DiffCount >= 8);
end;

initialization
  RegisterTest(TFloriaHashTest);

end.
