import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'error.dart';

/// Minimal uncompressed 16-bit TIFF writer, little-endian.
///
/// `package:image` decodes 16-bit TIFF correctly but its encoder funnels every
/// image through `toUint8List`, which truncates to 8 bits. Rather than
/// silently truncate a photographer's file, the pipeline routes uint16 output
/// here. Anything this writer cannot represent fails loudly in
/// [EngineError], which is what the UI already displays.
Uint8List encodeTiff16(img.Image image) {
  if (image.hasPalette) {
    throw EngineError(
      'Cannot write a paletted 16-bit TIFF. Convert to direct colour first.',
    );
  }
  if (image.format != img.Format.uint16) {
    throw EngineError(
      'encodeTiff16 needs a uint16 image, got ${image.format.name}.',
    );
  }
  final channels = image.numChannels;
  if (channels != 3 && channels != 4) {
    throw EngineError(
      'Cannot write a 16-bit TIFF with $channels channels; RGB or RGBA only.',
    );
  }

  final w = image.width;
  final h = image.height;
  final pixelBytes = _pixelBytes(image, w, h, channels);

  // Layout, all little-endian:
  //   header (8) | IFD (2 + 11*12 + 4) | BitsPerSample (2*nc) |
  //   SampleFormat (2*nc) | pixels
  const entries = 11;
  const ifdSize = 2 + entries * 12 + 4;
  final bpsOffset = 8 + ifdSize;
  final sfOffset = bpsOffset + 2 * channels;
  final dataOffset = sfOffset + 2 * channels;
  final total = dataOffset + pixelBytes.length;

  final out = ByteData(total);
  void u16(int at, int v) => out.setUint16(at, v, Endian.little);
  void u32(int at, int v) => out.setUint32(at, v, Endian.little);

  // Header: little-endian, magic 42, first IFD at 8.
  out.setUint8(0, 0x49);
  out.setUint8(1, 0x49);
  u16(2, 42);
  u32(4, 8);

  var at = 8;
  u16(at, entries);
  at += 2;

  void entry(int tag, int type, int count, int value) {
    u16(at, tag);
    u16(at + 2, type);
    u32(at + 4, count);
    u32(at + 8, value);
    at += 12;
  }

  entry(256, 4, 1, w); // ImageWidth, LONG
  entry(257, 4, 1, h); // ImageLength, LONG
  entry(258, 3, channels, bpsOffset); // BitsPerSample, SHORT
  entry(259, 3, 1, 1); // Compression = none
  entry(262, 3, 1, 2); // Photometric = RGB
  entry(273, 4, 1, dataOffset); // StripOffsets, LONG
  entry(277, 3, 1, channels); // SamplesPerPixel, SHORT
  entry(278, 4, 1, h); // RowsPerStrip, LONG
  entry(279, 4, 1, pixelBytes.length); // StripByteCounts, LONG
  entry(284, 3, 1, 1); // PlanarConfiguration = chunky
  entry(339, 3, channels, sfOffset); // SampleFormat = uint
  u32(at, 0); // no next IFD

  for (var c = 0; c < channels; c++) {
    u16(bpsOffset + 2 * c, 16);
    u16(sfOffset + 2 * c, 1);
  }

  out.buffer.asUint8List().setRange(dataOffset, total, pixelBytes);
  return out.buffer.asUint8List();
}

/// Raw 16-bit pixel bytes in RGB(A) order. Uses the image buffer directly when
/// it is tightly packed, which it is for every image this pipeline produces.
Uint8List _pixelBytes(img.Image image, int w, int h, int channels) {
  final tight = w * h * channels * 2;
  final buf = image.buffer;
  if (Endian.host == Endian.little && buf.lengthInBytes == tight) {
    return buf.asUint8List();
  }
  final out = ByteData(tight);
  var o = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = image.getPixel(x, y);
      out.setUint16(o, p.r.toInt().clamp(0, 65535), Endian.little);
      o += 2;
      out.setUint16(o, p.g.toInt().clamp(0, 65535), Endian.little);
      o += 2;
      out.setUint16(o, p.b.toInt().clamp(0, 65535), Endian.little);
      o += 2;
      if (channels == 4) {
        out.setUint16(o, p.a.toInt().clamp(0, 65535), Endian.little);
        o += 2;
      }
    }
  }
  return out.buffer.asUint8List();
}
