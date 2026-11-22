unit Floria.Image.GIF;

// Floria.Image.GIF
// ================
// Pure Object Pascal GIF87a and GIF89a decoder with multi-frame animation support.
// Handles LZW decompression, interlacing, Global/Local Color Tables,
// Graphic Control Extensions (delays, transparency, disposal methods),
// and Netscape Application Extensions (loop counts).
//
// Zero external dependencies.

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils,
  Floria.Image.Core;

type
  TFloriaGIFReader = class(TFloriaAnimatedReader)
  public
    class function CanRead(AStream: TStream): Boolean; override;
    class function CanReadAnimation(AStream: TStream): Boolean; override;
    class function Format(): TFloriaImageFormat; override;
    procedure ReadImage(AStream: TStream; AImage: TFloriaImage); override;
    procedure ReadAnimation(AStream: TStream; AAnim: TFloriaAnimatedImage); override;
  end;

implementation

const
  GIF_SIG_87A: array[0..5] of AnsiChar = ('G','I','F','8','7','a');
  GIF_SIG_89A: array[0..5] of AnsiChar = ('G','I','F','8','9','a');

type
  TGIFColor = packed record
    R, G, B: Byte;
  end;
  TGIFPalette = array[0..255] of TGIFColor;

  TGIFBitReader = record
    Stream: TStream;
    BlockLen: Byte;
    BlockPos: Byte;
    BlockBuf: array[0..255] of Byte;
    BitBuf: Cardinal;
    BitCount: Integer;
    EOFReached: Boolean;
    procedure Init(AStream: TStream);
    function ReadBits(NBits: Integer; out Value: Integer): Boolean;
    procedure SkipSubBlocks();
  end;

procedure TGIFBitReader.Init(AStream: TStream);
begin
  Stream := AStream;
  BlockLen := 0;
  BlockPos := 0;
  BitBuf := 0;
  BitCount := 0;
  EOFReached := False;
end;

function TGIFBitReader.ReadBits(NBits: Integer; out Value: Integer): Boolean;
var
  b: Byte;
begin
  Value := 0;
  while BitCount < NBits do
  begin
    if BlockPos >= BlockLen then
    begin
      if Stream.Read(BlockLen, 1) <> 1 then
      begin
        EOFReached := True;
        Exit(False);
      end;
      if BlockLen = 0 then
      begin
        EOFReached := True;
        Exit(False);
      end;
      if Stream.Read(BlockBuf[0], BlockLen) <> BlockLen then
      begin
        EOFReached := True;
        Exit(False);
      end;
      BlockPos := 0;
    end;
    b := BlockBuf[BlockPos];
    Inc(BlockPos);
    BitBuf := BitBuf or (Cardinal(b) shl BitCount);
    Inc(BitCount, 8);
  end;

  Value := BitBuf and ((1 shl NBits) - 1);
  BitBuf := BitBuf shr NBits;
  Dec(BitCount, NBits);
  Result := True;
end;

procedure TGIFBitReader.SkipSubBlocks();
var
  subLen: Byte;
begin
  while Stream.Position < Stream.Size do
  begin
    if Stream.Read(subLen, 1) <> 1 then Break;
    if subLen = 0 then Break;
    Stream.Seek(subLen, soFromCurrent);
  end;
end;

procedure SkipSubBlocksStream(AStream: TStream);
var
  subLen: Byte;
begin
  while AStream.Position < AStream.Size do
  begin
    if AStream.Read(subLen, 1) <> 1 then Break;
    if subLen = 0 then Break;
    AStream.Seek(subLen, soFromCurrent);
  end;
end;

function DecodeGIFImage(AStream: TStream;
                        const GlobalPalette: TGIFPalette;
                        const HasGlobalPalette: Boolean;
                        const TransparentColorIndex: Integer;
                        const HasTransparency: Boolean;
                        out FrameLeft, FrameTop, FrameW, FrameH: Integer): TFloriaImage;
var
  PackedByte, MinCodeSize: Byte;
  LocalPalette: TGIFPalette;
  ActivePalette: TGIFPalette;
  HasLocalPalette, IsInterlaced: Boolean;
  LCTCount, i: Integer;
  BitReader: TGIFBitReader;
  Prefix: array[0..4095] of Integer;
  Suffix: array[0..4095] of Byte;
  Stack: array[0..4095] of Byte;
  StackPtr: Integer;
  ClearCode, EOICode, AvailCode, CodeSize, CodeMask: Integer;
  Code, OldCode, CurCode, FirstChar: Integer;
  PixelCount, TotalPixels: Integer;
  CurX, CurY, Pass: Integer;
  W16, H16, L16, T16: Word;
