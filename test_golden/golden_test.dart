/// Golden image tests for the visual layer.
///
/// Why this directory is not `test/`
/// -------------------------------
/// Goldens only pass on the platform that generated them: font rasterization
/// and text shaping differ per OS. Inside `test/`, every contributor on Windows
/// or macOS would see a permanently red suite and learn to ignore it, which is
/// worse than having no golden coverage. So `flutter test` never sees this
/// directory, and `flutter test test_golden/` is an explicit, Linux-only step.
///
/// Regenerating
/// ------------
/// Linux only, via the manual workflow, which is the supported path from any
/// platform:
///
///   gh workflow run golden-generate.yml
///
/// Locally on Linux:
///   flutter test --update-goldens test_golden/
///
/// Then download the images and **look at every one** before committing. A
/// golden you have not looked at is not a verified change. If you cannot explain
/// why an image changed, that is a regression, not an update.
///
/// Never add `--update-goldens` to a CI job. A golden that can update itself is
/// not a test.
///
/// What these do not cover
/// -----------------------
/// Text. Flutter's test font draws every glyph as a filled box, so a changed
/// string renders identically to an unchanged one here. String changes are
/// asserted with `find.text` in `test/preview_test.dart`, which also checks real
/// pixel colours for the split preview. See docs/GOLDENS.md.
@Tags(['golden'])
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixelforge/core/controller.dart';
import 'package:pixelforge/ui/widgets/preview.dart';
import 'package:pixelforge/ui/widgets/queue_view.dart';
import 'package:pixelforge/ui/widgets/settings_view.dart';

/// A large, high-contrast image. The size matters: a thumbnail-sized swatch is
/// invisible under `BoxFit.contain` in a preview pane, and a golden that
/// cannot tell "the image rendered" from "the image silently vanished" is worse
/// than no golden at all.
Uint8List _swatch(int r, int g, int b) {
  final im = img.Image(width: 300, height: 200, numChannels: 3);
  img.fill(im, color: img.ColorRgba8(r, g, b, 255));
  // A visible block in one corner, so a wrongly-scaled or mirrored image is
  // distinguishable from a correctly-scaled one.
  img.fillRect(
    im,
    x1: 0,
    y1: 0,
    x2: 100,
    y2: 60,
    color: img.ColorRgba8(255, 255, 255, 255),
  );
  return img.encodePng(im);
}

Future<void> _pumpFrame(WidgetTester tester, Widget child, double width) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        // Pinned so a goldens result never depends on the machine that
        // produced it.
        data: const MediaQueryData(textScaler: TextScaler.noScaling),
        child: Scaffold(
          body: SizedBox(width: width, height: 700, child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Forces real image decoding to finish.
///
/// `Image.memory` resolves through a codec on a real async path that
/// `pumpAndSettle` does not await, because a completed decode does not schedule
/// a new frame in the test's fake-async zone. Without this, the golden captures
/// the frame *before* the bitmap exists: the preview renders as an empty box
/// and would still pass if image rendering broke outright. That is the worst
/// possible failure for a golden, so the decode is awaited explicitly.
Future<void> _decodeImages(
  WidgetTester tester,
  Finder host,
  List<Uint8List> images,
) async {
  if (images.isEmpty) return;
  final ctx = tester.element(host);
  await tester.runAsync(() async {
    for (final bytes in images) {
      await precacheImage(MemoryImage(bytes), ctx);
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('queue', () {
    testWidgets('empty at 400px', (tester) async {
      final controller = ResizeController();
      addTearDown(controller.dispose);
      await _pumpFrame(tester, QueueView(controller: controller), 400);
      await expectLater(
        find.byType(QueueView),
        matchesGoldenFile('goldens/queue_empty_400.png'),
      );
    });

    testWidgets('with items at 400px', (tester) async {
      final controller = ResizeController();
      addTearDown(controller.dispose);
      final a = _swatch(20, 90, 200);
      final b = _swatch(210, 90, 160);
      controller.addDroppedFiles([
        (name: 'a.jpg', bytes: a, path: null),
        (name: 'b.jpg', bytes: b, path: null),
      ]);
      await _pumpFrame(tester, QueueView(controller: controller), 400);
      await _decodeImages(tester, find.byType(QueueView), [a, b]);
      await expectLater(
        find.byType(QueueView),
        matchesGoldenFile('goldens/queue_items_400.png'),
      );
    });
  });

  group('preview', () {
    testWidgets('split at 800px', (tester) async {
      final before = _swatch(20, 90, 200);
      final after = _swatch(210, 90, 160);
      await _pumpFrame(tester, LargePreview(before: before, after: after), 800);
      await _decodeImages(tester, find.byType(LargePreview), [before, after]);
      await expectLater(
        find.byType(LargePreview),
        matchesGoldenFile('goldens/preview_split_800.png'),
      );
    });
  });

  group('settings', () {
    // Three widths, because a settings pane is a scrolling column whose real
    // failure mode is reflowing: labels wrapping into their controls, a slider
    // row overflowing, a two-column row collapsing to one. One width proves
    // none of that.
    testWidgets('at 320px', (tester) async {
      final controller = ResizeController();
      addTearDown(controller.dispose);
      await _pumpFrame(tester, SettingsView(controller: controller), 320);
      await expectLater(
        find.byType(SettingsView),
        matchesGoldenFile('goldens/settings_320.png'),
      );
    });

    testWidgets('at 400px', (tester) async {
      final controller = ResizeController();
      addTearDown(controller.dispose);
      await _pumpFrame(tester, SettingsView(controller: controller), 400);
      await expectLater(
        find.byType(SettingsView),
        matchesGoldenFile('goldens/settings_400.png'),
      );
    });

    testWidgets('at 800px', (tester) async {
      final controller = ResizeController();
      addTearDown(controller.dispose);
      await _pumpFrame(tester, SettingsView(controller: controller), 800);
      await expectLater(
        find.byType(SettingsView),
        matchesGoldenFile('goldens/settings_800.png'),
      );
    });
  });
}
