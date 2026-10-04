import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixelforge/core/detection/face_detector.dart';
import 'package:pixelforge/core/engine.dart';
import 'package:pixelforge/core/resize_mode.dart';
import 'package:pixelforge/core/settings.dart';

/// A stand-in for a detected face: the crop planner only ever sees centres, so
/// these are the points the tests are really about.
({double x, double y}) _at(double x, double y) => (x: x, y: y);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('centre crop is unchanged', () {
    // The phase contract is that a build with detection off is byte-identical
    // to the previous behaviour. These assert the exact integers the old code
    // produced, so a silent change to the default cannot pass.
    test('a wide source cropped to a square centres exactly', () {
      final plan = computeCropPlan(1000, 500, const TargetSize(100, 100));
      expect(plan.cropX, 250);
      expect(plan.cropY, 0);
      expect(plan.cropW, 500);
      expect(plan.cropH, 500);
    });

    test('a tall source cropped to a wide box centres exactly', () {
      // 500x1000 into a 2:1 box: the full width is kept and the height is cut,
      // so the window is 500x250 and only y can move.
      final plan = computeCropPlan(500, 1000, const TargetSize(200, 100));
      expect(plan.cropX, 0);
      expect(plan.cropW, 500);
      expect(plan.cropH, 250);
      expect(plan.cropY, 375, reason: '(1000 - 250) / 2');
    });

    test('a source that already fits is not cropped', () {
      final plan = computeCropPlan(100, 100, const TargetSize(50, 50));
      expect(plan, CropPlan.none);
    });
  });

  group('focal crop', () {
    test('a face on the left pulls the window left', () {
      // 1000 wide into a 500-wide window: the window can start anywhere from 0
      // to 500. A face centred at x=150 puts it in the middle of the window,
      // i.e. cropX near 0.
      final plan = computeCropPlan(
        1000,
        500,
        const TargetSize(100, 100),
        faces: [_at(150, 250)],
      );
      expect(
        plan.cropX,
        lessThan(125),
        reason: 'the window must move towards the face, not stay centred',
      );
      expect(
        plan.cropY,
        0,
        reason:
            'a 2:1 source cropped to a square uses the full height, so '
            'y cannot move at all',
      );
    });

    test('a face near the top biases the vertical window upwards', () {
      // A tall source cropped to a wide box: the full width is kept and only
      // y can move, which is where the subject-position bias shows up. A face
      // high in the frame must pull the window up, keeping the head rather than
      // the shoulders.
      final plan = computeCropPlan(
        800,
        1600,
        const TargetSize(100, 100),
        faces: [_at(400, 300)],
      );
      expect(plan.cropX, 0, reason: 'x cannot move in this geometry');
      expect(plan.cropH, lessThan(1600));
      final centred = (1600 - plan.cropH) ~/ 2;
      expect(
        plan.cropY,
        lessThan(centred),
        reason: 'a face above centre must pull the window up',
      );
    });

    test('a face on the right pulls the window right', () {
      final plan = computeCropPlan(
        1000,
        500,
        const TargetSize(100, 100),
        faces: [_at(850, 250)],
      );
      expect(plan.cropX, 500, reason: 'clamped to the right edge');
    });

    test('the window never runs off either edge', () {
      for (final x in [-500.0, 0.0, 250.0, 500.0, 1000.0, 99999.0]) {
        final plan = computeCropPlan(
          1000,
          500,
          const TargetSize(100, 100),
          faces: [_at(x, 250)],
        );
        expect(plan.cropX, inInclusiveRange(0, 500), reason: 'x=$x');
        expect(plan.cropW, 500);
      }
    });

    test('a face near the centre barely moves the crop', () {
      final plan = computeCropPlan(
        1000,
        500,
        const TargetSize(100, 100),
        faces: [_at(500, 250)],
      );
      expect(
        plan.cropX,
        250,
        reason: 'a centred face must give the same result as no face',
      );
    });
  });

  group('multiple faces', () {
    test('two faces that both fit are kept together', () {
      final plan = computeCropPlan(
        1000,
        500,
        const TargetSize(100, 100),
        faces: [_at(200, 200), _at(280, 220)],
      );
      expect(plan.cropX, 0, reason: 'midpoint 240 minus half a window clamps');
      expect(
        plan.cropX + plan.cropW,
        greaterThan(280),
        reason: 'both faces must be inside the window',
      );
    });

    test('faces spread wider than the window keep the largest group', () {
      final plan = computeCropPlan(
        2000,
        500,
        const TargetSize(100, 100),
        faces: [_at(100, 200), _at(180, 200), _at(1800, 200)],
      );
      expect(
        plan.cropX,
        lessThan(500),
        reason: 'the window must favour the group, not the lone outlier',
      );
    });

    test('detection order does not change the result', () {
      final a = computeCropPlan(
        2000,
        500,
        const TargetSize(100, 100),
        faces: [_at(300, 200), _at(340, 210), _at(1500, 200)],
      );
      final b = computeCropPlan(
        2000,
        500,
        const TargetSize(100, 100),
        faces: [_at(1500, 200), _at(340, 210), _at(300, 200)],
      );
      expect(
        a.cropX,
        b.cropX,
        reason: 'the plan must not depend on the order faces were reported',
      );
      expect(a.cropY, b.cropY);
    });

    test('an empty face list is exactly the centre crop', () {
      final withEmpty = computeCropPlan(
        1000,
        500,
        const TargetSize(100, 100),
        faces: const [],
      );
      final withNone = computeCropPlan(1000, 500, const TargetSize(100, 100));
      expect(withEmpty.cropX, withNone.cropX);
      expect(withEmpty.cropY, withNone.cropY);
      expect(withEmpty.cropW, withNone.cropW);
      expect(withEmpty.cropH, withNone.cropH);
    });
  });

  group('detector status', () {
    setUp(FaceDetector.debugResetRuntime);

    test('detection never throws and always reports a status', () async {
      final result = await FaceDetector.detect(
        img.Image(width: 40, height: 40),
      );
      expect(
        FaceDetectorStatus.values,
        contains(result.status),
        reason: 'a result must carry a known status',
      );
    });

    test('an empty image is available-but-empty, not a failure', () async {
      final result = await FaceDetector.detect(img.Image(width: 0, height: 0));
      expect(result.isAvailable, isTrue);
      expect(result.ranButFoundNothing, isTrue);
    });

    test('the reason is available to the UI when detection cannot run', () {
      final status = FaceDetector.installRuntime();
      expect(FaceDetector.isRuntimeAvailable, isFalse);
      expect(
        FaceDetector.unavailabilityReason,
        isNotNull,
        reason: 'the UI must be able to say why, not just fail silently',
      );
      expect(status, isNot(FaceDetectorStatus.available));
    });

    test('unavailable is distinguishable from found-nothing', () async {
      final unavailable = await FaceDetector.detect(
        img.Image(width: 20, height: 20),
      );
      expect(unavailable.isAvailable, isFalse);
      expect(unavailable.ranButFoundNothing, isFalse);
      expect(unavailable.faces, isEmpty);
    });

    test('the bundled model is committed and small', () {
      expect(
        FaceDetector.modelExists,
        isTrue,
        reason: 'the model asset must be in the repository',
      );
      final model = File(FaceDetector.modelPath);
      expect(
        model.lengthSync(),
        lessThan(10 * 1024 * 1024),
        reason: 'the phase caps the model at about 10 MB',
      );
    });

    test('the licence is committed next to the model', () {
      final licence = File('assets/models/LICENSE-yunet.txt');
      expect(licence.existsSync(), isTrue);
      final text = licence.readAsStringSync();
      expect(text, contains('MIT License'));
      expect(
        text.toLowerCase(),
        contains('without restriction'),
        reason: 'MIT must permit redistribution and sale',
      );
    });

    test('the detector adds no networking dependency', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      for (final banned in ['http:', 'dio:', 'socket_io_client:', 'sentry']) {
        expect(
          pubspec,
          isNot(contains(banned)),
          reason: 'face detection must not add $banned',
        );
      }
    });
  });

  group('settings toggle', () {
    test('face awareness is off by default', () {
      expect(
        ResizeSettings().faceAwareCrop,
        isFalse,
        reason: 'a false positive crop is worse than a centre crop',
      );
    });

    test('it survives a snapshot round trip', () {
      final a = ResizeSettings()..setFaceAwareCrop(true);
      final b = ResizeSettings()..loadFrom(a.toJson());
      expect(b.faceAwareCrop, isTrue);
    });

    test('a default snapshot does not enable it', () {
      final b = ResizeSettings()..loadFrom(ResizeSettings().toJson());
      expect(b.faceAwareCrop, isFalse);
    });
  });

  group('pipeline with detection unavailable', () {
    test(
      'exact-crop output is identical whether or not the toggle is on',
      () async {
        // The ONNX runtime is not bundled, so detection always reports
        // unavailable. Turning the toggle on must therefore change nothing, which
        // is the behaviour that keeps the default path provably safe.
        final src = img.Image(width: 300, height: 200);
        for (var y = 0; y < 200; y++) {
          for (var x = 0; x < 300; x++) {
            src.setPixelRgba(x, y, (x * 7) % 256, (y * 5) % 256, 90, 255);
          }
        }
        final png = img.encodePng(src);

        final off = ResizeSettings()
          ..setMode(ResizeMode.exactCrop)
          ..setWidth(120)
          ..setHeight(120)
          ..setFormat(OutputFormat.png);

        final on = ResizeSettings()
          ..setMode(ResizeMode.exactCrop)
          ..setWidth(120)
          ..setHeight(120)
          ..setFormat(OutputFormat.png)
          ..setFaceAwareCrop(true);

        final a = await ResizeEngine.run(png, off, name: 'a.png');
        final b = await ResizeEngine.run(png, on, name: 'a.png');

        expect(
          a.bytes,
          b.bytes,
          reason: 'unavailable detection must be a no-op',
        );
        expect(a.width, 120);
        expect(a.height, 120);
      },
    );
  });
}
