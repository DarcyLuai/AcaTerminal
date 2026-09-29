# AcaTerminal

**Your research, from idea to impact.**

AcaTerminal is a native macOS research lifecycle client. Papers, research questions, claims, evidence, manuscripts, submission histories and attributed impact snapshots share a local workspace. Zotero remains your library provider.

This is an independently implemented **v0.1 developer MVP**, not a signed public release. There is no cloud service, AI chat or journal-browser automation.

## Run on macOS

Requires macOS 13+ and Apple Swift 5.8+ (Command Line Tools or Xcode). No third-party package download is required.

```sh
./scripts/package.sh --check
open dist/AcaTerminal.app
```

The build produces a locally ad-hoc-signed app. Signing with a Developer ID and notarization are still required before public distribution. The included binary is built for the host architecture; source builds support Intel or Apple silicon.

With full Xcode, open `Package.swift`, select the AcaTerminal executable and run on My Mac. On a full developer installation, `swift build` and `swift run AcaChecks` are also supported. The direct build script works around SwiftPM's missing PlatformPath on Command Line Tools-only installations; it does not change the system toolchain.

## Start a research workflow

1. Import a PDF, Word or text document (⌘O), or select **Zotero → Connect & Review Import**. Bibliographic details are optional and can be edited later.
2. Create a project (⇧⌘N), enter a research question and add papers.
3. Double-click a paper or book to open the native Reader. Select text → right-click → **Evidence**, choose a Project and optionally a Claim. Use **Claim** to write your own assertion separately from the source statement.
4. Paste a submission URL. Retrieve public information where supported and supplement missing details. Private journal statuses remain manual; OpenReview public decisions can be refreshed.
5. Look up an ORCID iD in **My Research**, then use **Refresh Now** to establish a citation baseline. Charts and citation events remain available offline.
6. Use **Find full text** for local/Zotero, OpenAlex, Unpaywall (contact email required) and arXiv versions. Legal OA PDFs open in the existing Reader with version attribution.
7. Export a paper's versioned `AcaResearchExchange` JSON from the detail menu for future AcaTex integration.

A clean installation starts empty. There are no sample records or sample workspace controls. Settings → General → Interface language switches between English, 简体中文 and the system language. The native AcaTerminal menu contains About and Settings; Help contains privacy information and the GPL-3.0 license.

## v0.1 build 8

Reader zoom now changes real available reading space before magnifying PDF content. Toolbar buttons, native Reader menu and trackpad magnification share the same reversible zoom state. ⌘0 fits width; ⌘+ / ⌘− zoom; ⇧⌘F focuses. Outline and research panels reserve their own widths. Older saved reading positions remain compatible.

Projects have three primary areas: **Literature**, **Argument**, **Activity**. Discovery opens from Literature; List/Graph are secondary Argument views, and Changes/Timeline are secondary Activity views. The research question stays at the top; the graph inspector appears on selection and the project list can be collapsed.

See [build 8 verification](docs/BUILD8_VERIFICATION.md) and [build 7 Advanced verification](docs/ADVANCED_VERIFICATION.md).

## Included

- Native SwiftUI window, aligned spacious settings, English/简体中文 UI, system menus, System/Light/Eye Comfort/Dark appearance and keyboard shortcuts.
- Local searchable library, native PDFKit reader, outline/lazy page thumbnails, async PDF search, Focus mode, reading-position restoration and local highlights.
- Selection → Evidence / Claim / Note with paper/page attribution, optional claim association and inspector drag-and-drop.
- Citation copy and exchange export.
- Research projects, claims and evidence with supports/contradicts/extends/background relationships.
- URL-first submissions, optional details, OpenReview public decision lookup, raw + normalized statuses, dated timeline and duplicate-observation suppression.
- Zotero official local API or Web API v3: paginated collection/item/note import, API key in Keychain, exact-ID merge and manual ambiguity review.
- OpenAlex DOI/Work ID lookup, cursor-paginated author works and citing works, retained citation snapshots and provider-attributed annual/cumulative/per-paper charts.
- Citation ID monitoring, deduplicated events, citation detail → Reader/Project, Today activity and native macOS notifications.
- Full-text resolution with published/accepted/preprint provenance, OA downloads and publisher/institutional landing links.
- Personal developer ORCID OAuth flow using the official browser authorize/token endpoints, expiring state-checked callback and Keychain token storage.
- Shared AcaCore, AcaStorage and AcaConnectors Swift modules; UI and AppKit stay in the macOS executable.

