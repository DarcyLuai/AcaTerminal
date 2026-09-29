#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK_PATH="$(xcrun --show-sdk-path)"
swiftc -sdk "$SDK_PATH" -target "$(uname -m)-apple-macosx13.0" -I .build-local -L .build-local -parse-as-library Tests/ImpactLiveChecks/*.swift -lAcaConnectors -lAcaCore -o .build-local/ImpactLiveChecks
.build-local/ImpactLiveChecks "${1:-${TMPDIR:-/tmp}/AcaTerminal-LiveChecks}"
