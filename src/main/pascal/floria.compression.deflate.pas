unit Floria.Compression.Deflate;

// Floria.Compression.Deflate
// ==========================
// Full RFC 1951 Deflate compression and decompression (Inflate) engine.
// Pure Object Pascal, zero external dependencies.
//
// Features:
//   - Inflate: Full RFC 1951 decompressor supporting stored blocks,
//     fixed Huffman codes, dynamic Huffman trees, and LZ77 backward references.
//   - Deflate: RFC 1951 compressor supporting uncompressed blocks (fclNone)
//     and LZ77 match finder with fixed Huffman encoding (fclFast, fclDefault, fclMax).
//   - Stream and memory buffer APIs.

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Math,
  Floria.Compression.BitStream,
  Floria.Compression.Huffman;

type
  // Compression level
  TFloriaCompressionLevel = (
    fclNone,    // Stored uncompressed blocks (fastest, no CPU load)
    fclFast,    // Fast LZ77 (short hash chain search)
    fclDefault, // Balanced LZ77 (standard 32-entry search)
    fclMax      // Maximum LZ77 (deep 128-entry search)
  );

// Memory buffer decompression and compression
function Inflate(const ACompressedData: Pointer; const ACompressedSize: Integer; const AExpectedSize: Integer = 0): TBytes;
function Deflate(const AData: Pointer; const ASize: Integer; const Level: TFloriaCompressionLevel = fclDefault): TBytes;

// Stream decompression and compression
procedure InflateStream(AInStream, AOutStream: TStream; const AExpectedSize: Integer = 0);
procedure DeflateStream(AInStream, AOutStream: TStream; const Level: TFloriaCompressionLevel = fclDefault);

implementation

const
  LENS_ORDER: array[0..18] of Integer = (16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15);
  LENGTH_BASE: array[0..28] of Integer = (3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258);
  LENGTH_EXTRA: array[0..28] of Integer = (0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0);
  DIST_BASE: array[0..29] of Integer = (1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577);
  DIST_EXTRA: array[0..29] of Integer = (0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13);

  WINDOW_SIZE = 32768;
  HASH_SIZE   = 32768;
  HASH_MASK   = 32767;

// ---------------------------------------------------------------------------
// Inflate (RFC 1951 Decompressor)
// ---------------------------------------------------------------------------

function Inflate(const ACompressedData: Pointer; const ACompressedSize: Integer; const AExpectedSize: Integer = 0): TBytes;
var
  BR: TBitReaderLSB;
  IsFinal: Integer;
  BType: Integer;
  Len, NLen, I: Integer;
  HLit, HDist, HCLen: Integer;
  CodeLengths: array[0..18] of Integer;
  TreeCL: THuffmanTree;
  TreeLit, TreeDist: THuffmanTree;
  AllLengths: array of Integer;
  Sym, RepCount: Integer;
  MatchLen, MatchDist: Integer;
  DstPos, DstCap: Integer;
  SrcOffset: Integer;
  FixedLitTree, FixedDistTree: THuffmanTree;

  procedure EnsureCapacity(const Additional: Integer);
  begin
    if DstPos + Additional > DstCap then
    begin
      DstCap := Max(DstCap * 2, DstPos + Additional + 4096);
      SetLength(Result, DstCap);
    end;
  end;

