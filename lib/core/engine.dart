import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart' show Color;
import 'package:image/image.dart' as img;

import 'job.dart';
import 'error.dart';
import 'native_decoder.dart';
import 'native/libheif.dart';
import 'resize_mode.dart';
import 'settings.dart';
import 'tiff16.dart';

export 'error.dart';

class EngineResult {
  const EngineResult({
    required this.bytes,
    required this.width,
    required this.height,
    required this.extension,
    this.quality,
    this.metTarget = true,
    this.frames = 1,
    this.notice,
  });

  /// Rebuilds a result from the plain map a worker isolate sends back.
  /// Isolates can only carry primitives, maps and typed data, so results
  /// cross the boundary as maps and are rehydrated here.
  factory EngineResult.fromMap(Map<String, dynamic> m) => EngineResult(
        bytes: m['bytes'] as Uint8List,
        width: m['width'] as int,
        height: m['height'] as int,
        extension: m['extension'] as String,
        quality: m['quality'] as int?,
        metTarget: (m['metTarget'] as bool?) ?? true,
        frames: (m['frames'] as int?) ?? 1,
        notice: m['notice'] as String?,
      );

  final Uint8List bytes;
  final int width;
  final int height;
  final String extension;
  final int? quality;

  /// False when the requested byte budget could not be met at minimum quality.
  final bool metTarget;

  /// How many frames the encoded result actually holds.
  final int frames;

  /// Set when the output could not carry everything the source had. A user who
  /// loses frames without being told is worse served than one who gets told.
  final String? notice;
}

class SourceInfo {
  const SourceInfo(this.width, this.height, this.format, this.extension);

  final int width;
  final int height;
  final String? format;
  final String? extension;
}

const List<num> _sharpenKernel = [0, -1, 0, -1, 5, -1, 0, -1, 0];

/// Geometry resolved once per source image and reused for every frame, so an
/// animation keeps a uniform frame size instead of drifting with whatever
/// aspect ratio a later frame happens to carry.
class _FrameGeometry {
  const _FrameGeometry({
    required this.outer,
    required this.target,
    required this.crop,
    required this.interpolation,
  });

  /// The canvas a padded result is stretched out to. Equal to [target]
  /// whenever the mode does not pad.
  final TargetSize outer;

  /// The size every frame is resized to.
  final TargetSize target;

  /// The source-pixel rectangle removed before resizing, when cropping.
  final CropPlan crop;

  final img.Interpolation interpolation;
}

const List<String> supportedInputExtensions = <String>[
  'jpg',
  'jpeg',
  'jpe',
  'png',
  'webp',
  'gif',
  'tif',
  'tiff',
  'bmp',
  'ico',
  'tga',
  'psd',
  'pnm',
  'pvr',
  'exr',
  'heic',
  'heif',
  'avif',
];

const List<String> writeableExtensions = <String>[
  'jpg',
  'png',
  'webp',
  'gif',
  'tiff',
  'bmp',
];

/// Converts a Flutter colour to the codec library's channel colour.
img.Color toCodecColor(Color c) => img.ColorRgba8(
  (c.r * 255).round(),
  (c.g * 255).round(),
  (c.b * 255).round(),
  (c.a * 255).round(),
);