const
  PASS_START: array[0..3] of Integer = (0, 4, 2, 1);
  PASS_INC: array[0..3] of Integer   = (8, 8, 4, 2);

  procedure OutputPixel(const ColorIdx: Byte);
  var
    PixelCol: TBgraPixel;
  begin
    if (CurX >= 0) and (CurX < FrameW) and (CurY >= 0) and (CurY < FrameH) then
    begin
      if HasTransparency and (ColorIdx = TransparentColorIndex) then
        PixelCol := TBgraPixel.Create(0, 0, 0, 0)
      else
        PixelCol := TBgraPixel.Create(ActivePalette[ColorIdx].R, ActivePalette[ColorIdx].G, ActivePalette[ColorIdx].B, 255);
      Result.Pixels[CurX, CurY] := PixelCol;
    end;

    Inc(PixelCount);
    Inc(CurX);
    if CurX >= FrameW then
    begin
      CurX := 0;
      if IsInterlaced then
      begin
        CurY := CurY + PASS_INC[Pass];
        if (CurY >= FrameH) and (Pass < 3) then
        begin
          Inc(Pass);
          CurY := PASS_START[Pass];
        end;
      end
      else
        Inc(CurY);
    end;
  end;

begin
  Result := nil;
  FrameLeft := 0;
  FrameTop := 0;
  FrameW := 0;
  FrameH := 0;

  if AStream.Read(L16, 2) <> 2 then Exit;
  if AStream.Read(T16, 2) <> 2 then Exit;
  if AStream.Read(W16, 2) <> 2 then Exit;
  if AStream.Read(H16, 2) <> 2 then Exit;
  if AStream.Read(PackedByte, 1) <> 1 then Exit;

  FrameLeft := LEtoN(L16);
  FrameTop := LEtoN(T16);
  FrameW := LEtoN(W16);
  FrameH := LEtoN(H16);

  HasLocalPalette := (PackedByte and $80) <> 0;
  IsInterlaced := (PackedByte and $40) <> 0;

  if HasLocalPalette then
  begin
    LCTCount := 1 shl ((PackedByte and 7) + 1);
    FillChar(LocalPalette, SizeOf(LocalPalette), 0);
    AStream.ReadBuffer(LocalPalette[0], LCTCount * 3);
    ActivePalette := LocalPalette;
  end
  else if HasGlobalPalette then
    ActivePalette := GlobalPalette
  else
    FillChar(ActivePalette, SizeOf(ActivePalette), 0);

  if AStream.Read(MinCodeSize, 1) <> 1 then Exit;
  if (MinCodeSize < 2) or (MinCodeSize > 11) or (FrameW <= 0) or (FrameH <= 0) then
  begin
    SkipSubBlocksStream(AStream);
    Exit;
  end;

  Result := TFloriaImage.Create(FrameW, FrameH, fpfBGRA32);
  Result.Clear(0, 0, 0, 0);

  ClearCode := 1 shl MinCodeSize;
  EOICode := ClearCode + 1;
  AvailCode := ClearCode + 2;
  CodeSize := MinCodeSize + 1;
  CodeMask := (1 shl CodeSize) - 1;
  OldCode := -1;
  FirstChar := 0;

  for i := 0 to ClearCode - 1 do
  begin
    Prefix[i] := -1;
    Suffix[i] := Byte(i);
  end;

  BitReader.Init(AStream);
  TotalPixels := FrameW * FrameH;
  PixelCount := 0;
  CurX := 0;
  CurY := 0;
  Pass := 0;
  StackPtr := 0;

  while PixelCount < TotalPixels do
  begin
    if not BitReader.ReadBits(CodeSize, Code) then Break;
    if Code = EOICode then Break;

    if Code = ClearCode then
    begin
      CodeSize := MinCodeSize + 1;
      CodeMask := (1 shl CodeSize) - 1;
      AvailCode := ClearCode + 2;
      OldCode := -1;
      Continue;
    end;

    if OldCode = -1 then
    begin
      if Code < 4096 then
      begin
        FirstChar := Suffix[Code];
        OutputPixel(Byte(FirstChar));
        OldCode := Code;
      end;
      Continue;
    end;

    CurCode := Code;
    if CurCode >= AvailCode then
    begin
      Stack[StackPtr] := Byte(FirstChar);
      Inc(StackPtr);
      CurCode := OldCode;
    end;

    while (CurCode >= ClearCode) and (CurCode < 4096) do
    begin
      Stack[StackPtr] := Suffix[CurCode];
      Inc(StackPtr);
      CurCode := Prefix[CurCode];
    end;

    if CurCode < 4096 then
    begin
      FirstChar := Suffix[CurCode];
      Stack[StackPtr] := Byte(FirstChar);
      Inc(StackPtr);
    end;

    if AvailCode < 4096 then
    begin
      Prefix[AvailCode] := OldCode;
      Suffix[AvailCode] := Byte(FirstChar);
      Inc(AvailCode);
      if (AvailCode > CodeMask) and (CodeSize < 12) then
      begin
        Inc(CodeSize);
        CodeMask := (1 shl CodeSize) - 1;
      end;
    end;
    OldCode := Code;

    while StackPtr > 0 do
    begin
      Dec(StackPtr);
      OutputPixel(Stack[StackPtr]);
      if PixelCount >= TotalPixels then Break;
    end;
  end;

  BitReader.SkipSubBlocks();