begin
  if (ACompressedData = nil) or (ACompressedSize <= 0) then
  begin
    SetLength(Result, 0);
    Exit;
  end;

  BR.Init(ACompressedData, ACompressedSize);

  if AExpectedSize > 0 then
    DstCap := AExpectedSize
  else
    DstCap := ACompressedSize * 4;
  if DstCap < 1024 then DstCap := 1024;
  SetLength(Result, DstCap);
  DstPos := 0;

  FixedLitTree := GetFixedLiteralTree();
  FixedDistTree := GetFixedDistanceTree();

  repeat
    IsFinal := BR.ReadBit();
    BType := BR.ReadBits(2);

    case BType of
      0: // Stored uncompressed block
        begin
          BR.AlignToByte();
          Len := BR.ReadBits(16);
          NLen := BR.ReadBits(16);
          if (Len xor NLen) <> $FFFF then
            raise Exception.Create('Deflate uncompressed block length mismatch');

          EnsureCapacity(Len);
          for I := 0 to Len - 1 do
            Result[DstPos + I] := Byte(BR.ReadBits(8));
          Inc(DstPos, Len);
        end;

      1, 2: // Huffman block
        begin
          if BType = 1 then
          begin
            TreeLit := FixedLitTree;
            TreeDist := FixedDistTree;
          end
          else
          begin
            HLit := BR.ReadBits(5) + 257;
            HDist := BR.ReadBits(5) + 1;
            HCLen := BR.ReadBits(4) + 4;

            FillChar(CodeLengths, SizeOf(CodeLengths), 0);
            for I := 0 to HCLen - 1 do
              CodeLengths[LENS_ORDER[I]] := BR.ReadBits(3);

            TreeCL.Build(CodeLengths, 19);

            SetLength(AllLengths, HLit + HDist);
            I := 0;
            while I < HLit + HDist do
            begin
              Sym := TreeCL.DecodeLSB(BR);
              if Sym < 16 then
              begin
                AllLengths[I] := Sym;
                Inc(I);
              end
              else if Sym = 16 then
              begin
                RepCount := BR.ReadBits(2) + 3;
                if I = 0 then raise Exception.Create('Invalid repeat code in Deflate dynamic Huffman header');
                while (RepCount > 0) and (I < HLit + HDist) do
                begin
                  AllLengths[I] := AllLengths[I - 1];
                  Inc(I);
                  Dec(RepCount);
                end;
              end
              else if Sym = 17 then
              begin
                RepCount := BR.ReadBits(3) + 3;
                while (RepCount > 0) and (I < HLit + HDist) do
                begin
                  AllLengths[I] := 0;
                  Inc(I);
                  Dec(RepCount);
                end;
              end
              else if Sym = 18 then
              begin
                RepCount := BR.ReadBits(7) + 11;
                while (RepCount > 0) and (I < HLit + HDist) do
                begin
                  AllLengths[I] := 0;
                  Inc(I);
                  Dec(RepCount);
                end;
              end
              else
                raise Exception.Create('Invalid symbol in Deflate dynamic code lengths');
            end;

            TreeLit.Build(Slice(AllLengths, HLit), HLit);
            TreeDist.Build(Copy(AllLengths, HLit, HDist), HDist);
          end;

          // Decode compressed data
          while True do
          begin
            Sym := TreeLit.DecodeLSB(BR);
            if Sym < 0 then
              raise Exception.Create('Corrupted Deflate Huffman stream');

            if Sym < 256 then
            begin
              EnsureCapacity(1);
              Result[DstPos] := Byte(Sym);
              Inc(DstPos);
            end
            else if Sym = 256 then
              Break // End of block
            else
            begin
              Dec(Sym, 257);
              if (Sym < 0) or (Sym > 28) then
                raise Exception.Create('Invalid Deflate length symbol');
              MatchLen := LENGTH_BASE[Sym];
              if LENGTH_EXTRA[Sym] > 0 then
                Inc(MatchLen, BR.ReadBits(LENGTH_EXTRA[Sym]));

              Sym := TreeDist.DecodeLSB(BR);
              if (Sym < 0) or (Sym > 29) then
                raise Exception.Create('Invalid Deflate distance symbol');
              MatchDist := DIST_BASE[Sym];
              if DIST_EXTRA[Sym] > 0 then
                Inc(MatchDist, BR.ReadBits(DIST_EXTRA[Sym]));

              if MatchDist > DstPos then
                raise Exception.Create('Deflate backward distance exceeds buffer boundary');

              EnsureCapacity(MatchLen);
              SrcOffset := DstPos - MatchDist;
              for I := 0 to MatchLen - 1 do
                Result[DstPos + I] := Result[SrcOffset + I];
              Inc(DstPos, MatchLen);
            end;
          end;
        end;
    else
      raise Exception.Create('Reserved Deflate block type (3)');
    end;
  until IsFinal <> 0;

  SetLength(Result, DstPos);
end;

procedure InflateStream(AInStream, AOutStream: TStream; const AExpectedSize: Integer = 0);
var
  InBuf: TBytes;
  OutBuf: TBytes;
  InSize: Integer;
