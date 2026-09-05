#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT
CXX_BIN="${CXX:-c++}"
JAVA_BIN="${JAVA:-java}"

KOTLINC_BIN="${KOTLINC:-}"
if [[ -z "$KOTLINC_BIN" ]]; then
  KOTLINC_BIN="$(command -v kotlinc || true)"
fi
if [[ -z "$KOTLINC_BIN" && -x "/Applications/Android Studio.app/Contents/plugins/Kotlin/kotlinc/bin/kotlinc" ]]; then
  KOTLINC_BIN="/Applications/Android Studio.app/Contents/plugins/Kotlin/kotlinc/bin/kotlinc"
fi
if [[ -z "$KOTLINC_BIN" ]]; then
  echo "Kotlin compiler not found; set KOTLINC to a kotlinc executable." >&2
  exit 127
fi

"$CXX_BIN" \
  -std=c++17 \
  -Wall \
  -Wextra \
  -Werror \
  -I"$REPO_ROOT/tests/stubs" \
  -I"$REPO_ROOT/ios" \
  -x c++ \
  "$REPO_ROOT/ios/RNSideDrawerInteraction.mm" \
  "$REPO_ROOT/tests/ios/RNSideDrawerInteractionVerification.cpp" \
  -o "$BUILD_DIR/ios-side-drawer-verification"
"$BUILD_DIR/ios-side-drawer-verification"

"$KOTLINC_BIN" \
  "$REPO_ROOT/android/src/main/java/com/rninteractionprimitives/RNSideDrawerInteraction.kt" \
  "$REPO_ROOT/tests/android/RNSideDrawerInteractionVerification.kt" \
  -Werror \
  -include-runtime \
  -d "$BUILD_DIR/android-side-drawer-verification.jar"
"$JAVA_BIN" -jar "$BUILD_DIR/android-side-drawer-verification.jar"
