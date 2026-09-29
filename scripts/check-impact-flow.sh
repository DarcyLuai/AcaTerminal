#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK_PATH="$(xcrun --show-sdk-path)"
APP_SOURCES=()
for source in Sources/AcaTerminal/*.swift; do
    [[ "$source" == "Sources/AcaTerminal/App.swift" ]] || APP_SOURCES+=("$source")
done
swiftc -sdk "$SDK_PATH" -target "$(uname -m)-apple-macosx13.0" -I .build-local -I Sources/CSQLite -L .build-local -parse-as-library "${APP_SOURCES[@]}" Tests/ImpactFlowChecks/*.swift -lAcaStorage -lAcaConnectors -lAcaCore -o .build-local/ImpactFlowChecks
.build-local/ImpactFlowChecks "$1"
