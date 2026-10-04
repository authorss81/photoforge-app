import 'dart:math' as math;

/// How the output geometry is derived from the source image.
enum ResizeMode {
  original('Keep original'),
  longestSide('Fit inside box'),
  exactFit('Pad into box'),
  exactCrop('Crop to box'),
  exactStretch('Stretch to box'),
  width('Set width'),
  height('Set height'),
  percent('Scale by percent');

  const ResizeMode(this.label);

  final String label;

  /// True when the result is guaranteed to be exactly width x height.
  bool get isExact =>
      this == exactFit || this == exactCrop || this == exactStretch;
}

/// The pixel geometry of a result.
class TargetSize {
  const TargetSize(this.width, this.height);

  final int width;
  final int height;

  int get pixels => width * height;

  bool get isSquare => width == height;

  @override
  bool operator ==(Object other) =>
      other is TargetSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => '$width x $height';
}

/// Resize parameters fed into [computeTargetSize].
class ResizeSpec {
  const ResizeSpec({
    this.mode = ResizeMode.longestSide,
    this.width,
    this.height,
    this.percent = 100,
    this.allowUpscale = false,
  });

  final ResizeMode mode;
  final int? width;
  final int? height;
  final int percent;
  final bool allowUpscale;

  ResizeSpec copyWith({
    ResizeMode? mode,
    int? width,
    int? height,
    int? percent,
    bool? allowUpscale,
  }) => ResizeSpec(
    mode: mode ?? this.mode,
    width: width ?? this.width,
    height: height ?? this.height,
    percent: percent ?? this.percent,
    allowUpscale: allowUpscale ?? this.allowUpscale,
  );
}

/// Geometry for modes that centre-crop or pad, expressed as source-pixel
/// rectangles to crop and canvas offsets.
class CropPlan {
  const CropPlan({
    this.cropX = 0,
    this.cropY = 0,
    this.cropW = 0,
    this.cropH = 0,
  });

  final int cropX;
  final int cropY;
  final int cropW;
  final int cropH;

  static const none = CropPlan();
}

int _clampDim(num v) {
  if (v.isNaN || v.isInfinite) return 1;
  final i = v.round();
  return i < 1 ? 1 : i;
}

/// Resolves [spec] against a source of [srcW] x [srcH] pixels.
TargetSize computeTargetSize(ResizeSpec spec, int srcW, int srcH) {
  if (srcW <= 0 || srcH <= 0) return const TargetSize(1, 1);

  final mode = spec.mode;

  if (mode == ResizeMode.original) {
    return TargetSize(srcW, srcH);
  }

  if (mode == ResizeMode.percent) {
    final p = (spec.percent.clamp(1, 1000)) / 100.0;
    if (!spec.allowUpscale && p >= 1.0) return TargetSize(srcW, srcH);
    return TargetSize(_clampDim(srcW * p), _clampDim(srcH * p));
  }

  if (mode == ResizeMode.width) {
    final w = spec.width ?? srcW;
    final scaled = w / srcW;
    final h = _clampDim(srcH * scaled);
    return _guardUpscale(spec, srcW, srcH, TargetSize(_clampDim(w), h));
  }

  if (mode == ResizeMode.height) {
    final h = spec.height ?? srcH;
    final scaled = h / srcH;
    final w = _clampDim(srcW * scaled);
    return _guardUpscale(spec, srcW, srcH, TargetSize(w, _clampDim(h)));
  }

  final boxW = math.max(1, spec.width ?? srcW);
  final boxH = math.max(1, spec.height ?? srcH);

  switch (mode) {
    case ResizeMode.exactStretch:
      return TargetSize(_clampDim(boxW), _clampDim(boxH));

    case ResizeMode.exactFit:
    case ResizeMode.exactCrop:
      // These modes promise an exact box, so the upscale guard does not apply:
      // padding or cropping is how the box is reached. A 400x400 source asked
      // for 600x600 exact-fit gets a 600x600 canvas.
      return TargetSize(_clampDim(boxW), _clampDim(boxH));

    case ResizeMode.longestSide:
    default:
      final scale = math.min(boxW / srcW, boxH / srcH);
      if (scale >= 1.0 && !spec.allowUpscale) {
        return TargetSize(srcW, srcH);
      }
      return TargetSize(_clampDim(srcW * scale), _clampDim(srcH * scale));
  }
}

/// The scaled size a "fit inside the box, then pad" pass should scale to.
/// This is the inner rectangle [computeTargetSize] does not return for
/// [ResizeMode.exactFit], because the outer canvas is the box itself.
TargetSize computeFitInsideBox(
  int srcW,
  int srcH,
  int boxW,
  int boxH, {
  bool allowUpscale = false,
}) {
  if (srcW <= 0 || srcH <= 0) return const TargetSize(1, 1);
  final bw = math.max(1, boxW);
  final bh = math.max(1, boxH);
  final scale = math.min(bw / srcW, bh / srcH);
  if (scale >= 1.0 && !allowUpscale) return TargetSize(srcW, srcH);
  return TargetSize(_clampDim(srcW * scale), _clampDim(srcH * scale));
}

