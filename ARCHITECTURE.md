# Architecture

Research workflow → local-first → simplicity → native macOS → interoperability → feature count.

```text
AcaTerminal (SwiftUI / AppKit / PDFKit / Charts)
    ├── WorkspaceStore (MainActor, optimistic publish, user feedback)
    ├── AcaCore (Foundation value models + invariants + protocols)
    ├── AcaStorage (system SQLite, no UI imports)
    └── AcaConnectors (official APIs + Keychain, no UI imports)
          └── HTTPTransport (injectable; ephemeral URLSession)
```

## Domain

`ResearchObject` is platform-independent. Source references identify provider records; a paper is never a Zotero-specific subclass. `ObjectKind` includes paper, book, dataset, code, manuscript, note, person and project. The dedicated `ResearchProject` aggregate carries its question; object membership lives once in `ResearchObject.projects`.

Claim owns source and evidence UUIDs; Evidence belongs to a Project, refers to a paper and records a relationship, page, quote and/or note. It can precede a Claim. Attaching evidence validates project scope, deduplicates links and preserves source attribution. Submission links optionally to a manuscript UUID, separately retaining the journal's external manuscript ID. Submission history is ordered, preserves raw text, and avoids identical observations.

Normalization is deliberately conservative. For example “Required Reviews Completed” maps to `reviewsComplete`, not `underReview`. Unknown text stays `unknown`, and manual users can override a normalized status without changing raw text.

## Identity resolution

DOI → arXiv (version removed) → ISBN (separator normalized) → source identity for repeat imports → normalized title + first author + year as a **review candidate**. Multiple exact matches and conflicting stronger identifiers also require review. A lower-priority arXiv match cannot silently merge conflicting DOIs.

A merge preserves local UUID, title, project links and existing descriptive metadata, fills missing metadata, and updates the same provider source reference. Imported notes are remapped to the retained local paper UUID and upserted by their scoped provider ID. Imports are staged in a value copy, validated, then saved atomically. Ambiguities abort the whole transaction until a user chooses merge or separate.

Local and web Zotero IDs are scoped separately because local and server user/version spaces differ. DOI resolves overlap where present; identifier-poor overlap is reviewed. ISBN-10/13 equivalence and fuzzy author identity are not inferred.

## Storage decision (2026-09-28)

SwiftData is a reasonable future option for a macOS 14 / iOS 17 baseline, with explicit `VersionedSchema` / migration planning. It is unavailable in the installed macOS 13.3 SDK and Swift 5.8 toolchain. Requiring it here would prevent compiling and running the requested MVP.

v0.1 therefore uses the OS-provided SQLite C library behind `ResearchRepository`, with zero package dependencies. GRDB would be reasonable when normalized queries, FTS and complex migrations become necessary; adding it now is unnecessary.

- `PRAGMA user_version` owns the database schema. Version 0 → 1 creates the workspace table inside a transaction. Newer versions are rejected before changing journal settings.
- One JSON-encoded domain document stores a coherent research graph in one row. `formatVersion` versions the payload independently. Payload format 5 retains the citation and Advanced Research state from format 4 and adds Research Mark bindings, typed claims and evidence relations. Versions 1–4 migrate explicitly after a raw-payload backup; legacy evidence gets a project only when its claim owners agree. Future formats are rejected.
- `BEGIN IMMEDIATE`, WAL, `synchronous=FULL` and a monotonic revision protect durable, atomic saves and detect stale writers.
- UI mutations publish on MainActor; a serial RepositoryWorker performs validation, encoding and SQLite work off-main. The UI reports pending saves. The first failure stops subsequent writes, preserves in-memory edits for recovery export and prevents normal quit. Quit drains queued writes. Existing research is never substituted with seed data after a load failure.
- Snapshot storage is intentionally simple and O(workspace size) per save. It is suitable for an MVP, not a claim of large-library scalability. A later migration should normalize objects/relationships, add indexes/FTS, with migration fixtures and backups.
- Each app process owns one repository per active workspace; windows share WorkspaceStore. Concurrent processes receive a clear reload error rather than overwriting newer research.

## Networking and security boundaries

Connectors return AcaCore values and know nothing about ViewModels. HTTPTransport is replaceable for tests. Production transport has ephemeral sessions, no cookie store/cache, finite timeouts, denied redirects, safe errors and per-host server backoff. API keys use headers. Retry-After/Backoff retain cached data and require a later user retry; no background retry loop hides failures.

Zotero imports paginate in batches of 100 with a hard safety limit; no partial success is committed. Service snapshots remain accessible offline. Zotero is queried after user action. OpenAlex may also refresh on launch after a 24-hour stale threshold, with a Settings opt-out. There is no timer or remote monitor. Full source metadata never overwrites user text. There is no browser session extraction.

ORCID's public lookup and authenticated identity are distinct states. Personal-client OAuth is a developer flow; a distribution-ready OAuth registration/callback remains external work. See `docs/OAUTH.md`.

