import 'dart:async';

import 'package:flutter/foundation.dart';

import 'engine.dart';
import 'job.dart';
import 'picker.dart';
import 'saver/saver.dart';
import 'settings.dart';
import 'worker.dart';

/// Owns the queue and drives the batch pipeline.
class ResizeController extends ChangeNotifier {
  ResizeController({ResizeSettings? settings})
    : settings = settings ?? ResizeSettings(),
      _sink = createOutputSink();

  final ResizeSettings settings;
  final OutputSink _sink;
  WorkerPool? _pool;

  final List<ImageJob> _jobs = <ImageJob>[];
  List<ImageJob> get jobs => List.unmodifiable(_jobs);

  bool _busy = false;
  bool get busy => _busy;

  String? _selectedId;
  String? get selectedId => _selectedId;

  ImageJob? get selected {
    if (_selectedId == null) return null;
    for (final j in _jobs) {
      if (j.id == _selectedId) return j;
    }
    return null;
  }

  int get doneCount => _jobs.where((j) => j.status == JobStatus.done).length;
  int get failedCount =>
      _jobs.where((j) => j.status == JobStatus.failed).length;
  int get pendingCount => _jobs
      .where(
        (j) => j.status == JobStatus.queued || j.status == JobStatus.failed,
      )
      .length;

  int get totalInputBytes => _jobs.fold(0, (a, j) => a + j.inputBytes);
  int get totalOutputBytes => _jobs.fold(
    0,
    (a, j) => a + (j.status == JobStatus.done ? (j.outputBytes ?? 0) : 0),
  );

  double? get overallSavedRatio {
    final out = totalOutputBytes;
    final inp = totalInputBytes;
    if (out == 0 || inp == 0) return null;
    return 1 - (out / inp);
  }

  void _changed() => notifyListeners();

  void select(String? id) {
    _selectedId = id;
    _changed();
  }

  // ------------------------------------------------------------- queue edits
  Future<int> addViaPicker() async {
    if (_busy) return 0;
    final files = await SourcePicker.pickFiles();
    if (files.isEmpty) return 0;
    return _ingest(files);
  }

  int _ingest(List<({String name, Uint8List bytes, String? path})> files) {
    final before = _jobs.length;
    final added = SourcePicker.addToQueue(_jobs, files);
    if (added > 0) {
      _selectedId ??= _jobs.first.id;
      _probeAll();
      for (var i = before; i < _jobs.length; i++) {
        _makeThumbnail(_jobs[i]);
      }
      _changed();
    }
    return added;
  }

  /// Best-effort small preview, stored on the job so it survives [releaseSource].
  void _makeThumbnail(ImageJob job) {
    if (job.thumbnail != null || !job.hasSource) return;
    try {
      final thumb = ResizeEngine.thumbnail(job.bytes, maxDim: 256);
      if (thumb != null) job.setThumbnail(thumb);
    } catch (_) {
      // Thumbnails are cosmetic; the run phase reports real errors.
    }
  }

  void addDroppedFiles(
    List<({String name, Uint8List bytes, String? path})> files,
  ) {
    if (_busy) return;
    _ingest(files);
  }

  void _probeAll() {
    for (final job in _jobs) {
      if (job.sourceWidth != null || !job.hasSource) continue;
      try {
        final info = ResizeEngine.probe(job.bytes, name: job.name);
        job.markProbed(info.width, info.height);
      } catch (_) {
        // Left as unknown; the run phase reports the real error.
      }
    }
  }

  void removeJob(String id) {
    if (_busy) return;
    _jobs.removeWhere((j) => j.id == id);
    if (_selectedId == id) {
      _selectedId = _jobs.isEmpty ? null : _jobs.first.id;
    }
    _changed();
  }

  void clearFinished() {
    if (_busy) return;
    _jobs.removeWhere((j) => j.status == JobStatus.done);
    if (selected == null) _selectedId = _jobs.isEmpty ? null : _jobs.first.id;
    _changed();
  }

  void clearAll() {
    if (_busy) return;
    _jobs.clear();
    _selectedId = null;
    _changed();
  }

  void resetQueue() {
    if (_busy) return;
    for (final j in _jobs) {
      j.reset();
    }
    _changed();
  }

