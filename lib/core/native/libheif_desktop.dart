import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:image/image.dart' as img;

import '../error.dart';

/// libheif bindings for desktop HEIC/AVIF decoding.
///
/// Only the decode path is bound, and only what it needs: context lifecycle,
/// primary image handle, one decode call, plane reads, release. The enum
/// values below are from libheif's stable C ABI (heif.h). Planar RGB output
/// is requested deliberately: colorspace RGB (1), chroma 444 (3) and channels
/// R/G/B (3/4/5) are the values least likely to ever move, and interleaved
/// modes are avoided so there is nothing to guess about.
///
/// The library is bundled under windows/libheif and installed next to the
/// executable. It is never resolved from PATH and never assumed present.
/// Everything here fails closed with [EngineError].
final class _HeifError extends Struct {
  @Int32()
  external int code;

  @Int32()
  external int subcode;

  external Pointer<Utf8> message;
}

typedef _CtxAllocC = Pointer<Void> Function();
typedef _CtxAllocD = Pointer<Void> Function();

typedef _CtxFreeC = Void Function(Pointer<Void>);
typedef _CtxFreeD = void Function(Pointer<Void>);

typedef _ReadMemC = _HeifError Function(
    Pointer<Void>, Pointer<Uint8>, Size, Pointer<Void>);
typedef _ReadMemD = _HeifError Function(
    Pointer<Void>, Pointer<Uint8>, int, Pointer<Void>);

typedef _PrimaryC = _HeifError Function(Pointer<Void>, Pointer<Pointer<Void>>);
typedef _PrimaryD = _HeifError Function(
    Pointer<Void>, Pointer<Pointer<Void>>);

typedef _DecodeC = _HeifError Function(
    Pointer<Void>, Pointer<Pointer<Void>>, Int32, Int32, Pointer<Void>);
typedef _DecodeD = _HeifError Function(
    Pointer<Void>, Pointer<Pointer<Void>>, int, int, Pointer<Void>);

typedef _DimC = Int32 Function(Pointer<Void>, Int32);
typedef _DimD = int Function(Pointer<Void>, int);

typedef _PlaneC = Pointer<Uint8> Function(
    Pointer<Void>, Int32, Pointer<Int32>);
typedef _PlaneD = Pointer<Uint8> Function(
    Pointer<Void>, int, Pointer<Int32>);

typedef _ReleaseC = Void Function(Pointer<Void>);
typedef _ReleaseD = void Function(Pointer<Void>);

class Libheif {
  Libheif._(DynamicLibrary lib)
      : _alloc = lib.lookupFunction<_CtxAllocC, _CtxAllocD>(
            'heif_context_alloc'),
        _free = lib.lookupFunction<_CtxFreeC, _CtxFreeD>(
            'heif_context_free'),
        _readMem = lib.lookupFunction<_ReadMemC, _ReadMemD>(
            'heif_context_read_from_memory'),
        _primary = lib.lookupFunction<_PrimaryC, _PrimaryD>(
            'heif_context_get_primary_image_handle'),
        _decode = lib.lookupFunction<_DecodeC, _DecodeD>(
            'heif_decode_image'),
        _width = lib.lookupFunction<_DimC, _DimD>('heif_image_get_width'),
        _height = lib.lookupFunction<_DimC, _DimD>('heif_image_get_height'),
        _plane = lib.lookupFunction<_PlaneC, _PlaneD>(
            'heif_image_get_plane'),
        _imageRelease = lib.lookupFunction<_ReleaseC, _ReleaseD>(
            'heif_image_release'),
        _handleRelease = lib.lookupFunction<_ReleaseC, _ReleaseD>(
            'heif_image_handle_release');

  final _CtxAllocD _alloc;
  final _CtxFreeD _free;
  final _ReadMemD _readMem;
  final _PrimaryD _primary;
  final _DecodeD _decode;
  final _DimD _width;
  final _DimD _height;
  final _PlaneD _plane;
  final _ReleaseD _imageRelease;
  final _ReleaseD _handleRelease;

  static const _colorspaceRgb = 1;
  static const _chroma444 = 3;
  static const _chR = 3;
  static const _chG = 4;
  static const _chB = 5;

  static String? _cachedPath;
  static DynamicLibrary? _cachedLib;

