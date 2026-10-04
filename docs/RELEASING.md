# Releasing

A release turns a tag into a draft GitHub release with installable artifacts
attached. **Nothing is ever published automatically.** Publishing is a human
decision, made after someone has checked the artifacts.

## Why drafts

Publishing is irreversible in one direction. Once a version is out and users
install it, that version can never be replaced. So the workflow stops at a draft
and a human promotes it.

## Versioning

`pubspec.yaml` currently declares:

```
version: 1.0.0+1
```

**Proposed: `version: 1.0.0+24`.** Twenty-three phases have landed and the
build number is still 1, so every build since the first has been
indistinguishable from every other. A release that claims 1.0.0 forever is not a
version, it is a placeholder.

The bump is deliberately not applied by this phase. Choosing the number is a
product decision:

- `1.0.0` is defensible if you consider the feature set complete. It is.
- `0.9.0` is more honest if you expect the face detection and PDF work to
  change the app's shape.

Bump the number in `pubspec.yaml` before tagging. The release workflow reads the
version from the tag, not from `pubspec.yaml`, so the two cannot disagree, but
the app's own About screen will show whatever is declared.

## How to release

### 1. Make sure main is green

```bash
git checkout main
git pull
flutter analyze
flutter test
```

Then check the Actions tab: `verify`, `golden`, `android`, `windows`, `ios` and
`benchmark` must all be green.

### 2. Bump the version

```bash
# edit pubspec.yaml: version: 1.0.0+24
```

Commit that on its own, so the version bump is visible in the history
separately from the release itself.

### 3. Tag

```bash
git tag -a v1.0.0 -m "PixelForge 1.0.0"
git push origin v1.0.0
```

The tag must parse as `vMAJOR.MINOR.PATCH`. `v1.2`, `v1.2.3.4` and `latest` all
fail the workflow rather than producing an artifact with a guessed version. That
strictness is deliberate: the artifact gets installed by people.

Pushing a tag is the only irreversible step. Everything after it produces a
draft.

### 4. Wait, then check the draft

The `release` workflow builds and attaches:

| Artifact | Contents |
|---|---|
| `pixelforge-<version>-universal.apk` | One APK for every Android device |
| `pixelforge-<version>-armv7.apk` | 32-bit ARM |
| `pixelforge-<version>-arm64.apk` | 64-bit ARM, most modern phones |
| `pixelforge-<version>-x64.apk` | x86-64, emulators and Chromebooks |
| `pixelforge-<version>.aab` | Play Store upload bundle |
| `pixelforge-<version>-windows-x64.zip` | Windows desktop, zipped |

Then check the draft release at
`https://github.com/authorss81/photoforge-app/releases`.

### 5. Check the artifacts yourself

Do not trust the green ticks. The release body has a checklist; work through it:

- [ ] The universal APK installs on a real phone and opens an image.
- [ ] The Windows zip runs on a clean Windows machine.
- [ ] The signature is the real release key, not the throwaway CI key.
- [ ] `versionName` in the APK matches the tag.

### 6. Publish

Only after the checks pass. Edit the draft release and click publish.

## What CI verifies, and what it does not

**Verified in CI, against the built artifact:**

- The APK declares **no permissions at all**. `scripts/verify-apk-permissions.sh`
  runs `aapt2 dump permissions` and fails on anything. This is the offline claim
  checked against what actually ships, not against the source manifest, because
  source and artifact can disagree.
- The APK's `versionName` equals the tag.
- The Windows zip contains `pixelforge.exe` and at least one DLL. A build step
  exiting zero does not mean the zip is runnable.

**Not verified by CI:**

- That the app works when installed. Only the `smoke` job on an emulator comes
  close, and that runs the debug build.
- That the signature is correct. If `RELEASE_KEYSTORE_B64` is unset, CI
  generates a throwaway key and says so in the log. **A release built that way
  must not be published**, because a debug-signed or throwaway-signed APK cannot
  be updated in place later and the Play Store rejects it.
- Anything about iOS. See below.

## Signing

Signing is wired to three secrets:

| Secret | Meaning |
|---|---|
| `RELEASE_KEYSTORE_B64` | The keystore file, base64 encoded |
| `KEYSTORE_PASSWORD` | Its store password |
| `KEY_ALIAS` | The key alias |
| `KEY_PASSWORD` | The key password |

Create the keystore with:

```bash
keytool -genkeypair -v -keystore release.keystore \
  -alias pixelforge -keyalg RSA -keysize 4096 -validity 10000
base64 -w0 release.keystore
```

Paste that into the `RELEASE_KEYSTORE_B64` secret. See `docs/SIGNING.md`.

**Back up the keystore somewhere safe and keep it.** Lose it and you cannot
update your app on the Play Store, ever. Lose the password and the same.

## Checking a downloaded APK yourself

You do not need CI to check permissions. With the Android SDK on `PATH`:

```bash
bash scripts/verify-apk-permissions.sh ~/Downloads/pixelforge-1.0.0-universal.apk
```

It prints the permission list and exits:

| Code | Meaning |
|---|---|
| 0 | No permissions declared. Correct. |
| 1 | Permissions found. The offline claim is broken. |
| 2 | Could not check, no APK or no `aapt2`. |

Code 2 is deliberately distinct from 0. "Could not check" must never read as
"checked and fine".

Or by hand:

```bash
AAPT2="$(find "$ANDROID_HOME/build-tools" -maxdepth 2 -name aapt2 | sort -V | tail -1)"
"$AAPT2" dump permissions app-release.apk
```

A correct release prints nothing under `uses-permission`.

## iOS

Not built. An IPA needs a macOS runner, an Apple Developer account and a
provisioning profile, and none of that can be faked. The iOS source builds in
the `ios` CI job with `--no-codesign`, which proves it compiles but produces
nothing installable.

Treat iOS as future work.