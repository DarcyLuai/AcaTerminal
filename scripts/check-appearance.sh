#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK_PATH="$(xcrun --show-sdk-path)"
mkdir -p .build-local
swiftc -sdk "$SDK_PATH" -target "$(uname -m)-apple-macosx13.0" -parse-as-library Sources/AcaTerminal/Localization.swift Tests/AppearanceChecks/*.swift -o .build-local/AppearanceChecks
.build-local/AppearanceChecks "${1:-dist/AcaTerminal.app}" Resources/AppIcon.png