end;

procedure InternalReadGIF(AStream: TStream; AAnim: TFloriaAnimatedImage; AImageOnly: TFloriaImage);
var
  Header: array[0..5] of AnsiChar;
  W16, H16: Word;
  ScreenW, ScreenH: Integer;
  PackedByte, BgColorIdx, AspectRatio: Byte;
  HasGCT: Boolean;
  GCTCount: Integer;
  GlobalPalette: TGIFPalette;
  BlockType, ExtType, BlockSize, GCEPacked, GCETransIdx, SubLen, SubCode: Byte;
  GCEDelay: Word;
  CurDelayMs: Cardinal;
  CurDisposal: TFloriaDisposalMethod;
  HasTransparency: Boolean;
  TransparentIdx: Integer;
  FrameLeft, FrameTop, FrameW, FrameH: Integer;
  FrameImg: TFloriaImage;
  AppID: array[0..10] of AnsiChar;
  LoopCnt: Word;
begin
  if AStream.Read(Header[0], 6) <> 6 then Exit;
  if not ((CompareMem(@Header[0], @GIF_SIG_87A[0], 6)) or (CompareMem(@Header[0], @GIF_SIG_89A[0], 6))) then
    Exit;

  if AStream.Read(W16, 2) <> 2 then Exit;
  if AStream.Read(H16, 2) <> 2 then Exit;
  if AStream.Read(PackedByte, 1) <> 1 then Exit;
  if AStream.Read(BgColorIdx, 1) <> 1 then Exit;
  if AStream.Read(AspectRatio, 1) <> 1 then Exit;

  ScreenW := LEtoN(W16);
  ScreenH := LEtoN(H16);
  HasGCT := (PackedByte and $80) <> 0;

  FillChar(GlobalPalette, SizeOf(GlobalPalette), 0);
  if HasGCT then
  begin
    GCTCount := 1 shl ((PackedByte and 7) + 1);
    AStream.ReadBuffer(GlobalPalette[0], GCTCount * 3);
  end;

  if Assigned(AAnim) then
  begin
    AAnim.Width := ScreenW;
    AAnim.Height := ScreenH;
    AAnim.LoopCount := 0;
  end;

  CurDelayMs := 100;
  CurDisposal := fdmDoNotDispose;
  HasTransparency := False;
  TransparentIdx := -1;

  while AStream.Position < AStream.Size do
  begin
    if AStream.Read(BlockType, 1) <> 1 then Break;

    if BlockType = $21 then // Extension
    begin
      if AStream.Read(ExtType, 1) <> 1 then Break;

      if ExtType = $F9 then // Graphic Control Extension
      begin
        if AStream.Read(BlockSize, 1) <> 1 then Break;
        if BlockSize >= 4 then
        begin
          AStream.ReadBuffer(GCEPacked, 1);
          AStream.ReadBuffer(GCEDelay, 2);
          AStream.ReadBuffer(GCETransIdx, 1);
          if BlockSize > 4 then
            AStream.Seek(BlockSize - 4, soFromCurrent);

          CurDelayMs := Cardinal(LEtoN(GCEDelay)) * 10;
          if CurDelayMs <= 10 then
            CurDelayMs := 100;

          HasTransparency := (GCEPacked and 1) <> 0;
          if HasTransparency then
            TransparentIdx := GCETransIdx
          else
            TransparentIdx := -1;

          case (GCEPacked shr 2) and 7 of
            0, 1: CurDisposal := fdmDoNotDispose;
            2: CurDisposal := fdmRestoreBackground;
            3: CurDisposal := fdmRestorePrevious;
          else
            CurDisposal := fdmDoNotDispose;
          end;
        end
        else
          AStream.Seek(BlockSize, soFromCurrent);

        // Consume terminator
        SkipSubBlocksStream(AStream);
      end
      else if ExtType = $FF then // Application Extension
      begin
        if AStream.Read(BlockSize, 1) <> 1 then Break;
        if BlockSize = 11 then
        begin
          AStream.ReadBuffer(AppID[0], 11);
          if (Copy(string(AppID), 1, 11) = 'NETSCAPE2.0') or (Copy(string(AppID), 1, 11) = 'ANIMEXTS1.0') then
          begin
            if (AStream.Read(SubLen, 1) = 1) and (SubLen >= 3) then
            begin
              AStream.ReadBuffer(SubCode, 1);
              AStream.ReadBuffer(LoopCnt, 2);
              if Assigned(AAnim) and (SubCode = 1) then
                AAnim.LoopCount := LEtoN(LoopCnt);
              if SubLen > 3 then
                AStream.Seek(SubLen - 3, soFromCurrent);
            end;
          end;
        end
        else
          AStream.Seek(BlockSize, soFromCurrent);

        SkipSubBlocksStream(AStream);
      end
      else
      begin
        // Generic extension, skip sub-blocks
        if AStream.Read(BlockSize, 1) <> 1 then Break;
        AStream.Seek(BlockSize, soFromCurrent);
        SkipSubBlocksStream(AStream);
      end;
    end
    else if BlockType = $2C then // Image Descriptor
    begin
      FrameImg := DecodeGIFImage(AStream, GlobalPalette, HasGCT, TransparentIdx, HasTransparency,
                                 FrameLeft, FrameTop, FrameW, FrameH);

      if Assigned(FrameImg) then
      begin
        if Assigned(AImageOnly) then
        begin
          // For static load, copy first frame directly
          AImageOnly.Allocate(ScreenW, ScreenH, fpfBGRA32);
          AImageOnly.Clear(0, 0, 0, 0);
          AImageOnly.CopyFrom(FrameImg, 0, 0, FrameLeft, FrameTop, FrameW, FrameH);
          FrameImg.Free();
          Exit;
        end;

        if Assigned(AAnim) then
          AAnim.AddFrame(FrameImg, CurDelayMs, FrameLeft, FrameTop, CurDisposal, False);
      end;

      // Reset GCE state for next frame
      CurDelayMs := 100;
      CurDisposal := fdmDoNotDispose;
      HasTransparency := False;
      TransparentIdx := -1;
    end
    else if BlockType = $3B then // Trailer
      Break
    else
      Break;
  end;
