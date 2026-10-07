unit Floria.GPU.Shaders;

// Floria.GPU.Shaders
// ==================
// Ahead-Of-Time (AOT) Precompiled GLSL Mega-Shaders for 2D GPU Vector UI.
//
// Tenets:
// - 100% precompiled AOT shaders: zero runtime JIT compilation jank.
// - Pure GLSL 100 / 120 / GLES 2.0 & 3.0 dual-compatible shader code.
// - Analytical SDF rounded rectangles and border evaluation with sub-pixel AA.
// - Single-pass analytical box shadows via Erf Gaussian approximation.
// - Analytical Clip Chain fragment evaluation directly inside shaders.

{$mode objfpc}{$H+}

interface

uses
  ctypes, Classes, SysUtils, Math,
  Floria.GL,
  Floria.DisplayList.Clip,
  Floria.GPU.Batch;

const
  MAX_GPU_CLIP_ITEMS = 16;

type
  // ---------------------------------------------------------------------------
  // TFloriaGPUShaderProgram
  // ---------------------------------------------------------------------------
  TFloriaGPUShaderProgram = class
  private
    FProgramID       : Cardinal;
    FVertexShader    : Cardinal;
    FFragmentShader  : Cardinal;
    FLinked          : Boolean;

    // Standard Uniform Locations
    FUViewport       : Integer;
    FUTexture        : Integer;
    FUClipCount      : Integer;
    FUClipMinMax     : Integer;
    FUClipRadii      : Integer;
    FUClipKind       : Integer;

    // Standard Attribute Locations
    FAttribPosition  : Integer;
    FAttribTexCoord  : Integer;
    FAttribColor     : Integer;
    FAttribLocalRect : Integer;
    FAttribRadiiTL_TR: Integer;
    FAttribRadiiBR_BL: Integer;
    FAttribBorder    : Integer;
    FAttribExtra     : Integer;

    function CompileSource(gl: TGLEngine; AType: Cardinal; const ASource: string): Cardinal;
  public
    constructor Create(gl: TGLEngine; const AVertSource, AFragSource: string);
    destructor Destroy(); override;

    procedure Bind(gl: TGLEngine);
    procedure Unbind(gl: TGLEngine);
    procedure SetViewport(gl: TGLEngine; AWidth, AHeight: Single);
    procedure SetTextureUnit(gl: TGLEngine; AUnit: Integer);
    procedure UploadClipChain(gl: TGLEngine; const AClipItems: TFloriaGPUClipItemArray; ACount: Integer);
    procedure SetupVertexPointers(gl: TGLEngine);

    property ProgramID: Cardinal read FProgramID;
    property Linked   : Boolean  read FLinked;
  end;

  // ---------------------------------------------------------------------------
  // TFloriaGPUPipelineManager
  // ---------------------------------------------------------------------------
  TFloriaGPUPipelineManager = class
  private
    FPrograms: array[TFloriaGPUBatchType] of TFloriaGPUShaderProgram;
    FInitialized: Boolean;

    procedure InitShaders(gl: TGLEngine);
  public
    constructor Create();
    destructor Destroy(); override;

    procedure EnsureInitialized(gl: TGLEngine);
    function GetProgram(ABatchType: TFloriaGPUBatchType): TFloriaGPUShaderProgram;
    procedure ReleaseGPUResources();

    property Initialized: Boolean read FInitialized;
  end;

implementation