## macOS today, shared Core tomorrow

AcaCore, AcaStorage and AcaConnectors use Foundation, Security and SQLite, available across Apple platforms. AppKit, NSOpenPanel/NSSavePanel, pasteboard, Settings and desktop window management belong only to the app target. iOS would supply a separate app target, document picker/bookmarks and authentication callback adapter. The package declares iOS 16 support for shared modules; iOS compilation is not verified here.

No universal macOS/iOS view abstraction is added prematurely. No SwiftUI reference appears in shared modules.

## AcaTex boundary

`AcaTexBridge` emits `AcaResearchExchange` schema version 1. The shipped adapter exports citation JSON with stable identifiers, authors, year and project IDs. Local PDF paths are excluded. `docs/AcaResearchExchange.schema.json` defines the payload. Actual AcaTex app integration and reverse manuscript import are deferred.

## Reading isolation

ReaderSession owns a stable PDFView for one paper. Initial PDF parsing, fingerprinting and outline preparation happen off-main; ownership then transfers to PDFKit on the main thread. Search uses PDFKit asynchronous find. PDFView manages lazy continuous rendering. Thumbnail preparation uses a different PDFDocument on a serial utility queue and a bounded cache; the active view's document is never rendered concurrently from the worker.

Resize/zoom retain normalized page anchors. Reading positions are debounced and written through RepositoryWorker. Metadata refreshes cannot replace the PDFView document. AcaMotion centralizes short transitions and respects Reduce Motion. Eye Comfort changes surfaces while PDF page colors remain intact. See [Reading Environment](docs/READING_ENVIRONMENT.md) for interaction and migration details.

ZoteroAttachment uses a separate streaming download session: fixed official endpoints, constrained HTTPS redirects with credentials stripped, format/hash checks, local cache. It cannot follow a publisher URL supplied in metadata.

## Impact and full text (Phase A–H)

`CitationProvider → CitationMetrics → existing CitationSnapshot → ImpactAnalytics → Swift Charts`. Analytics is computed from an immutable local snapshot on a utility task; charts never call a provider. Separate provider IDs partition counts, annual series, baselines and events.

`CitationMonitor` returns a complete `CitationObservation`; Core unions known IDs, appends snapshots and deduplicates CitationEvent by cited UUID + provider + citing external ID. The first complete observation is silent. Failed/partial pagination retains the previous baseline. Notifications claim events durably before calling UserNotifications (at-most-once dispatch, not guaranteed delivery). A crash after claiming may lose a banner; the local event remains readable. Permission changes do not replay old notifications.

`FullTextResolver` ranks independent `FullTextProvider` results. Reader receives a local URL and provenance, not publisher-specific logic. OA streaming downloads allow HTTPS redirects without credentials and validate the PDF header; original files are unchanged. Unknown versions stay unknown, while closed-access locations remain external landing pages.

See [detailed behavior and verification](docs/IMPACT_AND_FULL_TEXT.md).

## Advanced local research

See [Advanced Research](docs/ADVANCED_RESEARCH.md). ProjectResearchProfile stays local; only DiscoveryRequest public identifiers cross the network boundary. Provider metadata → local DiscoveryCache ranking → LiteratureSnapshot diff → durable aggregate notification claim → native UI. ResearchQuerying is the shared Foundation-only query seam. MainWindowLifecycle owns the one real NSWindow and routes Dock/notification reopen without resetting WorkspaceStore.

## Reader viewport and native commands (build 8)

`ReaderViewport` owns one `AnchorPDFView`; `ReaderSession` owns a reversible relative reading scale. Below 1, the real PDF viewport grows toward available width. At/above 1, the viewport fills available width while PDFKit magnifies and scrolls its contents. Visible panels subtract space before this calculation. The current physical page and normalized destination are captured before resizing and restored afterward. No PDF layer transforms or modified PDF bytes are used.

`ReadingPosition.readingScale` is optional within payload format 4. Records without it derive a relative scale from their existing physical `zoom`. In build 8 both values remained persisted with SQLite schema 1 and payload 4; build 9 preserves these records while adding the payload-5 Research Marks migration. Reader controls and native menu items share session actions and loading availability. Project tab names map to the existing navigation state; no project data is migrated for presentation changes.

## Research Marks (v0.1 build 9)

AcaTexProjectReader → versioned ResearchMarkExchange → existing typed Claim aggregate, joined by MarkBinding. Three-way local sync retains conflict histories; EvidenceRelation stores a per-mark relationship. Native AcaTex paragraphs are read via stable anchorNodeId, never title matching. ResearchRoute reuses existing Reader selection restoration. SQLite payload 5 adds optional data to payload 4 and writes a migration backup. See [Research Marks](docs/ACATEX_RESEARCH_MARKS.md) for scope, review protocol and companion compatibility.
