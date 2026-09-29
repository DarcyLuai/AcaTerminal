#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK_PATH="$(xcrun --show-sdk-path)"
FIXTURE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/acaterminal-documents.XXXXXX")"
python3 - "$FIXTURE_DIR" <<'PY'
import sys, zipfile
from pathlib import Path
root=Path(sys.argv[1])
with zipfile.ZipFile(root/'Study.docx','w') as z:
    z.writestr('[Content_Types].xml','<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>')
    z.writestr('_rels/.rels','<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
    paras=''.join('<w:p><w:r><w:t>Evidence supports our hypothesis. Paragraph '+str(i)+'. 研究文字。</w:t></w:r></w:p>' for i in range(180))
    z.writestr('word/document.xml','<?xml version="1.0"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>'+paras+'</w:body></w:document>')
PY
swiftc -sdk "$SDK_PATH" -target "$(uname -m)-apple-macosx13.0" -I .build-local -L .build-local -parse-as-library Sources/AcaTerminal/DocumentImport.swift Sources/AcaTerminal/ReaderContextMenu.swift Tests/DocumentChecks/*.swift -lAcaCore -o .build-local/DocumentChecks
.build-local/DocumentChecks "$FIXTURE_DIR"