const
  // ---------------------------------------------------------------------------
  // Common Vertex Shader Source
  // ---------------------------------------------------------------------------
  COMMON_VERTEX_SHADER =
    '#ifdef GL_ES'#10 +
    'precision highp float;'#10 +
    '#endif'#10 +
    'attribute vec2 a_Position;'#10 +
    'attribute vec2 a_TexCoord;'#10 +
    'attribute vec4 a_Color;'#10 +
    'attribute vec4 a_LocalRect;'#10 +
    'attribute vec4 a_RadiiTL_TR;'#10 +
    'attribute vec4 a_RadiiBR_BL;'#10 +
    'attribute vec4 a_Border;'#10 +
    'attribute vec4 a_Extra;'#10 +
    'uniform vec2 u_Viewport;'#10 +
    'varying vec2 v_Position;'#10 +
    'varying vec2 v_TexCoord;'#10 +
    'varying vec4 v_Color;'#10 +
    'varying vec4 v_LocalRect;'#10 +
    'varying vec4 v_RadiiTL_TR;'#10 +
    'varying vec4 v_RadiiBR_BL;'#10 +
    'varying vec4 v_Border;'#10 +
    'varying vec4 v_Extra;'#10 +
    'void main() {'#10 +
    '  v_Position = a_Position;'#10 +
    '  v_TexCoord = a_TexCoord;'#10 +
    '  v_Color = a_Color;'#10 +
    '  v_LocalRect = a_LocalRect;'#10 +
    '  v_RadiiTL_TR = a_RadiiTL_TR;'#10 +
    '  v_RadiiBR_BL = a_RadiiBR_BL;'#10 +
    '  v_Border = a_Border;'#10 +
    '  v_Extra = a_Extra;'#10 +
    '  vec2 ndc = vec2(a_Position.x / (u_Viewport.x * 0.5) - 1.0,'#10 +
    '                  1.0 - a_Position.y / (u_Viewport.y * 0.5));'#10 +
    '  gl_Position = vec4(ndc, 0.0, 1.0);'#10 +
    '}'#10;

  // ---------------------------------------------------------------------------
  // Analytical Clip Chain Header for Fragment Shaders
  // ---------------------------------------------------------------------------
  CLIP_HEADER =
    '#ifdef GL_ES'#10 +
    'precision highp float;'#10 +
    '#endif'#10 +
    'uniform int u_ClipCount;'#10 +
    'uniform vec4 u_ClipMinMax[16];'#10 +
    'uniform vec4 u_ClipRadii[16];'#10 +
    'uniform vec4 u_ClipKind[16];'#10 +
    'bool evaluateClip(vec2 pos) {'#10 +
    '  for (int i = 0; i < 16; i++) {'#10 +
    '    if (i >= u_ClipCount) break;'#10 +
    '    vec4 box = u_ClipMinMax[i];'#10 +
    '    if (pos.x < box.x || pos.x > box.z || pos.y < box.y || pos.y > box.w) return false;'#10 +
    '    if (u_ClipKind[i].x > 1.5) {'#10 +
    '      vec4 radii = u_ClipRadii[i];'#10 +
    '      vec2 r = (pos.x < box.x + (box.z - box.x) * 0.5) ?'#10 +
    '        ((pos.y < box.y + (box.w - box.y) * 0.5) ? radii.xy : radii.zw) :'#10 +
    '        ((pos.y < box.y + (box.w - box.y) * 0.5) ? radii.xy : radii.zw);'#10 +
    '      vec2 halfSz = (box.zw - box.xy) * 0.5;'#10 +
    '      vec2 center = box.xy + halfSz;'#10 +
    '      vec2 q = abs(pos - center) - halfSz + r;'#10 +
    '      if (q.x > 0.0 && q.y > 0.0 && length(q) > r.x) return false;'#10 +
    '    }'#10 +
    '  }'#10 +
    '  return true;'#10 +
    '}'#10;

  // ---------------------------------------------------------------------------
  // Solid Quad Fragment Shader
  // ---------------------------------------------------------------------------
  SOLID_QUAD_FRAG =
    CLIP_HEADER +
    'varying vec2 v_Position;'#10 +
    'varying vec4 v_Color;'#10 +
    'varying vec4 v_Extra;'#10 +
    'void main() {'#10 +
    '  if (v_Extra.x >= 0.0 && !evaluateClip(v_Position)) discard;'#10 +
    '  gl_FragColor = v_Color;'#10 +
    '}'#10;

  // ---------------------------------------------------------------------------
  // Textured Quad Fragment Shader
  // ---------------------------------------------------------------------------
  TEXTURED_QUAD_FRAG =
    CLIP_HEADER +
    'uniform sampler2D u_Texture;'#10 +
    'varying vec2 v_Position;'#10 +
    'varying vec2 v_TexCoord;'#10 +
    'varying vec4 v_Color;'#10 +
    'varying vec4 v_Extra;'#10 +
    'void main() {'#10 +
    '  if (v_Extra.x >= 0.0 && !evaluateClip(v_Position)) discard;'#10 +
    '  vec4 tex = texture2D(u_Texture, v_TexCoord);'#10 +
    '  gl_FragColor = tex * v_Color;'#10 +
    '}'#10;

  // ---------------------------------------------------------------------------
  // Analytical SDF Rounded Rectangle & Border Fragment Shader
  // ---------------------------------------------------------------------------
  ROUNDED_RECT_FRAG =
    CLIP_HEADER +
    'varying vec2 v_Position;'#10 +
    'varying vec4 v_Color;'#10 +
    'varying vec4 v_LocalRect;'#10 +
    'varying vec4 v_RadiiTL_TR;'#10 +
    'varying vec4 v_RadiiBR_BL;'#10 +
    'varying vec4 v_Border;'#10 +
    'varying vec4 v_Extra;'#10 +
    'float evalSDF(vec2 pos, vec4 box, vec4 rTL_TR, vec4 rBR_BL) {'#10 +
    '  vec2 halfSz = box.zw * 0.5;'#10 +
    '  vec2 center = box.xy + halfSz;'#10 +
    '  vec2 p = pos - center;'#10 +
    '  vec2 r;'#10 +
    '  if (p.x < 0.0) {'#10 +
    '    r = (p.y < 0.0) ? rTL_TR.xy : rBR_BL.zw;'#10 +
    '  } else {'#10 +
    '    r = (p.y < 0.0) ? rTL_TR.zw : rBR_BL.xy;'#10 +
    '  }'#10 +
    '  vec2 q = abs(p) - halfSz + r;'#10 +
    '  return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r.x;'#10 +
    '}'#10 +
    'void main() {'#10 +
    '  if (v_Extra.x >= 0.0 && !evaluateClip(v_Position)) discard;'#10 +
    '  float d = evalSDF(v_Position, v_LocalRect, v_RadiiTL_TR, v_RadiiBR_BL);'#10 +
    '  float alpha = clamp(0.5 - d, 0.0, 1.0);'#10 +
    '  if (alpha <= 0.0) discard;'#10 +
    '  if (v_Border.x > 0.0) {'#10 +
    '    float innerD = d + v_Border.x;'#10 +
    '    float borderAlpha = clamp(innerD + 0.5, 0.0, 1.0);'#10 +
    '    vec4 c = mix(v_Color, vec4(v_Border.yzw, 1.0), borderAlpha);'#10 +
    '    gl_FragColor = vec4(c.rgb, c.a * alpha * v_Color.a);'#10 +
    '  } else {'#10 +
    '    gl_FragColor = vec4(v_Color.rgb, v_Color.a * alpha);'#10 +
    '  }'#10 +
    '}'#10;

  // ---------------------------------------------------------------------------
  // Analytical Box Shadow Fragment Shader
  // ---------------------------------------------------------------------------
  BOX_SHADOW_FRAG =
    CLIP_HEADER +
    'varying vec2 v_Position;'#10 +
    'varying vec4 v_Color;'#10 +
    'varying vec4 v_LocalRect;'#10 +
    'varying vec4 v_RadiiTL_TR;'#10 +
    'varying vec4 v_RadiiBR_BL;'#10 +
    'varying vec4 v_Extra;'#10 +
    'void main() {'#10 +
    '  if (v_Extra.x >= 0.0 && !evaluateClip(v_Position)) discard;'#10 +
    '  vec2 halfSz = v_LocalRect.zw * 0.5 + vec2(v_Extra.z);'#10 +
    '  vec2 center = v_LocalRect.xy + v_LocalRect.zw * 0.5;'#10 +
    '  vec2 p = abs(v_Position - center);'#10 +
    '  float r = v_RadiiTL_TR.x;'#10 +
    '  vec2 q = p - halfSz + vec2(r);'#10 +
    '  float d = min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;'#10 +
    '  float blur = max(1.0, v_Extra.y);'#10 +
    '  float alpha = clamp(0.5 - d / blur, 0.0, 1.0);'#10 +
    '  alpha = alpha * alpha * (3.0 - 2.0 * alpha);'#10 +
    '  if (alpha <= 0.0) discard;'#10 +
    '  gl_FragColor = vec4(v_Color.rgb, v_Color.a * alpha);'#10 +
    '}'#10;

  // ---------------------------------------------------------------------------
  // Linear Gradient Fragment Shader
  // ---------------------------------------------------------------------------
  LINEAR_GRADIENT_FRAG =
    CLIP_HEADER +
    'varying vec2 v_Position;'#10 +
    'varying vec4 v_Color;'#10 +
    'varying vec4 v_LocalRect;'#10 +
    'varying vec4 v_Border;'#10 +
    'varying vec4 v_Extra;'#10 +
    'void main() {'#10 +
    '  if (v_Extra.x >= 0.0 && !evaluateClip(v_Position)) discard;'#10 +
    '  float angleRad = radians(v_Extra.y);'#10 +
    '  vec2 dir = vec2(cos(angleRad), sin(angleRad));'#10 +
    '  vec2 rel = v_Position - v_LocalRect.xy;'#10 +
    '  float proj = dot(rel, dir);'#10 +
    '  float totalLen = max(1.0, dot(v_LocalRect.zw, abs(dir)));'#10 +
    '  float t = clamp(proj / totalLen, 0.0, 1.0);'#10 +
    '  vec4 cStart = v_Color;'#10 +
    '  vec4 cEnd = vec4(v_Border.yzw, v_Border.x);'#10 +
    '  gl_FragColor = mix(cStart, cEnd, t);'#10 +
    '}'#10;

  // ---------------------------------------------------------------------------
  // Path Mesh Fragment Shader (Triangles & AA Fringe strips with analytical clip)
  // ---------------------------------------------------------------------------
  PATH_MESH_FRAG =
    CLIP_HEADER +
    'varying vec2 v_Position;'#10 +
    'varying vec4 v_Color;'#10 +
    'varying vec4 v_Extra;'#10 +
    'void main() {'#10 +
    '  if (v_Extra.x >= 0.0 && !evaluateClip(v_Position)) discard;'#10 +
    '  if (v_Color.a <= 0.0) discard;'#10 +
    '  gl_FragColor = v_Color;'#10 +
    '}'#10;