begin
  if (AInStream = nil) or (AOutStream = nil) then Exit;
  InSize := AInStream.Size - AInStream.Position;
  if InSize <= 0 then Exit;
  SetLength(InBuf, InSize);
  AInStream.ReadBuffer(InBuf[0], InSize);

  OutBuf := Inflate(@InBuf[0], InSize, AExpectedSize);
  if Length(OutBuf) > 0 then
    AOutStream.WriteBuffer(OutBuf[0], Length(OutBuf));
end;

// ---------------------------------------------------------------------------
// Deflate (RFC 1951 Compressor)
// ---------------------------------------------------------------------------

function GetLengthCode(const L: Integer; out ExtraBits, ExtraValue: Integer): Integer; inline;
var
  I: Integer;
begin
  for I := 28 downto 0 do
  begin
    if L >= LENGTH_BASE[I] then
    begin
      Result := 257 + I;
      ExtraBits := LENGTH_EXTRA[I];
      ExtraValue := L - LENGTH_BASE[I];
      Exit;
    end;
  end;
  Result := 257;
  ExtraBits := 0;
  ExtraValue := 0;
end;

function GetDistanceCode(const D: Integer; out ExtraBits, ExtraValue: Integer): Integer; inline;
var
  I: Integer;
begin
  for I := 29 downto 0 do
  begin
    if D >= DIST_BASE[I] then
    begin
      Result := I;
      ExtraBits := DIST_EXTRA[I];
      ExtraValue := D - DIST_BASE[I];
      Exit;
    end;
  end;
  Result := 0;
  ExtraBits := 0;
  ExtraValue := 0;
end;

function Deflate(const AData: Pointer; const ASize: Integer; const Level: TFloriaCompressionLevel = fclDefault): TBytes;
var
  BW: TBitWriterLSB;
  FixedLitTree, FixedDistTree: THuffmanTree;
  Head: array[0..HASH_SIZE - 1] of Integer;
  Prev: array of Integer;
  PData: PByte;
  CurPos: Integer;
  Hash: Integer;
  MatchPos, BestPos, BestLen, CurLen: Integer;
  ChainLen, MaxChain: Integer;
  LenCode, DistCode: Integer;
  ExtraBits, ExtraVal: Integer;
  Remaining, ChunkSize: Integer;
  WordLen, WordNLen: Word;
  I: Integer;
