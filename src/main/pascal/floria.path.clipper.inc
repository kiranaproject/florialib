///////////////////////////////////////////////////////////////////////////////
// Floria Toolkit / Kirana
// Port of Clipper2 (Angus Johnson, Boost Software License 1.0)
// Compiler Include Directive
///////////////////////////////////////////////////////////////////////////////

// For user defined Z-coordinates, defined in Clipper's 'SetZ' callback event
{.$DEFINE USINGZ}

{$IFDEF FPC}
  {$DEFINE INLINING}
  {$MODE DELPHI}
  {$MODESWITCH ADVANCEDRECORDS}
  {$WARN 5024 OFF} // Parameter not used
  {$WARN 5023 OFF} // Unit not used
  {$WARN 5027 OFF} // Local variable not used
  {$WARN 5036 OFF} // Variable not initialized
  {$WARN 6018 OFF} // Inlining not inlined
{$ELSE}
  {$IF COMPILERVERSION >= 18}
    {$DEFINE RECORD_METHODS}
    {$DEFINE STRICT}
    {$DEFINE INLINING}
  {$IFEND}
{$ENDIF}

{$IFDEF DEBUG}
  {$UNDEF INLINING}
{$ENDIF}