TargetSize _guardUpscale(ResizeSpec spec, int srcW, int srcH, TargetSize t) {
  if (spec.allowUpscale) return t;
  if (t.width >= srcW && t.height >= srcH) return TargetSize(srcW, srcH);
  // Only block the axis that grew, keep the constraining one exact.
  var w = t.width;
  var h = t.height;
  if (w > srcW) {
    final k = srcW / w;
    w = srcW;
    h = _clampDim(h * k);
  }
  if (h > srcH) {
    final k = srcH / h;
    h = srcH;
    w = _clampDim(w * k);
  }
  return TargetSize(w, h);
}

/// Source-pixel crop needed to fill [target] at the source aspect ratio.
///
/// [focal] biases the window towards a point of interest, such as a detected
/// face, instead of the geometric centre. It is in source pixels and is
/// clamped so a box never runs off the edge. Passing null gives the exact
/// centre crop this function has always produced, byte for byte, which is what
/// keeps the default path provably unchanged.
///
/// With several [faces] the window is chosen to contain as many of them as
/// possible, and ties are broken towards the centre. A single face off to one
/// side therefore pulls the crop that way, while a group is kept together
/// rather than the crop jumping to whichever face was detected last.
CropPlan computeCropPlan(
  int srcW,
  int srcH,
  TargetSize target, {
  ({double x, double y})? focal,
  List<({double x, double y})> faces = const [],
}) {
  if (srcW <= 0 || srcH <= 0) return CropPlan.none;
  if (target.width <= 0 || target.height <= 0) return CropPlan.none;

  final targetAspect = target.width / target.height;
  final srcAspect = srcW / srcH;

  int w;
  int h;
  if (srcAspect > targetAspect) {
    h = srcH;
    w = _clampDim(srcH * targetAspect);
  } else {
    w = srcW;
    h = _clampDim(srcW / targetAspect);
  }

  if (w >= srcW && h >= srcH) return CropPlan.none;

  final x = _focalX(srcW, w, focal, faces);
  final y = _focalY(srcH, h, focal, faces);
  return CropPlan(cropX: x, cropY: y, cropW: w, cropH: h);
}

/// Chooses the horizontal offset for a crop window [w] wide in a [srcW] source.
int _focalX(
  int srcW,
  int w,
  ({double x, double y})? focal,
  List<({double x, double y})> faces,
) {
  final span = srcW - w;
  // No horizontal movement is possible.
  if (span <= 0) return 0;

  final points = faces.isNotEmpty
      ? faces
      : (focal == null ? const [] : [focal]);
  if (points.isEmpty) return span ~/ 2;

  // A single point of interest: centre the window on it.
  if (points.length == 1) {
    final p = points.first;
    return _clampOffset((p.x.round() - w ~/ 2), span);
  }

  // Several: prefer the window that contains the most of them. Among the
  // windows that tie, take the one closest to the source centre, so the result
  // is stable rather than dependent on detection order.
  final xs = <int>[for (final p in points) p.x.round()]..sort();
  final lo = xs.first;
  final hi = xs.last;
  if (hi - lo <= w) {
    // They all fit together, so centre on their midpoint.
    return _clampOffset(((lo + hi) ~/ 2) - w ~/ 2, span);
  }
  // Too wide to contain; aim at the largest group of consecutive faces the
  // window can hold.
  return _bestWindowFor(xs, w, span);
}

/// Largest run of consecutive [xs] that fits in [w], then centred.
int _bestWindowFor(List<int> xs, int w, int span) {
  // Cannot happen: callers pass at least two points. Guarded anyway, because a
  // window offset of zero would silently mean "left edge", which is a different
  // answer from "no faces at all".
  if (xs.isEmpty) return span ~/ 2;
  var bestCount = 0;
  var bestCentre = 0;
  for (var i = 0; i < xs.length; i++) {
    var j = i;
    while (j + 1 < xs.length && xs[j + 1] - xs[i] <= w) {
      j++;
    }
    final count = j - i + 1;
    final centre = ((xs[i] + xs[j]) ~/ 2) - w ~/ 2;
    if (count > bestCount ||
        (count == bestCount &&
            (centre - span ~/ 2).abs() < (bestCentre - span ~/ 2).abs())) {
      bestCount = count;
      bestCentre = centre;
    }
  }
  return _clampOffset(bestCentre, span);
}

int _focalY(
  int srcH,
  int h,
  ({double x, double y})? focal,
  List<({double x, double y})> faces,
) {
  final span = srcH - h;
  if (span <= 0) return 0;

  final points = faces.isNotEmpty
      ? faces
      : (focal == null ? const [] : [focal]);
  if (points.isEmpty) return span ~/ 2;

  if (points.length == 1) {
    // Faces sit in the upper half of a portrait far more often than not, so the
    // vertical axis is biased towards the subject rather than centred on it.
    // Without this a portrait cropped to 1:1 keeps the shoulders.
    final p = points.first;
    final ideal = (p.y.round() - h ~/ 2);
    return _clampOffset((ideal * 3) ~/ 4 + span ~/ 4, span);
  }

  final ys = points.map((p) => p.y.round()).toList()..sort();
  return _clampOffset(((ys.first + ys.last) ~/ 2) - h ~/ 2, span);
}

int _clampOffset(int v, int span) => v < 0 ? 0 : (v > span ? span : v);

/// Resampling method for a given downscale factor.
enum Resample { fast, balanced, high }

Resample defaultResample(int srcDim, int outDim) {
  final ratio = outDim <= 0 ? 1.0 : srcDim / outDim;
  if (ratio >= 3) return Resample.high;
  if (ratio >= 1.5) return Resample.balanced;
  return Resample.fast;
}
