import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelforge/core/diagnostics/crash_log.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('pixelforge-crashlog');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  CrashLog makeLog({int maxBytes = 4096, int maxFiles = 3}) =>
      CrashLog(directory: dir, maxBytes: maxBytes, maxFiles: maxFiles);

  group('writing', () {
    test('a thrown exception appears in the log file', () async {
      final log = makeLog();
      log.add('boom', 'something went wrong');
      await log.flush();

      expect(dir.listSync(), isNotEmpty, reason: 'nothing was written');
      expect(log.readAll(), contains('something went wrong'));
    });

    test('a framework error is recorded with its kind', () async {
      final log = makeLog();
      log.recordFlutterError(
        FlutterErrorDetails(
          exception: StateError('bad state'),
          stack: StackTrace.fromString('#0 a (package:x/y.dart:1:1)'),
        ),
      );
      await log.flush();

      final text = log.readAll();
      expect(text, contains('bad state'));
      expect(text, contains('framework error'));
    });

    test('an async error is recorded', () async {
      final log = makeLog();
      log.recordPlatformError(
        ArgumentError('nope'),
        StackTrace.fromString('#0 b (package:q/r.dart:2:2)'),
      );
      await log.flush();

      expect(log.readAll(), contains('nope'));
      expect(log.readAll(), contains('async error'));
    });

    test('a missing directory is created rather than throwing', () async {
      final nested = Directory(
        '${dir.path}${Platform.pathSeparator}a${Platform.pathSeparator}b',
      );
      expect(nested.existsSync(), isFalse);

      final log = CrashLog(directory: nested);
      log.add('kind', 'body');
      await log.flush();

      expect(nested.existsSync(), isTrue);
      expect(log.readAll(), contains('body'));
    });

    test('clear removes every file', () async {
      final log = makeLog();
      log.add('a', 'one');
      await log.flush();
      expect(log.files(), isNotEmpty);

      log.clear();
      expect(log.files(), isEmpty);
      expect(log.readAll(), isEmpty);
    });
  });

  group('privacy', () {
    // Each case is something that must never survive into the file. A crash
    // log containing a filename would undermine the entire product claim.
    final leaks = <String, String>{
      'unix path': 'failed reading /home/sam/Pictures/holiday',
      'windows path': r'failed reading C:\Users\sam\Documents\stuff',
      'image filename': 'could not decode photo.jpg',
      'heic filename': 'could not decode IMG_0042.HEIC',
      'png filename': 'output written to screenshot.png',
      'gif filename': 'animation at walk.gif',
      'file uri': 'at file:///home/sam/Pictures/a.png',
      'url query': 'fetched https://example.com/x?token=abc123',
    };

    leaks.forEach((name, input) {
      test('redacts $name', () {
        final out = CrashLog.redact(input);
        for (final needle in ['sam', 'holiday', 'IMG_0042', 'abc123']) {
          expect(
            out,
            isNot(contains(needle)),
            reason: '"$needle" leaked through "$name": $out',
          );
        }
      });
    });

    test('no leak reaches the written file', () async {
      final log = makeLog();
      for (final entry in leaks.entries) {
        log.add('test', '${entry.key}: ${entry.value}');
      }
      await log.flush();

      final text = log.readAll();
      for (final needle in [
        'sam',
        'holiday',
        'IMG_0042',
        'screenshot.png',
        'walk.gif',
        'abc123',
        'Documents',
        'Pictures',
      ]) {
        expect(
          text,
          isNot(contains(needle)),
          reason: '"$needle" reached the log file',
        );
      }
    });

    test('a stack trace is redacted too', () async {
      final log = makeLog();
      log.recordFlutterError(
        FlutterErrorDetails(
          exception: StateError('failed'),
          stack: StackTrace.fromString(
            '#0 load (file:///home/sam/pixelforge/lib/main.dart:12:3)\n'
            '#1 run (file:///home/sam/pixelforge/lib/main.dart:20:7)',
          ),
        ),
      );
      await log.flush();

      final text = log.readAll();
      expect(text, isNot(contains('/home/sam')));
      expect(text, isNot(contains('main.dart')));
    });

    test('a long opaque hash is replaced but the shape survives', () {
      const hash = 'deadbeefcafebabe0123456789abcdef0123';
      final out = CrashLog.redact('cache key $hash expired');
      expect(out, isNot(contains(hash)));
      expect(out, contains('<hash>'));
      expect(
        out,
        contains('cache key'),
        reason: 'redaction must keep the log diagnosable',
      );
    });

    test('the shared JSON is redacted as well', () async {
      final log = makeLog();
      log.add('test', 'reading /home/sam/Pictures/secret.jpg');
      await log.flush();

      final json = log.toShareJson();
      expect(json, isNot(contains('secret.jpg')));
      expect(json, isNot(contains('sam')));
      expect(json, contains('PixelForge'));
    });

    test('every declared rule is named and has a replacement', () {
      for (final rule in CrashLog.rules) {
        expect(
          rule.name,
          isNotEmpty,
          reason: 'an unnamed rule cannot be debugged when it misses',
        );
        expect(rule.replacement, isNotEmpty);
      }
    });
  });

  group('rotation', () {
    test('the live log file is capped in size', () async {
      final log = makeLog(maxBytes: 2048, maxFiles: 3);
      for (var i = 0; i < 200; i++) {
        log.add('loop', 'entry number $i padded out a little');
      }
      await log.flush();

      final live = File(CrashLog.logPathIn(dir, 0));
      expect(live.existsSync(), isTrue);
      expect(
        live.lengthSync(),
        lessThanOrEqualTo(2048 * 2),
        reason: 'the live file must be bounded, not grow without limit',
      );
    });

    test('rotation keeps a bounded number of files', () async {
      final log = makeLog(maxBytes: 1024, maxFiles: 3);
      for (var i = 0; i < 300; i++) {
        log.add('loop', 'entry $i with enough text to force rotation soon');
      }
      await log.flush();

      expect(
        log.files().length,
        lessThanOrEqualTo(3),
        reason: 'rotation must discard the oldest, not accumulate',
      );
    });

    test('total disk usage stays bounded', () async {
      final log = makeLog(maxBytes: 1024, maxFiles: 3);
      for (var i = 0; i < 400; i++) {
        log.add('loop', 'entry $i padding padding padding padding');
      }
      await log.flush();

      expect(
        log.totalBytes,
        lessThanOrEqualTo(1024 * 3 * 2),
        reason: 'a crash loop must not be able to fill the disk',
      );
    });

    test('the live file holds the newest entries, not the oldest', () async {
      final log = makeLog(maxBytes: 1024, maxFiles: 2);
      for (var i = 0; i < 200; i++) {
        log.add('loop', 'entry $i padding padding padding padding padding');
      }
      await log.flush();

      expect(log.files().length, 2);
      final live = File(CrashLog.logPathIn(dir, 0)).readAsStringSync();
      expect(live, contains('entry 199'));
    });

    test('a retention of zero still keeps the newest crash', () async {
      final log = makeLog(maxBytes: 512, maxFiles: 0);
      for (var i = 0; i < 100; i++) {
        log.add('loop', 'entry $i padding padding padding padding');
      }
      await log.flush();

      expect(
        log.files(),
        hasLength(1),
        reason:
            'discarding the crash that just happened would defeat the '
            'purpose of the log; zero is treated as one',
      );
      expect(log.readAll(), contains('entry 99'));
    });

    test('files are listed newest first', () async {
      final log = makeLog(maxBytes: 900, maxFiles: 3);
      for (var i = 0; i < 200; i++) {
        log.add('loop', 'entry $i padding padding padding padding');
      }
      await log.flush();

      final names = log
          .files()
          .map((f) => f.path.split(Platform.pathSeparator).last)
          .toList();
      expect(
        names.first,
        'crash.log',
        reason:
            'the live file must sort first and be named without a stray '
            'separator, or the diagnostics page shows a rotated file',
      );
      expect(names.length, greaterThan(1));
    });
  });

  group('diagnostics support', () {
    test('the log directory is app-private, not shared', () {
      final support = getApplicationSupportDirectory();
      expect(support.path, contains('PixelForge'));
      expect(
        support.path.toLowerCase(),
        isNot(contains('public')),
        reason: 'the log must not land in shared storage',
      );
    });

    test('reading a missing directory is empty, not an error', () {
      final log = CrashLog(
        directory: Directory('${dir.path}${Platform.pathSeparator}nope'),
      );
      expect(log.readAll(), isEmpty);
      expect(log.totalBytes, 0);
    });
  });
}
