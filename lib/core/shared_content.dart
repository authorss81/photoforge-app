import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Images arriving from outside the app, and results going back out.
///
/// Android delivers shares as content URIs through the launch intent, which
/// MainActivity stashes until Dart collects them. iOS delivers opened files
/// the same way. Both platforms expose one channel with one shape, so the
/// rest of the app never knows which OS it is on.
///
/// Saving needs no permission on Android 10+ (MediaStore) and needs the
/// add-only photo permission on iOS, which is the single justified exception
/// in test/privacy_test.dart. Everything here degrades to an error string,
/// never a crash.
class SharedContent {
  const SharedContent._();

  static const MethodChannel channel = MethodChannel(
    'dev.pixelforge/shared_content',
  );

  static bool get isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Drains whatever was shared into the app since the last call. Empty when
  /// nothing is waiting, null when the platform cannot provide any.
  static Future<List<({String name, Uint8List bytes, String? path})>?>
  collect() async {
    if (!isMobile) return null;
    try {
      final raw = await channel.invokeMethod<List<dynamic>>('getSharedImages');
      if (raw == null || raw.isEmpty) return const [];
      final out = <({String name, Uint8List bytes, String? path})>[];
      for (final item in raw.take(20)) {
        final m = (item as Map).cast<String, dynamic>();
        final bytes = m['bytes'] as Uint8List?;
        if (bytes == null || bytes.isEmpty) continue;
        out.add((
          name: (m['name'] as String?) ?? 'shared',
          bytes: bytes,
          path: null,
        ));
      }
      return out;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Writes one finished image to the gallery or Photos. Returns null on
  /// success, or a human-readable reason on failure.
  static Future<String?> saveToGallery(Uint8List bytes, String name) async {
    if (!isMobile) return 'Saving to the gallery is only available on phones.';
    try {
      await channel.invokeMethod<void>('saveToGallery', {
        'bytes': bytes,
        'name': name,
      });
      return null;
    } on PlatformException catch (e) {
      return e.message ?? 'Could not save to the gallery.';
    } on MissingPluginException {
      return 'Saving to the gallery is not available on this device.';
    }
  }
}
