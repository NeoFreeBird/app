#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ "$(uname -s)" != Darwin ]] || ! command -v xcrun >/dev/null 2>&1; then
    echo "Error: these tests require macOS and Apple command-line tools (xcrun)." >&2
    exit 1
fi

strings_failed=0
while IFS= read -r -d '' strings_file; do
    if ! plutil -lint -s -- "$strings_file"; then
        strings_failed=1
    fi
done < <(find layout -type f -name '*.strings' -print0)

if [[ "$strings_failed" -ne 0 ]]; then
    echo "Error: localization syntax checks failed." >&2
    exit 1
fi
echo "All localization syntax checks passed."

TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nfb-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

xcrun --sdk macosx clang -fobjc-arc -fblocks -Isrc \
    -framework Foundation \
    tests/TerminologyTests.m src/Core/BHTTerminology.m \
    -o "$TEST_DIR/TerminologyTests"

"$TEST_DIR/TerminologyTests"
