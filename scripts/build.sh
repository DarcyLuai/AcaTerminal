#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="${ACA_BUILD_DIR:-.build-local}"
mkdir -p "$BUILD_DIR"
SDK_PATH="$(xcrun --show-sdk-path)"
COMMON=(-sdk "$SDK_PATH" -target "$(uname -m)-apple-macosx13.0" -I "$BUILD_DIR" -I Sources/CSQLite -L "$BUILD_DIR")
swiftc "${COMMON[@]}" -parse-as-library -emit-module -emit-module-path "$BUILD_DIR/AcaCore.swiftmodule" -emit-library -static -module-name AcaCore Sources/AcaCore/*.swift -o "$BUILD_DIR/libAcaCore.a"
swiftc "${COMMON[@]}" -parse-as-library -emit-module -emit-module-path "$BUILD_DIR/AcaStorage.swiftmodule" -emit-library -static -module-name AcaStorage Sources/AcaStorage/*.swift -o "$BUILD_DIR/libAcaStorage.a"
swiftc "${COMMON[@]}" -parse-as-library -emit-module -emit-module-path "$BUILD_DIR/AcaConnectors.swiftmodule" -emit-library -static -module-name AcaConnectors Sources/AcaConnectors/*.swift -o "$BUILD_DIR/libAcaConnectors.a"
swiftc "${COMMON[@]}" -parse-as-library Sources/AcaTerminal/*.swift -lAcaStorage -lAcaConnectors -lAcaCore -o "$BUILD_DIR/AcaTerminal"
if [[ "${1:-}" == "--check" ]]; then
    swiftc "${COMMON[@]}" -parse-as-library Tests/AcaChecks/*.swift -lAcaStorage -lAcaConnectors -lAcaCore -o "$BUILD_DIR/AcaChecks"
    "$BUILD_DIR/AcaChecks"
fi
