import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixelforge/core/controller.dart';
import 'package:pixelforge/core/engine.dart';
import 'package:pixelforge/core/job.dart';
import 'package:pixelforge/core/native_decoder.dart';
import 'package:pixelforge/core/system_picker.dart';
import 'package:pixelforge/core/native/libheif.dart';
import 'package:pixelforge/core/tiff16.dart';
import 'package:pixelforge/core/resize_mode.dart';
import 'package:pixelforge/core/settings.dart';
import 'package:pixelforge/core/background_service.dart';
import 'package:pixelforge/core/shared_content.dart';
import 'package:pixelforge/core/worker.dart';

Uint8List _makeJpeg(int w, int h, {int quality = 92}) {
  final im = img.Image(width: w, height: h, numChannels: 3);
  img.fill(im, color: img.ColorRgba8(90, 140, 200, 255));
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      im.setPixelRgba(x, y, (x * 255 ~/ w), (y * 255 ~/ h), 128, 255);
    }
  }
  return img.encodeJpg(im, quality: quality);
}

Uint8List _makePngAlpha(int w, int h) {
  final im = img.Image(width: w, height: h, numChannels: 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      im.setPixelRgba(
        x,
        y,
        (x * 255 ~/ w),
        (y * 255 ~/ h),
        128,
        (x * 255 ~/ w),
      );
    }
  }
  return img.encodePng(im);
}

/// A gradient whose blue channel is a per-frame constant, so every frame is
/// still distinguishable from every other one after a resize and a lossy
/// re-encode. Mean blue is the statistic that proves it.
img.Image _frame(int index, int w, int h) {
  final im = img.Image(width: w, height: h, numChannels: 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      im.setPixelRgba(
        x,
        y,
        (x * 255 ~/ w),
        (y * 255 ~/ h),
        frameBlue(index),
        255,
      );
    }
  }
  return im;
}

/// Blue tint for frame [index]. Wide enough spacing that 256-colour
/// quantisation plus Floyd-Steinberg dithering cannot collapse two frames
/// onto the same value.
int frameBlue(int index) => 20 + index * 70;

Uint8List _makeAnimatedGif(
  int w,
  int h,
  int frameCount, {
  List<int>? durations,
}) {
  final head = _frame(0, w, h);
  head.frameDuration = durations?[0] ?? 100;
  for (var i = 1; i < frameCount; i++) {
    final f = head.addFrame(_frame(i, w, h));
    f.frameDuration = durations?[i] ?? 100;
  }
  return img.encodeGif(head, singleFrame: false);
}

Uint8List _makeAnimatedWebP(
  int w,
  int h,
  int frameCount, {
  List<int>? durations,
}) {
  final head = _frame(0, w, h);
  head.frameDuration = durations?[0] ?? 100;
  for (var i = 1; i < frameCount; i++) {
    final f = head.addFrame(_frame(i, w, h));
    f.frameDuration = durations?[i] ?? 100;
  }
  // lossless: false, because the codec is lossless by default and the quality
  // slider would otherwise be ignored.
  return img.encodeWebP(head, singleFrame: false, lossless: false, quality: 90);
}

ResizeSettings _gifSettings({int width = 60}) => ResizeSettings()
  ..setMode(ResizeMode.width)
  ..setWidth(width)
  ..setFormat(OutputFormat.gif);

