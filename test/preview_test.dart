import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixelforge/core/controller.dart';
import 'package:pixelforge/ui/widgets/preview.dart';
import 'package:pixelforge/ui/widgets/queue_view.dart';
import 'package:pixelforge/ui/widgets/settings_view.dart';

Uint8List _swatch(int r, int g, int b) {
  final im = img.Image(width: 64, height: 64, numChannels: 3);
  img.fill(im, color: img.ColorRgba8(r, g, b, 255));
  return img.encodePng(im);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('split view shows both images and a labelled handle', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: LargePreview(
              before: _swatch(10, 10, 10),
              after: _swatch(200, 200, 200),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Comparison divider'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(2));
  });

  testWidgets('split off shows a single image', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: LargePreview(
              before: _swatch(10, 10, 10),
              after: _swatch(200, 200, 200),
              split: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Comparison divider'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('empty state explains itself', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: LargePreview(before: null, after: null),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nothing to preview'), findsOneWidget);
  });

  testWidgets('every icon-only button is labelled', (tester) async {
    final controller = ResizeController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            height: 800,
            child: QueueView(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final unlabeled = <String>[];
    for (final e in find.byType(IconButton).evaluate()) {
      final button = e.widget as IconButton;
      final hasTooltip = button.tooltip != null && button.tooltip!.isNotEmpty;
      final hasSemantics =
          (e.findAncestorWidgetOfExactType<Semantics>()?.properties.label ?? '')
              .isNotEmpty;
      final hasTooltipWidget =
          e.findAncestorWidgetOfExactType<Tooltip>() != null;
      if (!hasTooltip && !hasSemantics && !hasTooltipWidget) {
        unlabeled.add(button.icon.toString());
      }
    }
    expect(unlabeled, isEmpty, reason: 'unlabelled icon buttons: $unlabeled');
  });

  testWidgets('settings survive RTL without overflow', (tester) async {
    final controller = ResizeController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SizedBox(
              width: 400,
              height: 800,
              child: SettingsView(controller: controller),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('preview survives 200% text scaling', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: LargePreview(
                before: _swatch(10, 10, 10),
                after: _swatch(200, 200, 200),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Comparison divider'), findsOneWidget);
  });

  // Regression test for a real bug: the split view painted "before" over the
  // whole pane, so the "after" image was never visible and the divider did
  // nothing. Counting Image widgets cannot catch that, because both images
  // existed in the tree the entire time. This asserts the actual pixels.
  testWidgets('split view actually shows before left of the divider and after '
      'right of it', (tester) async {
    const key = ValueKey('split-boundary');
    final before = _swatch(20, 90, 200);
    final after = _swatch(210, 90, 160);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 400,
              height: 300,
              child: LargePreview(before: before, after: after),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Image.memory resolves through a real async decode that pumpAndSettle
    // does not await, so the frames must be pumped before the pixels exist.
    final ctx = tester.element(find.byType(LargePreview));
    await tester.runAsync(() async {
      await precacheImage(MemoryImage(before), ctx);
      await precacheImage(MemoryImage(after), ctx);
    });
    await tester.pumpAndSettle();

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    late final Uint8List bytes;
    late final int width;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.0);
      width = image.width;
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      bytes = data.buffer.asUint8List();
    });

    ({int r, int g, int b}) at(int x, int y) {
      final i = (y * width + x) * 4;
      return (r: bytes[i], g: bytes[i + 1], b: bytes[i + 2]);
    }

    // The divider defaults to the midpoint, so sample well inside each half.
    expect(at(80, 150).r, closeTo(20, 6), reason: 'left half must be before');
    expect(at(80, 150).b, closeTo(200, 6));
    expect(at(320, 150).r, closeTo(210, 6), reason: 'right half must be after');
    expect(at(320, 150).b, closeTo(160, 6));
  });
}
