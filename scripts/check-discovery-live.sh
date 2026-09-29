#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swiftc -sdk "$(xcrun --show-sdk-path)" -target "$(uname -m)-apple-macosx13.0" -I .build-local -L .build-local -parse-as-library Tests/DiscoveryLiveChecks/*.swift -lAcaConnectors -lAcaCore -o .build-local/DiscoveryLiveChecks
.build-local/DiscoveryLiveChecks
