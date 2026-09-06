#!/usr/bin/env bash
set -euo pipefail

# Uses the example's React Native host with framework Instrumentation; no JS is needed.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_DIR="${ANDROID_SDK_ROOT:-${ANDROID_HOME:?Set ANDROID_HOME or ANDROID_SDK_ROOT}}"
ADB="$SDK_DIR/platform-tools/adb"
SERIAL="${1:?Pass an emulator or device serial}"
BUILD_DIR="$(mktemp -d)"
ABI="$("$ADB" -s "$SERIAL" shell getprop ro.product.cpu.abi | tr -d '\r')"
export RNIP_ANDROID_TEST_SOURCE="$REPO_ROOT/tests/android/ui"

cat > "$BUILD_DIR/init.gradle" <<'GRADLE'
allprojects { project ->
    project.plugins.withId('com.android.application') {
        if (project.name == 'app') {
            project.android.defaultConfig {
                testInstrumentationRunner 'com.rninteractionprimitives.RNSideDrawerViewVerification'
                testApplicationId 'com.interactionprimitives.verification'
            }
            project.android.sourceSets.androidTest.java.srcDir(System.getenv('RNIP_ANDROID_TEST_SOURCE'))
            project.android.sourceSets.androidTest.manifest.srcFile(
                System.getenv('RNIP_ANDROID_TEST_SOURCE') + '/AndroidManifest.xml')
        }
    }
}
GRADLE

if ! (cd "$REPO_ROOT/examples/android" && ./gradlew :app:assembleDebug :app:assembleDebugAndroidTest \
    "-PreactNativeArchitectures=$ABI" -I "$BUILD_DIR/init.gradle" --console=plain) > "$BUILD_DIR/build.log" 2>&1; then
  cat "$BUILD_DIR/build.log"
  exit 1
fi

APP_OUTPUT="$REPO_ROOT/examples/android/app/build/outputs/apk"
"$ADB" -s "$SERIAL" install -r "$APP_OUTPUT/debug/app-debug.apk"
"$ADB" -s "$SERIAL" install -r "$APP_OUTPUT/androidTest/debug/app-debug-androidTest.apk"
"$ADB" -s "$SERIAL" shell am instrument -w \
  com.interactionprimitives.verification/com.rninteractionprimitives.RNSideDrawerViewVerification \
  > "$BUILD_DIR/results.txt"
cat "$BUILD_DIR/results.txt"
grep -q '^failures=0$' "$BUILD_DIR/results.txt"
