#!/usr/bin/env bash
# Build a release app.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/setup.sh
xcodegen generate
xcodebuild -project agt.xcodeproj -scheme agt -configuration Release \
  -derivedDataPath build/DerivedData build
echo "built: build/DerivedData/Build/Products/Release/agt.app"
