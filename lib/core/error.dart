/// The one predictable failure type for the whole pipeline. Anything the user
/// can act on arrives as this; anything else is a bug and is reported as
/// "Unexpected error" so the two are never confused.
class EngineError implements Exception {
  EngineError(this.message);

  final String message;

  @override
  String toString() => message;
}
