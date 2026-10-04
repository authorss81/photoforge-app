# HEIC, HEIF and AVIF support

## Where each platform decodes

| Platform | Decoder | Needs anything installed |
|---|---|---|
| Android 9+ | `ImageDecoder` via method channel | No |
| iOS | `ImageIO` via method channel | No |
| Windows | Bundled libheif under `windows/libheif`, loaded from next to the exe | No |
| Linux | System `libheif.so.1`, loaded if present | `libheif1` package |
| Web | Nothing available | Convert to JPEG first |
| Android 8 and below | Nothing available | Convert to JPEG first |

Every path fails closed with a message naming what is missing. There is no
silent fallback and no corrupt output.

## The bundled Windows libraries

`windows/libheif` holds libheif plus the decoders it needs (libde265 for HEVC,
libx265, and MinGW runtimes), extracted from the `pillow-heif` wheel, which
redistributes tested builds. They are installed next to `pixelforge.exe` by
`windows/CMakeLists.txt` and loaded only from there, never from PATH and never
assumed present on the system.

### Licence and your rights

libheif, libde265 and x265 are **LGPL**-licensed. They are linked dynamically
as separate DLLs, which is exactly what the LGPL requires for proprietary or
differently-licensed apps to use them:

- You may replace any of these DLLs with your own build. The app loads
  whatever `libheif*.dll` it finds next to the executable; it does not check
  versions or signatures.
- The corresponding source for the bundled versions is at
  https://github.com/strukturag/libheif (libheif),
  https://github.com/strukturag/libde265 (libde265) and
  https://bitbucket.org/multicoreware/x265_git (x265).
- This app's own code remains MIT. Only the DLLs are LGPL, and only the terms
  above apply to them.

## For developers

- FFI bindings: `lib/core/native/libheif_desktop.dart`. Only the decode path
  is bound. Planar RGB output is requested deliberately to avoid guessing at
  interleaved enum values.
- `Libheif.load()` returns null when the library is absent. That is a normal
  state. `Libheif.decode()` throws `EngineError` naming libheif.
- Tests use real `.heic` fixtures in `test/fixtures/`, generated with
  pillow-heif. On CI the Windows job sets PATH so the test exercises the real
  FFI decode; everywhere else it asserts the fallback message.
