/// Why a file could not be processed.
///
/// Every case names something the user can act on. "Unsupported format" and
/// "the file is damaged" are different problems with different fixes, and a
/// single message for both tells the user to do something that will not work.
enum EngineErrorKind {
  /// The container or codec is not supported on this platform. The fix is to
  /// convert the file, or to use a build that has the decoder.
  unsupportedFormat,

  /// The bytes are damaged or truncated. Re-exporting or re-downloading the
  /// file is the fix; converting it is not.
  corruptData,

  /// A decoder exists for this format on other platforms but not here, usually
  /// because a native library is missing. Distinct from [unsupportedFormat]
  /// because the format *is* supported and the environment is at fault.
  codecUnavailable,

  /// The image needs more memory than the budget allows. Raising the memory
  /// budget, or resizing in two passes, is the fix.
  outOfMemory,

  /// The OS refused access to the file or the destination. Retrying or choosing
  /// another folder is the fix.
  permissionDenied,

  /// The requested settings cannot produce a valid result, such as an animated
  /// frame that does not fit its canvas.
  invalidSettings,

  /// The operation was cancelled by the user. Not a failure.
  cancelled,
}

/// The one predictable failure type for the whole pipeline. Anything the user
/// can act on arrives as this; anything else is a bug and is reported as
/// "Unexpected error" so the two are never confused.
class EngineError implements Exception {
  EngineError(
    this.message, {
    this.kind = EngineErrorKind.unsupportedFormat,
    this.detail,
  });

  /// A file in a container this build cannot open, for example AVIF on a
  /// platform with no AVIF decoder.
  EngineError.unsupportedFormat(String message, {String? detail})
    : this(message, kind: EngineErrorKind.unsupportedFormat, detail: detail);

  /// The bytes are not a valid image, or the file is truncated.
  EngineError.corruptData(String message, {String? detail})
    : this(message, kind: EngineErrorKind.corruptData, detail: detail);

  /// A decoder for this format should exist here but does not: a missing
  /// native library, or an API level that is too old.
  EngineError.codecUnavailable(String message, {String? detail})
    : this(message, kind: EngineErrorKind.codecUnavailable, detail: detail);

  /// Not enough memory to hold the image at this size.
  EngineError.outOfMemory(String message, {String? detail})
    : this(message, kind: EngineErrorKind.outOfMemory, detail: detail);

  /// The OS refused access to the source or the destination.
  EngineError.permissionDenied(String message, {String? detail})
    : this(message, kind: EngineErrorKind.permissionDenied, detail: detail);

  /// The chosen settings cannot produce a valid file.
  EngineError.invalidSettings(String message, {String? detail})
    : this(message, kind: EngineErrorKind.invalidSettings, detail: detail);

  final String message;

  /// Which failure this is. Drives the wording of the user-facing message and
  /// lets tests assert the distinction rather than matching on prose.
  final EngineErrorKind kind;

  /// Optional extra context, such as the file name or a native error code.
  final String? detail;

  @override
  String toString() => detail == null ? message : '$message ($detail)';
}
