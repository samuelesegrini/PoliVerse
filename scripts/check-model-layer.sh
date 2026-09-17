#!/usr/bin/env bash
# Checks the three rules of docs/data-layer-architecture.md against the tree.
#
# Rules 1 and 3 are enforced: any violation fails.
# Rule 2 — "an area names no other area" — is not something this code can
# satisfy today: every area names between two and seven others. Demanding it
# would mean a rewrite, not a move. So it is a ratchet instead: the number of
# cross-area edges is recorded, and the check fails only if it grows. The
# direction of travel is enforced; the current state is not pretended away.
#
# Runs anywhere bash and grep run — no Xcode, no Swift toolchain.
set -uo pipefail
cd "$(dirname "$0")/.."

MODEL="PoliVerse/Model"
BASELINE_FILE="scripts/model-layer-baseline.txt"
status=0

# Type names an area owns, as an alternation for grep.
types_of() {
    ls "$MODEL/$1"/*.swift 2>/dev/null | xargs -n1 basename | sed 's/\.swift$//' | paste -sd'|' -
}

# Does $1 (a folder) reference any of the types in $2 (an alternation) outside
# comments? Doc comments naming a type are prose, not a dependency.
references() {
    grep -rhE "\b($2)\b" "$1" 2>/dev/null | grep -vE '^\s*(///|//|\*)' | grep -qE "\b($2)\b"
}

areas=$(ls "$MODEL" | grep -vE '^(Support|Mock)$')

echo "== Rule 1: Support/ names no area =="
for a in $areas; do
    types=$(types_of "$a")
    for f in "$MODEL"/Support/*.swift; do
        if grep -E "\b($types)\b" "$f" | grep -qvE '^\s*(///|//|\*)'; then
            echo "  FAIL  $(basename "$f") names $a"
            status=1
        fi
    done
done
[ $status -eq 0 ] && echo "  ok"

echo "== Rule 3: nothing under Model/ imports SwiftUI =="
if grep -rl '^import SwiftUI' "$MODEL" 2>/dev/null | grep .; then
    echo "  FAIL  the model layer is not a view layer"
    status=1
else
    echo "  ok"
fi

echo "== Rule 2 (ratchet): edges between areas =="
edges=0
for a in $areas; do
    for o in $areas; do
        [ "$a" = "$o" ] && continue
        references "$MODEL/$a" "$(types_of "$o")" && edges=$((edges + 1))
    done
done
baseline=$(grep -oE "^[0-9]+" "$BASELINE_FILE" 2>/dev/null | head -1)
[ -z "$baseline" ] && baseline=$edges
echo "  $edges edges (baseline $baseline)"
if [ "$edges" -gt "$baseline" ]; then
    echo "  FAIL  the areas got more tangled, not less"
    echo "        if this is deliberate, update $BASELINE_FILE and say why"
    status=1
elif [ "$edges" -lt "$baseline" ]; then
    echo "  the ratchet moved: write $edges into $BASELINE_FILE"
fi

exit $status
