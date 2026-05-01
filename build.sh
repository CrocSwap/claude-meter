#!/usr/bin/env bash
# Build and launch claude-meter. Used by the README quickstart; safe to re-run.
set -euo pipefail

cd "$(dirname "$0")"

xcodebuild -project ClaudeMeter/ClaudeMeter.xcodeproj \
           -scheme ClaudeMeter \
           -configuration Release \
           -derivedDataPath build \
           build

open build/Build/Products/Release/ClaudeMeter.app