begin
  if (AData = nil) or (ASize <= 0) then
  begin
    // Empty Deflate stream: 1 final stored block of 0 bytes
    BW.Init();
    try
      BW.WriteBits(1, 1); // BFINAL = 1
      BW.WriteBits(0, 2); // BTYPE = 00
      BW.AlignToByte();
      WordLen := 0;
      WordNLen := $FFFF;
      BW.Stream.WriteBuffer(WordLen, 2);
      BW.Stream.WriteBuffer(WordNLen, 2);
      Result := BW.ToBytes();
    finally
      BW.Done();
    end;
    Exit;
  end;

  BW.Init();
  try
    PData := PByte(AData);

    if Level = fclNone then
    begin
      // Stored uncompressed blocks (BTYPE 00)
      Remaining := ASize;
      CurPos := 0;
      while Remaining > 0 do
      begin
        ChunkSize := Remaining;
        if ChunkSize > 65535 then ChunkSize := 65535;

        if Remaining = ChunkSize then
          BW.WriteBits(1, 1) // BFINAL = 1
        else
          BW.WriteBits(0, 1); // BFINAL = 0

        BW.WriteBits(0, 2); // BTYPE = 00
        BW.AlignToByte();

        WordLen := Word(ChunkSize);
        WordNLen := not WordLen;
        BW.Stream.WriteBuffer(WordLen, 2);
        BW.Stream.WriteBuffer(WordNLen, 2);

        BW.Stream.WriteBuffer((PData + CurPos)^, ChunkSize);
        Inc(CurPos, ChunkSize);
        Dec(Remaining, ChunkSize);
      end;
      Result := BW.ToBytes();
      Exit;
    end;

    // Compressed with Fixed Huffman codes (BTYPE 01) + LZ77 match finder
    FixedLitTree := GetFixedLiteralTree();
    FixedDistTree := GetFixedDistanceTree();

    case Level of
      fclFast:    MaxChain := 4;
      fclDefault: MaxChain := 32;
      fclMax:     MaxChain := 128;
    else
      MaxChain := 32;
    end;

    // Initialize hash table
    for I := 0 to HASH_SIZE - 1 do
      Head[I] := -1;
    SetLength(Prev, ASize);

    // Emit block header
    BW.WriteBits(1, 1); // BFINAL = 1 (single compressed block)
    BW.WriteBits(1, 2); // BTYPE = 01 (fixed Huffman)

    CurPos := 0;
    while CurPos < ASize do
    begin
      BestLen := 0;
      BestPos := -1;

      // Find LZ77 match if at least 3 bytes remain
      if CurPos + 2 < ASize then
      begin
        Hash := ((Integer(PData[CurPos]) shl 10) xor
                 (Integer(PData[CurPos + 1]) shl 5) xor
                  Integer(PData[CurPos + 2])) and HASH_MASK;

        MatchPos := Head[Hash];
        Head[Hash] := CurPos;
        Prev[CurPos] := MatchPos;

        ChainLen := 0;
        while (MatchPos >= 0) and (CurPos - MatchPos <= WINDOW_SIZE) and (ChainLen < MaxChain) do
        begin
          if (PData[MatchPos] = PData[CurPos]) and
             (PData[MatchPos + BestLen] = PData[CurPos + BestLen]) then
          begin
            CurLen := 0;
            while (CurPos + CurLen < ASize) and (CurLen < 258) and
                  (PData[MatchPos + CurLen] = PData[CurPos + CurLen]) do
              Inc(CurLen);

            if CurLen > BestLen then
            begin
              BestLen := CurLen;
              BestPos := MatchPos;
              if BestLen >= 258 then Break;
            end;
          end;

          MatchPos := Prev[MatchPos];
          Inc(ChainLen);
        end;
      end;

      if BestLen >= 3 then
      begin
        // Emit length code
        LenCode := GetLengthCode(BestLen, ExtraBits, ExtraVal);
        BW.WriteBits(FixedLitTree.Codes[LenCode], FixedLitTree.Lengths[LenCode]);
        if ExtraBits > 0 then
          BW.WriteBits(Cardinal(ExtraVal), ExtraBits);

        // Emit distance code
        DistCode := GetDistanceCode(CurPos - BestPos, ExtraBits, ExtraVal);
        BW.WriteBits(FixedDistTree.Codes[DistCode], FixedDistTree.Lengths[DistCode]);
        if ExtraBits > 0 then
          BW.WriteBits(Cardinal(ExtraVal), ExtraBits);

        // Insert skipped positions into hash table
        for I := 1 to BestLen - 1 do
        begin
          if CurPos + I + 2 < ASize then
          begin
            Hash := ((Integer(PData[CurPos + I]) shl 10) xor
                     (Integer(PData[CurPos + I + 1]) shl 5) xor
                      Integer(PData[CurPos + I + 2])) and HASH_MASK;
            Prev[CurPos + I] := Head[Hash];
            Head[Hash] := CurPos + I;
          end;
        end;

        Inc(CurPos, BestLen);
      end
      else
      begin
        // Emit literal byte
        BW.WriteBits(FixedLitTree.Codes[PData[CurPos]], FixedLitTree.Lengths[PData[CurPos]]);
        Inc(CurPos);
      end;
    end;

    // End-of-block symbol (256)
    BW.WriteBits(FixedLitTree.Codes[256], FixedLitTree.Lengths[256]);
    BW.AlignToByte();

    Result := BW.ToBytes();
  finally
    BW.Done();
  end;
end;

procedure DeflateStream(AInStream, AOutStream: TStream; const Level: TFloriaCompressionLevel = fclDefault);
var
  InBuf: TBytes;
  OutBuf: TBytes;
  InSize: Integer;
begin
  if (AInStream = nil) or (AOutStream = nil) then Exit;
  InSize := AInStream.Size - AInStream.Position;
  if InSize <= 0 then Exit;
  SetLength(InBuf, InSize);
  AInStream.ReadBuffer(InBuf[0], InSize);

  OutBuf := Deflate(@InBuf[0], InSize, Level);
  if Length(OutBuf) > 0 then
    AOutStream.WriteBuffer(OutBuf[0], Length(OutBuf));
end;

end.