// -----------------------------------------------------------------------------
// TFloriaGPUShaderProgram Implementation
// -----------------------------------------------------------------------------
constructor TFloriaGPUShaderProgram.Create(gl: TGLEngine; const AVertSource, AFragSource: string);
var
  Status: cint;
begin
  inherited Create();
  FLinked         := False;
  FProgramID      := 0;
  FVertexShader   := 0;
  FFragmentShader := 0;

  if not Assigned(gl) or not gl.Available then Exit;

  FVertexShader   := CompileSource(gl, GL_VERTEX_SHADER, AVertSource);
  FFragmentShader := CompileSource(gl, GL_FRAGMENT_SHADER, AFragSource);

  if (FVertexShader = 0) or (FFragmentShader = 0) then Exit;

  FProgramID := gl.CreateProgram();
  gl.AttachShader(FProgramID, FVertexShader);
  gl.AttachShader(FProgramID, FFragmentShader);
  gl.LinkProgram(FProgramID);

  gl.GetProgramiv(FProgramID, GL_LINK_STATUS, @Status);
  FLinked := Status = GL_TRUE;

  if FLinked then
  begin
    // Query Uniforms
    FUViewport   := gl.GetUniformLocation(FProgramID, 'u_Viewport');
    FUTexture    := gl.GetUniformLocation(FProgramID, 'u_Texture');
    FUClipCount  := gl.GetUniformLocation(FProgramID, 'u_ClipCount');
    FUClipMinMax := gl.GetUniformLocation(FProgramID, 'u_ClipMinMax');
    FUClipRadii  := gl.GetUniformLocation(FProgramID, 'u_ClipRadii');
    FUClipKind   := gl.GetUniformLocation(FProgramID, 'u_ClipKind');

    // Query Attributes
    FAttribPosition   := gl.GetAttribLocation(FProgramID, 'a_Position');
    FAttribTexCoord   := gl.GetAttribLocation(FProgramID, 'a_TexCoord');
    FAttribColor      := gl.GetAttribLocation(FProgramID, 'a_Color');
    FAttribLocalRect  := gl.GetAttribLocation(FProgramID, 'a_LocalRect');
    FAttribRadiiTL_TR := gl.GetAttribLocation(FProgramID, 'a_RadiiTL_TR');
    FAttribRadiiBR_BL := gl.GetAttribLocation(FProgramID, 'a_RadiiBR_BL');
    FAttribBorder     := gl.GetAttribLocation(FProgramID, 'a_Border');
    FAttribExtra      := gl.GetAttribLocation(FProgramID, 'a_Extra');
  end;