  /// Loads the bundled library, or null when it is absent. Never throws for a
  /// missing file; a missing file is a normal state, not an error.
  static DynamicLibrary? load() {
    if (_cachedLib != null) return _cachedLib;
    for (final path in _candidates()) {
      try {
        final lib = DynamicLibrary.open(path);
        // Prove it is really libheif before trusting it.
        lib.lookupFunction<_CtxAllocC, _CtxAllocD>('heif_context_alloc');
        _cachedPath = path;
        _cachedLib = lib;
        return lib;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  static String? get loadedFrom => _cachedPath;

  static Iterable<String> _candidates() sync* {
    if (!Platform.isWindows && !Platform.isLinux) return;
    final sep = Platform.pathSeparator;
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    // Installed layout: any libheif build next to the executable. The bundled
    // files carry hashed MinGW names, so glob rather than guessing.
    yield* _globLibheif(exeDir);
    // Source tree, so `flutter test` exercises the real decoder without an
    // install step. Never used in a shipped build.
    yield* _globLibheif(
      '${Directory.current.path}${sep}windows${sep}libheif',
    );
    // System library as a last resort on Linux.
    if (Platform.isLinux) {
      yield 'libheif.so.1';
      yield 'libheif.so';
    }
  }

  static Iterable<String> _globLibheif(String dir) sync* {
    // Bare names first for hand-rolled installs, then whatever the bundle
    // actually shipped.
    if (Platform.isWindows) yield '$dir${Platform.pathSeparator}libheif.dll';
    if (Platform.isLinux) {
      yield '$dir${Platform.pathSeparator}libheif.so.1';
      yield '$dir${Platform.pathSeparator}libheif.so';
    }
    try {
      final d = Directory(dir);
      if (!d.existsSync()) return;
      final ext = Platform.isWindows ? '.dll' : '.so';
      // Match the file name, not the whole path: the bundle directory itself
      // is called libheif, which would otherwise match every DLL in it and
      // waste an open plus a symbol lookup on each.
      final names = d
          .listSync()
          .whereType<File>()
          .map((f) => f.path)
          .where((p) {
            final base = p.split(Platform.pathSeparator).last.toLowerCase();
            return base.startsWith('libheif') && base.endsWith(ext);
          })
          .toList()
        ..sort();
      yield* names;
    } catch (_) {
      // A missing or unreadable directory is normal, not an error.
    }
  }

  /// Decodes to an RGB image. Throws [EngineError] naming the failure.
  static img.Image decode(Uint8List bytes) {
    final lib = load();
    if (lib == null) {
      throw EngineError(
        'HEIC decoding needs the bundled libheif, which was not found. '
        'Convert to JPEG first.',
      );
    }
    final api = Libheif._(lib);
    return api._decodeToImage(bytes);
  }

  img.Image _decodeToImage(Uint8List bytes) {
    final ctx = _alloc();
    try {
      final src = calloc<Uint8>(bytes.length);
      try {
        src.asTypedList(bytes.length).setAll(0, bytes);
        final err = _readMem(ctx, src, bytes.length, nullptr);
        _check(err, 'read');
      } finally {
        calloc.free(src);
      }
      final handlePtr = calloc<Pointer<Void>>();
      try {
        _check(_primary(ctx, handlePtr), 'primary image');
        final handle = handlePtr.value;
        try {
          final imgPtr = calloc<Pointer<Void>>();
          try {
            _check(
              _decode(handle, imgPtr, _colorspaceRgb, _chroma444, nullptr),
              'decode',
            );
            return _readRgb(imgPtr.value);
          } finally {
            calloc.free(imgPtr);
          }
        } finally {
          _handleRelease(handle);
        }
      } finally {
        calloc.free(handlePtr);
      }
    } finally {
      _free(ctx);
    }
  }

  img.Image _readRgb(Pointer<Void> image) {
    try {
      final w = _width(image, _chR);
      final h = _height(image, _chR);
      if (w <= 0 || h <= 0 || w > 20000 || h > 20000) {
        throw EngineError('libheif reported an absurd size ($w x $h).');
      }
      final out = img.Image(width: w, height: h, numChannels: 3);
      final planes = <int, Uint8List>{};
      final strides = <int, int>{};
      for (final ch in [_chR, _chG, _chB]) {
        final stridePtr = calloc<Int32>();
        try {
          final ptr = _plane(image, ch, stridePtr);
          if (ptr == nullptr) {
            throw EngineError('libheif returned no data for a colour plane.');
          }
          final stride = stridePtr.value;
          planes[ch] = ptr.asTypedList(stride * h);
          strides[ch] = stride;
        } finally {
          calloc.free(stridePtr);
        }
      }
      // Copy row by row; strides are only guaranteed >= width.
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          out.setPixelRgba(
            x,
            y,
            planes[_chR]![y * strides[_chR]! + x],
            planes[_chG]![y * strides[_chG]! + x],
            planes[_chB]![y * strides[_chB]! + x],
            255,
          );
        }
      }
      return out;
    } finally {
      _imageRelease(image);
    }
  }

  void _check(_HeifError err, String step) {
    if (err.code == 0) return;
    final detail = err.message == nullptr ? '' : ' ${err.message.toDartString()}';
    throw EngineError('libheif failed to $step the image (code ${err.code}).$detail');
  }
}
