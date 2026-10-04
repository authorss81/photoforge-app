import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../error.dart';

/// No-op libheif for platforms without `dart:io`. Every call fails closed
/// with the same message the desktop loader produces when the library file
/// is absent, so behaviour is uniform and never a crash.
class Libheif {
  Libheif._();

  static dynamic load() => null;

  static String? get loadedFrom => null;

  static img.Image decode(Uint8List bytes) {
    throw EngineError(
      'HEIC decoding needs the bundled libheif, which was not found. '
      'Convert to JPEG first.',
    );
  }
}
