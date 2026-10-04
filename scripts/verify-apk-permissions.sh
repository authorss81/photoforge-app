#!/usr/bin/env bash
#
# Verify that a built APK requests no permissions at all.
#
# PixelForge's central claim is that it cannot upload your photos, and the
# mechanism behind that claim is the absence of android.permission.INTERNET from
# the manifest. A release APK that quietly gained a permission would make the
# README a lie, so this checks the built artifact rather than the source
# manifest: source and artifact can disagree, and only the artifact is what gets
# installed.
#
# Runnable by hand:
#   bash scripts/verify-apk-permissions.sh build/app/outputs/flutter-apk/app-release.apk
#
# Exits 0 when the APK declares no permissions, 1 otherwise, 2 when it cannot
# tell. Code 2 is deliberately distinct from 1: "could not check" must never read
# as "checked and fine".

set -euo pipefail

APK="${1:-}"

if [ -z "$APK" ]; then
  echo "usage: $0 <path-to.apk>" >&2
  exit 2
fi

if [ ! -f "$APK" ]; then
  echo "no such APK: $APK" >&2
  exit 2
fi

# Locate the newest aapt2. Version directories sort lexicographically, which is
# wrong for 9.0 vs 10.0, so sort by version.
find_aapt2() {
  local root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  if [ -z "$root" ]; then
    return 1
  fi
  local candidate
  for candidate in $(find "$root/build-tools" -maxdepth 2 -name 'aapt2' -type f 2>/dev/null | sort -V); do
    AAPT2="$candidate"
  done
  [ -n "${AAPT2:-}" ]
}

if ! find_aapt2; then
  echo "could not find aapt2 under \$ANDROID_HOME/build-tools" >&2
  echo "set ANDROID_HOME, or run this where the Android SDK is installed" >&2
  exit 2
fi

echo "using $AAPT2"
echo "checking $APK"
echo

# aapt2 prints "uses-permission: name='android.permission.X'" lines for every
# permission. dump badging is used rather than dump permissions because badging
# is stable across build-tools versions for this purpose.
DUMP="$("$AAPT2" dump permissions "$APK" 2>/dev/null || true)"

if [ -z "$DUMP" ]; then
  echo "could not read permissions from the APK" >&2
  exit 2
fi

echo "--- permissions declared ---"
echo "$DUMP"
echo

# Collect just the permission names.
PERMS="$(echo "$DUMP" | sed -n "s/.*name='\([^']*\)'.*/\1/p" | sort -u)"

if [ -z "$PERMS" ]; then
  echo "PASS: the APK declares no permissions at all."
  echo
  echo "This is the product's central claim, verified against the built"
  echo "artifact rather than the source manifest."
  exit 0
fi

echo "FAIL: the APK declares permissions:" >&2
echo "$PERMS" | sed 's/^/  - /' >&2
echo >&2
echo "PixelForge must ship with zero permissions. INTERNET in particular means" >&2
echo "the installed app can open a socket, which breaks the offline guarantee." >&2
exit 1