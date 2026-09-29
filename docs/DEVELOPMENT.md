# Development and verification

Build instructions, storage details and current limits for AcaTerminal v0.1 build 10. Run commands from the repository root. For the product overview, see the [README](../README.md).

## Run on macOS

Requires macOS 13+ and Apple Swift 5.8+ (Command Line Tools or Xcode). No third-party package download is required.

```sh
./scripts/package.sh --check
open dist/AcaTerminal.app
```

The build produces a locally ad-hoc-signed app. Signing with a Developer ID and notarization are still required before public distribution. The packaged binary is built for the host architecture; source builds support Intel or Apple silicon.

With full Xcode, open `Package.swift`, select the AcaTerminal executable and run on My Mac. On a full developer installation, `swift build` and `swift run AcaChecks` are also supported. The direct build script works around SwiftPM's missing PlatformPath on Command Line Tools-only installations; it does not change the system toolchain.

## Known boundaries

- **ORCID production one-click OAuth is not configured.** The developer flow requires the user's own registered API client and HTTPS redirect URI, with a manually pasted callback. No shared secret is embedded. Public profile lookup is clearly marked unauthenticated. See [OAuth design](OAUTH.md).
- Zotero authentication currently uses a user-generated read-only Web API key or the official local read API. Zotero OAuth 1.0a registration is future work. No Zotero database is opened directly; imports never write back or delete local records after a remote deletion.
- Zotero notes import as plain text. Local PDFs and documented Zotero PDF attachment downloads are supported; live account downloads still need verification. Annotation sync, OCR, moved-file bookmarks and selective Paper Tint are deferred. PDF colors remain unchanged. See [Reading Environment](READING_ENVIRONMENT.md).
- OpenAlex author and citing-work queries paginate completely up to a 10,000-record safety limit; incomplete observations do not update a citation baseline. First monitoring establishes a silent baseline. “New” means newly detected locally, not necessarily newly published. Annual cumulative charts cover only API-provided years.
- Unpaywall requires your contact email in Settings; its adapter has fixture coverage but no live verification in this build. System notifications require macOS permission. Event deduplication is tested; OS banner delivery/click routing still needs permission-enabled end-to-end verification.
- Impact analytics currently use OpenAlex. Semantic Scholar, citation graphs and always-running/cloud monitoring are not included.
- Crossref/Semantic Scholar and automated journal connectors are extension points, not shipped implementations. There is no Google Scholar scraper.
- AcaTex export is implemented; AcaTex-side ingestion and manuscript round-trip are not.
- No iOS app has been built. Shared modules declare iOS 16 compatibility but have not been compiled with an iOS SDK on this machine.
- This MVP supports adding and connecting research; full editing/deletion, undo, accessibility audit, broader language coverage, incremental sync and large-library performance work remain before a stable, notarized distribution.

## Storage and privacy

Real data: `~/Library/Application Support/AcaTerminal/research.sqlite`.


All research state, citation history, events and known citing IDs stay local. Service actions, requested full text and uncached Zotero attachments use the network. When enabled, impact refreshes on launch only if the last attempt is at least 24 hours old; there is no repeating timer or server. Only public identifiers and configured API credentials/contact email go to the relevant provider; private notes, claims, manuscripts and PDF contents are never uploaded. Local Zotero reads use loopback port 23119; external requests use HTTPS. API keys, ORCID personal-client secrets and access tokens use Apple Keychain. No passwords, browser cookies or telemetry are collected.

For backups, quit the app and copy its Application Support directory, including SQLite sidecars if present. New PDF/Word/text imports are copied under Application Support/Documents, including their originals. Older externally attached PDFs remain at their original locations and need their own backups; downloaded Zotero PDFs are cached under Application Support/Attachments. An unreadable or newer database is reported, never silently replaced. Database contents are not encrypted by this app; credentials are stored separately in Keychain.

For isolated development or UI tests, set `ACATERMINAL_DATA_DIR` to a test directory before launching the executable. Never use a real research database as a test fixture.

Research edits publish immediately while saving on a serial background queue. The interface shows pending/error state; quitting waits for writes. Settings can export all in-memory research if persistence fails. Payload formats 1–4 migrate to format 5 with a local raw-payload backup before saving; the SQLite table schema remains version 1. Older binaries reject format 5 and must not edit an upgraded database.

## Verification

```sh
./scripts/build.sh --check    # deterministic, offline behavior checks
./scripts/check-reader.sh     # native PDFKit + persistence integration checks
./scripts/check-documents.sh  # Word/PDF/text import and native annotation menu checks
./scripts/check-appearance.sh # packaged English/Chinese resources + transparent icon
./scripts/check-impact-live.sh # optional real OpenAlex + arXiv smoke checks
```

Checks exercise identity resolution/conflicts, atomic imports, note remapping, evidence links, submission transitions, SQLite durability/schema rejection/conflicting writers, OAuth state/checksum/form encoding, fixture-based Zotero pagination and OpenAlex decoding, and the exchange contract. No real credentials are needed for the offline suite. See [verification record](VERIFICATION.md).

See [Impact and full-text delivery record](IMPACT_AND_FULL_TEXT.md) for Phase A–H behavior, migration, changed files and verification boundaries.

See [file-first reading and URL-first submissions](FILE_FIRST_WORKFLOW.md) for supported formats and automation boundaries.

See [interaction polish and mouse verification](INTERACTION_POLISH.md) for full-area hit targets, shared feedback, trailing disclosure arrows and motion refinements.

See [interface and language notes](INTERFACE.md) for the latest visual refinement.
