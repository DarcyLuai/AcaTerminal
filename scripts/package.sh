#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh "${1:-}"
./scripts/build-icon.sh
DIST_DIR="${ACA_DIST_DIR:-dist}"
mkdir -p "$DIST_DIR/AcaTerminal.app/Contents/MacOS" "$DIST_DIR/AcaTerminal.app/Contents/Resources"
cp "${ACA_BUILD_DIR:-.build-local}/AcaTerminal" "$DIST_DIR/AcaTerminal.app/Contents/MacOS/"
cp Resources/Info.plist "$DIST_DIR/AcaTerminal.app/Contents/"
cp "${ACA_BUILD_DIR:-.build-local}/AppIcon.icns" "$DIST_DIR/AcaTerminal.app/Contents/Resources/"
cp LICENSE "$DIST_DIR/AcaTerminal.app/Contents/Resources/LICENSE.txt"
cp COPYRIGHT "$DIST_DIR/AcaTerminal.app/Contents/Resources/COPYRIGHT.txt"
cp -R Sources/AcaTerminal/Resources/*.lproj "$DIST_DIR/AcaTerminal.app/Contents/Resources/"
# Finder may attach bundle metadata in Documents; remove only signing-incompatible metadata.
xattr -dr com.apple.FinderInfo "$DIST_DIR/AcaTerminal.app" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$DIST_DIR/AcaTerminal.app" 2>/dev/null || true
codesign --force --sign - "$DIST_DIR/AcaTerminal.app"
printf '%s\n' "Built $DIST_DIR/AcaTerminal.app (local ad-hoc signature; not notarized)."
