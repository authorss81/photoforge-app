# Testing

PixelForge is tested in layers, and each layer has blind spots. This document
records what each one covers and, more importantly, what it cannot catch, so a
green suite is not mistaken for more assurance than it gives.

## The layers

| Layer | Command | Runs on | Cost |
|---|---|---|---|
| Unit and widget | `flutter test` | every platform | ~40s |
| Golden | `flutter test test_golden/` | Linux only | ~5s |
| Smoke | `flutter test integration_test/app_test.dart` | emulator, CI | ~10min |
| Build | `flutter build apk / windows / ios` | CI | ~5min |

## Unit and widget tests

`flutter test` covers the pipeline, the settings model, the controllers and the
widgets. This is where almost everything lives.

**Cannot catch:** anything requiring the real platform. Widget tests never launch
the OS, so a plugin that fails to register, an app that crashes on startup, or a
platform channel with the wrong name all pass here. That gap is what the smoke
test exists for.

## Golden image tests

`test_golden/`, verified by the `golden` CI job. Catches layout regressions:
spacing, alignment, overflow, and whether content appears in the right place at
a given width.

**Cannot catch:**

- **Text.** Flutter's test font draws every glyph as a filled box, so a changed
  string renders identically to an unchanged one. String changes are asserted
  with `find.text` instead.
- **Anything off Linux.** Font rasterization differs per OS, so goldens are
  generated and verified on Linux only. See `docs/GOLDENS.md`.

## Smoke test

`integration_test/app_test.dart`, run by the `smoke` CI job on an emulator. This
is the only automated check that the app actually launches, and it asserts
output *dimensions* rather than merely that nothing crashed.

**Cannot catch:** behaviour that only shows on a physical device, such as camera
quality, real GPU drivers, or battery impact.

The job is deliberately configured with KVM and hardware acceleration. Without
them the emulator is slow enough that the job gets disabled, and a disabled
smoke test is worse than none because it still looks like coverage.

## Privacy invariants

`test/privacy_test.dart` is load-bearing and must never be loosened. It asserts:

- the release manifest requests no permission except
  `FOREGROUND_SERVICE_DATA_SYNC`
- iOS carries no network entitlement
- no networking package appears as a direct dependency

The `android` CI job independently dumps the built APK's permission list and
fails on `INTERNET`, so the claim is checked against the artifact and not only
against the source.

## Native syntax check

`scripts/check_native_syntax.py` verifies brace balance across the Kotlin and
Swift sources, and rejects a duplicate Kotlin `companion object`. Neither
language can be compiled without the Android toolchain or Xcode, and a stray
brace in either file once survived nine phases because only CI could see it.

**Cannot catch:** type errors, missing symbols, or anything requiring a real
compiler. It is a syntax gate, not a build. The `android` and `ios` jobs remain
the real check.

## Before you push

```bash
flutter analyze                                       # must be clean, warnings included
dart format --output=none --set-exit-if-changed lib test test_golden integration_test
flutter test                                          # must be all green
python scripts/check_native_syntax.py                 # if you touched Kotlin or Swift
```

## Things a green suite will not tell you

- That the app looks right. Only a human, or a human-inspected golden, can say.
- That a test asserts what you meant. A test that passes for the wrong reason is
  worse than no test, because it looks like coverage.
- That a new platform still builds. Only CI builds it.
- That the model you added is licensed for redistribution. That is a legal
  question, not a testing one, and no test can answer it.