## Known boundaries

- **ORCID production one-click OAuth is not configured.** The developer flow requires the user's own registered API client and HTTPS redirect URI, with a manually pasted callback. No shared secret is embedded. Public profile lookup is clearly marked unauthenticated. See [OAuth design](docs/OAUTH.md).
- Zotero authentication currently uses a user-generated read-only Web API key or the official local read API. Zotero OAuth 1.0a registration is future work. No Zotero database is opened directly; imports never write back or delete local records after a remote deletion.
- Zotero notes import as plain text. Local PDFs and documented Zotero PDF attachment downloads are supported; live account downloads still need verification. Annotation sync, OCR, moved-file bookmarks and selective Paper Tint are deferred. PDF colors remain unchanged. See [Reading Environment](docs/READING_ENVIRONMENT.md).
- OpenAlex author and citing-work queries paginate completely up to a 10,000-record safety limit; incomplete observations do not update a citation baseline. First monitoring establishes a silent baseline. “New” means newly detected locally, not necessarily newly published. Annual cumulative charts cover only API-provided years.
- Unpaywall requires your contact email in Settings; its adapter has fixture coverage but no live verification in this build. System notifications require macOS permission. Event deduplication is tested; OS banner delivery/click routing still needs permission-enabled end-to-end verification.
- This increment stops at Phase H. Semantic Scholar, citation graphs and always-running/cloud monitoring are deferred.
- Crossref/Semantic Scholar and automated journal connectors are extension points, not shipped implementations. There is no Google Scholar scraper.
- AcaTex export is implemented; AcaTex-side ingestion and manuscript round-trip are not.
- No iOS app has been built. Shared modules declare iOS 16 compatibility but have not been compiled with an iOS SDK on this machine.
- This MVP supports adding and connecting research; full editing/deletion, undo, accessibility audit, broader language coverage, incremental sync and large-library performance work remain before a public release.

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

Checks exercise identity resolution/conflicts, atomic imports, note remapping, evidence links, submission transitions, SQLite durability/schema rejection/conflicting writers, OAuth state/checksum/form encoding, fixture-based Zotero pagination and OpenAlex decoding, and the exchange contract. No real credentials are needed for the offline suite. See [verification record](docs/VERIFICATION.md).

See [Impact and full-text delivery record](docs/IMPACT_AND_FULL_TEXT.md) for Phase A–H behavior, migration, changed files and verification boundaries.

See [file-first reading and URL-first submissions](docs/FILE_FIRST_WORKFLOW.md) for supported formats and automation boundaries.

See [interaction polish and mouse verification](docs/INTERACTION_POLISH.md) for full-area hit targets, shared feedback, trailing disclosure arrows and motion refinements.

See [interface and language notes](docs/INTERFACE.md) for the latest visual refinement.

## Open source

AcaTerminal is licensed under GNU GPL version 3 (`GPL-3.0-only`); see [LICENSE](LICENSE) and [COPYRIGHT](COPYRIGHT). No reference-project implementation or asset has been incorporated. The source repository must not include `dist`, credentials or local research databases.

Read [ARCHITECTURE](ARCHITECTURE.md), [CONTRIBUTING](CONTRIBUTING.md), [prior-art research](docs/PRIOR_ART.md) and the [connector guide](docs/CONNECTOR_GUIDE.md).

## Advanced research (build 7)

Dock reopening now restores the existing main window and Reader state. Project tabs add a navigable Claim Graph, explainable OpenAlex discovery, local literature snapshots and aggregated project changes. See [advanced research](docs/ADVANCED_RESEARCH.md) and [window lifecycle verification](docs/WINDOW_LIFECYCLE.md) for behavior, migration, privacy and test boundaries.

### AcaTex Research Marks — v0.1 build 10

Connect a saved local AcaTex project from the project menu. Questions, Claims, Hypotheses and Findings appear in 论证; selected PDF text can become linked evidence. Stable IDs, explicit evidence relationships, three-way conflicts and local JSON exchange connect the two apps without uploading research. This release changes AcaTerminal only and reads existing saved AcaTex projects. Export writes a local exchange file; applying it or navigating to an exact mark requires AcaTex-side support and is not claimed here. Internal IDs stay out of the daily interface. [Workflow and compatibility](docs/ACATEX_RESEARCH_MARKS.md).
