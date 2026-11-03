#!/bin/bash
# Run the opt-in, on-device benchmark. Other iOS-only tests aren't portable to Mac.
set -euo pipefail
cd "$(dirname "$0")/.."
verification_destination="${1:-platform=macOS}"
verification_results="$(mktemp -d "${TMPDIR:-/tmp}/poliverse-evaluations.XXXXXX")/Evaluation.xcresult"
verification_args=(-resultBundlePath "$verification_results" -project PoliVerse.xcodeproj -scheme PoliVerseNoticeEvaluations -destination "$verification_destination" test)
if [[ "$verification_destination" == platform=macOS* ]]; then
    verification_excluded=$(rg --files PoliVerseTests -g '*.swift' -g '!NoticeSummaryEvaluation.swift' -g '!NoticeSummarySamples.swift' | sed 's|.*/||' | tr '\n' ' ')
    verification_args+=(SDKROOT=macosx SUPPORTED_PLATFORMS=macosx 'TEST_HOST=$(BUILT_PRODUCTS_DIR)/PoliVerse.app/Contents/MacOS/PoliVerse' "EXCLUDED_SOURCE_FILE_NAMES=$verification_excluded")
fi
TEST_RUNNER_RUN_NOTICE_EVALUATIONS=1 xcodebuild "${verification_args[@]}"

xcrun xcresulttool get test-results tests --path "$verification_results" --compact | python3 -c '
import json, sys

def walk(node):
    if isinstance(node, dict):
        if node.get("nodeIdentifier") == "NoticeSummaryTests/quality()":
            yield node
        for child in node.values():
            yield from walk(child)
    elif isinstance(node, list):
        for child in node:
            yield from walk(child)

nodes = list(walk(json.load(sys.stdin)))
if len(nodes) != 1 or nodes[0].get("result") != "Passed":
    raise SystemExit("La valutazione non risulta eseguita e superata; controllare il bundle dei risultati.")
'
