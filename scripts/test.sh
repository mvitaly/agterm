#!/usr/bin/env bash
# Run the host-free agtCore unit tests (no Xcode, no libghostty, no Metal).
set -euo pipefail
cd "$(dirname "$0")/../agtCore"
swift test