/// The pure-Dart image pipeline. No network, no platform channels.
class ResizeEngine {
  /// True for a JPEG whose frames carry four components (CMYK or YCCK).
  ///
  /// Found by scanning SOF markers rather than by decoding, because the
  /// decoder has no CMYK path and would otherwise produce wrong colours
  /// without any error. Malformed data safely reports false; the decoder then
  /// produces its own error downstream.
  static bool isCmykJpeg(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return false;
    var i = 2;
    while (i + 4 <= bytes.length) {
      if (bytes[i] != 0xFF) return false;
      final marker = bytes[i + 1];
      // Standalone markers carry no length.
      if (marker == 0xD8 || marker == 0xD9 || (marker >= 0xD0 && marker <= 0xD7) || marker == 0x01) {
        i += 2;
        continue;
      }
      if (i + 4 > bytes.length) return false;
      final length = (bytes[i + 2] << 8) | bytes[i + 3];
      if (length < 2) return false;
      // SOF0-SOF15 except DHT (C4), JPG (C8) and DAC (CC).
      final isSof = marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isSof && i + 10 <= bytes.length) {
        final components = bytes[i + 9];
        if (components == 4) return true;
        if (components == 1 || components == 3) return false;
      }
      // SOS: entropy data follows, no more markers worth scanning.
      if (marker == 0xDA) return false;
      i += 2 + length;
    }
    return false;
  }

  /// Whether the decoder can scale during the entropy decode (libjpeg 1/8, 1/4,
  /// 1/2 factors), so a 24 MP source shrunk to 400px never materialises.
  ///
  /// False. `package:image` ships its own pure-Dart JPEG decoder with no
  /// scaled-decode path, and there is no way to add one without replacing the
  /// decoder. This constant exists so the limitation is a checked-in fact
  /// rather than tribal knowledge, and so a test fails if anyone claims the
  /// capability without implementing it. Real scaled decode arrives with the
  /// native decoders in phases 14 through 16, which scale during decode on
  /// every platform.
  static const bool supportsScaledDecode = false;

  /// Full decodes performed. Test observability for the multi-output work:
  /// one decode must feed any number of presets.
  static int decodeCount = 0;

  /// The most channels any working image carried during the last [run].
  /// Test observability for the phase-06 memory work, nothing more.
  static int lastWorkingChannels = 0;

  const ResizeEngine._();

  static String? extensionOf(String path) {
    final i = path.lastIndexOf('.');
    if (i < 0 || i == path.length - 1) return null;
    return path.substring(i + 1).toLowerCase();
  }

  static String? extensionOfName(String name) {
    final i = name.lastIndexOf('.');
    if (i < 0 || i == name.length - 1) return null;
    return name.substring(i + 1).toLowerCase();
  }

  /// Reads dimensions and container so the UI can show real numbers.
  static SourceInfo probe(Uint8List bytes, {String? name}) {
    final ext = name == null ? null : extensionOfName(name);
    final decoded = _decodeOrThrow(bytes, name);
    return SourceInfo(decoded.width, decoded.height, decoded.format.name, ext);
  }

  /// Decoders throw on malformed data rather than returning null, so every entry
  /// point funnels through here to give the UI one predictable error type.
  /// Async decode that tries the platform decoder first for the HEIF family.
  ///
  /// Method channels do not exist in worker isolates, so pooled callers must
  /// not rely on this; the controller partitions HEIF work onto the main
  /// isolate instead.
  static Future<img.Image> decodeAsync(Uint8List bytes, String? name) async {
    final ext = name == null ? null : extensionOfName(name);
    if (NativeDecoder.isHeifFamily(ext)) {
      final png = await NativeDecoder.decodeToPng(bytes);
      if (png != null) {
        try {
          final decoded = img.decodePng(png);
          if (decoded != null && decoded.isValid) return decoded;
        } catch (_) {
          // Fall through to the standard path and its clear error.
        }
      }
      // Desktop ships a bundled libheif. Mobile relies on the platform
      // decoder above; when that is absent there is nothing left to try.
      if (Libheif.load() != null) {
        return Libheif.decode(bytes);
      }
    }
    return _decodeOrThrow(bytes, name);
  }

  static img.Image _decodeOrThrow(Uint8List bytes, String? name) {
    if (isCmykJpeg(bytes)) {
      throw EngineError(
        'This JPEG uses CMYK colour, which the decoder cannot convert to RGB. '
        'Convert it to sRGB first${name == null ? '' : ' ($name)'}.',
      );
    }
    decodeCount++;
    img.Image? decoded;
    try {
      decoded = img.decodeNamedImage(name ?? '', bytes);
    } catch (e) {
      decoded = null;
    }
    if (decoded == null || !decoded.isValid) {
      throw EngineError(
        'Could not decode this file — unsupported or corrupt data. HEIC, HEIF '
        'and AVIF decode natively on Android 9+ and on iOS; on desktop and web, '
        'convert to JPEG first.',
      );
    }
    return decoded;
  }

  /// Full pipeline. [onProgress] receives 0..1 on a best-effort basis.
  static Future<EngineResult> run(
    Uint8List source,
    ResizeSettings s, {
    String? name,
    void Function(double)? onProgress,
    CancellationToken? cancellation,
  }) async {
    final results = await runAll(
      source,
      s,
      name: name,
      onProgress: onProgress,
      cancellation: cancellation,
    );
    return results.first;
  }

  /// One result per independently shippable image. Animations stay a single
  /// result; multi-page documents (TIFF pages) split into one result per page.
  static Future<List<EngineResult>> runAll(
    Uint8List source,
    ResizeSettings s, {
    String? name,
    void Function(double)? onProgress,
    CancellationToken? cancellation,
  }) async {
    void tick(double v) => onProgress?.call(v.clamp(0.0, 1.0));

    tick(0.02);

    final decoded = await decodeAsync(source, name);
    lastWorkingChannels = 0;
    cancellation?.throwIfCancelled();

    tick(0.10);

    final outFormat = _resolveFormat(
      s.format,
      s.keepExtensionWhenKeepFormat,
      name == null ? null : extensionOfName(name),
    );

    return _renderAll(
      decoded,
      s,
      outFormat,
      name: name,
      onProgress: onProgress,
      cancellation: cancellation,
    );
  }

  /// Shared render path: one result normally, one per page for multi-page
  /// documents. Used by both [runAll] and [runMulti] so the two agree.
  static Future<List<EngineResult>> _renderAll(
    img.Image decoded,
    ResizeSettings s,
    OutputFormat outFormat, {
    String? name,
    void Function(double)? onProgress,
    CancellationToken? cancellation,
  }) async {
    void tick(double v) => onProgress?.call(v.clamp(0.0, 1.0));

    final pages =
        decoded.frameType == img.FrameType.page && decoded.numFrames > 1;
    if (!pages) {
      return [
        await _runDecoded(
          decoded,
          s,
          outFormat,
          name: name,
          onProgress: onProgress,
          cancellation: cancellation,
        )
      ];
    }

    final results = <EngineResult>[];
    for (var p = 0; p < decoded.numFrames; p++) {
      cancellation?.throwIfCancelled();
      final page = _detachFrame(decoded.getFrame(p));
      results.add(
        await _runDecoded(
          page,
          s,
          outFormat,
          name: name,
          pageIndex: p,
          pageCount: decoded.numFrames,
          onProgress: (v) => tick(0.10 + 0.90 * (p + v) / decoded.numFrames),
          cancellation: cancellation,
        ),
      );
    }
    return results;
  }

