import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Platform decoders for formats the pure-Dart codecs cannot read.
///
/// Today that means HEIC, HEIF and AVIF on Android, where `ImageDecoder`
/// handles them natively since API 28 with no extra dependency and no new
/// permission. The native side returns lossless PNG bytes, so the Dart
/// pipeline treats the result like any other file from there on.
///
/// Every method returns null when the platform cannot help, and the caller
/// falls back to the Dart decoder, which produces the documented clear error.
/// Null is never a crash.
class NativeDecoder {
  const NativeDecoder._();

  static const MethodChannel channel =
      MethodChannel('dev.pixelforge/native_decoder');

  static const List<String> heifFamily = ['heic', 'heif', 'avif'];

  static bool isHeifFamily(String? extension) {
    if (extension == null) return false;
    return heifFamily.contains(extension.toLowerCase());
  }

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// True on any platform with a native decoder wired. Method channels do not
  /// exist in worker isolates, so pooled callers must pre-decode on the main
  /// isolate; see the controller partition.
  static bool get isNativeCapable => isAndroid || isIOS;

  /// Full-resolution PNG bytes, or null when unavailable for any reason:
  /// wrong platform, old API level, missing plugin, undecodable file.
  static Future<Uint8List?> decodeToPng(Uint8List bytes) async {
    if (!isNativeCapable) return null;
    try {
      return await channel.invokeMethod<Uint8List>(
        'decodeImage',
        {'bytes': bytes},
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