ResizeSettings _webpSettings({int width = 60}) => ResizeSettings()
  ..setMode(ResizeMode.width)
  ..setWidth(width)
  ..setFormat(OutputFormat.webp);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('geometry', () {
    test('longestSide fits inside the box without growing', () {
      final t = computeTargetSize(
        const ResizeSpec(
          mode: ResizeMode.longestSide,
          width: 1000,
          height: 1000,
        ),
        4000,
        2000,
      );
      expect(t.width, 1000);
      expect(t.height, 500);
    });

    test('longestSide never upscales unless allowed', () {
      final spec = ResizeSpec(
        mode: ResizeMode.longestSide,
        width: 4000,
        height: 4000,
      );
      expect(computeTargetSize(spec, 800, 600), const TargetSize(800, 600));
      expect(
        computeTargetSize(spec.copyWith(allowUpscale: true), 800, 600),
        const TargetSize(4000, 3000),
      );
    });

    test('exact modes land on the requested box', () {
      for (final mode in const [
        ResizeMode.exactFit,
        ResizeMode.exactCrop,
        ResizeMode.exactStretch,
      ]) {
        final t = computeTargetSize(
          ResizeSpec(mode: mode, width: 1080, height: 1080),
          3000,
          1700,
        );
        expect(t.width, 1080);
        expect(t.height, 1080, reason: 'mode ${mode.name}');
      }
    });

    test('percent scales both axes', () {
      final t = computeTargetSize(
        const ResizeSpec(mode: ResizeMode.percent, percent: 50),
        1600,
        900,
      );
      expect(t.width, 800);
      expect(t.height, 450);
    });

    test('single-axis modes derive the other axis from the source ratio', () {
      expect(
        computeTargetSize(
          const ResizeSpec(mode: ResizeMode.width, width: 800),
          1600,
          900,
        ),
        const TargetSize(800, 450),
      );
      expect(
        computeTargetSize(
          const ResizeSpec(mode: ResizeMode.height, height: 450),
          1600,
          900,
        ),
        const TargetSize(800, 450),
      );
    });

    test('never returns a zero or negative dimension', () {
      final t = computeTargetSize(
        const ResizeSpec(mode: ResizeMode.width, width: 1),
        4000,
        3,
      );
      expect(t.width, greaterThanOrEqualTo(1));
      expect(t.height, greaterThanOrEqualTo(1));
    });

    test('crop plan matches the target aspect and stays in bounds', () {
      final plan = computeCropPlan(3000, 1700, const TargetSize(1080, 1080));
      expect(plan.cropW, 1700);
      expect(plan.cropH, 1700);
      expect(plan.cropX, (3000 - 1700) ~/ 2);
      expect(plan.cropY, 0);
    });

    test('crop plan is a no-op when the aspect already matches', () {
      final plan = computeCropPlan(1000, 1000, const TargetSize(500, 500));
      expect(plan, CropPlan.none);
    });
  });

  group('pipeline', () {
    test('resizes and reports the real output geometry', () async {
      final s = ResizeSettings()..setMode(ResizeMode.exactCrop);
      s.setWidth(400);
      s.setHeight(400);
      s.setFormat(OutputFormat.jpeg);

      final res = await ResizeEngine.run(
        _makeJpeg(1200, 800),
        s,
        name: 'a.jpg',
      );

      expect(res.width, 400);
      expect(res.height, 400);
      expect(res.extension, 'jpg');

      final decoded = img.decodeJpg(res.bytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, 400);
      expect(decoded.height, 400);
    });

    test('target KB solver lands under the budget', () async {
      final s = ResizeSettings()..setMode(ResizeMode.exactCrop);
      s.setWidth(1200);
      s.setHeight(1200);
      s.setFormat(OutputFormat.jpeg);
      s.setTargetKb(60);

      final res = await ResizeEngine.run(
        _makeJpeg(2400, 1600),
        s,
        name: 'b.jpg',
      );

      expect(res.metTarget, isTrue);
      expect(res.bytes.length, lessThanOrEqualTo(60 * 1024));
      expect(res.quality, isNotNull);
      expect(res.quality, greaterThan(0));
    });

    test('reports when the budget is impossible instead of lying', () async {
      final s = ResizeSettings()..setMode(ResizeMode.exactStretch);
      s.setWidth(3000);
      s.setHeight(3000);
      s.setFormat(OutputFormat.jpeg);
      s.setTargetKb(1);

      final res = await ResizeEngine.run(
        _makeJpeg(3000, 3000),
        s,
        name: 'c.jpg',
      );
      expect(res.metTarget, isFalse);
    });

    test('solver uses at most two full-resolution encodes', () async {
      final s = ResizeSettings()..setMode(ResizeMode.exactCrop);
      s.setWidth(1200);
      s.setHeight(1200);
      s.setFormat(OutputFormat.jpeg);
      s.setTargetKb(60);

      await ResizeEngine.run(_makeJpeg(2400, 1600), s, name: 'b2.jpg');
      expect(
        ResizeEngine.lastSolveFullEncodes,
        lessThanOrEqualTo(2),
        reason:
            'proxy search plus at most one correction, never a full binary search',
      );
    });

    test('proxy solver agrees with the legacy solver', () async {
      final prepared = img.copyResize(
        img.decodeJpg(_makeJpeg(1600, 1000))!,
        width: 800,
        height: 500,
        interpolation: img.Interpolation.average,
      );
      const budget = 80 * 1024;
      final s = ResizeSettings()..setFormat(OutputFormat.jpeg);

      final legacy = ResizeEngine.solveToBudgetLegacy(
        prepared,
        OutputFormat.jpeg,
        s,
        budget,
        animated: false,
      );
      expect(legacy.bytes.length, lessThanOrEqualTo(budget));

      final s2 = ResizeSettings()
        ..setMode(ResizeMode.exactStretch)
        ..setWidth(800)
        ..setHeight(500)
        ..setFormat(OutputFormat.jpeg)
        ..setTargetKb(80);
      final res = await ResizeEngine.run(
        _makeJpeg(1600, 1000),
        s2,
        name: 'cmp.jpg',
      );
      expect(res.metTarget, isTrue);
      expect(res.bytes.length, lessThanOrEqualTo(budget));

      final drift =
          (res.bytes.length - legacy.bytes.length).abs() / legacy.bytes.length;
      expect(
        drift,
        lessThan(0.05),
        reason:
            'both solvers land just under the same budget, so they must agree closely',
      );
    });

    test('quality ordering: lower quality means fewer bytes', () async {
      final high = ResizeSettings()..setQuality(95);
      final low = ResizeSettings()..setQuality(20);

      final big = _makeJpeg(1000, 800);
      final a = await ResizeEngine.run(big, high, name: 'd.jpg');
      final b = await ResizeEngine.run(big, low, name: 'd.jpg');

      expect(b.bytes.length, lessThan(a.bytes.length));
    });

    test('png stays lossless through a resize', () async {
      final s = ResizeSettings()
        ..setMode(ResizeMode.width)
        ..setWidth(120)
        ..setFormat(OutputFormat.png);

      final res = await ResizeEngine.run(_makeJpeg(600, 400), s, name: 'e.jpg');
      expect(res.extension, 'png');
      expect(res.bytes.length, greaterThan(0));
      expect(img.decodePng(res.bytes)!.width, 120);
    });

    test('webp encoder honours the lossy switch', () async {
      final lossless = ResizeSettings()
        ..setFormat(OutputFormat.webp)
        ..setWebpLossless(true);
      final lossy = ResizeSettings()
        ..setFormat(OutputFormat.webp)
        ..setWebpLossless(false)
        ..setQuality(40);

      final src = _makeJpeg(800, 600);
      final a = await ResizeEngine.run(src, lossless, name: 'f.jpg');
      final b = await ResizeEngine.run(src, lossy, name: 'f.jpg');

      expect(resizeEngineDecodes(a.extension), isTrue);
      expect(resizeEngineDecodes(b.extension), isTrue);
      expect(b.bytes.length, lessThan(a.bytes.length));
    });

    test('strips GPS but keeps the camera tag', () async {
      Uint8List tagged() {
        final exif = img.ExifData();
        exif.imageIfd.data[0x010F] = img.IfdValueAscii('TestMake');
        exif.imageIfd.data[0x0132] = img.IfdValueAscii('2020:01:02 03:04:05');
        exif.imageIfd.sub.directories['gps'] = img.IfdDirectory()
          ..setGpsLocation(latitude: 1.5, longitude: 2.5);
        return img.injectJpgExif(_makeJpeg(400, 300), exif)!;
      }

      // Sanity: the tags survive a round trip with stripping off.
      final plain = ResizeSettings()
        ..setMode(ResizeMode.original)
        ..setFormat(OutputFormat.jpeg)
        ..setStripMetadata(false);
      final kept = img.decodeJpgExif(
        (await ResizeEngine.run(tagged(), plain, name: 'ex.jpg')).bytes,
      )!;
      expect(kept.imageIfd.sub.directories.containsKey('gps'), isTrue);
      expect(kept.imageIfd.data[0x010F]?.toString(), contains('TestMake'));

      // Strip GPS only.
      final gpsOnly = ResizeSettings()
        ..setMode(ResizeMode.original)
        ..setFormat(OutputFormat.jpeg)
        ..setStripMetadata(true)
        ..setStripGps(true)
        ..setStripCamera(false)
        ..setStripTimestamps(false)
        ..setStripThumbnail(false);
      final out = img.decodeJpgExif(
        (await ResizeEngine.run(tagged(), gpsOnly, name: 'ex.jpg')).bytes,
      )!;
      expect(out.imageIfd.sub.directories.containsKey('gps'), isFalse);
      expect(out.imageIfd.data[0x010F]?.toString(), contains('TestMake'));
      expect(out.imageIfd.data.containsKey(0x0132), isTrue);

      // Strip timestamps only.
      final tsOnly = ResizeSettings()
        ..setMode(ResizeMode.original)
        ..setFormat(OutputFormat.jpeg)
        ..setStripMetadata(true)
        ..setStripGps(false)
        ..setStripCamera(false)
        ..setStripTimestamps(true)
        ..setStripThumbnail(false);
      final outTs = img.decodeJpgExif(
        (await ResizeEngine.run(tagged(), tsOnly, name: 'ex.jpg')).bytes,
      )!;
      expect(outTs.imageIfd.sub.directories.containsKey('gps'), isTrue);
      expect(outTs.imageIfd.data.containsKey(0x0132), isFalse);

      // Master off keeps everything even when the individual flags are armed.
      final masterOff = ResizeSettings()
        ..setMode(ResizeMode.original)
        ..setFormat(OutputFormat.jpeg)
        ..setStripMetadata(false)
        ..setStripGps(true)
        ..setStripCamera(true)
        ..setStripTimestamps(true)
        ..setStripThumbnail(true);
      final outKept = img.decodeJpgExif(
        (await ResizeEngine.run(tagged(), masterOff, name: 'ex.jpg')).bytes,
      )!;
      expect(outKept.imageIfd.sub.directories.containsKey('gps'), isTrue);
      expect(outKept.imageIfd.data[0x010F]?.toString(), contains('TestMake'));
    });

    test('rotating by 90 degrees swaps the axes', () async {
      final s = ResizeSettings()
        ..setMode(ResizeMode.original)
        ..rotateBy(1)
        ..setFormat(OutputFormat.png);

      final res = await ResizeEngine.run(_makeJpeg(800, 400), s, name: 'h.jpg');
      expect(res.width, 400);
      expect(res.height, 800);
    });

    test('pad mode keeps the box and adds background', () async {
      final s = ResizeSettings()
        ..setMode(ResizeMode.exactFit)
        ..setWidth(600)
        ..setHeight(600)
        ..setPadColor(const Color(0xFFFF0000))
        ..setFormat(OutputFormat.png);

      final res = await ResizeEngine.run(
        _makeJpeg(1200, 400),
        s,
        name: 'i.jpg',
      );
      expect(res.width, 600);
      expect(res.height, 600);

      final decoded = img.decodePng(res.bytes)!;
      final corner = decoded.getPixel(2, 2);
      expect(corner.r, greaterThan(200));
      expect(corner.g, lessThan(80));
    });

    test('watermark visibly changes pixels', () async {
      final plain = ResizeSettings()
        ..setMode(ResizeMode.original)
        ..setFormat(OutputFormat.png);
      final marked = ResizeSettings()
        ..setMode(ResizeMode.original)
        ..setWatermark(
          const WatermarkSettings(text: 'DEMO', enabled: true, scale: 0.14),
        )
        ..setFormat(OutputFormat.png);

      final src = _makeJpeg(600, 400);
      final a = img.decodePng(
        (await ResizeEngine.run(src, plain, name: 'j.jpg')).bytes,
      )!;
      final b = img.decodePng(
        (await ResizeEngine.run(src, marked, name: 'j.jpg')).bytes,
      )!;

      expect(b.width, 600);
      expect(b.height, 400);

      var changed = 0;
      for (final p in a) {
        final q = b.getPixel(p.x, p.y);
        if ((p.r - q.r).abs() + (p.g - q.g).abs() + (p.b - q.b).abs() > 12) {
          changed++;
        }
      }
      expect(
        changed,
        greaterThan(200),
        reason: 'watermark ink should be visible',
      );
    });

    test('rejects data that is not an image', () async {
      final s = ResizeSettings();
      expect(
        () => ResizeEngine.run(
          Uint8List.fromList(List.filled(64, 7)),
          s,
          name: 'x.jpg',
        ),
        throwsA(isA<EngineError>()),
      );
    });
  });

  group('formats', () {
    double meanAbs(img.Image a, img.Image b) {
      var sum = 0;
      var n = 0;
      for (var y = 0; y < a.height && y < b.height; y++) {
        for (var x = 0; x < a.width && x < b.width; x++) {
          final pa = a.getPixel(x, y);
          final pb = b.getPixel(x, y);
          sum += (pa.r - pb.r).abs().toInt();
          sum += (pa.g - pb.g).abs().toInt();
          sum += (pa.b - pb.b).abs().toInt();
          n += 3;
        }
      }
      return sum / n;
    }

    test('indexed GIF resizes through direct colour, not nearest', () async {
      // Smooth diagonal gradient: nearest-neighbour downscaling staircases it.
      final direct = img.Image(width: 200, height: 200, numChannels: 3);
      for (final p in direct) {
        direct.setPixelRgba(
          p.x,
          p.y,
          (p.x + p.y) ~/ 2,
          (p.x * 2) % 256,
          128,
          255,
        );
      }
      final paletted = img.decodeGif(img.encodeGif(direct, singleFrame: true))!;
      expect(paletted.hasPalette, isTrue);
      final gif = img.encodeGif(paletted, singleFrame: true);

      final s = ResizeSettings()
        ..setMode(ResizeMode.width)
        ..setWidth(100)
        ..setFormat(OutputFormat.png);
      final res = await ResizeEngine.run(gif, s, name: 'idx.gif');
      final out = img.decodePng(res.bytes)!;
      expect(out.width, 100);

      // Reference: the same resize from direct colour.
      final ref = img.copyResize(
        direct,
        width: 100,
        height: 100,
        interpolation: img.Interpolation.average,
      );
      // Baseline: what the old nearest-neighbour path produced.
      final baseline = img.copyResize(
        img.decodeGif(gif)!,
        width: 100,
        height: 100,
        interpolation: img.Interpolation.nearest,
      );
      expect(
        meanAbs(out, ref),
        lessThan(meanAbs(baseline, ref)),
        reason:
            'direct-colour resize must beat nearest-neighbour against the reference',
      );
    });

    Uint8List sofJpeg(int components) {
      final bytes = <int>[
        0xFF, 0xD8, // SOI
        0xFF, 0xC0, 0x00, 0x0B, // SOF0, length 11
        0x08, // precision
        0x00, 0x01, // height
        0x00, 0x01, // width
        components,
        0x01, 0x11, 0x00,
        0x02, 0x11, 0x00,
        0x03, 0x11, 0x00,
      ];
      if (components == 4) bytes.addAll([0x04, 0x11, 0x00]);
      return Uint8List.fromList(bytes);
    }

    test('detects four-component JPEGs and nothing else', () {
      expect(ResizeEngine.isCmykJpeg(sofJpeg(4)), isTrue);
      expect(ResizeEngine.isCmykJpeg(sofJpeg(3)), isFalse);
      expect(ResizeEngine.isCmykJpeg(sofJpeg(1)), isFalse);
      expect(
        ResizeEngine.isCmykJpeg(Uint8List.fromList([1, 2, 3, 4])),
        isFalse,
      );
      expect(ResizeEngine.isCmykJpeg(Uint8List(0)), isFalse);
    });

    test('rejects CMYK with a message naming the problem', () async {
      final s = ResizeSettings()..setFormat(OutputFormat.jpeg);
      expect(
        () => ResizeEngine.run(sofJpeg(4), s, name: 'cmyk.jpg'),
        throwsA(
          isA<EngineError>().having(
            (e) => e.message,
            'message',
            contains('CMYK'),
          ),
        ),
      );
    });

    test('16-bit TIFF survives the pipeline at 16 bits', () async {
      final src = img.Image(
        width: 120,
        height: 90,
        format: img.Format.uint16,
        numChannels: 3,
      );
      for (final p in src) {
        src.setPixelRgba(p.x, p.y, p.x * 500, p.y * 600, 40000, 65535);
      }
      // The package encoder truncates to 8 bits on write, so the source file
      // itself is built with our own writer. That is also the dogfood.
      final tiff = encodeTiff16(src);
      expect(img.decodeTiff(tiff)!.format, img.Format.uint16);

      final s = ResizeSettings()
        ..setMode(ResizeMode.width)
        ..setWidth(60)
        ..setFormat(OutputFormat.tiff);
      final res = await ResizeEngine.run(tiff, s, name: 'deep.tiff');
      final out = img.decodeTiff(res.bytes)!;
      expect(
        out.format,
        img.Format.uint16,
        reason: 'precision must not be silently truncated',
      );
      expect(out.width, 60);
      var peak = 0;
      for (final p in out) {
        if (p.r.toInt() > peak) peak = p.r.toInt();
      }
      expect(
        peak,
        greaterThan(255),
        reason: 'values above 8-bit range must survive',
      );
    });

    test('multi-page TIFF splits into one result per page', () async {
      // The package encoder writes exactly one IFD, so a multi-page TIFF can
      // only be hand-rolled here. Uncompressed RGB, little-endian, one strip
      // per page.
      Uint8List twoPageTiff() {
        const w = 8, h = 4, pxLen = w * h * 3;
        final page0 = List<int>.generate(pxLen, (i) => i % 251);
        final page1 = List<int>.generate(pxLen, (i) => (i * 2) % 251);
        final ifdSize = 2 + 10 * 12 + 4;
        var at = 8 + (ifdSize + 6 + pxLen) * 2 + 0;
        // Compute offsets first: header(8) then per page [IFD, bps, pixels].
        var cursor = 8;
        final offs = <int>[];
        for (var p = 0; p < 2; p++) {
          final ifdAt = cursor;
          final bpsAt = ifdAt + ifdSize;
          final pxAt = bpsAt + 6;
          offs.addAll([ifdAt, bpsAt, pxAt]);
          cursor = pxAt + pxLen;
        }
        at = cursor;
        final out = ByteData(at);
        void u16(int o, int v) => out.setUint16(o, v, Endian.little);
        void u32(int o, int v) => out.setUint32(o, v, Endian.little);
        out.setUint8(0, 0x49);
        out.setUint8(1, 0x49);
        u16(2, 42);
        u32(4, offs[0]);
        for (var p = 0; p < 2; p++) {
          final ifdAt = offs[p * 3],
              bpsAt = offs[p * 3 + 1],
              pxAt = offs[p * 3 + 2];
          var e = ifdAt;
          u16(e, 10);
          e += 2;
          void entry(int tag, int type, int count, int value) {
            u16(e, tag);
            u16(e + 2, type);
            u32(e + 4, count);
            u32(e + 8, value);
            e += 12;
          }

          entry(256, 4, 1, w);
          entry(257, 4, 1, h);
          entry(258, 3, 3, bpsAt);
          entry(259, 3, 1, 1);
          entry(262, 3, 1, 2);
          entry(273, 4, 1, pxAt);
          entry(277, 3, 1, 3);
          entry(278, 4, 1, h);
          entry(279, 4, 1, pxLen);
          entry(284, 3, 1, 1);
          u32(e, p == 0 ? offs[3] : 0);
          for (var c = 0; c < 3; c++) {
            u16(bpsAt + 2 * c, 8);
          }
          final px = p == 0 ? page0 : page1;
          out.buffer.asUint8List().setRange(pxAt, pxAt + px.length, px);
        }
        return out.buffer.asUint8List();
      }

      final tiff = twoPageTiff();
      final decoded = img.decodeTiff(tiff)!;
      expect(decoded.numFrames, 2);
      expect(decoded.frameType, img.FrameType.page);

      final s = ResizeSettings()
        ..setMode(ResizeMode.width)
        ..setWidth(4)
        ..setFormat(OutputFormat.png);
      final results = await ResizeEngine.runAll(tiff, s, name: 'doc.tiff');
      expect(results, hasLength(2));
      expect(results[0].width, 4);
      expect(results[1].width, 4);
      expect(results[0].notice, contains('Page 1 of 2'));
      expect(results[1].notice, contains('Page 2 of 2'));
      for (final r in results) {
        expect(img.decodePng(r.bytes)!.width, 4);
      }
    });

    test('an animation to TIFF is reported, not silently flattened', () async {
      img.Image frame(int v) {
        final im = img.Image(width: 160, height: 120, numChannels: 3);
        img.fill(im, color: img.ColorRgba8(v, v, v, 255));
        return im;
      }

      // The TIFF encoder writes exactly one IFD, so multi-frame output is not
      // encodable with this package. The contract is reporting, not preserving.
      final anim = frame(10)..addFrame(frame(200));
      anim.frameType = img.FrameType.animation;
      final gif = img.encodeGif(anim, singleFrame: false);

      final s = ResizeSettings()
        ..setMode(ResizeMode.width)
        ..setWidth(80)
        ..setFormat(OutputFormat.tiff);
      final res = await ResizeEngine.run(gif, s, name: 'a.gif');
      final out = img.decodeTiff(res.bytes)!;
      expect(out.width, 80);
      expect(res.notice, isNotNull);
      expect(res.notice, contains('TIFF'));
    });
  });

  group('multi-output', () {
    ResizeSettings buildPreset(OutputFormat f, int w, {int? kb}) {
      final s = ResizeSettings()
        ..setMode(ResizeMode.width)
        ..setWidth(w)
        ..setFormat(f);
      if (kb != null) s.setTargetKb(kb);
      return s;
    }

    test('three presets share exactly one decode', () async {
      final src = _makeJpeg(1200, 800);
      final before = ResizeEngine.decodeCount;
      final out = await ResizeEngine.runMulti(src, [
        buildPreset(OutputFormat.jpeg, 400),
        buildPreset(OutputFormat.png, 300),
        buildPreset(OutputFormat.webp, 200),
      ], name: 'm.jpg');
      expect(ResizeEngine.decodeCount - before, 1);
      expect(out, hasLength(3));
      expect(out[0].first.width, 400);
      expect(out[0].first.extension, 'jpg');
      expect(out[1].first.width, 300);
      expect(out[1].first.extension, 'png');
      expect(out[2].first.width, 200);
      expect(out[2].first.extension, 'webp');
    });

    test('each preset solves its own byte budget', () async {
      final src = _makeJpeg(1600, 1000);
      final out = await ResizeEngine.runMulti(src, [
        buildPreset(OutputFormat.jpeg, 800, kb: 40),
        buildPreset(OutputFormat.jpeg, 400, kb: 12),
      ], name: 'm.jpg');
      expect(out, hasLength(2));
      expect(out[0].first.bytes.length, lessThanOrEqualTo(40 * 1024));
      expect(out[1].first.bytes.length, lessThanOrEqualTo(12 * 1024));
      expect(
        out[1].first.bytes.length,
        lessThan(out[0].first.bytes.length),
        reason: 'the 12 KB thumbnail must come out smaller than the 40 KB hero',
      );
    });

    test('an empty preset list returns nothing without decoding', () async {
      final before = ResizeEngine.decodeCount;
      final out = await ResizeEngine.runMulti(
        _makeJpeg(100, 80),
        [],
        name: 'm.jpg',
      );
      expect(out, isEmpty);
      expect(ResizeEngine.decodeCount - before, 0);
    });
  });

  group('isolates', () {
    ResizeSettings sizedSettings() {
      final s = ResizeSettings()
        ..setMode(ResizeMode.width)
        ..setWidth(200)
        ..setFormat(OutputFormat.jpeg);
      return s;
    }

    test(
      'a worker produces byte-identical output',
      () async {
        final pool = await WorkerPool.create(size: 1);
        try {
          final src = _makeJpeg(600, 400);
          final direct = await ResizeEngine.run(
            src,
            sizedSettings(),
            name: 'w.jpg',
          );

          var sawProgress = false;
          final maps = await pool.run(
            IsolateMessage(
              id: pool.nextId(),
              settingsJson: sizedSettings().toJson(),
              source: src,
              name: 'w.jpg',
            ),
            (_) => sawProgress = true,
          );
          final viaWorker = EngineResult.fromMap(maps.first);

          expect(viaWorker.bytes, orderedEquals(direct.bytes));
          expect(viaWorker.width, direct.width);
          expect(viaWorker.quality, direct.quality);
          expect(
            sawProgress,
            isTrue,
            reason: 'progress must cross the isolate boundary',
          );
        } finally {
          pool.dispose();
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'one failure does not take down the batch',
      () async {
        final pool = await WorkerPool.create(size: 2);
        try {
          final good = _makeJpeg(300, 200);
          final bad = Uint8List.fromList(List.filled(64, 7));
          final json = sizedSettings().toJson();

          EngineResult? okResult;
          Object? badError;
          Future<void> runGood() async {
            final m = await pool.run(
              IsolateMessage(
                id: pool.nextId(),
                settingsJson: json,
                source: good,
                name: 'ok.jpg',
              ),
            );
            okResult = EngineResult.fromMap(m.first);
          }

          Future<void> runBad() async {
            try {
              await pool.run(
                IsolateMessage(
                  id: pool.nextId(),
                  settingsJson: json,
                  source: bad,
                  name: 'bad.jpg',
                ),
              );
            } catch (e) {
              badError = e;
            }
          }

          await Future.wait([runGood(), runBad()]);

          expect(okResult, isNotNull);
          expect(okResult!.width, greaterThan(0));
          expect(badError, isA<EngineError>());
        } finally {
          pool.dispose();
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'concurrency never exceeds the pool size',
      () async {
        final pool = await WorkerPool.create(size: 2);
        try {
          expect(pool.size, 2);
          expect(pool.busyCount, 0);
          final json = sizedSettings().toJson();
          final src = _makeJpeg(200, 150);
          final f1 = pool.run(
            IsolateMessage(
              id: pool.nextId(),
              settingsJson: json,
              source: src,
              name: 'a.jpg',
            ),
          );
          final f2 = pool.run(
            IsolateMessage(
              id: pool.nextId(),
              settingsJson: json,
              source: src,
              name: 'b.jpg',
            ),
          );
          // Both dispatched synchronously; the pool holds exactly two workers.
          await Future.wait([f1, f2]);
          expect(pool.busyCount, 0);
        } finally {
          pool.dispose();
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

  group('native', () {
    test('recognises the HEIF family by extension', () {
      expect(NativeDecoder.isHeifFamily('heic'), isTrue);
      expect(NativeDecoder.isHeifFamily('HEIF'), isTrue);
      expect(NativeDecoder.isHeifFamily('avif'), isTrue);
      expect(NativeDecoder.isHeifFamily('jpg'), isFalse);
      expect(NativeDecoder.isHeifFamily(null), isFalse);
    });

    test('system picker returns photos without a permission', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final png = img.encodePng(
        img.Image(width: 30, height: 20, numChannels: 3),
      );
      try {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemPicker.channel, (call) async {
              expect(call.method, 'pickImages');
              return [
                {'name': 'a.heic', 'bytes': png},
                {'name': 'empty.jpg', 'bytes': Uint8List(0)},
              ];
            });
        final out = await SystemPicker.pickImages();
        expect(out, hasLength(1));
        expect(out!.first.name, 'a.heic');
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemPicker.channel, null);
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('system picker failure means fallback, not a crash', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemPicker.channel, (call) async {
              throw PlatformException(code: 'UNSUPPORTED');
            });
        expect(await SystemPicker.pickImages(), isNull);
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemPicker.channel, null);
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('system picker stays off desktop', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        var called = false;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemPicker.channel, (call) async {
              called = true;
              return null;
            });
        expect(await SystemPicker.pickImages(), isNull);
        expect(called, isFalse);
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemPicker.channel, null);
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('libheif decodes a real HEIC when the library is present', () async {
      final file = File('test/fixtures/gradient.heic');
      if (!file.existsSync()) {
        markTestSkipped('no HEIC fixture');
        return;
      }
      final bytes = await file.readAsBytes();
      if (Libheif.load() == null) {
        // Library absent (CI Linux, macOS): the failure must name libheif.
        expect(
          () => Libheif.decode(bytes),
          throwsA(
            isA<EngineError>().having(
              (e) => e.message,
              'message',
              contains('libheif'),
            ),
          ),
        );
        return;
      }
      final image = Libheif.decode(bytes);
      expect(image.width, 160);
      expect(image.height, 120);
      // Gradient content: top-left dark, bottom-right bright.
      final tl = image.getPixel(4, 4);
      final br = image.getPixel(155, 115);
      expect(tl.r + tl.g + tl.b, lessThan(br.r + br.g + br.b));

      // And through the full pipeline.
      final s = ResizeSettings()
        ..setMode(ResizeMode.width)
        ..setWidth(80)
        ..setFormat(OutputFormat.jpeg);
      final res = await ResizeEngine.run(bytes, s, name: 'gradient.heic');
      expect(res.width, 80);
    });

    test('does not touch the channel off mobile', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        var called = false;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(NativeDecoder.channel, (call) async {
              called = true;
              return null;
            });
        final out = await NativeDecoder.decodeToPng(
          Uint8List.fromList([1, 2, 3]),
        );
        expect(out, isNull);
        expect(called, isFalse);
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(NativeDecoder.channel, null);
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('decodes through a mocked platform channel', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final png = img.encodePng(
        img.Image(width: 40, height: 30, numChannels: 3),
      );
      try {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(NativeDecoder.channel, (call) async {
              expect(call.method, 'decodeImage');
              return png;
            });
        final decoded = await ResizeEngine.decodeAsync(
          Uint8List.fromList([9, 9, 9]),
          'photo.heic',
        );
        expect(decoded.width, 40);
        expect(decoded.height, 30);
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(NativeDecoder.channel, null);
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('the iOS path uses the same channel contract', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(NativeDecoder.isNativeCapable, isTrue);
      final png = img.encodePng(
        img.Image(width: 24, height: 18, numChannels: 3),
      );
      try {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(NativeDecoder.channel, (call) async {
              expect(call.method, 'decodeImage');
              expect((call.arguments as Map)['bytes'], isA<Uint8List>());
              return png;
            });
        final decoded = await ResizeEngine.decodeAsync(
          Uint8List.fromList([7, 7, 7]),
          'photo.heic',
        );
        expect(decoded.width, 24);
        expect(decoded.height, 18);
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(NativeDecoder.channel, null);
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('a failing channel falls back to the clear error', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(NativeDecoder.channel, (call) async {
              throw PlatformException(code: 'DECODE', message: 'nope');
            });
        final s = ResizeSettings()..setFormat(OutputFormat.jpeg);
        // Whatever the environment provides, a dead channel must end in a
        // clear EngineError, never a crash and never silence. With libheif
        // present the error names libheif; without it, the HEIC fallback.
        if (Libheif.load() == null) {
          expect(
            () => ResizeEngine.run(
              Uint8List.fromList([9, 9, 9]),
              s,
              name: 'photo.heic',
            ),
            throwsA(
              isA<EngineError>().having(
                (e) => e.message,
                'message',
                contains('HEIC'),
              ),
            ),
          );
        } else {
          expect(
            () => ResizeEngine.run(
              Uint8List.fromList([9, 9, 9]),
              s,
              name: 'photo.heic',
            ),
            throwsA(isA<EngineError>()),
          );
        }
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(NativeDecoder.channel, null);
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('shared content collects and saves through one channel', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final png = img.encodePng(
        img.Image(width: 20, height: 10, numChannels: 3),
      );
      try {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SharedContent.channel, (call) async {
              if (call.method == 'getSharedImages') {
                return [
                  {'name': 'shared.png', 'bytes': png},
                ];
              }
              if (call.method == 'saveToGallery') {
                expect((call.arguments as Map)['name'], 'out.png');
                return null;
              }
              throw PlatformException(code: 'UNIMPLEMENTED');
            });
        final got = await SharedContent.collect();
        expect(got, hasLength(1));
        expect(got!.first.name, 'shared.png');
        expect(await SharedContent.saveToGallery(png, 'out.png'), isNull);
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SharedContent.channel, null);
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('shared content stays off desktop', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        var called = false;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SharedContent.channel, (call) async {
              called = true;
              return null;
            });
        expect(await SharedContent.collect(), isNull);
        expect(
          await SharedContent.saveToGallery(Uint8List.fromList([1]), 'x.png'),
          contains('phones'),
        );
        expect(called, isFalse);
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SharedContent.channel, null);
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('cancellation', () {
    ResizeController makeController() {
      final c = ResizeController();
      c.settings
        ..setMode(ResizeMode.width)
        ..setWidth(120)
        ..setFormat(OutputFormat.jpeg);
      return c;
    }

    List<({String name, Uint8List bytes, String? path})> makeFiles(int n) => [
      for (var i = 0; i < n; i++)
        (name: 'c$i.jpg', bytes: _makeJpeg(300, 200), path: null),
    ];

    test('a pre-cancelled token skips instead of failing', () async {
      final job = ImageJob(id: 'x', name: 'x.jpg', bytes: _makeJpeg(300, 200));
      final token = CancellationToken()..cancel();
      final s = ResizeSettings()
        ..setMode(ResizeMode.width)
        ..setWidth(100)
        ..setFormat(OutputFormat.jpeg);
      final results = await processJob(job, s, cancellation: token);
      expect(results, isEmpty);
      expect(job.status, JobStatus.skipped);
      expect(job.error, contains('Cancelled'));
      expect(job.output, isNull);
    });

    test(
      'cancelling mid-batch keeps finished work and skips the rest',
      () async {
        final c = makeController();
        c.addDroppedFiles(makeFiles(6));
        var cancelled = false;
        c.addListener(() {
          if (!cancelled && c.doneCount >= 1) {
            cancelled = true;
            c.cancelBatch();
          }
        });
        await c.runBatch();
        expect(cancelled, isTrue);
        for (final j in c.jobs) {
          expect(j.status, isNot(JobStatus.running));
          expect(j.status, isNot(JobStatus.queued));
        }
        expect(c.doneCount, greaterThanOrEqualTo(1));
        expect(
          c.jobs.where((j) => j.status == JobStatus.failed),
          isEmpty,
          reason: 'interruption is a skip, never a failure',
        );
        c.dispose();
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'cancel is safe twice and after completion',
      () async {
        final c = makeController();
        c.addDroppedFiles(makeFiles(2));
        await c.runBatch();
        expect(c.doneCount, 2);
        c.cancelBatch();
        c.cancelBatch();
        expect(c.doneCount, 2);
        expect(c.busy, isFalse);
        c.dispose();
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

  group('background', () {
    test('start, progress and stop cross the channel', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final calls = <String>[];
      try {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(BackgroundService.channel, (call) async {
          calls.add(call.method);
          return null;
        });
        await BackgroundService.start(4, onCancel: () {});
        await BackgroundService.progress(2, 4);
        await BackgroundService.stop();
        expect(calls, ['start', 'progress', 'stop']);
      } finally {
        BackgroundService.resetForTest();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(BackgroundService.channel, null);
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('a refusing device never fails the batch', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(BackgroundService.channel, (call) async {
          throw PlatformException(code: 'DENIED');
        });
        await BackgroundService.start(4, onCancel: () {});
        await BackgroundService.progress(1, 4);
        await BackgroundService.stop();
      } finally {
        BackgroundService.resetForTest();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(BackgroundService.channel, null);
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('unsupported platforms are a silent no-op', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        var called = false;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(BackgroundService.channel, (call) async {
          called = true;
          return null;
        });
        expect(BackgroundService.isSupported, isFalse);
        await BackgroundService.start(4, onCancel: () {});
        await BackgroundService.progress(1, 4);
        await BackgroundService.stop();
        expect(called, isFalse);
      } finally {
        BackgroundService.resetForTest();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(BackgroundService.channel, null);
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('live-preview', () {
    test('renders the real pipeline at preview size', () async {
      final s = ResizeSettings()
        ..setMode(ResizeMode.width)
        ..setWidth(400)
        ..setFormat(OutputFormat.jpeg);
      final out = await ResizeEngine.renderPreview(
        _makeJpeg(1600, 1000),
        s,
        name: 'p.jpg',
      );
      expect(out, isNotNull);
      final decoded = img.decodeJpg(out!);
      expect(decoded, isNotNull);
      // Proxy longest edge is 900, then width 400 of the 1.6 aspect.
      expect(decoded!.width, 400);
      expect(decoded.height, 250);
    });

    test('preview applies the current settings', () async {
      final plain = ResizeSettings()
        ..setMode(ResizeMode.original)
        ..setFormat(OutputFormat.png);
      final gray = ResizeSettings()
        ..setMode(ResizeMode.original)
        ..setFormat(OutputFormat.png)
        ..setGrayscale(1.0);
      final src = _makeJpeg(200, 140);
      final a = img.decodePng((await ResizeEngine.renderPreview(src, plain, name: 'p.jpg'))!)!;
      final b = img.decodePng((await ResizeEngine.renderPreview(src, gray, name: 'p.jpg'))!)!;
      var saturation = 0;
      for (final p in b) {
        saturation += ((p.r - p.g).abs() + (p.g - p.b).abs()).toInt();
      }
      expect(saturation, 0, reason: 'full grayscale leaves no chroma');
      expect(a.width, b.width);
    });

    test('preview of garbage is null, never a throw', () async {
      final s = ResizeSettings()..setFormat(OutputFormat.jpeg);
      expect(
        await ResizeEngine.renderPreview(
          Uint8List.fromList(List.filled(64, 7)),
          s,
          name: 'x.jpg',
        ),
        isNull,
      );
    });
  });

  group('streaming', () {
    ResizeController makeController() {
      final c = ResizeController();
      c.settings
        ..setMode(ResizeMode.width)
        ..setWidth(120)
        ..setFormat(OutputFormat.jpeg);
      return c;
    }

    List<({String name, Uint8List bytes, String? path})> makeFiles(int n) => [
      for (var i = 0; i < n; i++)
        (name: 's$i.jpg', bytes: _makeJpeg(300, 200), path: null),
    ];

    test('a released source keeps its thumbnail', () {
      final job = ImageJob(id: 't', name: 't.jpg', bytes: _makeJpeg(100, 80));
      expect(job.hasSource, isTrue);
      job.setThumbnail(Uint8List.fromList([1, 2, 3]));
      job.releaseSource();
      expect(job.hasSource, isFalse);
      expect(job.thumbnail, isNotNull);
      expect(job.inputBytes, 0);
    });

    test(
      'saveAll releases sources once written',
      () async {
        final c = makeController();
        final dir = await Directory.systemTemp.createTemp('pf-save');
        try {
          c.settings.setOutputDirectory(dir.path);
          c.addDroppedFiles(makeFiles(2));
          await c.runBatch();
          expect(c.doneCount, 2);
          final written = await c.saveAll();
          expect(written, 2);
          for (final j in c.jobs) {
            expect(j.hasSource, isFalse);
            expect(j.output, isNotNull);
          }
          expect(dir.listSync(), hasLength(2));
        } finally {
          await dir.delete(recursive: true);
          c.dispose();
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'write-immediately streams each file and frees its source',
      () async {
        final c = makeController();
        final dir = await Directory.systemTemp.createTemp('pf-now');
        try {
          c.settings
            ..setOutputDirectory(dir.path)
            ..setWriteImmediately(true);
          c.addDroppedFiles(makeFiles(3));
          await c.runBatch();
          expect(c.doneCount, 3);
          expect(dir.listSync(), hasLength(3));
          for (final j in c.jobs) {
            expect(
              j.hasSource,
              isFalse,
              reason: 'streamed jobs must not retain their inputs',
            );
          }
        } finally {
          await dir.delete(recursive: true);
          c.dispose();
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'an oversized batch is chunked, not refused',
      () async {
        final c = makeController();
        // 64 MB budget with ~1 MB inputs forces several chunks.
        c.settings.setMemoryBudgetMb(64);
        c.addDroppedFiles(makeFiles(4));
        await c.runBatch();
        expect(c.doneCount, 4);
        c.dispose();
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('a job without a source is skipped with a reason', () async {
      final c = makeController();
      c.addDroppedFiles(makeFiles(1));
      final job = c.jobs.first;
      job.releaseSource();
      await c.runBatch();
      expect(job.status, JobStatus.skipped);
      expect(job.error, contains('re-add'));
      c.dispose();
    });
  });

  group('memory', () {
    test('scaled decode is documented as unsupported', () {
      // If anyone implements it, this test must be updated to assert the new
      // capability instead of the limitation. A comment claiming otherwise
      // without this test changing is the failure this guards against.
      expect(ResizeEngine.supportsScaledDecode, isFalse);
    });

    test('opaque output drops alpha at the earliest point', () async {
      final s = ResizeSettings()
        ..setMode(ResizeMode.width)
        ..setWidth(200)
        ..setFormat(OutputFormat.jpeg);

      final res = await ResizeEngine.run(
        _makePngAlpha(600, 400),
        s,
        name: 'a.png',
      );
      expect(res.width, 200);
      expect(
        ResizeEngine.lastWorkingChannels,
        3,
        reason: 'JPEG output with no watermark and no pad never needs alpha',
      );
    });

    test('transparent output keeps its alpha', () async {
      final s = ResizeSettings()
        ..setMode(ResizeMode.width)
        ..setWidth(200)
        ..setFormat(OutputFormat.png);

      await ResizeEngine.run(_makePngAlpha(600, 400), s, name: 'a.png');
      expect(ResizeEngine.lastWorkingChannels, 4);
    });

    test('an active watermark keeps alpha for compositing', () async {
      final s = ResizeSettings()
        ..setMode(ResizeMode.width)
        ..setWidth(200)
        ..setFormat(OutputFormat.jpeg)
        ..setWatermark(const WatermarkSettings(text: 'X', enabled: true));

      await ResizeEngine.run(_makePngAlpha(600, 400), s, name: 'a.png');
      expect(
        ResizeEngine.lastWorkingChannels,
        4,
        reason: 'the watermark layer composites with alpha blending',
      );
    });

    test('pad mode keeps alpha for the canvas', () async {
      final s = ResizeSettings()
        ..setMode(ResizeMode.exactFit)
        ..setWidth(300)
        ..setHeight(300)
        ..setFormat(OutputFormat.jpeg);

      await ResizeEngine.run(_makePngAlpha(600, 400), s, name: 'a.png');
      expect(ResizeEngine.lastWorkingChannels, 4);
    });
  });

  group('naming', () {
    test('substitutes every token and strips illegal characters', () {
      final out = renderTemplate(
        '{name}_{w}x{h}_{index}.{ext}',
        baseName: r'a/b:c',
        outWidth: 100,
        outHeight: 200,
        srcWidth: 400,
        srcHeight: 800,
        extension: 'webp',
        index: 7,
      );
      expect(out, 'a_b_c_100x200_0007.webp');
    });

    test('never returns an empty stem', () {
      final out = renderTemplate(
        '{name}',
        baseName: 'photo',
        outWidth: 1,
        outHeight: 1,
        srcWidth: 1,
        srcHeight: 1,
        extension: 'jpg',
        index: 1,
      );
      expect(out, isNotEmpty);
    });
  });

  group('animation', () {
    test('an animated GIF keeps every frame', () async {
      final res = await ResizeEngine.run(
        _makeAnimatedGif(80, 60, 5),
        _gifSettings(width: 40),
        name: 'spin.gif',
      );

      expect(res.extension, 'gif');
      expect(res.frames, 5);
      expect(res.notice, isNull);

      final decoded = img.decodeGif(res.bytes)!;
      expect(decoded.numFrames, 5, reason: 'the animation was flattened');
    });

    test('an animated WebP keeps every frame', () async {
      final res = await ResizeEngine.run(
        _makeAnimatedWebP(80, 60, 4),
        _webpSettings(width: 40),
        name: 'spin.webp',
      );

      expect(res.extension, 'webp');
      expect(res.frames, 4);
      expect(res.notice, isNull);

      final decoded = img.decodeWebP(res.bytes)!;
      expect(decoded.numFrames, 4, reason: 'the animation was flattened');
    });

    test('every frame is resized, not just the first', () async {
      final res = await ResizeEngine.run(
        _makeAnimatedGif(80, 60, 5),
        _gifSettings(width: 40),
        name: 'spin.gif',
      );

      final decoded = img.decodeGif(res.bytes)!;
      expect(decoded.width, 40);
      expect(decoded.height, 30);
      for (var i = 0; i < decoded.numFrames; i++) {
        final f = decoded.frames[i];
        expect(f.width, 40, reason: 'frame $i width');
        expect(f.height, 30, reason: 'frame $i height');
      }
    });

    test('frames keep their own durations', () async {
      const durations = [40, 80, 120, 200];
      final source = _makeAnimatedGif(80, 60, 4, durations: durations);
      expect(
        img.decodeGif(source)!.frames.map((f) => f.frameDuration).toList(),
        durations,
        reason: 'the fixture itself must round-trip',
      );

      final res = await ResizeEngine.run(
        source,
        _gifSettings(width: 40),
        name: 'spin.gif',
      );

      final decoded = img.decodeGif(res.bytes)!;
      expect(decoded.frames.map((f) => f.frameDuration).toList(), durations);
    });

    test('each frame keeps its own pixels', () async {
      // Lossless WebP so the check reads the pipeline rather than GIF's
      // 256-colour quantiser, which is free to shift a channel by a few steps.
      final res = await ResizeEngine.run(
        _makeAnimatedGif(80, 60, 4),
        ResizeSettings()
          ..setMode(ResizeMode.width)
          ..setWidth(40)
          ..setFormat(OutputFormat.webp)
          ..setWebpLossless(true),
        name: 'spin.gif',
      );

      final decoded = img.decodeWebP(res.bytes)!;
      expect(decoded.numFrames, 4);
      for (var i = 0; i < decoded.numFrames; i++) {
        final f = decoded.frames[i];
        var sum = 0.0;
        for (final p in f) {
          sum += p.b;
        }
        expect(
          sum / (f.width * f.height),
          closeTo(frameBlue(i), 1),
          reason: 'frame $i is not the frame it should be',
        );
      }
    });

    test('preserveAnimation false flattens to frame one', () async {
      final source = _makeAnimatedGif(80, 60, 5);

      final kept = await ResizeEngine.run(
        source,
        _gifSettings(width: 40),
        name: 'spin.gif',
      );
      final flattened = await ResizeEngine.run(
        source,
        _gifSettings(width: 40)..setPreserveAnimation(false),
        name: 'spin.gif',
      );

      expect(img.decodeGif(kept.bytes)!.numFrames, 5);
      expect(img.decodeGif(flattened.bytes)!.numFrames, 1);
      expect(flattened.frames, 1);
      expect(flattened.width, 40);
      expect(flattened.height, 30);
    });

    test('the opt-out says so instead of losing frames quietly', () async {
      final res = await ResizeEngine.run(
        _makeAnimatedGif(80, 60, 5),
        _gifSettings(width: 40)..setPreserveAnimation(false),
        name: 'spin.gif',
      );
      expect(res.notice, contains('Preserve animation'));
    });

    test('a still source produces no notice at all', () async {
      final res = await ResizeEngine.run(
        img.encodeGif(_frame(0, 80, 60), singleFrame: true),
        _gifSettings(width: 40),
        name: 'still.gif',
      );
      expect(res.frames, 1);
      expect(res.notice, isNull);
    });

    test('a frame-less container reports the flattening', () async {
      final res = await ResizeEngine.run(
        _makeAnimatedGif(80, 60, 5),
        ResizeSettings()
          ..setMode(ResizeMode.width)
          ..setWidth(40)
          ..setFormat(OutputFormat.jpeg),
        name: 'spin.gif',
      );

      expect(res.frames, 1);
      expect(img.decodeJpg(res.bytes)!.numFrames, 1);
      expect(res.notice, contains('JPEG'));
      expect(res.notice, contains('cannot hold'));
    });

    test('an animation survives a byte budget solve', () async {
      final res = await ResizeEngine.run(
        _makeAnimatedWebP(80, 60, 3),
        _webpSettings(width: 40)..setTargetKb(4),
        name: 'spin.webp',
      );

      expect(res.frames, 3);
      expect(img.decodeWebP(res.bytes)!.numFrames, 3);
      expect(res.bytes.length, lessThanOrEqualTo(4 * 1024));
    });

    test('rotation is applied to every frame', () async {
      final s = ResizeSettings()
        ..setMode(ResizeMode.original)
        ..rotateBy(1)
        ..setFormat(OutputFormat.gif);

      final res = await ResizeEngine.run(
        _makeAnimatedGif(80, 60, 3),
        s,
        name: 'spin.gif',
      );

      expect(res.width, 60);
      expect(res.height, 80);
      final decoded = img.decodeGif(res.bytes)!;
      expect(decoded.numFrames, 3);
      for (final f in decoded.frames) {
        expect(f.width, 60);
        expect(f.height, 80);
      }
    });

    test('every frame is padded onto the same canvas', () async {
      final s = ResizeSettings()
        ..setMode(ResizeMode.exactFit)
        ..setWidth(50)
        ..setHeight(50)
        ..setFormat(OutputFormat.gif);

      final res = await ResizeEngine.run(
        _makeAnimatedGif(80, 60, 4),
        s,
        name: 'spin.gif',
      );

      expect(res.width, 50);
      expect(res.height, 50);
      final decoded = img.decodeGif(res.bytes)!;
      expect(decoded.numFrames, 4);
      for (var i = 0; i < decoded.numFrames; i++) {
        expect(decoded.frames[i].width, 50, reason: 'frame $i width');
        expect(decoded.frames[i].height, 50, reason: 'frame $i height');
      }
    });

    test('the crop plan is computed once and used by every frame', () async {
      final s = ResizeSettings()
        ..setMode(ResizeMode.exactCrop)
        ..setWidth(40)
        ..setHeight(40)
        ..setFormat(OutputFormat.webp);

      final res = await ResizeEngine.run(
        _makeAnimatedWebP(80, 60, 4),
        s,
        name: 'spin.webp',
      );

      expect(res.width, 40);
      expect(res.height, 40);
      final decoded = img.decodeWebP(res.bytes)!;
      expect(decoded.numFrames, 4);
      for (var i = 0; i < decoded.numFrames; i++) {
        expect(decoded.frames[i].width, 40, reason: 'frame $i width');
        expect(decoded.frames[i].height, 40, reason: 'frame $i height');
      }
    });

    test(
      'an animated TIFF is reported rather than silently pageless',
      () async {
        final res = await ResizeEngine.run(
          _makeAnimatedGif(80, 60, 3),
          ResizeSettings()
            ..setMode(ResizeMode.width)
            ..setWidth(40)
            ..setFormat(OutputFormat.tiff),
          name: 'spin.gif',
        );

        expect(res.frames, 1);
        expect(res.notice, contains('TIFF'));
      },
    );
  });

  group('settings persistence', () {
    test('a snapshot round-trips through json', () {
      final a = ResizeSettings()
        ..setMode(ResizeMode.exactCrop)
        ..setWidth(1234)
        ..setHeight(567)
        ..setFormat(OutputFormat.webp)
        ..setQuality(42)
        ..setTargetKb(88)
        ..setNameTemplate('{name}_{w}')
        ..setWatermark(
          const WatermarkSettings(text: 'X', enabled: true, opacity: 0.3),
        );

      final b = ResizeSettings()..loadFrom(a.toJson());

      expect(b.mode, ResizeMode.exactCrop);
      expect(b.width, 1234);
      expect(b.height, 567);
      expect(b.format, OutputFormat.webp);
      expect(b.quality, 42);
      expect(b.targetKb, 88);
      expect(b.nameTemplate, '{name}_{w}');
      expect(b.watermark.text, 'X');
      expect(b.watermark.opacity, 0.3);
    });

    test('quality overrides an active size budget', () {
      final s = ResizeSettings()..setTargetKb(50);
      expect(s.qualityIsAutomatic, isTrue);
      s.setQuality(70);
      expect(s.qualityIsAutomatic, isFalse);
      expect(s.targetKb, isNull);
    });

    test('preserveAnimation defaults on and survives a snapshot', () {
      final a = ResizeSettings();
      expect(a.preserveAnimation, isTrue, reason: 'flattening must be opt-in');

      a.setPreserveAnimation(false);
      final b = ResizeSettings()..loadFrom(a.toJson());
      expect(b.preserveAnimation, isFalse);
    });
  });
}

bool resizeEngineDecodes(String ext) {
  return ext == 'jpg' ||
      ext == 'png' ||
      ext == 'webp' ||
      ext == 'gif' ||
      ext == 'bmp' ||
      ext == 'tiff';
}