/// One decode feeding any number of presets. Each preset renders from a clone,
  /// so per-preset transforms cannot leak into each other, and each preset
  /// solves its own quality against its own byte budget. Returns one list of
  /// results per preset, in preset order.
  static Future<List<List<EngineResult>>> runMulti(
    Uint8List source,
    List<ResizeSettings> presets, {
    String? name,
    void Function(double)? onProgress,
    CancellationToken? cancellation,
  }) async {
    if (presets.isEmpty) return const [];
    final decoded = await decodeAsync(source, name);
    final out = <List<EngineResult>>[];
    for (var i = 0; i < presets.length; i++) {
      final s = presets[i];
      final outFormat = _resolveFormat(
        s.format,
        s.keepExtensionWhenKeepFormat,
        name == null ? null : extensionOfName(name),
      );
      final results = await _renderAll(
        decoded.clone(),
        s,
        outFormat,
        name: name,
        onProgress: onProgress == null
            ? null
            : (v) => onProgress((i + v) / presets.length),
      );
      out.add(results);
    }
    return out;
  }

  static Future<EngineResult> _runDecoded(
    img.Image decoded,
    ResizeSettings s,
    OutputFormat outFormat, {
    String? name,
    int? pageIndex,
    int? pageCount,
    void Function(double)? onProgress,
    CancellationToken? cancellation,
  }) async {
    void tick(double v) => onProgress?.call(v.clamp(0.0, 1.0));

    // Orientation, rotation and flips act on the whole animation, so they run
    // once over every frame at once instead of inside the per-frame transform.
    final oriented = _applySourceTransforms(decoded, s);
    cancellation?.throwIfCancelled();

    tick(0.22);

    // Frames only survive when the user has not opted out and the chosen
    // container can actually hold them.
    final animated =
        s.preserveAnimation && decoded.hasAnimation && outFormat.supportsFrames;
    final inputs = animated
        ? oriented.frames.map(_detachFrame).toList()
        : <img.Image>[_detachFrame(oriented.frames.first)];

    // Geometry comes from frame 0 once, so every frame lands on identical
    // dimensions instead of drifting with each frame's own aspect ratio.
    final geometry = _geometryFor(s.spec, inputs.first);

    final total = inputs.length;
    final produced = <img.Image>[];
    for (var i = 0; i < total; i++) {
      cancellation?.throwIfCancelled();
      final out = _applyToFrame(inputs[i], s, geometry, outFormat);
      out.frameDuration = inputs[i].frameDuration;
      produced.add(out);
      tick(0.22 + (0.80 - 0.22) * (i + 1) / total);
    }

    if (s.stripMetadata) {
      for (final f in produced) {
        _applyMetadataPolicy(f, s);
      }
    }

    final work = _assemble(produced, loopCount: oriented.loopCount);
    cancellation?.throwIfCancelled();
    final notice = pageIndex != null && pageCount != null
        ? 'Page ${pageIndex + 1} of $pageCount.'
        : _animationNotice(
            sourceFrames: decoded.numFrames,
            animated: animated,
            outFormat: outFormat,
            preserveAnimation: s.preserveAnimation,
          );

    final budget = s.targetKb == null ? null : s.targetKb! * 1024;
    if (budget != null && outFormat.supportsQuality) {      final solved = _solveToBudget(
        work,
        outFormat,
        s,
        budget,
        animated: animated,
        notice: notice,
      );
      tick(1.0);
      return solved;
    }

    final encoded = _encode(work, outFormat, s, animated: animated);
    tick(1.0);

    return EngineResult(
      bytes: encoded,
      width: work.width,
      height: work.height,
      extension: outFormat.extension!,
      quality: outFormat.supportsQuality ? s.quality : null,
      frames: animated ? total : 1,
      notice: notice,
    );
  }

  // ------------------------------------------------------------- animations
  /// Rotation and flipping are source-level: they must move every frame
  /// together or the animation tears. `bakeOrientation` and `copyRotate`
  /// already walk `frames`, and `flipHorizontal`/`flipVertical` edit them in
  /// place.
  static img.Image _applySourceTransforms(img.Image src, ResizeSettings s) {
    var work = src;

    // Orientation is always baked when metadata is being dropped, otherwise the
    // stripped orientation tag would leave the pixels sideways.
    if (work.exif.imageIfd.hasOrientation &&
        work.exif.imageIfd.orientation != 1) {
      work = img.bakeOrientation(work);
    }

    if (s.rotateQuarterTurns != 0) {
      work = img.copyRotate(work, angle: 90 * s.rotateQuarterTurns);
    }
    if (s.flipH) work = img.flipHorizontal(work);
    if (s.flipV) work = img.flipVertical(work);

    return work;
  }

  /// Resolves the shared geometry for every frame of one source image.
  ///
  /// Crop and pad are expressed against frame 0's pixel grid and the resampling
  /// method is chosen from the post-crop dimensions, which is what the
  /// single-frame path did.
  static _FrameGeometry _geometryFor(ResizeSpec spec, img.Image source) {
    // exactFit scales to sit inside the box and then pads out to it, so it needs
    // two sizes: the scaled inner rect and the outer canvas.
    final outer = computeTargetSize(spec, source.width, source.height);
    final target = spec.mode == ResizeMode.exactFit
        ? computeFitInsideBox(
            source.width,
            source.height,
            outer.width,
            outer.height,
            allowUpscale: spec.allowUpscale,
          )
        : outer;

    var crop = CropPlan.none;
    var srcW = source.width;
    var srcH = source.height;
    if (spec.mode == ResizeMode.exactCrop) {
      final plan = computeCropPlan(srcW, srcH, target);
      if (plan != CropPlan.none) {
        crop = plan;
        srcW = plan.cropW;
        srcH = plan.cropH;
      }
    }

    final resample = defaultResample(
      math.max(srcW, srcH),
      math.max(target.width, target.height),
    );

    return _FrameGeometry(
      outer: outer,
      target: target,
      crop: crop,
      interpolation: switch (resample) {
        Resample.high => img.Interpolation.cubic,
        Resample.balanced => img.Interpolation.average,
        Resample.fast => img.Interpolation.linear,
      },
    );
  }

  /// Frame zero of a decoded animation *is* the animation: `frames` hangs the
  /// whole sequence off it. Every transform in the pipeline walks `frames`, so a
  /// frame has to be handed over detached or transforming frame 0 would quietly
  /// re-process every other frame as well.
  static img.Image _detachFrame(img.Image frame) =>
      frame.numFrames == 1 ? frame : img.Image.from(frame, noAnimation: true);

  /// One frame through the whole pipeline.
  ///
  /// [geometry] is shared by every frame of a source so an animation cannot
  /// drift out of alignment frame by frame.
  static img.Image _applyToFrame(
    img.Image frame,
    ResizeSettings s,
    _FrameGeometry geometry,
    OutputFormat outFormat,
  ) {
    var work = frame;

    // Phase-06: drop alpha at the earliest point the rest of the pipeline
    // provably does not need it. A 24 MP RGBA image is ~96 MB resident; RGB is
    // ~72 MB, and the saving compounds across every intermediate allocation.
    // Safe only when nothing downstream touches transparency: opaque output
    // container, no watermark compositing, and no pad canvas.
    if (work.hasAlpha &&
        (outFormat == OutputFormat.jpeg || outFormat == OutputFormat.bmp) &&
        !s.watermark.active &&
        s.spec.mode != ResizeMode.exactFit) {
      work = work.convert(numChannels: 3);
    }
    if (work.numChannels > lastWorkingChannels) {
      lastWorkingChannels = work.numChannels;
    }

    if (geometry.crop != CropPlan.none) {
      work = img.copyCrop(
        work,
        x: geometry.crop.cropX,
        y: geometry.crop.cropY,
        width: geometry.crop.cropW,
        height: geometry.crop.cropH,
      );
    }

    if (work.width != geometry.target.width ||
        work.height != geometry.target.height) {
      // copyResize silently downgrades paletted images to nearest-neighbour,
      // which turns smooth gradients into staircases. Go through direct
      // colour for the resize; the GIF encoder re-quantizes on the way out.
      // The size cost of the round trip is measured in the phase-13 test.
      if (work.hasPalette) {
        work = work.convert(numChannels: work.hasAlpha ? 4 : 3);
      }
      work = img.copyResize(
        work,
        width: geometry.target.width,
        height: geometry.target.height,
        interpolation: geometry.interpolation,
      );
    }

    work = _applyAdjustments(work, s);
    work = _applyFilters(work, s);

    if (s.spec.mode == ResizeMode.exactFit) {
      work = _pad(work, geometry.outer, toCodecColor(s.padColor));
    }

    if (s.watermark.active) {
      work = _applyWatermark(work, s.watermark);
    }

    return _prepareChannels(work, outFormat);
  }

  /// Rebuilds an animation from already-transformed frames, keeping the source
  /// loop count so the result still repeats the way the input did.
  static img.Image _assemble(List<img.Image> frames, {required int loopCount}) {
    final head = frames.first;
    for (var i = 1; i < frames.length; i++) {
      head.addFrame(frames[i]);
    }
    head.loopCount = loopCount;
    return head;
  }

  /// Explains, rather than hides, the two ways an animation can be lost.
  static String? _animationNotice({
    required int sourceFrames,
    required bool animated,
    required OutputFormat outFormat,
    required bool preserveAnimation,
  }) {
    if (sourceFrames < 2 || animated) return null;
    // The only way to reach here with a frame-capable container is the opt-out,
    // because [animated] folds [preserveAnimation] in.
    if (outFormat.supportsFrames && !preserveAnimation) {
      return 'Animation flattened to one frame: "Preserve animation" is off.';
    }
    return 'Animation flattened to one frame: ${outFormat.label} cannot hold '
        'more than one frame.';
  }

  /// libwebp's demuxer rejects the whole file when a frame overruns the canvas,
  /// so the failure is raised as a real message rather than an opaque encoder
  /// exception reported as "Unexpected error".
  static void _assertFramesFitCanvas(img.Image im) {
    for (var i = 0; i < im.numFrames; i++) {
      final f = im.frames[i];
      if (f.width > im.width || f.height > im.height) {
        throw EngineError(
          'Frame $i of this animation is ${f.width}x${f.height} and does not '
          'fit the ${im.width}x${im.height} canvas WebP requires.',
        );
      }
    }
  }

  // ------------------------------------------------------------------ output
  static OutputFormat _resolveFormat(
    OutputFormat chosen,
    bool keepExtension,
    String? sourceExt,
  ) {
    if (chosen != OutputFormat.keep) return chosen;
    if (keepExtension) {
      final mapped = OutputFormat.fromExtension(sourceExt);
      if (mapped != OutputFormat.keep) return mapped;
    }
    return OutputFormat.jpeg;
  }

  /// Removes exactly the metadata the settings ask for, nothing more.
  ///
  /// Each flag maps onto the IFD that carries it: GPS lives in the `gps` sub
  /// directory of IFD0, camera data in the `exif` sub directory, timestamps in
  /// three well-known tags, and the thumbnail in IFD1. When every flag is set
  /// the whole container is replaced, which is also faster than pruning.
  static void _applyMetadataPolicy(img.Image work, ResizeSettings s) {
    if (!s.stripGps &&
        !s.stripCamera &&
        !s.stripTimestamps &&
        !s.stripThumbnail) {
      return;
    }
    if (s.stripGps && s.stripCamera && s.stripTimestamps && s.stripThumbnail) {
      work.exif = img.ExifData();
      return;
    }
    final exif = work.exif;
    // operator[] auto-creates directories on read, so check first to avoid
    // manufacturing empty IFD structure on images that carry no metadata.
    final hasIfd0 = exif.directories.containsKey('ifd0');
    if (s.stripGps && hasIfd0) {
      exif.imageIfd.sub.directories.remove('gps');
    }
    if (s.stripCamera && hasIfd0) {
      exif.imageIfd.sub.directories.remove('exif');
    }
    if (s.stripTimestamps && hasIfd0) {
      // 0x0132 ModifyDate in IFD0; 0x9003 DateTimeOriginal and 0x9004 CreateDate
      // in the EXIF sub IFD.
      exif.imageIfd.data.remove(0x0132);
      final subExif = exif.imageIfd.sub.directories['exif'];
      if (subExif != null) {
        subExif.data.remove(0x9003);
        subExif.data.remove(0x9004);
      }
    }
    if (s.stripThumbnail) {
      exif.directories.remove('ifd1');
    }
  }

  static img.Image _applyAdjustments(img.Image src, ResizeSettings s) {
    final a = s.adjustments;
    if (a.isNeutral) return src;

    var out = img.adjustColor(
      src,
      brightness: a.brightness == 0 ? null : a.brightness,
      contrast: a.contrast == 0 ? null : a.contrast,
      saturation: a.saturation == 0 ? null : a.saturation,
      exposure: a.exposure == 0 ? null : a.exposure,
      hue: a.hue == 0 ? null : a.hue,
      gamma: a.gamma == 0 ? null : a.gamma,
      amount: a.amount,
    );

    // A flat histogram stretch recovers blown or muddy shots. Only fires when
    // the caller has not set brightness/contrast/exposure/gamma, so intent wins.
    if (a.brightness == 0 &&
        a.contrast == 0 &&
        a.exposure == 0 &&
        a.gamma == 0) {
      out = img.normalize(out, min: 0, max: 255);
    }

    return out;
  }

  static img.Image _applyFilters(img.Image src, ResizeSettings s) {
    var out = src;

    if (s.blurRadius >= 0.5) {
      out = img.gaussianBlur(out, radius: s.blurRadius.round());
    }
    if (s.sharpenAmount > 0) {
      out = img.convolution(
        out,
        filter: _sharpenKernel,
        amount: s.sharpenAmount,
      );
    }
    if (s.grayscale > 0) {
      out = _mix(out, img.grayscale(out), s.grayscale);
    }
    if (s.sepia > 0) {
      out = _mix(out, img.sepia(out), s.sepia);
    }

    return out;
  }

  static img.Image _mix(img.Image a, img.Image b, num t) {
    if (t >= 1) return b;
    if (t <= 0) return a;
    final out = a.clone();
    for (final p in out) {
      final q = b.getPixel(p.x, p.y);
      p
        ..r = _lerp(p.r, q.r, t)
        ..g = _lerp(p.g, q.g, t)
        ..b = _lerp(p.b, q.b, t)
        ..a = _lerp(p.a, q.a, t);
    }
    return out;
  }

  static int _lerp(num a, num b, num t) =>
      (a + (b - a) * t).round().clamp(0, 255);

  static img.Image _pad(img.Image src, TargetSize target, img.Color color) {
    if (src.width == target.width && src.height == target.height) return src;
    final out = img.Image(
      width: target.width,
      height: target.height,
      numChannels: 4,
    );
    img.fill(out, color: color);
    img.compositeImage(
      out,
      src,
      dstX: (target.width - src.width) ~/ 2,
      dstY: (target.height - src.height) ~/ 2,
      blend: img.BlendMode.alpha,
    );
    return out;
  }

  // -------------------------------------------------------------- watermark
  static img.BitmapFont _fontForHeight(int h) {
    if (h <= 16) return img.arial14;
    if (h <= 28) return img.arial24;
    return img.arial48;
  }

  static img.Image _applyWatermark(img.Image src, WatermarkSettings wm) {
    final text = wm.text.trim();
    if (text.isEmpty) return src;

    final base = math.min(src.width, src.height);
    final targetHeight = (base * wm.scale).round().clamp(8, 220);
    final color = toCodecColor(wm.color);

    // Render onto a deliberately oversized canvas, then crop to the ink box and
    // scale that down. Drawing straight into a tightly-sized layer clips glyphs.
    final canvas = img.Image(
      width: math.min(src.width * 2, 4096),
      height: math.min(targetHeight * 3, 1024),
      numChannels: 4,
    );
    img.drawString(
      canvas,
      text,
      font: _fontForHeight(targetHeight),
      x: 0,
      y: 0,
      color: color,
    );

    final bbox = _tightBounds(canvas);
    if (bbox == null) return src;

    var layer = img.copyCrop(
      canvas,
      x: bbox.x,
      y: bbox.y,
      width: bbox.width,
      height: bbox.height,
    );
    layer = img.copyResize(
      layer,
      width: (bbox.width * (targetHeight / bbox.height)).round().clamp(
        1,
        src.width,
      ),
      height: targetHeight.clamp(1, src.height),
      interpolation: img.Interpolation.average,
    );
    layer = _applyOpacity(layer, wm.opacity);

    final w = layer.width;
    final h = layer.height;
    final margin = (base * wm.margin).round();
    late final int dx;
    late final int dy;
    switch (wm.corner) {
      case WatermarkCorner.topLeft:
        dx = margin;
        dy = margin;
      case WatermarkCorner.topRight:
        dx = src.width - w - margin;
        dy = margin;
      case WatermarkCorner.bottomLeft:
        dx = margin;
        dy = src.height - h - margin;
      case WatermarkCorner.bottomRight:
        dx = src.width - w - margin;
        dy = src.height - h - margin;
      case WatermarkCorner.center:
        dx = (src.width - w) ~/ 2;
        dy = (src.height - h) ~/ 2;
    }

    final out = src.clone();
    img.compositeImage(
      out,
      layer,
      dstX: dx.clamp(0, math.max(0, src.width - 1)),
      dstY: dy.clamp(0, math.max(0, src.height - 1)),
      blend: img.BlendMode.alpha,
    );
    return out;
  }

  static ({int x, int y, int width, int height})? _tightBounds(img.Image im) {
    var minX = im.width;
    var minY = im.height;
    var maxX = -1;
    var maxY = -1;
    for (final p in im) {
      if (p.a != 0) {
        if (p.x < minX) minX = p.x;
        if (p.x > maxX) maxX = p.x;
        if (p.y < minY) minY = p.y;
        if (p.y > maxY) maxY = p.y;
      }
    }
    if (maxX < 0 || maxY < 0) return null;
    return (x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1);
  }

  static img.Image _applyOpacity(img.Image src, double opacity) {
    if (opacity >= 1) return src;
    final out = src.clone();
    for (final p in out) {
      p.a = opacity <= 0 ? 0 : (p.a * opacity).round().clamp(0, 255);
    }
    return out;
  }

  /// Flattens alpha where the container cannot carry it.
  static img.Image _prepareChannels(img.Image src, OutputFormat fmt) {
    switch (fmt) {
      case OutputFormat.jpeg:
      case OutputFormat.bmp:
        return src.hasAlpha ? src.convert(numChannels: 3) : src;
      case OutputFormat.gif:
        return src.hasAlpha ? src : src.convert(numChannels: 4);
      case OutputFormat.png:
      case OutputFormat.webp:
      case OutputFormat.tiff:
        return src.hasAlpha ? src : src.convert(numChannels: 4);
      case OutputFormat.keep:
        return src;
    }
  }

  // ---------------------------------------------------------------- encoding
  /// [animated] must be true whenever [im] holds more than one frame, otherwise
  /// the encoder is told to write a still and silently drops the rest.
  static Uint8List _encode(
    img.Image im,
    OutputFormat fmt,
    ResizeSettings s, {
    int? quality,
    bool animated = false,
  }) {
    final q = quality ?? s.quality;
    switch (fmt) {
      case OutputFormat.jpeg:
        return img.encodeJpg(
          im,
          quality: q,
          chroma: s.chroma == ChromaMode.yuv420
              ? img.JpegChroma.yuv420
              : img.JpegChroma.yuv444,
        );
      case OutputFormat.png:
        return img.encodePng(im, level: s.pngLevel);
      case OutputFormat.webp:
        if (animated) _assertFramesFitCanvas(im);
        return img.encodeWebP(
          im,
          // lossless is on by default in the codec, and it makes quality and
          // method do nothing, so it has to be turned off deliberately.
          lossless: s.webpLossless,
          quality: s.webpLossless ? 100 : q,
          method: s.webpMethod,
          singleFrame: !animated,
        );
      case OutputFormat.gif:
        return img.encodeGif(im, singleFrame: !animated);
      case OutputFormat.tiff:
        // The package encoder truncates everything to 8 bits through
        // toUint8List, so 16-bit output goes through our own writer.
        if (im.format == img.Format.uint16) return encodeTiff16(im);
        return img.encodeTiff(im, singleFrame: !animated);
      case OutputFormat.bmp:
        return img.encodeBmp(im);
      case OutputFormat.keep:
        throw EngineError('Unresolved output format.');
    }
  }

  /// Binary-searches the best quality whose encoded size fits [budgetBytes].
  ///
  /// Solved on a ~512px proxy of frame zero, not on the full image. The old
  /// code did seven to eight full-resolution encodes per file; this does the
  /// search on a thumbnail and at most two full encodes. The single correcting
  /// encode absorbs the proxy's estimation error. See [_solveToBudgetLegacy],
  /// kept beside it so tests can compare the two.
  static int lastSolveFullEncodes = 0;

  static EngineResult _solveToBudget(
    img.Image im,
    OutputFormat fmt,
    ResizeSettings s,
    int budgetBytes, {
    required bool animated,
    String? notice,
  }) {
    lastSolveFullEncodes = 0;
    final minQ = fmt == OutputFormat.jpeg ? 25 : 10;
    final maxQ = fmt == OutputFormat.jpeg ? 96 : 92;
    final frameCount = animated ? im.numFrames : 1;

    Uint8List fullEncode(int q) {
      lastSolveFullEncodes++;
      return _encode(im, fmt, s, quality: q, animated: animated);
    }

    EngineResult finish(Uint8List bytes, int q, bool met) => EngineResult(
          bytes: bytes,
          width: im.width,
          height: im.height,
          extension: fmt.extension!,
          quality: q,
          frames: frameCount,
          metTarget: met,
          notice: notice,
        );

    // Proxy: frame zero, longest edge around 512px. Byte count scales close to
    // linearly with pixel count, so the budget scales by the pixel ratio and
    // the frame count. Animation delta-frames compress better than stills, so
    // this is an estimator, not a promise; the correcting encode absorbs it.
    final src0 = _detachFrame(animated ? im.getFrame(0) : im);
    final longest = math.max(src0.width, src0.height);
    final img.Image proxy;
    if (longest > 512) {
      final k = 512 / longest;
      proxy = img.copyResize(
        src0,
        width: (src0.width * k).round().clamp(1, src0.width),
        height: (src0.height * k).round().clamp(1, src0.height),
        interpolation: img.Interpolation.average,
      );
    } else {
      proxy = src0;
    }
    final ratio = (proxy.width * proxy.height) /
        math.max(1, im.width * im.height) /
        math.max(1, frameCount);
    final proxyBudget = math.max(64, (budgetBytes * ratio).round());

    int proxySize(int q) =>
        _encode(proxy, fmt, s, quality: q, animated: false).length;

    if (proxySize(minQ) > proxyBudget) {
      return finish(fullEncode(minQ), minQ, false);
    }

    var lo = minQ;
    var hi = maxQ;
    var bestQ = minQ;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      if (proxySize(mid) <= proxyBudget) {
        bestQ = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }

    var bytes = fullEncode(bestQ);
    if (bytes.length <= budgetBytes) {
      return finish(bytes, bestQ, true);
    }

    final corrected = math.max(minQ, bestQ - 5).toInt();
    bytes = fullEncode(corrected);
    return finish(bytes, corrected, bytes.length <= budgetBytes);
  }

