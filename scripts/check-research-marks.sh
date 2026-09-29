#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swiftc -sdk "$(xcrun --show-sdk-path)" -target "$(uname -m)-apple-macosx13.0" -I .build-local -I Sources/CSQLite -L .build-local -parse-as-library Sources/AcaTerminal/ReaderSession.swift Sources/AcaTerminal/ReaderThumbnails.swift Tests/ResearchMarkFlowChecks/*.swift -lAcaStorage -lAcaConnectors -lAcaCore -o .build-local/ResearchMarkFlowChecks
.build-local/ResearchMarkFlowChecks "$@"
