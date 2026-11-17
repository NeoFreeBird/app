#!/usr/bin/env bash
set -euo pipefail

# Run the terminology regression tests on macOS with Apple command-line tools.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ "$(uname -s)" != Darwin ]] || ! command -v xcrun >/dev/null 2>&1; then
    echo "Error: these tests require macOS and Apple command-line tools (xcrun)." >&2
    exit 1
fi

TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nfb-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

xcrun --sdk macosx clang -fobjc-arc -fblocks -Isrc \
    -framework Foundation \
    tests/TerminologyTests.m src/Core/BHTTerminology.m \
    -o "$TEST_DIR/TerminologyTests"

"$TEST_DIR/TerminologyTests"
