#!/bin/zsh
# Throwaway feature-tour prototypes. All examples run on the dedicated UI simulator.
set -eu
cd "${0:A:h:h}"
chapter=${1:-day}
topic=${2:-0}
case "$chapter" in day) step=intents ;; study) step=preview ;; *) print -u2 'Choose day or study'; exit 1 ;; esac
case "$topic" in 0|1|2) ;; *) print -u2 'Choose topic 0, 1 or 2'; exit 1 ;; esac
device=${POLIVERSE_PREVIEW_DEVICE:-64F5472E-4A6F-4256-8E05-ABE1A60B3872}
build=/tmp/PoliVerse-linking-build
xcrun simctl boot "$device" 2>/dev/null || true
xcodebuild build -project PoliVerse.xcodeproj -scheme PoliVerseUI \
  -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$build" \
  > /tmp/poliverse-features-prototype-build.log 2>&1
xcrun simctl install "$device" "$build/Build/Products/Debug-iphonesimulator/PoliVerse.app"
open -a Simulator --args -CurrentDeviceUDID "$device"
xcrun simctl launch --terminate-running-process "$device" segrini.samuele.PoliVerse \
  -useMockData '<true/>' -hasCompletedOnboarding '<false/>' \
  -PreviewOnboarding "$step" -PrototypeFeatures Illustrated -PrototypeTopic "$topic" -AppleLanguages '(it)' -AppleLocale it_IT
print "Illustrated prototype / $chapter. Browse topics or pause the animation on screen."
