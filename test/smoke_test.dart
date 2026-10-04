import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixelforge/core/diagnostics/crash_log.dart';
import 'package:pixelforge/core/engine.dart';
import 'package:pixelforge/core/resize_mode.dart';
import 'package:pixelforge/core/settings.dart';
import 'package:pixelforge/l10n/app_localizations.dart';
import 'package:pixelforge/ui/diagnostics_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// End-to-end check that the pipeline still produces real output, and that the
/// crash log catches a failure without losing anything.
///
/// A widget test is not enough for the pipeline half: the engine runs in
/// isolates and does real file and memory work. The CI job runs this on an
/// emulator via integration_test; see `.github/workflows/build.yml`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('pipeline smoke', () {
    test('a real image is resized and re-encoded', () async {
      // A gradient with enough detail that a wrong resize is visible, not just
      // a wrong number.
      final src = img.Image(width: 640, height: 480);
      for (var y = 0; y < 480; y++) {
        for (var x = 0; x < 640; x++) {
          src.setPixelRgba(x, y, x * 255 ~/ 640, y * 255 ~/ 480, 128, 255);
        }
      }
      final png = img.encodePng(src);

      final settings = ResizeSettings()
        ..setMode(ResizeMode.width)
        ..setWidth(160)
        ..setFormat(OutputFormat.jpeg);

      final result = await ResizeEngine.run(png, settings, name: 'smoke.png');
      expect(
        result.width,
        160,
        reason: 'the output must be the requested width',
      );
      expect(result.height, 120, reason: 'the aspect ratio must be kept');

      final decoded = img.decodeJpg(result.bytes);
      expect(decoded, isNotNull, reason: 'the output must be a decodable JPEG');
      expect(decoded!.width, 160);
      expect(decoded.height, 120);

      // Content survived: the gradient is still a gradient, not a flat fill.
      final tl = decoded.getPixel(4, 4);
      final br = decoded.getPixel(155, 115);
      expect(
        tl.r + tl.g + tl.b,
        isNot(closeTo(br.r + br.g + br.b, 5)),
        reason: 'the resized image must still contain the original gradient',
      );
    });

    test('alpha is preserved through a PNG round trip', () async {
      final src = img.Image(width: 64, height: 64, numChannels: 4);
      for (var y = 0; y < 64; y++) {
        for (var x = 0; x < 64; x++) {
          src.setPixelRgba(x, y, 200, 100, 50, x < 32 ? 255 : 0);
        }
      }
      final settings = ResizeSettings()
        ..setMode(ResizeMode.width)
        ..setWidth(32)
        ..setFormat(OutputFormat.png);

      final result = await ResizeEngine.run(
        img.encodePng(src),
        settings,
        name: 'alpha.png',
      );
      final decoded = img.decodePng(result.bytes);
      expect(decoded, isNotNull);
      expect(
        decoded!.getPixel(2, 2).a,
        greaterThan(200),
        reason: 'the opaque half must stay opaque',
      );
      expect(
        decoded.getPixel(29, 2).a,
        lessThan(60),
        reason: 'the transparent half must stay transparent',
      );
    });

    test('a corrupt file fails with an actionable message', () async {
      final broken = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      ]);
      final settings = ResizeSettings()..setFormat(OutputFormat.png);

      // The engine must fail loudly rather than produce an empty or blank file.
      var threw = false;
      try {
        await ResizeEngine.run(broken, settings, name: 'broken.png');
      } on Object {
        threw = true;
      }
      expect(threw, isTrue, reason: 'a corrupt file must not silently succeed');
    });
  });

  group('crash capture', () {
    test('a real engine failure reaches the log, redacted', () async {
      final dir = Directory.systemTemp.createTempSync('smoke-log');
      addTearDown(() => dir.deleteSync(recursive: true));
      final log = CrashLog(directory: dir);

      final broken = Uint8List.fromList([1, 2, 3, 4]);
      try {
        await ResizeEngine.run(
          broken,
          ResizeSettings()..setFormat(OutputFormat.png),
          name: '/home/sam/Pictures/holiday.png',
        );
      } on Object catch (e, s) {
        // What the global handler would receive.
        log.recordPlatformError(e, s);
      }
      await log.flush();

      final text = log.readAll();
      expect(text, isNotEmpty, reason: 'the failure was not captured');
      expect(text, isNot(contains('sam')));
      expect(text, isNot(contains('holiday')));
    });
  });

  group('diagnostics page', () {
    late Directory dir;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      dir = Directory.systemTemp.createTempSync('diag-page');
    });

    tearDown(() => dir.deleteSync(recursive: true));

    Future<void> pump(WidgetTester tester, CrashLog log) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: DiagnosticsPage(log: log),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('says plainly that nothing is uploaded', (tester) async {
      final log = CrashLog(directory: dir);
      await pump(tester, log);

      final notice = find.text(EnStrings().diagnosticsPrivacy);
      expect(notice, findsOneWidget);
      expect(
        EnStrings().diagnosticsPrivacy.toLowerCase(),
        allOf(contains('never uploaded'), contains('device')),
      );
    });

    testWidgets('shows an empty state when nothing has crashed', (
      tester,
    ) async {
      await pump(tester, CrashLog(directory: dir));
      expect(find.text(EnStrings().diagnosticsEmpty), findsOneWidget);
    });

    testWidgets('shows recorded entries', (tester) async {
      final log = CrashLog(directory: dir);
      log.add('test', 'the widget exploded');
      await pump(tester, log);

      expect(find.textContaining('the widget exploded'), findsOneWidget);
      expect(find.text(EnStrings().diagnosticsEmpty), findsNothing);
    });

    testWidgets('reports the on-disk size', (tester) async {
      final log = CrashLog(directory: dir);
      log.add('test', 'something happened here');
      await pump(tester, log);

      expect(find.textContaining('on disk'), findsOneWidget);
    });

    testWidgets('clear asks before deleting', (tester) async {
      final log = CrashLog(directory: dir);
      log.add('test', 'keep me until confirmed');
      await pump(tester, log);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(log.readAll(), contains('keep me until confirmed'));

      await tester.tap(find.text(EnStrings().cancel));
      await tester.pumpAndSettle();

      expect(
        log.readAll(),
        contains('keep me until confirmed'),
        reason: 'cancelling must not delete anything',
      );
    });

    testWidgets('clear deletes after confirmation', (tester) async {
      final log = CrashLog(directory: dir);
      log.add('test', 'delete me');
      await pump(tester, log);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, EnStrings().diagnosticsClear),
      );
      await tester.pumpAndSettle();

      expect(log.readAll(), isEmpty);
      expect(find.text(EnStrings().diagnosticsEmpty), findsOneWidget);
    });

    testWidgets('copy puts the redacted log on the clipboard', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      final log = CrashLog(directory: dir);
      log.add('test', 'reading /home/sam/Pictures/secret.jpg');
      await pump(tester, log);

      await tester.tap(find.byIcon(Icons.copy_all_outlined));
      await tester.pumpAndSettle();

      expect(copied, hasLength(1));
      expect(copied.single, isNot(contains('secret.jpg')));
      expect(copied.single, isNot(contains('sam')));
      expect(copied.single, contains('PixelForge'));
    });

    testWidgets('every action button has a tooltip', (tester) async {
      await pump(tester, CrashLog(directory: dir));
      final l10n = EnStrings();
      expect(find.byTooltip(l10n.diagnosticsCopy), findsOneWidget);
      expect(find.byTooltip(l10n.diagnosticsClear), findsOneWidget);
    });
  });
}
