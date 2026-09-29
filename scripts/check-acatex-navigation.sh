#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="${ACA_BUILD_DIR:-.build-local}"
swiftc -sdk "$(xcrun --show-sdk-path)" -target "$(uname -m)-apple-macosx13.0" -I "$BUILD_DIR" -L "$BUILD_DIR" -parse-as-library Sources/AcaTerminal/AcaTexNavigation.swift Tests/AcaTexNavigationChecks/Main.swift -lAcaCore -o "$BUILD_DIR/AcaTexNavigationChecks"
"$BUILD_DIR/AcaTexNavigationChecks"
