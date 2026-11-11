#!/bin/bash
# Native appearance must be set on the simulator; AppleInterfaceStyle launch arguments do not do it.
set -euo pipefail
cd "$(dirname "$0")/.."
simulator="${1:?Usage: scripts/test-release-controls.sh <simulator-udid> [derived-data-path]}"
derived="${2:-$PWD/build/release-controls/DerivedData}"
original=$(xcrun simctl ui "$simulator" appearance)
trap 'xcrun simctl ui "$simulator" appearance "$original"' EXIT
xcrun simctl ui "$simulator" appearance light
xcodebuild test -project PoliVerse.xcodeproj -scheme PoliVerseUI \
  -destination "platform=iOS Simulator,id=$simulator" -derivedDataPath "$derived" \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:PoliVerseUITests/ReleaseControlsUITests/testHistoryAndBetaRoundTrip \
  -only-testing:PoliVerseUITests/ReleaseControlsUITests/testHistoryAndBetaAtLargeText
xcrun simctl ui "$simulator" appearance dark
xcodebuild test-without-building -project PoliVerse.xcodeproj -scheme PoliVerseUI \
  -destination "platform=iOS Simulator,id=$simulator" -derivedDataPath "$derived" \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:PoliVerseUITests/ReleaseControlsUITests/testHistoryAndBetaInDarkMode