end;

destructor TFloriaGPUShaderProgram.Destroy();
var
  gl: TGLEngine;
begin
  gl := FloriaGL();
  if gl.Available then
  begin
    if FVertexShader <> 0 then gl.DeleteShader(FVertexShader);
    if FFragmentShader <> 0 then gl.DeleteShader(FFragmentShader);
    if FProgramID <> 0 then gl.DeleteProgram(FProgramID);
  end;
  inherited Destroy();
end;

function TFloriaGPUShaderProgram.CompileSource(gl: TGLEngine; AType: Cardinal; const ASource: string): Cardinal;
var
  ShaderID: Cardinal;
  P: PChar;
  Len: cint;
  Status: cint;
begin
  Result := 0;
  if not Assigned(gl) or not gl.Available then Exit;

  ShaderID := gl.CreateShader(AType);
  P := PChar(ASource);
  Len := Length(ASource);
  gl.ShaderSource(ShaderID, 1, @P, @Len);
  gl.CompileShader(ShaderID);

  gl.GetShaderiv(ShaderID, GL_COMPILE_STATUS, @Status);
  if Status <> GL_TRUE then
  begin
    gl.DeleteShader(ShaderID);
    Exit(0);
  end;

  Result := ShaderID;
end;

procedure TFloriaGPUShaderProgram.Bind(gl: TGLEngine);
begin
  if Assigned(gl) and gl.Available and FLinked then
    gl.UseProgram(FProgramID);