/// The pre-phase-04 solver: binary search with full-resolution encodes.
/// Kept as the reference so tests can prove the proxy path agrees with it.
/// Do not call from production code.
  static EngineResult solveToBudgetLegacy(
    img.Image im,
    OutputFormat fmt,
    ResizeSettings s,
    int budgetBytes, {
    required bool animated,
    String? notice,
  }) {
    final minQ = fmt == OutputFormat.jpeg ? 25 : 10;
    final maxQ = fmt == OutputFormat.jpeg ? 96 : 92;
    final frameCount = animated ? im.numFrames : 1;

    final atMax = _encode(im, fmt, s, quality: maxQ, animated: animated);
    if (atMax.length <= budgetBytes) {
      return EngineResult(
        bytes: atMax,
        width: im.width,
        height: im.height,
        extension: fmt.extension!,
        quality: maxQ,
        frames: frameCount,
        notice: notice,
      );
    }

    final atMin = _encode(im, fmt, s, quality: minQ, animated: animated);
    if (atMin.length > budgetBytes) {
      return EngineResult(
        bytes: atMin,
        width: im.width,
        height: im.height,
        extension: fmt.extension!,
        quality: minQ,
        metTarget: false,
        frames: frameCount,
        notice: notice,
      );
    }

    var lo = minQ;
    var hi = maxQ;
    var bestQ = minQ;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      final size = _encode(im, fmt, s, quality: mid, animated: animated).length;
      if (size <= budgetBytes) {
        bestQ = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }

    return EngineResult(
      bytes: _encode(im, fmt, s, quality: bestQ, animated: animated),
      width: im.width,
      height: im.height,
      extension: fmt.extension!,
      quality: bestQ,
      frames: frameCount,
      notice: notice,
    );
  }

  // ----------------------------------------------------------------- preview
  /// Small PNG for the UI preview pane.
  static Uint8List? thumbnail(Uint8List source, {int maxDim = 720}) {
    final decoded = img.decodeImage(source);
    if (decoded == null || !decoded.isValid) return null;
    var work = decoded;
    if (work.exif.imageIfd.hasOrientation &&
        work.exif.imageIfd.orientation != 1) {
      work = img.bakeOrientation(work);
    }
    final longest = math.max(work.width, work.height);
    if (longest > maxDim) {
      final k = maxDim / longest;
      work = img.copyResize(
        work,
        width: (work.width * k).round(),
        height: (work.height * k).round(),
        interpolation: img.Interpolation.average,
      );
    }
    return img.encodePng(work, level: 3);
  }
}

