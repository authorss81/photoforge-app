# The face detection model

PixelForge can centre a crop on detected faces instead of on the geometric
centre. This document records which model is used, why, and what it costs.

## The model

| | |
|---|---|
| Name | YuNet, `face_detection_yunet_2023mar.onnx` |
| Path | `assets/models/face_detection_yunet_2023mar.onnx` |
| Size | 227 KB (232,589 bytes) |
| Licence | MIT, committed at `assets/models/LICENSE-yunet.txt` |
| Source | [opencv/opencv_zoo](https://github.com/opencv/opencv_zoo/tree/main/models/face_detection_yunet) |
| Paper | *YuNet: A tiny millisecond-level face detector* |

The licence text is committed next to the model on purpose. A licence file in a
repository is easy to lose in a refactor and impossible to reconstruct from
memory, and "we checked once" is not a licence position.

## Why YuNet and not SCRFD

SCRFD is the stronger detector, and it was the first choice. It was rejected on
licensing, and the reason is worth recording because it is easy to get wrong.

**The code and the weights are licensed separately.** SCRFD's repository is
Apache-2.0, but the repository itself says:

> The license applied only to code. The models are a derivative work of
> InsightFace and are used for testing purposes only without any license
> warranties.

InsightFace is not licensed for commercial use. Shipping its weights inside a
commercial app would therefore be a licence violation even though every line of
SCRFD you can read in the repository is permissively licensed. Reading the
repository's badge and concluding "Apache-2.0, fine to ship" is exactly the
mistake to avoid.

YuNet has no such split: the model directory is MIT, covering both the weights
and the accompanying code, and MIT permits redistribution and commercial use.

This was verified by reading `models/face_detection_yunet/LICENSE` in
opencv_zoo, which is the authoritative location, rather than a model card
summary.

## Size delta

| | Bytes |
|---|---|
| Repository before | 29,704,749 |
| Model added | 232,589 |
| Repository after | 29,937,338 |

The phase budget was about 10 MB. The model is 2.2% of that, which is why a
detector this small was worth shipping rather than skipping the feature.

## Cost

Detection runs on a copy whose longest edge is 640 pixels, not on the source.
YuNet detects faces of roughly 10 to 300 pixels, so downscaling loses nothing
that matters while making the cost independent of image size. The decode and
the inference both run on a worker isolate, so neither blocks a frame.

**Not yet measured.** The acceptance criterion was under 200 ms on a 24 MP
image, measured with the phase-12 benchmark harness. That measurement has not
been taken, because the ONNX runtime is not wired up yet. When it is, the number
goes in this table rather than being estimated.

## Current status: the runtime is not bundled

This is the important part, and it is why the feature is off by default.

The model is committed and the crop planner that consumes detections is
implemented and tested. **Inference is not.** No ONNX Runtime shared library is
bundled for any platform yet, so `FaceDetector.installRuntime()` reports
`runtimeMissing` and `FaceDetector.detect()` returns that status.

Consequently:

- Face-aware cropping is a no-op on every platform right now.
- The setting is present, off by default, and round-trips through the settings
  snapshot.
- With detection unavailable the crop is the exact centre crop, byte for byte.
  `test/face_crop_test.dart` asserts this by comparing pipeline output with the
  toggle on and off.

The reason is not conservatism about the model. It is that a native ONNX Runtime
has to be bundled per platform and architecture, and none of that can be built
or verified on the machine this was written on. Shipping a feature that silently
does nothing while appearing to work is worse than shipping the parts that do.

## What remains to finish it

1. Bundle an ONNX Runtime shared library for Windows, Android and iOS.
2. Implement `_infer` in `FaceDetector`, which currently throws if reached.
3. Add the toggle to the settings UI, showing
   `FaceDetector.unavailabilityReason` when detection cannot run.
4. Measure the 24 MP cost with the benchmark harness and record it above.
5. Run the smoke job on an emulator, which is the only place the native library
   is actually exercised.

The interface is deliberately narrow and `FaceDetectionResult` carries its own
status, so none of these steps change a caller.

## Design decisions in the crop planner

- **Off by default.** A false positive moves the crop away from the subject,
  which is worse than a plain centre crop.
- **No fallback that guesses.** When nothing is detected the centre crop is
  used, not a saliency heuristic.
- **Detection order does not matter.** Candidate windows are scored by how many
  faces they contain, tie-broken towards the source centre, so the result is
  stable rather than depending on which face the detector reported first.
- **Vertical bias.** A single face is placed three-quarters of the way towards
  its own position, because faces sit in the upper part of a portrait far more
  often than not and a centred crop keeps the shoulders.