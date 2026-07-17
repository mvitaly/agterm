#!/usr/bin/env bash
# Build the debug app and launch it.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/setup.sh
xcodegen generate
# AGTERM_ARCHS optionally overrides the target architectures (project.yml pins
# arm64), e.g. AGTERM_ARCHS=x86_64 for an Intel-only build on/for an Intel Mac.
xcodebuild -project agterm.xcodeproj -scheme agterm -configuration Debug \
  -derivedDataPath build/DerivedData ${AGTERM_ARCHS:+ARCHS="$AGTERM_ARCHS"} build
open build/DerivedData/Build/Products/Debug/agterm.app
