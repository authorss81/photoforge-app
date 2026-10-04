import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The operating system's own photo picker, reached over a method channel.
///
/// Android's Photo Picker and iOS's PHPicker return only what the user
/// selected and require no library permission, which is why this exists: the
/// generic file picker cannot promise either. Everything here degrades to
/// null, and the caller falls back to the file picker, so an unsupported
/// device loses convenience, never function.
class SystemPicker {
  const SystemPicker._();

  static const MethodChannel channel = MethodChannel(
    'dev.pixelforge/system_picker',
  );

  /// Cap per pick. A larger selection risks OOM before the batch memory guard
  /// ever sees it, because these bytes arrive all at once.
  static const int maxSelection = 20;

  static bool get isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<List<({String name, Uint8List bytes, String? path})>?>
  pickImages() async {
    if (!isMobile) return null;
    try {
      final raw = await channel.invokeMethod<List<dynamic>>('pickImages');
      if (raw == null || raw.isEmpty) return const [];
      final out = <({String name, Uint8List bytes, String? path})>[];
      for (final item in raw.take(maxSelection)) {
        final m = (item as Map).cast<String, dynamic>();
        final bytes = m['bytes'] as Uint8List?;
        if (bytes == null || bytes.isEmpty) continue;
        out.add((
          name: (m['name'] as String?) ?? 'image',
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
}