  // ----------------------------------------------------------------- naming
  String baseNameOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0) return fileName;
    return fileName.substring(0, dot);
  }

  String _siblingName(String fileName, int page) {
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0) return '${fileName}_p$page';
    return '${fileName.substring(0, dot)}_p$page${fileName.substring(dot)}';
  }

  Future<String> resolveOutputName(ImageJob job, int index) async {
    final bytes = job.output;
    final ext = ResizeEngine.extensionOfName(job.name) ?? 'jpg';
    final outExt = _outputExtension(ext);
    var base = renderTemplate(
      settings.nameTemplate,
      baseName: baseNameOf(job.name),
      outWidth: job.outWidth ?? job.sourceWidth ?? 0,
      outHeight: job.outHeight ?? job.sourceHeight ?? 0,
      srcWidth: job.sourceWidth ?? 0,
      srcHeight: job.sourceHeight ?? 0,
      extension: outExt,
      index: index,
      presetName: settings.presetName,
    );

    if (settings.overwrite) return '$base.$outExt';

    var candidate = '$base.$outExt';
    if (bytes == null) return candidate;
    var n = 1;
    while (await _sink.exists(candidate, directory: _outDir)) {
      candidate = '$base ($n).$outExt';
      n++;
      if (n > 9999) break;
    }
    return candidate;
  }

  String _outputExtension(String sourceExt) {
    if (settings.format == OutputFormat.keep) {
      if (settings.keepExtensionWhenKeepFormat) {
        return sourceExt;
      }
      return 'jpg';
    }
    return settings.format.extension!;
  }

  String? get _outDir {
    final d = settings.outputDirectory.trim();
    return d.isEmpty ? null : d;
  }

  bool get canPickDirectory => _sink.supportsDirectory;

  Future<void> chooseOutputDirectory() async {
    final dir = await SourcePicker.pickDirectory();
    if (dir != null) settings.setOutputDirectory(dir);
  }

  // ---------------------------------------------------------------- pipeline
  /// Rough resident peak for one job: decoded RGBA plus working copies.
  /// Conservative on purpose; underestimating is how batches OOM.
  static int _jobPeak(ImageJob job) => job.inputBytes * 5 + (10 * 1024 * 1024);

  Future<void> runBatch() async {
    if (_busy) return;
    var targets = _jobs.where((j) => j.status != JobStatus.done).toList();
    if (targets.isEmpty) return;

    // Sources released after an earlier write cannot run again.
    for (final j in targets.where((j) => !j.hasSource)) {
      j.markSkipped('Source was released after writing; re-add the file to run it again.');
    }
    targets = targets.where((j) => j.hasSource && j.status != JobStatus.done).toList();
    if (targets.isEmpty) {
      _changed();
      return;
    }

    _busy = true;
    _changed();

    final snapshot = settings.toJson();
    final runSettings = ResizeSettings()..loadFrom(snapshot);
    _cancelToken = CancellationToken();

    try {
      // Split the batch so no chunk's estimated peak exceeds the budget. A
      // single oversized job still runs alone; refusing it would be hostile
      // and the estimate is conservative anyway.
      final budget = runSettings.memoryBudgetMb * 1024 * 1024;
      final chunks = <List<ImageJob>>[];
      var current = <ImageJob>[];
      var currentPeak = 0;
      for (final job in targets) {
        final peak = _jobPeak(job);
        if (current.isNotEmpty && currentPeak + peak > budget) {
          chunks.add(current);
          current = <ImageJob>[];
          currentPeak = 0;
        }
        current.add(job);
        currentPeak += peak;
      }
      if (current.isNotEmpty) chunks.add(current);

      var index = 0;
      for (final chunk in chunks) {
        if (_cancelToken?.isCancelled ?? false) {
          for (final job in chunk) {
            if (job.status == JobStatus.queued) {
              job.markSkipped('Cancelled.');
            }
          }
          _changed();
          break;
        }
        if (WorkerPool.isSupported) {
          _pool ??= await WorkerPool.create();
          await _runPooled(chunk, runSettings, _cancelToken);
        } else {
          for (var i = 0; i < chunk.length; i++) {
            await _runOne(chunk[i], runSettings, _cancelToken);
          }
        }
        index++;
        if (runSettings.writeImmediately) {
          await _writeChunkNow(chunk, index);
        }
      }
    } finally {
      if (_cancelToken?.isCancelled ?? false) {
        for (final j in _jobs.where((j) => j.status == JobStatus.queued)) {
          j.markSkipped('Cancelled.');
        }
      }
      _busy = false;
      _cancelToken = null;
      _changed();
    }
  }

  CancellationToken? _cancelToken;

  /// Stops the batch. Safe to call twice and safe to call after completion.
  /// Jobs already running finish; everything still queued is skipped.
  void cancelBatch() {
    _cancelToken?.cancel();
    _changed();
  }

  /// Writes every freshly completed job in the chunk, then releases its source
  /// bytes. On web this is one download per file; everywhere else it is a
  /// file write followed by freeing the input.
  Future<void> _writeChunkNow(List<ImageJob> chunk, int chunkIndex) async {
    for (var i = 0; i < chunk.length; i++) {
      final job = chunk[i];
      if (job.status != JobStatus.done || job.output == null) continue;
      final name = await resolveOutputName(job, chunkIndex * 1000 + i + 1);
      if (await _sink.saveBytes(job.output!, name, directory: _outDir)) {
        job.releaseSource();
      }
    }
    _changed();
  }

  /// One job on the calling isolate. The web path and every test.
  Future<void> _runOne(
    ImageJob job,
    ResizeSettings runSettings, [
    CancellationToken? cancellation,
  ]) async {
    job.markRunning(0.0);
    _changed();
    final results = await processJob(
      job,
      runSettings,
      cancellation: cancellation,
    );
    _adoptExtraPages(job, results);
    _changed();
  }

  /// Up to [pool] jobs at once, each on its own worker. Progress arrives over
  /// the shared reply port while the UI isolate stays responsive.
  Future<void> _runPooled(
    List<ImageJob> targets,
    ResizeSettings runSettings, [
    CancellationToken? cancellation,
  ]) async {
    final pool = _pool!;
    final settingsJson = runSettings.toJson();
    var next = 0;
    await Future.wait([
      for (var w = 0; w < pool.size; w++)
        _drain(pool, targets, settingsJson, () => next++, cancellation),
    ]);
  }

  Future<void> _drain(
    WorkerPool pool,
    List<ImageJob> targets,
    Map<String, dynamic> settingsJson,
    int Function() take, [
    CancellationToken? cancellation,
  ]) async {
    while (true) {
      if (cancellation?.isCancelled ?? false) return;
      final i = take();
      if (i >= targets.length) return;
      final job = targets[i];
      if (cancellation?.isCancelled ?? false) {
        job.markSkipped('Cancelled.');
        _changed();
        continue;
      }
      job.markRunning(0.0);
      _changed();
      final id = pool.nextId();
      try {
        final maps = await pool.run(
          IsolateMessage(
            id: id,
            settingsJson: settingsJson,
            source: job.bytes,
            name: job.name,
          ),
          job.markRunning,
        );
        final results = maps.map(EngineResult.fromMap).toList();
        final first = results.first;
        job.markDone(
          output: first.bytes,
          width: first.width,
          height: first.height,
          quality: first.quality,
          frames: first.frames,
          notice: first.notice,
        );
        _adoptExtraPages(job, results);
      } on EngineError catch (e) {
        job.markFailed(e.message);
      } catch (e) {
        job.markFailed('Unexpected error: $e');
      }
      _changed();
    }
  }

  /// A multi-page document yields one result per page. The first stays on the
  /// original job; the rest become siblings so each saves under its own name.
  void _adoptExtraPages(ImageJob job, List<EngineResult> results) {
    for (var k = 1; k < results.length; k++) {
      final r = results[k];
      final sibling = ImageJob(
        id: '${job.id}-p${k + 1}',
        name: _siblingName(job.name, k + 1),
        bytes: job.bytes,
        path: job.path,
      );
      sibling.markDone(
        output: r.bytes,
        width: r.width,
        height: r.height,
        quality: r.quality,
        frames: r.frames,
        notice: r.notice,
      );
      final at = _jobs.indexOf(job);
      _jobs.insert(at < 0 ? _jobs.length : at + k, sibling);
    }
  }

  Future<int> saveAll() async {
    final done = _jobs
        .where((j) => j.status == JobStatus.done && j.output != null)
        .toList();
    if (done.isEmpty) return 0;

    var written = 0;
    for (var i = 0; i < done.length; i++) {
      final job = done[i];
      final bytes = job.output;
      if (bytes == null) continue;
      final name = await resolveOutputName(job, i + 1);
      if (await _sink.saveBytes(bytes, name, directory: _outDir)) {
        written++;
        job.releaseSource();
      }
    }
    _changed();
    return written;
  }

  @override
  void dispose() {
    settings.dispose();
    for (final j in _jobs) {
      j.dispose();
    }
    _pool?.dispose();
    super.dispose();
  }
}
