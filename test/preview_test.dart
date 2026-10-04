import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixelforge/ui/widgets/preview.dart';

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
}
