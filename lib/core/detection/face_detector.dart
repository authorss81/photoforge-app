import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:image/image.dart' as img;

/// A face found in an image, in source pixels.
class FaceBox {
  const FaceBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.confidence,
  });

  /// Centre of the box, which is what the crop planner wants.
  ({double x, double y}) get centre => (x: x + width / 2, y: y + height / 2);

  final double x;
  final double y;
  final double width;
  final double height;

  /// Model confidence, 0..1. Exposed so the UI can show it rather than acting
  /// on a detection the user cannot see.
  final double confidence;

  @override
  String toString() =>
      'FaceBox($x, $y, $width x $height, ${confidence.toStringAsFixed(2)})';
}

/// Why detection is not available, so the UI can say so rather than silently
/// falling back to a centre crop and leaving the user to wonder.
enum FaceDetectorStatus {
  /// Detection ran and worked.
  available,

  /// The model file is not in the build.
  modelMissing,

  /// An ONNX Runtime shared library for this platform and architecture could not
  /// be loaded.
  runtimeMissing,

  /// The platform has no FFI, such as web.
  unsupportedPlatform,
}

class FaceDetectionResult {
  const FaceDetectionResult({
    required this.status,
    this.faces = const [],
    this.elapsedMs = 0,
    this.detail,
  });

  /// Detection could not run at all.
  const FaceDetectionResult.unavailable(
    FaceDetectorStatus status, [
    String? detail,
  ]) : this(status: status, detail: detail);

  final FaceDetectorStatus status;

  /// Empty when unavailable or when nothing was found. An empty list with
  /// [FaceDetectorStatus.available] genuinely means "no faces", which is a
  /// different thing from "could not look". The crop planner depends on telling
  /// those apart.
  final List<FaceBox> faces;

  final double elapsedMs;
  final String? detail;

  bool get isAvailable => status == FaceDetectorStatus.available;

  /// True when detection ran and found nothing, so the crop planner keeps the
  /// plain centre crop.
  bool get ranButFoundNothing => isAvailable && faces.isEmpty;

  @override
  String toString() =>
      'FaceDetectionResult(${status.name}, ${faces.length} faces, '
      '${elapsedMs.toStringAsFixed(1)}ms)';
}

/// Runs YuNet face detection locally.
///
/// Offline by construction: the model is a bundled asset and inference is a
/// local call. No network, no download, no telemetry, which is what makes the
/// feature compatible with the rest of the product.
///
/// The model is YuNet (`assets/models/face_detection_yunet_2023mar.onnx`), MIT
/// licensed, 227 KB. It was chosen over SCRFD because SCRFD's *weights* are
/// derived from InsightFace, which is not licensed for commercial use, even
/// though the surrounding code is Apache-2.0. That distinction is the whole
/// reason for the choice, and docs/FACE_MODEL.md records it.
///
/// ## Runtime availability
///
/// Inference needs an ONNX Runtime shared library for the host platform. Until
/// that is wired up, detection reports [FaceDetectorStatus.runtimeMissing] and
/// the crop planner falls back to the centre crop, which is the correct and
/// documented behaviour rather than a silent one. This is asserted by tests, so
/// the fallback path is covered even though it is not the path we want to ship.
///
/// The interface is deliberately narrow and the result type carries its own
/// status, so adding the runtime binding does not change any caller.
class FaceDetector {
  const FaceDetector._();

  /// Longest edge the model runs at. YuNet detects faces of roughly 10px to
  /// 300px, and detection does not need source resolution, so a 24MP image is
  /// downscaled before inference. This is the main reason the feature is cheap
  /// enough to be worth enabling.
  static const int inferenceSize = 640;

  /// YuNet's own default is 0.6. Higher is stricter here on purpose: a false
  /// positive moves the crop away from the subject, which is worse than not
  /// detecting at all.
  static const double defaultScoreThreshold = 0.85;

  /// Whether an ONNX Runtime library has been loaded successfully.
  ///
  /// False until [installRuntime] succeeds. Exposed so the settings UI can say
  /// "detection is unavailable on this build" rather than pretending.
  static bool get isRuntimeAvailable =>
      _runtime.status == FaceDetectorStatus.available;

  /// Outcome of the most recent [installRuntime] call, and the reason it failed.
  static _RuntimeState _runtime = const _RuntimeState(
    FaceDetectorStatus.runtimeMissing,
    'Face detection has not been initialised.',
  );

