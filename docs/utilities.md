# Compression & Hashing Utilities

`florialib` includes pure Pascal compression and hashing units used by the PNG,
Zlib, Gzip, and SVGZ paths. They are usable independently of the graphics stack.

---

## 1. Compression (`Floria.Compression.*`)

| Unit | Purpose |
|---|---|
| [`Floria.Compression.BitStream`](../src/main/pascal/floria.compression.bitstream.pas) | LSB/MSB bit readers and writers, byte alignment, bit reversal |
| [`Floria.Compression.Huffman`](../src/main/pascal/floria.compression.huffman.pas) | Canonical Huffman tree construction and decoding |
| [`Floria.Compression.Deflate`](../src/main/pascal/floria.compression.deflate.pas) | Raw Deflate inflate/deflate, streaming variants |
| [`Floria.Compression.Zlib`](../src/main/pascal/floria.compression.zlib.pas) | RFC 1950 Zlib wrapper with Adler-32 verification |
| [`Floria.Compression.Gzip`](../src/main/pascal/floria.compression.gzip.pas) | RFC 1952 Gzip wrapper and gzip detection |
| [`Floria.Compression.CRC`](../src/main/pascal/floria.compression.crc.pas) | Compatibility forwarder; new code should use `Floria.Hash.CRC` and `Floria.Hash.Adler` |

### Deflate

```pascal
uses
  Floria.Compression.Deflate;

var
  Compressed: TBytes;
  Restored: TBytes;
begin
  Compressed := Deflate(@Data[0], Length(Data));
  Restored := Inflate(@Compressed[0], Length(Compressed), Length(Data));
end;
```

Streaming versions are available as `DeflateStream` / `InflateStream`. The
optional `Level` parameter uses `TFloriaCompressionLevel`
(`fclNone`, `fclFast`, `fclDefault`, `fclMax`).

### Zlib

```pascal
uses
  Floria.Compression.Zlib;

Compressed := ZlibCompress(@Data[0], Length(Data));
Restored := ZlibDecompress(@Compressed[0], Length(Compressed));
```

Zlib validates the header and the Adler-32 checksum; corrupt data raises an
exception rather than returning partial output.

### Gzip

```pascal
uses
  Floria.Compression.Gzip;

if IsGzip(@Data[0], Length(Data)) then
  Restored := GzipDecompress(@Data[0], Length(Data));
```

Gzip is used by the SVG parser to transparently read `.svgz` input.

### Bit-level helpers

`TBitReaderLSB`, `TBitReaderMSB`, `TBitWriterLSB`, and `TBitWriterMSB` are
record types. `Init` the reader/writer, call `ReadBits`/`WriteBits`, and use
`AlignToByte` when switching between bit and byte streams.

---

## 2. Hashing (`Floria.Hash.*`)

| Unit | Algorithms |
|---|---|
| [`Floria.Hash.CRC`](../src/main/pascal/floria.hash.crc.pas) | CRC-16, CRC-32, CRC-64, incremental `Update*` variants, stream helpers |
| [`Floria.Hash.Adler`](../src/main/pascal/floria.hash.adler.pas) | Adler-32 and streaming/incremental variants |
| [`Floria.Hash.FNV`](../src/main/pascal/floria.hash.fnv.pas) | FNV-1a 32-bit and 64-bit, string/stream helpers |
| [`Floria.Hash.Murmur`](../src/main/pascal/floria.hash.murmur.pas) | MurmurHash3 32-bit, 64-bit, and 128-bit; `THash128` |

Examples:

```pascal
uses
  Floria.Hash.CRC,
  Floria.Hash.Adler,
  Floria.Hash.FNV,
  Floria.Hash.Murmur;

Crc := CRC32(@Buffer[0], Length(Buffer));
Adler := Adler32(@Buffer[0], Length(Buffer));
Fnv := FNV1a_64(@Buffer[0], Length(Buffer));
H128 := MurmurHash3_128(@Buffer[0], Length(Buffer), 0);
```

`Crc` and `Adler` are `Cardinal`, `Fnv` is `QWord`, and `H128` is a `THash128`
record. Use `H128.ToString()` for a hexadecimal representation.

The `*Stream` helpers accept a `TStream` and an optional byte count
(`-1` means read to the end). The `*Str` helpers operate on `AnsiString`.

---

## 3. Compatibility note

`Floria.Compression.CRC` exists only to keep older imports working. It forwards
to `Floria.Hash.CRC` and `Floria.Hash.Adler`; use those units in new code.

---

## 4. Tests

`src/test/pascal/floria.compression.test.pas` and
`src/test/pascal/floria.hash.test.pas` cover known vectors, round-trips, stream
helpers, and corruption handling. Run them with:

```bash
pasbuild test -p pic
```
