#!/usr/bin/env bash
# Run the application-hosted AppKit unit tests with scheme launch isolation.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/setup.sh
xcodegen generate
# AGTERM_ARCHS optionally narrows the target architectures, e.g.
# AGTERM_ARCHS=x86_64 for an Intel-only run. Needed because project.yml
# advertises the standard (universal) set while setup.sh stages a native-only
# GhosttyKit, so the other slice has nothing to link against.
#
# AGTERM_TEST_SKIP optionally omits tests that cannot pass in the caller's
# environment, space separated, e.g.
# AGTERM_TEST_SKIP="agtermTests/SomeTests/testSomething". The caller owns the
# reason for each entry; nothing is skipped by default.
SKIP_ARGS=()
for test_id in ${AGTERM_TEST_SKIP:-}; do SKIP_ARGS+=(-skip-testing:"$test_id"); done
xcodebuild test \
  -project agterm.xcodeproj \
  -scheme agtermTests \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  ${SKIP_ARGS[@]+"${SKIP_ARGS[@]}"} \
  ${AGTERM_ARCHS:+ARCHS="$AGTERM_ARCHS"}
