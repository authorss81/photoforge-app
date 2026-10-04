# Background processing

## What it does

When a batch is worth keeping alive (more than a couple of files, or over
10 MB in), Android runs a foreground service while Dart isolates process. The
service does no work itself. It exists for two reasons:

1. Android kills backgrounded processes aggressively. A foreground service
   with a visible notification is the only reliable way to survive a batch
   measured in minutes.
2. The notification shows live progress with a cancel action.

The notification's cancel action reopens the app with a cancel extra, which
`MainActivity` forwards to Dart. A broadcast receiver cannot reach the Flutter
engine cleanly, so the activity round-trip is the mechanism, not a shortcut.

## Permissions

One: `FOREGROUND_SERVICE_DATA_SYNC`. It is a normal install-time permission
that grants no data access. It exists only because Android 14+ requires a
declared service type. `test/privacy_test.dart` allowlists exactly this one
permission; anything else fails the suite.

No notification permission is requested. Foreground-service notifications are
system-mandated and shown even when the user denies notification permission,
so there is nothing to ask for.

## Limits, stated plainly

- If the user swipes the app away *and* Android is under memory pressure, the
  process can still die. The service makes that rare, not impossible.
- The service never starts for trivial batches. A single quick image does not
  need a keep-alive and does not get one.
- Cancelling stops dispatch immediately. Workers already running finish their
  current image first, because an isolate cannot be interrupted mid-encode.
  Their results still land.
- iOS has no equivalent here. The bundle identifier
  `dev.pixelforge.pixelforge.batch` is registered in `Info.plist`, which is
  the required groundwork, but real background execution needs a headless
  engine and is future work. The app never claims otherwise: `BackgroundService`
  reports unsupported on iOS and the UI offers nothing.
