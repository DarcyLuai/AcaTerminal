#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK_PATH="$(xcrun --show-sdk-path)"
swiftc -sdk "$SDK_PATH" -target "$(uname -m)-apple-macosx13.0" -I .build-local -I Sources/CSQLite -L .build-local -parse-as-library Sources/AcaTerminal/ReaderSession.swift Sources/AcaTerminal/ReaderThumbnails.swift Tests/ReaderChecks/*.swift -lAcaStorage -lAcaCore -o .build-local/ReaderChecks
.build-local/ReaderChecks
