import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixelforge/core/controller.dart';
import 'package:pixelforge/ui/widgets/preview.dart';
import 'package:pixelforge/ui/widgets/queue_view.dart';
import 'package:pixelforge/ui/widgets/settings_view.dart';

Uint8List _swatch(int v) {
  final im = img.Image(width: 8, height: 8, numChannels: 3);
  img.fill(im, color: img.ColorRgba8(v, v, v, 255));
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
            child: LargePreview(before: _swatch(10), after: _swatch(200)),
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
              before: _swatch(10),
              after: _swatch(200),
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
      final hasTooltip =
          button.tooltip != null && button.tooltip!.isNotEmpty;
      final hasSemantics = (e
              .findAncestorWidgetOfExactType<Semantics>()
              ?.properties
              .label ??
          '')
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
              child: LargePreview(before: _swatch(10), after: _swatch(200)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Comparison divider'), findsOneWidget);
  });
}
