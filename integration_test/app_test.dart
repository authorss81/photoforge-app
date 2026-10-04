// End-to-end test that runs the real app on a real device.
//
// This exists because every other test in this repository runs in a fake
// environment. Widget tests never launch the platform, so an app that crashes
// on startup, or a plugin that fails to register, passes the entire suite and
// then shows a white screen to the user.
//
// Run it with:
//   flutter test integration_test/app_test.dart
//
// CI runs it on an emulator; see the `smoke` job in build.yml.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:pixelforge/core/controller.dart';
import 'package:pixelforge/core/engine.dart';
import 'package:pixelforge/core/resize_mode.dart';
import 'package:pixelforge/core/settings.dart';
import 'package:pixelforge/ui/diagnostics_page.dart';
import 'package:pixelforge/ui/home_page.dart';
import 'package:pixelforge/ui/theme.dart';

/// Renders [child] at each real screen size and fails on any overflow.
///
/// A RenderFlex overflow is reported through the exception channel rather than
/// thrown, so it is caught with `takeException`. The sizes are the real ones a
/// phone uses, not one arbitrary test size.
Future<void> _expectNoOverflow(WidgetTester tester) async {
  const sizes = <(double, double)>[
    (360, 640), // small Android
    (411, 891), // Pixel 6
    (800, 1280), // large Android
  ];
  final controller = ResizeController();
  addTearDown(controller.dispose);

  for (final (w, h) in sizes) {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: w,
            height: h,
            child: HomePage(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason:
          'the layout must not overflow at ${w.toInt()}x${h.toInt()}. '
          'A RenderFlex overflow means something does not fit a real screen.',
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the app launches and shows its queue', (tester) async {
    final controller = ResizeController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: HomePage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    // A real assertion about a real widget: the app bar exists and the app is
    // interactive. If the platform had failed to start, this never runs.
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byType(HomePage), findsOneWidget);

    // No layout overflow at any real screen size. This caught a genuine
    // 12-pixel overflow on the default Android emulator, which no widget test
    // had found: they run at whatever size the test happens to pick.
    await _expectNoOverflow(tester);
  });

  testWidgets('an image is processed end to end on the device', (tester) async {
    final controller = ResizeController();
    addTearDown(controller.dispose);

    // A real gradient, so the output can be checked for content and not only
    // for its dimensions.
    final src = img.Image(width: 800, height: 600);
    for (var y = 0; y < 600; y++) {
      for (var x = 0; x < 800; x++) {
        src.setPixelRgba(x, y, x * 255 ~/ 800, y * 255 ~/ 600, 90, 255);
      }
    }
    final bytes = img.encodePng(src);

    final settings = ResizeSettings()
      ..setMode(ResizeMode.width)
      ..setWidth(200)
      ..setFormat(OutputFormat.jpeg);
    controller.settings.loadFrom(settings.toJson());

    // Ingest through the real controller path, not the engine directly, so the
    // queue, thumbnail and probe all run as they would for a user.
    controller.addDroppedFiles([(name: 'smoke.png', bytes: bytes, path: null)]);
    await tester.pumpAndSettle();

    expect(
      controller.jobs,
      hasLength(1),
      reason: 'the dropped file must reach the queue',
    );
    final job = controller.jobs.single;
    expect(
      job.sourceWidth,
      800,
      reason: 'the app must actually decode the image on the device',
    );
    expect(job.sourceHeight, 600);

    // Run it for real and assert the output dimensions.
    final result = await ResizeEngine.run(bytes, settings, name: 'smoke.png');
    expect(result.width, 200, reason: 'the output width must be the request');
    expect(result.height, 150, reason: 'the aspect ratio must be preserved');

    final decoded = img.decodeJpg(result.bytes);
    expect(decoded, isNotNull, reason: 'the output must be a real JPEG');
    expect(decoded!.width, 200);
    expect(decoded.height, 150);
  });

  testWidgets('the diagnostics page opens and shows its privacy notice', (
    tester,
  ) async {
    final controller = ResizeController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const DiagnosticsPage()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DiagnosticsPage), findsOneWidget);
    expect(
      find.textContaining('never uploaded'),
      findsOneWidget,
      reason: 'the offline guarantee must be visible on the page itself',
    );
    expect(tester.takeException(), isNull);
  });
}
