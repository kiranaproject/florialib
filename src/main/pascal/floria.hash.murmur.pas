unit Floria.Hash.Murmur;

// Floria.Hash.Murmur
// ==================
// Austin Appleby's MurmurHash3 (32-bit and 128-bit) implementations.
// Excellent distribution, avalanche characteristics, and throughput.
// Ideal for graphics caches (shader PSOs, glyph cache keys, display lists).
//
// Pure Object Pascal, zero dependencies.

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils;

type
  // 128-bit hash value record
  THash128 = record
    Low: QWord;
    High: QWord;
    function ToString(): string;
    class function Create(const ALow, AHigh: QWord): THash128; static;
  end;

// MurmurHash3 32-bit
function MurmurHash3_32(const ABuffer: Pointer; const ALength: Cardinal; const ASeed: Cardinal = 0): Cardinal;
function MurmurHash3_32Str(const S: AnsiString; const ASeed: Cardinal = 0): Cardinal; inline;

// MurmurHash3 128-bit (x64 optimized)
function MurmurHash3_128(const ABuffer: Pointer; const ALength: Cardinal; const ASeed: Cardinal = 0): THash128;
function MurmurHash3_128Str(const S: AnsiString; const ASeed: Cardinal = 0): THash128; inline;

// Fast 64-bit hash derived from MurmurHash3
function MurmurHash3_64(const ABuffer: Pointer; const ALength: Cardinal; const ASeed: Cardinal = 0): QWord; inline;
function MurmurHash3_64Str(const S: AnsiString; const ASeed: Cardinal = 0): QWord; inline;

implementation

class function THash128.Create(const ALow, AHigh: QWord): THash128;
begin
  Result.Low := ALow;
  Result.High := AHigh;
end;

function THash128.ToString(): string;
begin
  Result := Format('%016X%016X', [High, Low]);
end;

function RotL32(const X: Cardinal; const R: Byte): Cardinal; inline;
begin
  Result := (X shl R) or (X shr (32 - R));
end;

function RotL64(const X: QWord; const R: Byte): QWord; inline;
begin
  Result := (X shl R) or (X shr (64 - R));
end;

function FMix32(H: Cardinal): Cardinal; inline;
begin
  H := H xor (H shr 16);
  H := H * $85EBCA6B;
  H := H xor (H shr 13);
  H := H * $C2B2AE35;
  H := H xor (H shr 16);
  Result := H;
end;

function FMix64(K: QWord): QWord; inline;
begin
  K := K xor (K shr 33);
  K := K * $FF51AFD7ED558CCD;
  K := K xor (K shr 33);
  K := K * $C4CEB9FE1A85EC53;
  K := K xor (K shr 33);
  Result := K;
end;

// ---------------------------------------------------------------------------
// MurmurHash3 32-bit
// ---------------------------------------------------------------------------

function MurmurHash3_32(const ABuffer: Pointer; const ALength: Cardinal; const ASeed: Cardinal = 0): Cardinal;
const
  C1 = $CC9E2D51;
  C2 = $1B873593;
var
  H, K1: Cardinal;
  NBlocks, I: Integer;
  Blocks: PCardinal;
  Tail: PByte;
begin
  H := ASeed;
  if (ABuffer = nil) or (ALength = 0) then Exit(FMix32(H));

  NBlocks := Integer(ALength div 4);
  Blocks := PCardinal(ABuffer);

  for I := 0 to NBlocks - 1 do
  begin
    K1 := Blocks^;
    Inc(Blocks);

    K1 := K1 * C1;
    K1 := RotL32(K1, 15);
    K1 := K1 * C2;

    H := H xor K1;
    H := RotL32(H, 13);
    H := H * 5 + $E6546B64;
  end;

  // Tail
  Tail := PByte(ABuffer) + NBlocks * 4;
  K1 := 0;

  case ALength and 3 of
    3:
      begin
        K1 := K1 xor (Cardinal(Tail[2]) shl 16);
        K1 := K1 xor (Cardinal(Tail[1]) shl 8);
        K1 := K1 xor Cardinal(Tail[0]);
        K1 := K1 * C1;
        K1 := RotL32(K1, 15);
        K1 := K1 * C2;
        H := H xor K1;
      end;
    2:
      begin
        K1 := K1 xor (Cardinal(Tail[1]) shl 8);
        K1 := K1 xor Cardinal(Tail[0]);
        K1 := K1 * C1;
        K1 := RotL32(K1, 15);
        K1 := K1 * C2;
        H := H xor K1;
      end;
    1:
      begin
        K1 := K1 xor Cardinal(Tail[0]);
        K1 := K1 * C1;
        K1 := RotL32(K1, 15);
        K1 := K1 * C2;
        H := H xor K1;
      end;
  end;

  // Finalization
  H := H xor ALength;
  Result := FMix32(H);