end;

procedure TFloriaGPUShaderProgram.Unbind(gl: TGLEngine);
begin
  if Assigned(gl) and gl.Available then
    gl.UseProgram(0);
end;

procedure TFloriaGPUShaderProgram.SetViewport(gl: TGLEngine; AWidth, AHeight: Single);
begin
  if Assigned(gl) and gl.Available and (FUViewport >= 0) then
    gl.Uniform2f(FUViewport, AWidth, AHeight);
end;

procedure TFloriaGPUShaderProgram.SetTextureUnit(gl: TGLEngine; AUnit: Integer);
begin
  if Assigned(gl) and gl.Available and (FUTexture >= 0) then
    gl.Uniform1i(FUTexture, AUnit);
end;

procedure TFloriaGPUShaderProgram.UploadClipChain(gl: TGLEngine; const AClipItems: TFloriaGPUClipItemArray; ACount: Integer);
var
  MinMax: array[0..MAX_GPU_CLIP_ITEMS * 4 - 1] of cfloat;
  Radii:  array[0..MAX_GPU_CLIP_ITEMS * 4 - 1] of cfloat;
  Kind:   array[0..MAX_GPU_CLIP_ITEMS * 4 - 1] of cfloat;
  I, ActualCount: Integer;
begin
  if not Assigned(gl) or not gl.Available or (FUClipCount < 0) then Exit;

  ActualCount := Min(ACount, MAX_GPU_CLIP_ITEMS);
  gl.Uniform1i(FUClipCount, ActualCount);

  if ActualCount = 0 then Exit;

  for I := 0 to ActualCount - 1 do
  begin
    MinMax[I * 4 + 0] := AClipItems[I].RectMinX;
    MinMax[I * 4 + 1] := AClipItems[I].RectMinY;
    MinMax[I * 4 + 2] := AClipItems[I].RectMaxX;
    MinMax[I * 4 + 3] := AClipItems[I].RectMaxY;

    Radii[I * 4 + 0]  := AClipItems[I].RadiiTL_X;
    Radii[I * 4 + 1]  := AClipItems[I].RadiiTL_Y;
    Radii[I * 4 + 2]  := AClipItems[I].RadiiTR_X;
    Radii[I * 4 + 3]  := AClipItems[I].RadiiTR_Y;

    Kind[I * 4 + 0]   := AClipItems[I].ClipKind;
    Kind[I * 4 + 1]   := AClipItems[I].AntiAlias;
    Kind[I * 4 + 2]   := 0.0;
    Kind[I * 4 + 3]   := 0.0;
  end;

  if FUClipMinMax >= 0 then
    gl.Uniform4fv(FUClipMinMax, ActualCount, @MinMax[0]);
  if FUClipRadii >= 0 then
    gl.Uniform4fv(FUClipRadii, ActualCount, @Radii[0]);
  if FUClipKind >= 0 then
    gl.Uniform4fv(FUClipKind, ActualCount, @Kind[0]);
end;

procedure TFloriaGPUShaderProgram.SetupVertexPointers(gl: TGLEngine);
var
  Stride: cint;
