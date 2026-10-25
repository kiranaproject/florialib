unit Floria.Errors;

// Floria.Errors
// =============
// Stable exception hierarchy for the library. Consumers can catch
// EFloriaError to handle any first-party failure without catching every
// generic Exception.

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

type
  // Base class for all first-party florialib errors.
  EFloriaError = class(Exception);

  // Raised when a backend cannot perform an operation that the public API
  // otherwise advertises (for example, GPU layer compositing).
  EFloriaNotSupported = class(EFloriaError);

  // Image codec / raster errors.
  EFloriaImageError = class(EFloriaError);

  // Compression / archive errors.
  EFloriaCompressionError = class(EFloriaError);

implementation

end.
