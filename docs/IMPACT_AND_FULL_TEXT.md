# Impact and full text — Phase A–H delivery

Build 5 · 2026-09-29 · macOS 13+ · independently implemented on the existing MVP.

This increment stops at Phase H. Semantic Scholar is intentionally deferred. Reader/PDFKit, ResearchObject identity, Project/Claim/Evidence, Zotero import and the local repository remain in place.

## Shipped behavior

| Phase | Implemented |
| --- | --- |
| A | FullTextProvider, FullTextLocation, access/version enums and ranked FullTextResolver |
| B | Local/Zotero/OpenAlex/Unpaywall/arXiv locations, OA PDF download and publisher/JSTOR browser fallback |
| C | Pure local ImpactAnalytics with provider partitioning and background computation |
| D | Swift Charts: annual, available-year cumulative, per-paper local snapshots, per-paper citations and works by year; Light/Dark/Eye Comfort |
| E | Append-only existing CitationSnapshot history and format 1/2 → 3 migration with backup |
| F | CitationMonitor, known citing IDs, silent initial baseline, deduplicated events, detail view and Reader/Project actions |
| G | Native UserNotifications service, durable at-most-once notification claims, citation callback routing, submission reuse and notification preferences |
| H | Today activity, weekly newly detected citations, citing-paper actions and reading progress |

Monitoring is manual or once at launch when at least 24 hours have elapsed since the last attempt. There is no continuous polling, daemon, cloud server or paid gate. Weekly summary is off by default and is evaluated during refresh, not by a background scheduler. New citations/submission change preferences default on; actual delivery requires macOS authorization via Settings.

Full-text ranking: local PDF → Zotero PDF → OA published version → accepted manuscript → preprint → unknown OA → institutional access → landing page. Unknown remains unknown. Only locations explicitly marked OA become publisher/repository direct downloads. arXiv IDs retain requested revisions and always identify a preprint. PDF contents and colors are never modified. The Reader receives source provenance alongside its local URL.

OpenAlex author works and citing works use cursor pagination (100/page, 10,000 total safety limit). Partial/repeated-cursor responses fail instead of becoming a new baseline. Provider count can differ from the citing-ID list; monitoring compares IDs, not count changes. Removed/reappearing IDs remain known. Citation events are unique by cited local UUID + provider + citing provider ID.

Citation history remains local and is never overwritten by a refresh. Different provider counts are never averaged or combined. Annual cumulative values cover only the years actually returned by the API and are explicitly labeled as such. “Recently cited” means recently detected locally; “fastest growing” requires local snapshots at least one day apart. Bars show the top 12 while all works remain in the list.

## Models and protocols

- Protocols: `FullTextProvider`, `CitationMonitor`; existing `CitationProvider`, `Connector`, `ResearchRepository` continue to serve their original roles.
- Full text: `FullTextLocation`, `AccessType`, `PaperVersion`, `FullTextResolution`, `FullTextResolver`.
- Impact: `CitingWork`, `CitationObservation`, `CitationState`, `CitationEvent`, `ImpactRefreshState`, `CitationProviderID`, `ImpactAnalytics`, `ImpactPaper`, `ImpactYear`, `ImpactPoint`.
- Existing `CitationSnapshot` gets paper/provider/count/timestamp accessors. It still stores the same object ID and CitationMetrics; no competing snapshot store was created.
- `ResearcherIdentity` gains optional per-work metrics. `ResearchDatabase` gains optional events, citing states and refresh state; identity refresh merges into stable ResearchObject UUIDs and preserves local titles and project links.

## Database migration

SQLite table schema (`PRAGMA user_version`) remains **1**. Domain payload format is now **3**.

Loading format 1 or 2 first writes an atomic raw JSON payload backup named `migration-format-{oldFormat}-{revision}.json` next to the database. Existing reading migration remains intact. Identity works are matched into local ResearchObjects, old snapshots remain, and empty citation event/state collections are added. Normal saves use the existing transactional repository worker. A failed backup/load is reported rather than resetting research. Unsupported future formats are rejected. Older binaries reject format 3.

Migration was verified against a real format-2 payload in a temporary SQLite database, with notes, claims/evidence, stable IDs and snapshots preserved. SQLite reopen tests verify event and snapshot persistence. The user's real database was not opened by the development/QA build; migration occurs when the delivered app is launched on it.

## Verification and honest limits

| Check | Result |
| --- | --- |
| Final build/package | Swift 5.8.1 / Apple macOS 13.3 SDK, arm64, succeeded |
| Offline behavior suite | **34 groups passed**, including 16 new impact/full-text groups |
| Impact application integration | **10 assertions passed**: callback → detail/seen, duplicate import, actual PDF → Reader, version provenance, reading position, resolver fallback, restart and unchanged PDF bytes |
| Existing PDFKit regression suite | **17 assertions passed**, 120/320-page PDFs and a 52 MB scanned PDF, search/zoom/resize/focus/selection/highlights/position restoration |
| Document import/menu suite | **9 assertions passed**, PDF/Word/text handling and native annotation menu |
| Appearance/resource suite | **16 assertions passed**, English/Chinese key parity and transparent system icon |
| Analytics performance | 1,000 works / 12,000 snapshots, approximately **98–111 ms** on this machine; computed off-main |
| Native UI | Synthetic isolated 120-work workspace: Today → citation detail → add to project → Reader verified; Light, Eye Comfort and Dark charts inspected; final dark chart contrast improved |

