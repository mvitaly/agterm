#!/usr/bin/env bash
# Build the debug app and launch it.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/setup.sh
xcodegen generate
xcodebuild -project agt.xcodeproj -scheme agt -configuration Debug \
  -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/agt.app
