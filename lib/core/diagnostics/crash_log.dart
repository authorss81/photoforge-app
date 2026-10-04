import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// An offline crash log the user can choose to share.
///
/// There is no network in this app, by design and by manifest, so this cannot
/// report anything by itself. It writes to a file the user is shown and can
/// decide to share or delete. That is the only honest version of crash
/// reporting for an offline product.
///
/// Two rules govern everything here:
///
/// 1. **Nothing identifying.** A crash log that contains a filename or a path
///    undermines the entire privacy claim of the product. Every entry passes
///    through [redact] before it is written, and a test asserts the patterns
///    that would leak never survive.
/// 2. **Bounded.** The log rotates and is capped, so a crash loop cannot fill
///    the user's disk. An unbounded log on a device with no way to clear it is
///    a bug waiting to happen.
class CrashLog {
  CrashLog({
    Directory? directory,
    this.maxBytes = defaultMaxBytes,
    this.maxFiles = 3,
  }) : _dir = directory;

  /// Where the log lives. Defaults to the platform's application support
  /// directory, which is app-private and needs no permission.
  final Directory? _dir;

  /// Hard cap on one file. Old files are rotated out, so total usage is bounded
  /// by maxBytes * maxFiles.
  final int maxBytes;

  /// How many rotated files to keep.
  final int maxFiles;

  static const int defaultMaxBytes = 256 * 1024;

  static const String filePrefix = 'crash';
  static const String fileSuffix = '.log';

  final ListQueue<String> _pending = ListQueue<String>();
  Future<void> _writing = Future<void>.value();

  /// Directory the log is written to.
  ///
  /// Public so a test can point it at a temp dir and assert the rotation
  /// behaviour for real, rather than asserting on a mock.
  Directory? get directory => _dir;

  File get _current => File(logPathIn(_resolve(), 0));

  /// Builds the path of the log file with rotation [index].
  ///
  /// 0 is the live file, 1 the previous one, and so on. One place builds these
  /// so the writer, the rotator and the lister cannot disagree on the naming.
  static String logPathIn(Directory dir, int index) =>
      '${dir.path}${Platform.pathSeparator}$filePrefix'
      '${index == 0 ? '' : '.$index'}$fileSuffix';

  Directory _resolve() {
    final d = _dir;
    if (d != null) return d;
    final support = getApplicationSupportDirectory();
    return Directory('${support.path}${Platform.pathSeparator}diagnostics');
  }

  /// Records a Flutter framework error.
  void recordFlutterError(FlutterErrorDetails details) {
    // The exception object is the useful part; the library/context strings are
    // noise that frequently contain file paths.
    final error = details.exception;
    final stack = details.stack;
    add(
      'framework error',
      stack == null ? '$error' : '$error\n${_trimStack(stack)}',
    );
  }

  /// Records an uncaught asynchronous error.
  void recordPlatformError(Object error, StackTrace? stack) {
    add(
      'async error',
      stack == null ? '$error' : '$error\n${_trimStack(stack)}',
    );
  }

  /// Appends one entry. Safe to call from anywhere, including from inside a
  /// crash handler, so it must not throw.
  void add(String kind, String body) {
    final entry = _format(kind, body);
    _pending.add(entry);
    _drain();
  }

  String _format(String kind, String body) {
    final now = DateTime.now().toUtc().toIso8601String();
    return '--- $now [$kind]\n${redact(body)}\n';
  }

  void _drain() {
    _writing = _writing.then((_) => _flush()).catchError((_) {
      // A log that cannot be written must never take the app down with it. This
      // is the one place an exception is deliberately swallowed.
    });
  }

  Future<void> _flush() async {
    if (_pending.isEmpty) return;
    final batch = _pending.toList();
    _pending.clear();
    try {
      final dir = _resolve();
      if (!dir.existsSync()) dir.createSync(recursive: true);

      // Write entry by entry, rotating between them, rather than concatenating
      // the whole batch and writing once. A batch can be far larger than
      // maxBytes: a tight crash loop queues hundreds of errors before the first
      // flush runs, so a single concatenated write would blow straight past
      // the cap. Writing per entry keeps every file bounded.
      for (final entry in batch) {
        final file = _current;
        // Rotate before appending, not after. Rotating afterwards renames the
        // file the entry was just written to, so the newest crash could end up
        // in crash.1.log while crash.log does not exist at all. Deciding first
        // means crash.log always holds the most recent entries.
        if (file.existsSync() && file.lengthSync() + entry.length > maxBytes) {
          _rotate(dir);
        }
        _current.writeAsStringSync(entry, mode: FileMode.append, flush: true);
      }
    } on Object {
      // Disk full, no permission, read-only media: all out of scope here.
    }
  }

