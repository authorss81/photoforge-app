import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps the process alive during long batches on Android via a foreground
/// service with a live progress notification and a cancel action.
///
/// The service does no work itself; Dart isolates do. It exists only so
/// Android does not kill the process mid-batch, and so the user can see
/// progress and cancel from the notification shade.
///
/// iOS has no equivalent here. Background execution there needs a headless
/// engine, which is a separate project, so [isSupported] is Android-only and
/// the UI never promises what the platform cannot do. See docs/BACKGROUND.md.
class BackgroundService {
  const BackgroundService._();

  static const MethodChannel channel = MethodChannel(
    'dev.pixelforge/background',
  );

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool _listening = false;

  /// Starts the service and routes the notification's cancel action to
  /// [onCancel]. Idempotent; safe to call when already started.
  static Future<void> start(
    int total, {
    required void Function() onCancel,
  }) async {
    if (!isSupported) return;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onCancel') onCancel();
    });
    _listening = true;
    try {
      await channel.invokeMethod<void>('start', {'total': total});
    } on PlatformException {
      // A device that refuses the service still processes normally; the batch
      // just loses its keep-alive. Never fail a batch over this.
    } on MissingPluginException {
      // No native side (tests, desktop builds sharing this code path).
    }
  }

  static Future<void> progress(int done, int total) async {
    if (!isSupported || !_listening) return;
    try {
      await channel.invokeMethod<void>('progress', {
        'done': done,
        'total': total,
      });
    } on PlatformException {
      // Best effort; the batch continues regardless.
    } on MissingPluginException {
      // Best effort; the batch continues regardless.
    }
  }

  static Future<void> stop() async {
    if (!isSupported || !_listening) return;
    _listening = false;
    try {
      await channel.invokeMethod<void>('stop');
    } on PlatformException {
      // Best effort.
    } on MissingPluginException {
      // Best effort.
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _listening = false;
  }
}
