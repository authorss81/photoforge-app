import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixelforge/core/engine.dart';
import 'package:pixelforge/core/resize_mode.dart';
import 'package:pixelforge/core/settings.dart';

/// Benchmark harness. Not part of the fast suite: run explicitly with
/// `flutter test benchmark/`. CI runs it as a separate job and uploads the
/// table; it is never a required check.
///
/// Every number below is a median over at least five iterations with the
/// spread reported. A single run is noise. Sources carry high-frequency
/// content so the encoders do real work; a gradient would compress trivially
/// and hide every cost that matters.
Uint8List _noisySource(int w, int h) {
  final im = img.Image(width: w, height: h, numChannels: 3);
  var seed = 0x12345;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      // Low-frequency gradient plus high-frequency hash detail.
      final r = ((x * 255 ~/ w) + (seed >> 16 & 63)) ~/ 2;
      final g = ((y * 255 ~/ h) + (seed >> 8 & 63)) ~/ 2;
      final b = 128 + (seed & 63) - 32;
      im.setPixelRgba(
        x,
        y,
        r.clamp(0, 255),
        g.clamp(0, 255),
        b.clamp(0, 255),
        255,
      );
    }
  }
  return img.encodeJpg(im, quality: 95);
}

double _median(List<double> xs) {
  final s = [...xs]..sort();
  return s[s.length ~/ 2];
}

String _cell(double medianMs, double spreadMs, int bytes) {
  final kb = (bytes / 1024).toStringAsFixed(0);
  final spread = spreadMs.toStringAsFixed(0);
  return '${medianMs.toStringAsFixed(0)} ms ±$spread / $kb KB';
}

void main() {
  test(
    'matrix: sizes x modes x formats',
    () async {
      final sizes = <String, List<int>>{
        '1 MP': [1280, 800],
        '4 MP': [2560, 1600],
        '16 MP': [5120, 3200],
      };
      final modes = <String, ResizeSpec Function()>{
        'fit-1080': () => const ResizeSpec(
          mode: ResizeMode.longestSide,
          width: 1080,
          height: 1080,
        ),
        'crop-1080': () => const ResizeSpec(
          mode: ResizeMode.exactCrop,
          width: 1080,
          height: 1080,
        ),
      };
      final formats = <String, OutputFormat>{
        'jpeg-q85': OutputFormat.jpeg,
        'webp-q80': OutputFormat.webp,
      };

      final sources = <String, Uint8List>{
        for (final e in sizes.entries)
          e.key: _noisySource(e.value[0], e.value[1]),
      };

      final table = <String, Map<String, String>>{};
      for (final sizeEntry in sizes.entries) {
        final row = <String, String>{};
        for (final modeEntry in modes.entries) {
          for (final formatEntry in formats.entries) {
            final times = <double>[];
            var bytes = 0;
            for (var i = 0; i < 5; i++) {
              final s = ResizeSettings();
              final spec = modeEntry.value();
              s.setMode(spec.mode);
              if (spec.width != null) s.setWidth(spec.width!);
              if (spec.height != null) s.setHeight(spec.height!);
              s.setFormat(formatEntry.value);
              s.setQuality(formatEntry.value == OutputFormat.jpeg ? 85 : 80);
              final sw = Stopwatch()..start();
              final res = await ResizeEngine.run(
                sources[sizeEntry.key]!,
                s,
                name: 'bench.jpg',
              );
              sw.stop();
              times.add(sw.elapsedMicroseconds / 1000.0);
              bytes = res.bytes.length;
            }
            final med = _median(times);
            final spread = times.map((t) => (t - med).abs()).reduce(math.max);
            row['${modeEntry.key} ${formatEntry.key}'] = _cell(
              med,
              spread,
              bytes,
            );
          }
        }
        table[sizeEntry.key] = row;
      }

      final cols = table.values.first.keys.toList();
      final buf = StringBuffer()
        ..writeln('| source | ${cols.join(' | ')} |')
        ..writeln('| --- | ${List.filled(cols.length, '---').join(' | ')} |');
      for (final e in table.entries) {
        buf.writeln(
          '| ${e.key} | ${cols.map((c) => e.value[c]).join(' | ')} |',
        );
      }
      // ignore: avoid_print
      print('\nBENCHMARK TABLE\n$buf');
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
