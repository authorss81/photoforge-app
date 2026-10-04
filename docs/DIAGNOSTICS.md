# Diagnostics

PixelForge has no telemetry. It has no crash reporter, no analytics, no
counters, and no network code at all — the release APK requests no
`INTERNET` permission, which is enforced by `test/privacy_test.dart` and by the
`android` CI job inspecting the built APK.

What it has instead is a crash log written to a file on your device, which you
can read, copy and delete. You decide whether to share it. Nothing is uploaded
by the app.

Open it from the bug icon in the top right.

## What is recorded

- The error and, where available, a trimmed stack trace.
- A UTC timestamp.
- A category: `framework error` or `async error`.

## What is never recorded

- Image data. No pixels, no thumbnails, no encoded bytes.
- File names or paths. Stripped before anything is written.
- URLs, including their query strings.
- Anything outside the app's own support directory.

Every entry passes through a redaction pass before it reaches the file. The
rules are declared as data in `lib/core/diagnostics/crash_log.dart` so the code
that strips them and the test that asserts they are stripped cannot drift
apart. `test/crash_log_test.dart` feeds each pattern through the real writer
and asserts the sensitive fragments are absent from the bytes on disk.

This matters more than it might seem. The product's central claim is that your
photos cannot leave your device, and a crash log full of filenames would
undermine that claim even though the file never left the device. So filenames,
paths and URLs are removed, and long opaque strings are replaced with
`<hash>` while the surrounding text is kept, because a log nobody can read is
not a diagnostic tool.

## Where it lives

The app's private support directory, under `diagnostics/`. App-private means
other apps cannot read it without a permission this app does not request.

## Rotation

| Setting | Default | Meaning |
|---|---|---|
| Max size per file | 256 KB | The live file is rotated before it would exceed this |
| Files kept | 3 | The live file plus two rotations |

Total usage is bounded at roughly 768 KB. A crash loop cannot fill your disk.

Rotation happens *before* the append, not after, so the newest crash always
lands in the live file rather than being renamed into a rotated one the moment
it is written. A retention of zero is treated as one, because discarding the
crash that just happened would defeat the purpose of having a log.

## Sharing

The share action copies the log as JSON to the clipboard. It deliberately does
not use a share sheet: a share plugin can send a file anywhere, which is
exactly the capability this app refuses to take on. Pasting into somewhere you
chose is a deliberate act.

The copied text is redacted identically to the file, so sharing it does not
reveal more than reading it does.

## Clearing

The clear button asks first, then deletes every log file. There is no undo and
no backup; if you want the contents, copy them first.

## Known limits

- No symbolication. The log shows Dart stack frames, not resolved names.
- No automatic upload, by design.
- If the disk is full or the directory is not writable, entries are dropped
  silently. A logging failure must never take the app down with it, which means
  it also cannot report itself.