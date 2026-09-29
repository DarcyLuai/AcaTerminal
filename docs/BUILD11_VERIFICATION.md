# Build 11 — installed AcaTex Research Bridge integration

Verified locally on 2026-09-29, Apple Silicon, macOS 15.4.1.

## Delivered behavior

- Project → Arguments → mark menu → **Open in AcaTex** opens the original document/mark identity in a compatible companion. AcaTex's own unsaved-document protection remains in charge.
- AcaTex compatibility requires the expected bundle identity, `acatex` URL scheme and `AcaTeXResearchBridgeVersion = 1`. An older installation falls back to Finder with a localized explanation. The verified app is targeted explicitly, avoiding an older registered copy.
- Opening state prevents repeated launch requests and errors remain visible. English and Simplified Chinese strings are included.
- Evidence import remains an explicit, local exchange-file workflow. It does not insert or rewrite manuscript prose or create argument marks in AcaTex.
- A Reader defect discovered during installed-app testing was fixed: layout calls with unchanged geometry/scale no longer restore a transient PDFKit destination over an explicit evidence jump.

## Actual installed-app checks

Both applications were built and installed under `/Applications`. Test runs used an isolated AcaTex profile and independent Terminal databases; no user manuscript or production database was used as a test fixture.

1. AcaTex File → Import Research Evidence opened a real Terminal-generated exchange. Selecting one relationship imported evidence for `CLAIM-003` as **qualifies**, displayed as 限定.
2. AcaTex's evidence panel displayed page 17 and the original source quote. Its real **Open source in AcaTerminal** button opened Reader, with the original passage selected.
3. Terminal's real **Open in AcaTex** menu item reached AcaTex. With a different unsaved document active, AcaTex prompted before replacement.
4. **Cancel** retained the unsaved test text. A subsequent **Save** wrote that text to a separate test document and continued to the requested Claim, without redirecting Save to the target manuscript.
5. AcaTex was quit and cold-launched through the exact-mark URL with its isolated profile. It reopened the intended manuscript and Claim. The imported relationship, quote and page remained present after restart.
6. Terminal was cold-launched through the evidence URL with its isolated database. The Reader displayed physical page 17/20 and the selected original passage. The first navigation remained stable after the layout fix.
7. After restarting both apps, clicking the retained evidence in AcaTex again returned to the selected passage in Reader.
8. Disk inspection confirmed one evidence record, unchanged IDs, `qualifies`, page label 17, physical page index 16, identical normalized rectangles and PDF fingerprint. Original PDF bytes and original test-manuscript prose were unchanged. The separately saved unsaved document had a different document ID.

## Automated verification

| Suite | Result |
| --- | --- |
| Terminal core/storage/connectors checks | 63 passed |
| AcaTex capability and opaque-ID routing | 5 passed |
| Reader layout/zoom/theme/reopen checks | 27 passed |
| Reader integration, search, PDF immutability and save queue | 17 passed |
| AcaTex Vitest suite, independently rerun during preceding review of the same source | 382 passed, 10 skipped |
| AcaTex bridge/menu/atomic-file Node tests, independently rerun during preceding review | 14 passed |
| AcaTex TypeScript check | Passed |
| Terminal build, AcaTex web build and local application signing verification | Passed |

The Reader checks exercised 120-page and 320-page text PDFs, a 24-page scanned PDF, Reduced Motion, light/dark appearance, Eye Comfort surfaces, zoom, resize, selection coordinates and persisted reading position. They do not establish display-refresh-rate performance or simulate hardware trackpad events.

Reproduce Terminal checks after building with:

```sh
./scripts/build.sh --check
./scripts/check-acatex-navigation.sh
./scripts/check-reader.sh
# Requires a new isolated directory and a PDF with at least 25 pages:
ACATERMINAL_DATA_DIR=/path/to/new-test-workspace \
  ./scripts/check-reading-space.sh /path/to/test.pdf
```

## Storage and migration

No database schema migration was added in build 11. SQLite `user_version = 1`, Terminal payload format 5 and Research Mark exchange version 1 remain unchanged. AcaTex retains native document schema 13 and its separate local ResearchExchange store. Existing migration checks still pass.

## Files changed in Terminal

- `Sources/AcaTerminal/AcaTexNavigation.swift` — companion capability detection.
- `Sources/AcaTerminal/ResearchMarkWorkspace.swift` — explicit application/mark dispatch and fallback.
- `Sources/AcaTerminal/ResearchMarkView.swift`, `WorkspaceStore.swift` — navigation action and opening state.
- `Sources/AcaTerminal/ReaderSession.swift` — preserve explicit navigation through unchanged layouts.
- Both `Localizable.strings` files — navigation state, fallback and launch failure.
- `Resources/Info.plist` — build 11.
- `Tests/AcaTexNavigationChecks/Main.swift`, `scripts/check-acatex-navigation.sh` — compatibility/identity checks.
- `Tests/ReadingSpaceChecks/Main.swift` — repeated-layout passage regression.
- README and integration/development documentation.

AcaTex was built from its existing Research Bridge implementation; this task did not alter its source code.

## Boundaries and local packaging

- These are local ad-hoc-signed builds, not a newly notarized public release. AcaTex's local package was built without Hardened Runtime; its production signing configuration was not changed. Original installed AcaTex is retained in the task's `work/acatex-review/AcaTeX-before-bridge.app.backup` directory.
- The Documents test directory exhibited an OS file-open stall on a later Terminal launch. Sampling showed a worker blocked in `guarded_open_np`, while the main thread stayed responsive. Cold-start verification was completed using a non-synced temporary directory and byte-identical local source files. The exact cause of the Documents access stall was not established; iCloud placeholders/external-folder access are not certified by this test.
- The Discard branch was covered by AcaTex's earlier harness verification; this installed-app pass specifically exercised Cancel and Save, not Discard.
- No automatic evidence synchronization, new-Claim insertion into AcaTex, signed distribution, external API validation or cross-machine transfer was added or claimed.
- Application installation and verification were local. Source publication does not constitute a notarized binary release.