  /// Resets the cached runtime state. Tests only.
  @visibleForTesting
  static void debugResetRuntime() {
    _runtime = const _RuntimeState(
      FaceDetectorStatus.runtimeMissing,
      'Face detection has not been initialised.',
    );
  }

  /// Loads the ONNX Runtime shared library, if one is bundled.
  ///
  /// Returns the status so a caller can report it. Safe to call repeatedly;
  /// only the first call does work.
  static FaceDetectorStatus installRuntime() {
    if (_runtime.status == FaceDetectorStatus.available) return _runtime.status;
    if (!Platform.isAndroid &&
        !Platform.isIOS &&
        !Platform.isWindows &&
        !Platform.isLinux) {
      _runtime = _RuntimeState(
        FaceDetectorStatus.unsupportedPlatform,
        'Face detection is not available on ${Platform.operatingSystem}.',
      );
      return _runtime.status;
    }
    _runtime = _RuntimeState(
      FaceDetectorStatus.runtimeMissing,
      'No ONNX Runtime shared library is bundled for '
      '${Platform.operatingSystem} on this architecture yet.',
    );
    return _runtime.status;
  }

  /// Human-readable reason detection is unavailable, or null when it is
  /// available.
  static String? get unavailabilityReason =>
      isRuntimeAvailable ? null : _runtime.detail;

  /// Detects faces in [image], returning source-pixel boxes.
  ///
  /// Never throws. A detector that can crash the pipeline on a malformed image
  /// would be worse than no detector, so every failure becomes a status.
  static Future<FaceDetectionResult> detect(
    img.Image image, {
    double scoreThreshold = defaultScoreThreshold,
  }) async {
    if (image.width <= 0 || image.height <= 0) {
      return const FaceDetectionResult(status: FaceDetectorStatus.available);
    }

    final status = installRuntime();
    if (status != FaceDetectorStatus.available) {
      return FaceDetectionResult.unavailable(status, _runtime.detail);
    }

    if (!modelExists) {
      return const FaceDetectionResult.unavailable(
        FaceDetectorStatus.modelMissing,
        'The bundled face model is missing from this build.',
      );
    }

    // Downscale before inference, and again here so the work happens off the
    // UI isolate. Decode is the expensive part and must not block a frame.
    try {
      final small = _downscale(image, inferenceSize);
      final found = await Isolate.run(() => _infer(small, scoreThreshold));
      final scaleX = image.width / small.width;
      final scaleY = image.height / small.height;
      return FaceDetectionResult(
        status: FaceDetectorStatus.available,
        faces: [
          for (final f in found)
            FaceBox(
              x: f.x * scaleX,
              y: f.y * scaleY,
              width: f.width * scaleX,
              height: f.height * scaleY,
              confidence: f.confidence,
            ),
        ],
      );
    } on Object catch (e) {
      // A runtime crash must degrade to "unavailable", never take the batch down.
      return FaceDetectionResult.unavailable(
        FaceDetectorStatus.runtimeMissing,
        'Face detection failed: $e',
      );
    }
  }

  /// Whether the model asset is present in the build.
  static bool get modelExists {
    try {
      return File(modelPath).existsSync();
    } on Object {
      return false;
    }
  }

  /// Path to the bundled model, relative to the package root in a test run and
  /// absolute in a built app.
  static String get modelPath {
    final override = Platform.environment['PIXELFORGE_FACE_MODEL'];
    if (override != null && override.isNotEmpty) return override;
    return _findModel();
  }

  static String _findModel() {
    const name = 'face_detection_yunet_2023mar.onnx';
    var dir = Directory.current;
    for (var i = 0; i < 6; i++) {
      final candidate = File('${dir.path}/assets/models/$name');
      if (candidate.existsSync()) return candidate.path;
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return 'assets/models/$name';
  }

  /// Scales the longest edge down to [longest], never up.
  static img.Image _downscale(img.Image im, int longest) {
    final w = im.width;
    final h = im.height;
    final m = w > h ? w : h;
    if (m <= longest) return im;
    final k = longest / m;
    return img.copyResize(
      im,
      width: (w * k).round(),
      height: (h * k).round(),
      interpolation: img.Interpolation.average,
    );
  }

  /// Runs the model. Throws only if the runtime is genuinely broken.
  static List<FaceBox> _infer(img.Image im, double scoreThreshold) {
    throw StateError(
      'ONNX Runtime is not wired up. installRuntime() must succeed before '
      'this path is reached.',
    );
  }
}

/// Cached outcome of the runtime load attempt.
class _RuntimeState {
  const _RuntimeState(this.status, this.detail);

  final FaceDetectorStatus status;
  final String detail;
}