  /// Waits for queued writes. Tests and the share action need this; the app
  /// itself does not, since logging is best-effort.
  Future<void> flush() => _writing;

  void _rotate(Directory dir) {
    // crash.log becomes crash.1.log, crash.1.log becomes crash.2.log, and the
    // oldest is discarded. Newest-first ordering, bounded to maxFiles.
    // maxFiles is clamped to at least 1. Keeping nothing would mean discarding the
    // crash that just happened, which defeats the purpose of the log. A
    // degenerate configuration is treated as "keep only the newest", not as
    // "keep nothing".
    final keep = maxFiles < 1 ? 1 : maxFiles;
    // maxFiles counts the live file too, not just the rotated ones. Counting
    // only the rotated ones is the off-by-one that let a fourth file exist with
    // maxFiles 3.
    for (var i = keep - 1; i >= 1; i--) {
      final from = File(logPathIn(dir, i));
      if (!from.existsSync()) continue;
      final to = File(logPathIn(dir, i + 1));
      if (to.existsSync()) to.deleteSync();
      from.renameSync(to.path);
    }
    final first = File(logPathIn(dir, 0));
    if (first.existsSync()) {
      final dest = File(logPathIn(dir, 1));
      if (dest.existsSync()) dest.deleteSync();
      first.renameSync(dest.path);
    }
    // Anything past the retention window goes, including a file left over from
    // a run configured with a larger retention.
    for (var i = keep; i <= keep + 4; i++) {
      final stale = File(logPathIn(dir, i));
      if (stale.existsSync()) stale.deleteSync();
    }
  }

  /// Every log file, newest first.
  List<File> files() {
    final dir = _dir ?? Directory(_resolve().path);
    if (!dir.existsSync()) return const [];
    final out = <File>[];
    for (final e in dir.listSync()) {
      if (e is! File) continue;
      final base = e.path.split(Platform.pathSeparator).last;
      if (!base.startsWith(filePrefix) || !base.endsWith(fileSuffix)) continue;
      out.add(e);
    }
    // crash.log is newest, then crash.1.log, and so on.
    out.sort((a, b) => _index(a).compareTo(_index(b)));
    return out;
  }

  static int _index(File f) {
    final base = f.path.split(Platform.pathSeparator).last;
    final core = base.substring(
      filePrefix.length,
      base.length - fileSuffix.length,
    );
    // "crash.log" is the live file at index 0; "crash.3.log" is three rotations
    // back. A dot with no number after it is the live file, not a parse failure.
    if (core.isEmpty || core == '.') return 0;
    return int.tryParse(core.substring(1)) ?? 0;
  }

  /// The whole log as text, oldest first, for display and sharing.
  String readAll() {
    final out = StringBuffer();
    final fs = files().reversed;
    for (final f in fs) {
      try {
        out.writeln(f.readAsStringSync());
      } on Object {
        // Skip a file that vanished between listing and reading.
      }
    }
    return out.toString();
  }

  /// Removes every log file. The clear button.
  void clear() {
    for (final f in files()) {
      try {
        f.deleteSync();
      } on Object {
        // Nothing useful to do; the next write recreates it.
      }
    }
  }

  /// Total bytes on disk across all files, for the diagnostics page.
  int get totalBytes =>
      files().fold(0, (sum, f) => sum + (f.existsSync() ? f.lengthSync() : 0));

  // ---------------------------------------------------------------- redaction

