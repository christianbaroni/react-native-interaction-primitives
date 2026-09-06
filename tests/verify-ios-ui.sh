#!/usr/bin/env bash
set -euo pipefail

# Requires a booted iOS simulator; pass its UDID when more than one is booted.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="${RNIP_IOS_SOURCE_DIR:-$REPO_ROOT/ios}"
BUILD_DIR="$(mktemp -d)"
SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
SIMULATOR="${1:-booted}"
SIMULATOR_ARCH="$(uname -m)"

xcrun --sdk iphonesimulator clang++ \
  -target "$SIMULATOR_ARCH-apple-ios15.1-simulator" \
  -isysroot "$SDK_PATH" \
  -std=c++20 -fobjc-arc -Wall -Wextra -Werror \
  -I"$REPO_ROOT/tests/ios/react-stubs" -I"$SOURCE_DIR" \
  "$REPO_ROOT/tests/ios/RNSideDrawerViewVerification.mm" \
  "$SOURCE_DIR/RNSideDrawerView.mm" \
  "$SOURCE_DIR/RNSideDrawerContentView.mm" \
  "$SOURCE_DIR/RNSideDrawerPanelView.mm" \
  "$SOURCE_DIR/RNSideDrawerGestureScrollView.mm" \
  "$SOURCE_DIR/RNSideDrawerInteraction.mm" \
  "$SOURCE_DIR/RNSideDrawerMotion.mm" \
  "$SOURCE_DIR/RNInteractionHapticFeedback.mm" \
  -framework UIKit -framework Foundation -framework QuartzCore -framework CoreGraphics \
  -o "$BUILD_DIR/side-drawer-ui-verification"

xcrun simctl spawn "$SIMULATOR" "$BUILD_DIR/side-drawer-ui-verification"
