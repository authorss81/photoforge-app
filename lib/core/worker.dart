import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'engine.dart';
import 'settings.dart';
import 'worker_size_stub.dart' if (dart.library.io) 'worker_size_io.dart';

/// A unit of work sent to a background isolate. Everything in the message is
/// a primitive, a plain map, or typed data, because that is all an isolate
/// message can carry. Settings travel as their JSON snapshot and are rebuilt
/// on the other side, so this file can never drift from [ResizeSettings].
class IsolateMessage {
  const IsolateMessage({
    required this.id,
    required this.settingsJson,
    required this.source,
    required this.name,
  });

  final int id;
  final Map<String, dynamic> settingsJson;
  final Uint8List source;
  final String? name;

  Map<String, dynamic> toMessage(SendPort replyTo) => {
        'id': id,
        'settings': settingsJson,
        'source': source,
        'name': name,
        'replyTo': replyTo,
      };
}

/// Entry point for every worker isolate. Top-level, so the VM can spawn it.
void workerEntry(SendPort mainPort) {
  final inbox = ReceivePort();
  mainPort.send(inbox.sendPort);
  inbox.listen((raw) async {
    final msg = raw as Map;
    final int id = msg['id'] as int;
    final SendPort replyTo = msg['replyTo'] as SendPort;
    try {
      final settings = ResizeSettings()
        ..loadFrom((msg['settings'] as Map).cast<String, dynamic>());
      final result = await ResizeEngine.runAll(
        msg['source'] as Uint8List,
        settings,
        name: msg['name'] as String?,
        onProgress: (v) => replyTo.send({'id': id, 'progress': v}),
      );
      replyTo.send({
        'id': id,
        'results': [
          for (final r in result)
            {
              'bytes': r.bytes,
              'width': r.width,
              'height': r.height,
              'extension': r.extension,
              'quality': r.quality,
              'metTarget': r.metTarget,
              'frames': r.frames,
              'notice': r.notice,
            },
        ],
      });
    } catch (e) {
      replyTo.send({'id': id, 'error': e.toString()});
    }
  });
}

class _Worker {
  _Worker(this.sendPort);

  final SendPort sendPort;
  bool busy = false;
}

/// A fixed pool of background isolates. One job per worker, so peak memory is
/// bounded by the pool size rather than the queue length.
///
/// Replies from every worker arrive on one shared port and are demultiplexed
/// by job id, so per-call ports are never created or leaked.
class WorkerPool {
  WorkerPool._(this._workers, this._replies, this._replyTo);

  final List<_Worker> _workers;
  final ReceivePort _replies;
  final SendPort _replyTo;

  int _nextId = 0;
  final Map<int, Completer<List<Map<String, dynamic>>>> _pending = {};
  final Map<int, void Function(double)> _progress = {};

  /// Isolates do not exist on web. Callers must fall back to main-isolate
  /// execution there; this class is never constructed on web.
  static bool get isSupported => !kIsWeb;

  static Future<WorkerPool> create({int? size}) async {
    final n = (size != null && size > 0) ? size : defaultWorkerCount();
    final replies = ReceivePort();
    final pool = WorkerPool._([], replies, replies.sendPort);
    replies.listen(pool._onMessage);
    for (var i = 0; i < n; i++) {
      final fromWorker = ReceivePort();
      await Isolate.spawn(workerEntry, fromWorker.sendPort);
      final sendPort = await fromWorker.first as SendPort;
      fromWorker.close();
      pool._workers.add(_Worker(sendPort));
    }
    return pool;
  }

  void _onMessage(dynamic raw) {
    final msg = raw as Map;
    final int id = msg['id'] as int;
    if (msg.containsKey('progress')) {
      _progress[id]?.call((msg['progress'] as num).toDouble());
      return;
    }
    final completer = _pending.remove(id);
    _progress.remove(id);
    final worker = _workerFor(id);
    if (worker != null) worker.busy = false;
    if (completer == null) return;
    if (msg.containsKey('error')) {
      completer.completeError(EngineError(msg['error'] as String));
    } else {
      completer.complete(
        ((msg['results'] as List).cast<Map>())
            .map((m) => m.cast<String, dynamic>())
            .toList(),
      );
    }
  }

  final Map<int, _Worker> _byId = {};

  _Worker? _workerFor(int id) => _byId.remove(id);

  /// Runs one job on the first free worker. Throws [EngineError] when the
  /// worker reports one.
  Future<List<Map<String, dynamic>>> run(
    IsolateMessage message, [
    void Function(double)? onProgress,
  ]) {
    final worker = _workers.firstWhere(
      (w) => !w.busy,
      orElse: () => throw StateError('no free worker; the pool is oversubscribed'),
    );
    worker.busy = true;
    _byId[message.id] = worker;
    final completer = Completer<List<Map<String, dynamic>>>();
    _pending[message.id] = completer;
    if (onProgress != null) _progress[message.id] = onProgress;
    worker.sendPort.send(message.toMessage(_replyTo));
    return completer.future;
  }

  int nextId() => _nextId++;

  int get size => _workers.length;

  int get busyCount => _workers.where((w) => w.busy).length;

  void dispose() {
    _replies.close();
  }
}
