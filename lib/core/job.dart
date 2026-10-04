import 'package:flutter/foundation.dart';

import 'error.dart';

enum JobStatus { queued, running, done, failed, skipped }

/// Thrown inside the pipeline when cancellation is requested. Caught by
/// [processJob] and reported as skipped, never as failed, because nothing
/// went wrong.
class JobCancelled implements Exception {
  const JobCancelled();
}

/// Main-isolate cancellation. Checked at cheap points (after decode, between
/// frames, before encode), never inside per-pixel loops. Cannot cross into a
/// worker isolate, so pooled cancellation stops dispatch and lets in-flight
/// workers finish; the direct path interrupts within one image.
class CancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw const JobCancelled();
  }
}

class ImageJob extends ChangeNotifier {
  ImageJob({
    required this.id,
    required this.name,
    required Uint8List bytes,
    this.path,
    this.presetName,
  }) : _source = bytes;

  final String id;
  final String name;
  Uint8List? _source;
  final String? path;

  /// Which output preset produced this job, for multi-output siblings.
  /// Feeds the {preset} filename token. Null means the main settings.
  final String? presetName;

  /// The original file bytes. Null once released to bound peak memory.
  /// Check [hasSource] before touching [bytes].
  Uint8List get bytes => _source!;
  bool get hasSource => _source != null;

  Uint8List? _thumbnail;

  /// A small preview that survives [releaseSource], so a written job still
  /// shows in the queue after its megabytes are gone.
  Uint8List? get thumbnail => _thumbnail;
  void setThumbnail(Uint8List bytes) {
    _thumbnail = bytes;
    notifyListeners();
  }

  /// Drops the source bytes. Only safe once the output is written, because a
  /// re-run needs the source back and it is gone.
  void releaseSource() {
    if (_source == null) return;
    _source = null;
    notifyListeners();
  }

  JobStatus _status = JobStatus.queued;
  Uint8List? _output;
  String? _error;
  EngineErrorKind? _errorKind;
  String? _notice;
  int? _sourceWidth;
  int? _sourceHeight;
  int? _outWidth;
  int? _outHeight;
  int? _solvedQuality;
  int _outFrames = 1;
  double _progress = 0;

  JobStatus get status => _status;
  Uint8List? get output => _output;
  String? get error => _error;

  /// Why this job failed, so the UI can distinguish a damaged file from a
  /// missing decoder from a refused write. Null unless the job failed.
  EngineErrorKind? get errorKind => _errorKind;

  /// Non-fatal loss the user should know about, e.g. an animation flattened to
  /// one frame because the chosen container cannot hold more.
  String? get notice => _notice;
  int? get sourceWidth => _sourceWidth;
  int? get sourceHeight => _sourceHeight;
  int? get outWidth => _outWidth;
  int? get outHeight => _outHeight;
  int? get solvedQuality => _solvedQuality;

  /// How many frames the output holds. Above one means the animation survived.
  int get outFrames => _outFrames;
  double get progress => _progress;

  int get inputBytes => _source?.length ?? 0;
  int? get outputBytes => _output?.length;

  double? get savedRatio {
    final o = _output?.length;
    final s = _source?.length;
    if (o == null || s == null || s == 0) return null;
    return 1 - (o / s);
  }

  String get sourceSizeLabel {
    final w = _sourceWidth;
    final h = _sourceHeight;
    if (w == null || h == null) return '-';
    return '$w x $h';
  }

  String get outputSizeLabel {
    final w = _outWidth;
    final h = _outHeight;
    if (w == null || h == null) return '-';
    return '$w x $h';
  }

  void markProbed(int w, int h) {
    _sourceWidth = w;
    _sourceHeight = h;
    notifyListeners();
  }

  void markRunning(double progress) {
    _status = JobStatus.running;
    _progress = progress;
    notifyListeners();
  }

  void markDone({
    required Uint8List output,
    required int width,
    required int height,
    int? quality,
    int frames = 1,
    String? notice,
  }) {
    _output = output;
    _outWidth = width;
    _outHeight = height;
    _solvedQuality = quality;
    _outFrames = frames < 1 ? 1 : frames;
    _status = JobStatus.done;
    _progress = 1;
    _error = null;
    _errorKind = null;
    _notice = notice;
    notifyListeners();
  }

  void markFailed(
    String message, {
    EngineErrorKind kind = EngineErrorKind.corruptData,
  }) {
    _error = message;
    _errorKind = kind;
    _notice = null;
    _status = JobStatus.failed;
    _progress = 1;
    notifyListeners();
  }

  void markSkipped(String reason) {
    _error = reason;
    _errorKind = EngineErrorKind.cancelled;
    _status = JobStatus.skipped;
    _progress = 1;
    notifyListeners();
  }

  void reset() {
    _status = JobStatus.queued;
    _output = null;
    _error = null;
    _errorKind = null;
    _notice = null;
    _progress = 0;
    _solvedQuality = null;
    _outFrames = 1;
    notifyListeners();
  }
}

String formatBytes(int? bytes) {
  if (bytes == null) return '-';
  if (bytes < 1000) return '$bytes B';
  if (bytes < 1000 * 1000) return '${(bytes / 1000).toStringAsFixed(1)} KB';
  if (bytes < 1000 * 1000 * 1000) {
    return '${(bytes / 1000000).toStringAsFixed(2)} MB';
  }
  return '${(bytes / 1000000000).toStringAsFixed(2)} GB';
}

int extensionToDotsPerInch(String? ext) {
  switch (ext?.toLowerCase().replaceAll('.', '')) {
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'tif':
    case 'tiff':
    case 'webp':
      return 300;
    case 'bmp':
    case 'gif':
    case 'ico':
      return 72;
    default:
      return 96;
  }
}