end;

// ============================================================================
// TFloriaGIFReader
// ============================================================================

class function TFloriaGIFReader.CanRead(AStream: TStream): Boolean;
var
  Header: array[0..5] of AnsiChar;
  OldPos: Int64;
begin
  Result := False;
  if not Assigned(AStream) or (AStream.Size - AStream.Position < 6) then Exit;

  OldPos := AStream.Position;
  try
    if AStream.Read(Header[0], 6) = 6 then
      Result := (CompareMem(@Header[0], @GIF_SIG_87A[0], 6)) or
                (CompareMem(@Header[0], @GIF_SIG_89A[0], 6));
  finally
    AStream.Position := OldPos;
  end;
end;

class function TFloriaGIFReader.CanReadAnimation(AStream: TStream): Boolean;
begin
  Result := CanRead(AStream);
end;

class function TFloriaGIFReader.Format(): TFloriaImageFormat;
begin
  Result := fifGIF;
end;

procedure TFloriaGIFReader.ReadImage(AStream: TStream; AImage: TFloriaImage);
begin
  InternalReadGIF(AStream, nil, AImage);
end;

procedure TFloriaGIFReader.ReadAnimation(AStream: TStream; AAnim: TFloriaAnimatedImage);
begin
  InternalReadGIF(AStream, AAnim, nil);
end;

initialization
  RegisterAnimatedReader(TFloriaGIFReader);

end.
