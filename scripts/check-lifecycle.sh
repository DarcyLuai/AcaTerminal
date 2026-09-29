#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP_SOURCES=()
for source in Sources/AcaTerminal/*.swift; do [[ "$source" == "Sources/AcaTerminal/App.swift" ]] || APP_SOURCES+=("$source"); done
swiftc -sdk "$(xcrun --show-sdk-path)" -target "$(uname -m)-apple-macosx13.0" -I .build-local -I Sources/CSQLite -L .build-local -parse-as-library "${APP_SOURCES[@]}" Tests/LifecycleChecks/*.swift -lAcaStorage -lAcaConnectors -lAcaCore -o .build-local/LifecycleChecks
.build-local/LifecycleChecks "$1"