end;

function MurmurHash3_32Str(const S: AnsiString; const ASeed: Cardinal = 0): Cardinal;
begin
  if Length(S) = 0 then
    Result := FMix32(ASeed)
  else
    Result := MurmurHash3_32(PAnsiChar(S), Length(S), ASeed);
end;

// ---------------------------------------------------------------------------
// MurmurHash3 128-bit (x64)
// ---------------------------------------------------------------------------

function MurmurHash3_128(const ABuffer: Pointer; const ALength: Cardinal; const ASeed: Cardinal = 0): THash128;
const
  C1: QWord = $87C37B91114253D5;
  C2: QWord = $4CF5AD432745937F;
var
  H1, H2: QWord;
  K1, K2: QWord;
  NBlocks, I: Integer;
  Blocks: PQWord;
  Tail: PByte;
begin
  H1 := ASeed;
  H2 := ASeed;

  if (ABuffer = nil) or (ALength = 0) then
  begin
    H1 := FMix64(H1);
    H2 := FMix64(H2);
    H1 := H1 + H2;
    H2 := H2 + H1;
    Result.Low := H1;
    Result.High := H2;
    Exit;
  end;

  NBlocks := Integer(ALength div 16);
  Blocks := PQWord(ABuffer);

  for I := 0 to NBlocks - 1 do
  begin
    K1 := Blocks^; Inc(Blocks);
    K2 := Blocks^; Inc(Blocks);

    K1 := K1 * C1; K1 := RotL64(K1, 31); K1 := K1 * C2; H1 := H1 xor K1;
    H1 := RotL64(H1, 27); H1 := H1 + H2; H1 := H1 * 5 + $52DCE729;

    K2 := K2 * C2; K2 := RotL64(K2, 33); K2 := K2 * C1; H2 := H2 xor K2;
    H2 := RotL64(H2, 31); H2 := H2 + H1; H2 := H2 * 5 + $38495AB5;
  end;

  Tail := PByte(ABuffer) + NBlocks * 16;
  K1 := 0;
  K2 := 0;

  case ALength and 15 of
    15: K2 := K2 xor (QWord(Tail[14]) shl 48);
    14: K2 := K2 xor (QWord(Tail[13]) shl 40);
    13: K2 := K2 xor (QWord(Tail[12]) shl 32);
    12: K2 := K2 xor (QWord(Tail[11]) shl 24);
    11: K2 := K2 xor (QWord(Tail[10]) shl 16);
    10: K2 := K2 xor (QWord(Tail[9]) shl 8);
    9:
      begin
        K2 := K2 xor QWord(Tail[8]);
        K2 := K2 * C2; K2 := RotL64(K2, 33); K2 := K2 * C1; H2 := H2 xor K2;
      end;
    8: K1 := K1 xor (QWord(Tail[7]) shl 56);
    7: K1 := K1 xor (QWord(Tail[6]) shl 48);
    6: K1 := K1 xor (QWord(Tail[5]) shl 40);
    5: K1 := K1 xor (QWord(Tail[4]) shl 32);
    4: K1 := K1 xor (QWord(Tail[3]) shl 24);
    3: K1 := K1 xor (QWord(Tail[2]) shl 16);
    2: K1 := K1 xor (QWord(Tail[1]) shl 8);
    1:
      begin
        K1 := K1 xor QWord(Tail[0]);
        K1 := K1 * C1; K1 := RotL64(K1, 31); K1 := K1 * C2; H1 := H1 xor K1;
      end;
  end;

  H1 := H1 xor ALength;
  H2 := H2 xor ALength;

  H1 := H1 + H2;
  H2 := H2 + H1;

  H1 := FMix64(H1);
  H2 := FMix64(H2);

  H1 := H1 + H2;
  H2 := H2 + H1;

  Result.Low := H1;
  Result.High := H2;
end;

function MurmurHash3_128Str(const S: AnsiString; const ASeed: Cardinal = 0): THash128;
begin
  if Length(S) = 0 then
    Result := MurmurHash3_128(nil, 0, ASeed)
  else
    Result := MurmurHash3_128(PAnsiChar(S), Length(S), ASeed);
end;

function MurmurHash3_64(const ABuffer: Pointer; const ALength: Cardinal; const ASeed: Cardinal = 0): QWord;
begin
  Result := MurmurHash3_128(ABuffer, ALength, ASeed).Low;
end;

function MurmurHash3_64Str(const S: AnsiString; const ASeed: Cardinal = 0): QWord;
begin
  Result := MurmurHash3_128Str(S, ASeed).Low;
end;

end.