These totals mix behavioral groups and assertions, so they are reported separately. They are not 86 distinct user scenarios.

**Real APIs verified:** Native URLSession fetched OpenAlex metadata/full-text locations for DOI `10.48550/arXiv.2205.01833` (300 citations at verification), fetched one concrete citing work for `W7108210309`, and repeated the monitor without duplicate events. A real arXiv OA PDF downloaded successfully (720,014 bytes, `%PDF` validated), and the integration test opened those bytes in the existing Reader. Results can change over time.

**Fixture-only or not yet verified:** Unpaywall parsing/version classification uses synthetic fixtures; no live request was sent because no contact email was supplied. OpenAlex multi-page behavior is fixture-tested; the live citing-work check was small. Native system banner delivery and clicking an actual delivered notification remain unverified because the QA app did not request/grant OS permission. The delegate callback routing and durable notification deduplication are tested. This round did not re-authenticate a real Zotero library or a real ORCID OAuth client; existing offline regressions passed. Large-library chart calculation was measured, not a display-refresh-rate benchmark.

The app ships no sample workspace, fabricated citations or demo metrics. Synthetic works/events exist only in explicit test executables and isolated QA data, never in the packaged app or source archive as a database. Notification dispatch is **at-most-once**, not guaranteed delivery: a crash after a durable claim but before OS acceptance can omit a banner; the event remains in Today/My Research. Permission changes do not replay old events.

## Changed files

All paths below are relative to the project root.

| Area | Files |
| --- | --- |
| New Core | `Sources/AcaCore/FullText.swift`, `Impact.swift` |
| Extended Core | `Models.swift`, `Reading.swift`, `Validation.swift`, `Connectors.swift` (portable exchange excludes all local document paths) |
| New connectors | `Sources/AcaConnectors/FullTextProviders.swift`, `FullTextDownload.swift` |
| Extended provider | `Sources/AcaConnectors/OpenAlexProvider.swift` |
| Storage | `Sources/AcaStorage/SQLiteRepository.swift` |
| New app components | `Sources/AcaTerminal/FullTextView.swift`, `ImpactWorkspace.swift`, `ImpactPreferences.swift`, `ResearchNotifications.swift` |
| App integration | `App.swift`, `WorkspaceStore.swift`, `ImpactView.swift`, `ShellView.swift`, `LibraryView.swift`, `ServicesView.swift`, `PreferencesView.swift` |
| Small Reader integration | `ReaderWorkspace.swift`, `ReaderSession.swift`, `ReaderView.swift` (resolver fallback, chosen source, version label; PDF renderer retained) |
| Localization/build | both `Sources/AcaTerminal/Resources/*/Localizable.strings`, `Resources/Info.plist`, `.gitignore` |
| Tests | `Tests/AcaChecks/ImpactChecks.swift`, `Checks.swift`, `Tests/ImpactFlowChecks/Main.swift`, `Tests/ImpactLiveChecks/Main.swift`, `Tests/ImpactFixtures/Main.swift` |
| Scripts | `scripts/check-impact-flow.sh`, `scripts/check-impact-live.sh` |
| Documentation | `README.md`, `ARCHITECTURE.md`, `docs/CONNECTOR_GUIDE.md`, `docs/READING_ENVIRONMENT.md`, `docs/VERIFICATION.md`, this document |

## Reproduce

```sh
./scripts/package.sh --check
./scripts/check-reader.sh
./scripts/check-documents.sh
./scripts/check-appearance.sh dist/AcaTerminal.app
./scripts/check-impact-live.sh /path/to/isolated/live-checks
# The next path must NOT already exist. Supply a local test PDF.
ACATERMINAL_DATA_DIR=/path/to/new/isolated/flow-checks ./scripts/check-impact-flow.sh /path/to/test.pdf
```

`Tests/ImpactFixtures/Main.swift` is an explicit developer-only UI fixture generator. It refuses to overwrite an existing database and is not linked to the app.

## Next three priorities

1. Complete permission-enabled native notification banner/click/cold-start acceptance and live Unpaywall verification using a supplied contact email.
2. Validate the full lifecycle with an actual ORCID/OpenAlex works set over several refreshes, then add incremental/resumable citing-work retrieval for highly cited authors without weakening complete-baseline semantics.
3. If this workflow proves useful, implement Semantic Scholar behind the same contracts with separate provider attribution; do not merge its counts into OpenAlex.

## Official references consulted

Independent implementation; no third-party source or UI was copied. No new third-party dependency.

- [OpenAlex authentication](https://help.openalex.org/api/authentication/) and [paging](https://help.openalex.org/api/paging/).
- [OpenAlex works filters / cites semantics](https://github.com/ourresearch/openalex-docs/blob/main/api-entities/works/filter-works.md).
- [Unpaywall API](https://data.unpaywall.org/products/api) and [data format](https://unpaywall.org/data-format).
- [arXiv identifiers and versions](https://info.arxiv.org/help/arxiv_identifier.html).
- [Apple local notifications](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app).