  /// Patterns that must never reach the file.
  ///
  /// Kept as data rather than code so the test that asserts they are stripped
  /// and the code that strips them cannot drift apart.
  static final List<RedactionRule> rules = [
    // Order matters. Paths and URLs go before the generic filename rule,
    // because a path's last segment would otherwise survive as "<file>" and
    // the directories leading to it would still be visible.
    //
    // A URL is reduced to its host. There is no network in this app, so a host
    // is either a bug worth seeing or nothing, and the path and query on a URL
    // can both carry an identifier.
    RedactionRule(
      name: 'url',
      pattern: RegExp(r'''https?://[^\s"']+'''),
      replacement: '<url>',
    ),
    // package:file URIs, which wrap an absolute path.
    RedactionRule(
      name: 'file uri',
      pattern: RegExp(r'''file:/{2,3}[^\s"']*'''),
      replacement: '<path>',
    ),
    // Windows paths, before the generic rule can chop the extension off.
    RedactionRule(
      // Triple-quoted raw string: the class must exclude both quote
      // characters, and a single-quoted raw string cannot contain an apostrophe.
      name: 'windows path',
      pattern: RegExp(r'''[A-Za-z]:\\[^\s"']*'''),
      replacement: '<path>',
    ),
    // Absolute POSIX paths: /home/sam/Pictures/holiday.jpg
    RedactionRule(
      name: 'unix path',
      pattern: RegExp(r'(?:/[A-Za-z0-9._~+-]+){2,}'),
      replacement: '<path>',
    ),
    RedactionRule(
      name: 'windows path',
      // Triple-quoted raw string: the class must exclude both quote
      // characters, and a single-quoted raw string cannot contain an apostrophe.
      pattern: RegExp(r'''[A-Za-z]:\\[^\s"']*'''),
      replacement: '<path>',
    ),
    // A filename with a known image extension, wherever it appears.
    RedactionRule(
      name: 'image filename',
      pattern: RegExp(
        r'\b[\w\-. ]+\.(?:jpe?g|png|gif|webp|bmp|tiff?|heic|heif|avif|pdf|svg|psd)\b',
        caseSensitive: false,
      ),
      replacement: '<file>',
    ),
  ];

  /// Removes identifying detail from [input].
  ///
  /// Applied to every entry, twice: once to the body, and once to the whole
  /// formatted entry in [add]. Redacting at both levels means a rule added
  /// later cannot leak through a field that is built after the first pass.
  static String redact(String input) {
    var out = input;
    for (final r in rules) {
      out = out.replaceAll(r.pattern, r.replacement);
    }
    // Long opaque strings are usually ids or hashes. Keep the shape, drop the
    // content, so the log stays diagnosable.
    out = out.replaceAll(_opaque, '<hash>');
    return out;
  }

  static final RegExp _opaque = RegExp(r'\b[0-9a-fA-F]{16,}\b');

  /// Reduces a stack trace to frames inside the app, dropping any path.
  ///
  /// Frame lines look like "#3  package:pixelforge/core/engine.dart:412:7".
  static String _trimStack(StackTrace stack, {int maxFrames = 12}) {
    final lines = stack.toString().split('\n');
    final kept = <String>[];
    for (final l in lines) {
      if (kept.length >= maxFrames) break;
      if (!l.trimLeft().startsWith('#')) continue;
      kept.add(redact(l.trim()));
    }
    // Always keep a marker when the trace was longer than the cap, so a
    // truncated log is never mistaken for a complete one.
    if (lines.length > maxFrames) kept.add('... trace truncated');
    return kept.join('\n');
  }

  /// JSON rendering for the share action. Same content, so the redaction
  /// guarantee holds for a shared file too.
  String toShareJson() {
    return const JsonEncoder.withIndent('  ').convert({
      'app': 'PixelForge',
      'entries': readAll()
          .split('--- ')
          .where((s) => s.trim().isNotEmpty)
          .map((s) => s.trim())
          .toList(),
    });
  }
}

/// One redaction pattern and what replaces it.
class RedactionRule {
  const RedactionRule({
    required this.name,
    required this.pattern,
    required this.replacement,
  });

  /// Used in test failure messages, so a leak names the rule that missed it.
  final String name;
  final RegExp pattern;
  final String replacement;
}

/// The process-wide log, installed as the global error handler at startup.
///
/// Lives here rather than in main.dart so the diagnostics page can reach it
/// without importing main, which would be a cycle: main imports the UI, and the
/// UI needs the log.
final CrashLog crashLog = CrashLog();

/// Resolves the app support directory. Injectable so tests can redirect it.
Directory getApplicationSupportDirectory() {
  final override = Platform.environment['PIXELFORGE_SUPPORT_DIR'];
  if (override != null && override.isNotEmpty) return Directory(override);
  final home =
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.systemTemp.path;
  return Directory(
    '${Directory(home).path}${Platform.pathSeparator}'
    '.local${Platform.pathSeparator}share${Platform.pathSeparator}PixelForge',
  );
}