begin
  if not Assigned(gl) or not gl.Available then Exit;

  Stride := SizeOf(TFloriaGPUVertex);

  if FAttribPosition >= 0 then
  begin
    gl.EnableVertexAttribArray(FAttribPosition);
    gl.VertexAttribPointer(FAttribPosition, 2, GL_FLOAT, False, Stride, Pointer(0));
  end;

  if FAttribTexCoord >= 0 then
  begin
    gl.EnableVertexAttribArray(FAttribTexCoord);
    gl.VertexAttribPointer(FAttribTexCoord, 2, GL_FLOAT, False, Stride, Pointer(8));
  end;

  if FAttribColor >= 0 then
  begin
    gl.EnableVertexAttribArray(FAttribColor);
    gl.VertexAttribPointer(FAttribColor, 4, GL_FLOAT, False, Stride, Pointer(16));
  end;

  if FAttribLocalRect >= 0 then
  begin
    gl.EnableVertexAttribArray(FAttribLocalRect);
    gl.VertexAttribPointer(FAttribLocalRect, 4, GL_FLOAT, False, Stride, Pointer(32));
  end;

  if FAttribRadiiTL_TR >= 0 then
  begin
    gl.EnableVertexAttribArray(FAttribRadiiTL_TR);
    gl.VertexAttribPointer(FAttribRadiiTL_TR, 4, GL_FLOAT, False, Stride, Pointer(48));
  end;

  if FAttribRadiiBR_BL >= 0 then
  begin
    gl.EnableVertexAttribArray(FAttribRadiiBR_BL);
    gl.VertexAttribPointer(FAttribRadiiBR_BL, 4, GL_FLOAT, False, Stride, Pointer(64));
  end;

  if FAttribBorder >= 0 then
  begin
    gl.EnableVertexAttribArray(FAttribBorder);
    gl.VertexAttribPointer(FAttribBorder, 4, GL_FLOAT, False, Stride, Pointer(80));
  end;

  if FAttribExtra >= 0 then
  begin
    gl.EnableVertexAttribArray(FAttribExtra);
    gl.VertexAttribPointer(FAttribExtra, 4, GL_FLOAT, False, Stride, Pointer(96));
  end;
end;

// -----------------------------------------------------------------------------
// TFloriaGPUPipelineManager Implementation
// -----------------------------------------------------------------------------
constructor TFloriaGPUPipelineManager.Create();
var
  BT: TFloriaGPUBatchType;
begin
  inherited Create();
  FInitialized := False;
  for BT := Low(TFloriaGPUBatchType) to High(TFloriaGPUBatchType) do
    FPrograms[BT] := nil;
end;

destructor TFloriaGPUPipelineManager.Destroy();
begin
  ReleaseGPUResources();
  inherited Destroy();
end;

procedure TFloriaGPUPipelineManager.ReleaseGPUResources();
var
  BT: TFloriaGPUBatchType;
begin
  for BT := Low(TFloriaGPUBatchType) to High(TFloriaGPUBatchType) do
    if Assigned(FPrograms[BT]) then
      FreeAndNil(FPrograms[BT]);
  FInitialized := False;
end;

procedure TFloriaGPUPipelineManager.InitShaders(gl: TGLEngine);
begin
  if not Assigned(gl) or not gl.Available then Exit;

  FPrograms[gbtSolidQuad]      := TFloriaGPUShaderProgram.Create(gl, COMMON_VERTEX_SHADER, SOLID_QUAD_FRAG);
  FPrograms[gbtTexturedQuad]   := TFloriaGPUShaderProgram.Create(gl, COMMON_VERTEX_SHADER, TEXTURED_QUAD_FRAG);
  FPrograms[gbtRoundedRect]    := TFloriaGPUShaderProgram.Create(gl, COMMON_VERTEX_SHADER, ROUNDED_RECT_FRAG);
  FPrograms[gbtBoxShadow]      := TFloriaGPUShaderProgram.Create(gl, COMMON_VERTEX_SHADER, BOX_SHADOW_FRAG);
  FPrograms[gbtLinearGradient] := TFloriaGPUShaderProgram.Create(gl, COMMON_VERTEX_SHADER, LINEAR_GRADIENT_FRAG);
  FPrograms[gbtPathMesh]       := TFloriaGPUShaderProgram.Create(gl, COMMON_VERTEX_SHADER, PATH_MESH_FRAG);

  FInitialized := True;
end;

procedure TFloriaGPUPipelineManager.EnsureInitialized(gl: TGLEngine);
begin
  if not FInitialized then
    InitShaders(gl);
end;

function TFloriaGPUPipelineManager.GetProgram(ABatchType: TFloriaGPUBatchType): TFloriaGPUShaderProgram;
begin
  Result := FPrograms[ABatchType];
end;

end.
