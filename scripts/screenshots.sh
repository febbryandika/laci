#!/usr/bin/env bash
# Records every screen in id, en and ja at the default and AX5 text sizes on both device families
# (SPEC §9 verification). Output lands in fastlane/screenshots/<idiom>/, which is gitignored.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${LACI_SCREENSHOT_DIR:-$ROOT/fastlane/screenshots}"
rm -rf "$OUT"
mkdir -p "$OUT"

for DEVICE in "iPhone 17" "iPad Pro 11-inch (M5)"; do
  DESTINATION="platform=iOS Simulator,name=$DEVICE,OS=26.5"
  xcodebuild build-for-testing \
    -project "$ROOT/Laci.xcodeproj" -scheme Laci \
    -destination "$DESTINATION" \
    -derivedDataPath "$ROOT/DerivedData" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -quiet
  TEST_RUNNER_LACI_SCREENSHOTS=1 TEST_RUNNER_LACI_SCREENSHOT_DIR="$OUT" \
  xcodebuild test-without-building \
    -project "$ROOT/Laci.xcodeproj" -scheme Laci \
    -destination "$DESTINATION" \
    -derivedDataPath "$ROOT/DerivedData" \
    -only-testing:LaciUITests/ScreenshotTests \
    -parallel-testing-enabled NO -quiet
done

find "$OUT" -name '*.png' | sort