/// Runs one job through the engine and updates its state.
Future<List<EngineResult>> processJob(
  ImageJob job,
  ResizeSettings settings, {
  CancellationToken? cancellation,
}) async {
  job.markRunning(0.0);
  try {
    final results = await ResizeEngine.runAll(
      job.bytes,
      settings,
      name: job.name,
      onProgress: job.markRunning,
      cancellation: cancellation,
    );
    final res = results.first;
    job.markDone(
      output: res.bytes,
      width: res.width,
      height: res.height,
      quality: res.quality,
      frames: res.frames,
      notice: res.notice,
    );
    return results;
  } on JobCancelled {
    job.markSkipped('Cancelled.');
  } on EngineError catch (e) {
    job.markFailed(e.message);
  } catch (e) {
    job.markFailed('Unexpected error: $e');
  }
  return const <EngineResult>[];
}

/// Renders `{token}` patterns for an output filename.
String renderTemplate(
  String template, {
  required String baseName,
  required int outWidth,
  required int outHeight,
  required int srcWidth,
  required int srcHeight,
  required String extension,
  required int index,
  String? presetName,
}) {
  var s = template;
  s = s.replaceAll('{name}', baseName);
  s = s.replaceAll('{w}', outWidth.toString());
  s = s.replaceAll('{h}', outHeight.toString());
  s = s.replaceAll('{origw}', srcWidth.toString());
  s = s.replaceAll('{origh}', srcHeight.toString());
  s = s.replaceAll('{index}', index.toString().padLeft(4, '0'));
  s = s.replaceAll('{ext}', extension);
  s = s.replaceAll('{preset}', presetName ?? 'custom');
  s = s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.isEmpty) s = baseName;
  return s;
}
