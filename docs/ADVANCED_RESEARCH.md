# Advanced research — build 7

This increment extends the existing local graph, Reader, providers and SQLite repository. No cloud service, AI model, background daemon or new dependency is introduced.

## Window lifecycle (P0)

See [WINDOW_LIFECYCLE.md](WINDOW_LIFECYCLE.md) for the specific ownership/reopen defect, AppKit callback semantics, same-window restoration and the physical-Dock testing boundary. The fix retains a single SwiftUI `Window(id: "main")`, the existing WorkspaceStore/ReaderSession and quit/save barrier. A minimized window is deminiaturized; only a closed window opens the scene. The application remains regular.

## Claim graph

`ClaimRelation` is a separate flat record with project, source/target claim IDs, relationship and timestamp. Allowed relationships: supports, contradicts, extends, qualifies, dependsOn. Self-relations, cross-project links and duplicate directed relationships are rejected. Different relation types and reciprocal directions remain legitimate.

Project tabs expose Overview, Claims, Graph, Timeline, Discover and What's New. The layered graph has drag panning, zoom buttons, search, focus-neighborhood and an inspector. Arrows point from source to target. Graph focus includes the papers underlying a selected claim's evidence. The inspector links related claims and opens evidence in the existing Reader. Relations can be removed from their contextual menu.

The existing Evidence `documentID` and normalized `PDFTextLocation` rectangles are reused. For an identical PDF fingerprint, source navigation restores the original selection. For a changed document, it tries the exact quote on the stored physical page. If that fails, it opens the page and explicitly reports that the passage could not be located. Original PDF bytes are never written.

## Discovery and privacy

`ProjectResearchProfile` builds local terms from the research question, claims, linked papers, tags and evidence. It never crosses the connector boundary. `DiscoveryRequest` permits only validated public DOI/OpenAlex IDs, at most five, from published object types. No manuscript, PDF, notes, claims, evidence, project question or locally edited title is sent to a provider.

`OpenAlexDiscoveryProvider` resolves public seed metadata, then requests four bounded candidate sets through the official API: related work IDs, works citing seed papers, recent works in seed topics, and recent works by seed authors. Each set is capped at 50. The first two authors and primary topic of each public seed form the tracked scope. Tracking is automatic and visible as counts; editing individual tracked authors/topics is a future extension.

Official API references: [filtering](https://help.openalex.org/api/filtering/), [API recipes](https://help.openalex.org/how-to/api-recipes/), [work filters](https://github.com/ourresearch/openalex-docs/blob/main/api-entities/works/filter-works.md). No scraping or private API is used.

Ranking is entirely deterministic and local. Shared references, direct citations, provider related-work links, author/topic matches and recency have explicit reasons. Keyword overlap is labeled local, with the matching claim when available. Potential challenges/support require at least two claim terms plus explicit challenge/support words in public metadata. This is a coarse English-vocabulary heuristic, not semantic entailment or a scholarly judgment. Methods uses method-related words; highly cited means at least 50 OpenAlex citations and no recorded reading activity. All categories require researcher review.

Feedback relevant/notRelevant/alreadyKnown is persisted per project/provider/work. Dismissed records remain recoverable through Include dismissed. Relevant feedback boosts subsequent ranking. Import uses the existing ResearchObjectResolver/LibraryImport so identities and project memberships are retained and ambiguous matches require review. Read uses the existing FullTextResolver and Reader, with existing OA/version/paywall behavior.

## Literature monitoring

`DiscoveryCache` is an offline view of the last successful bounded exploration. `LiteratureSnapshot` retains cumulative known IDs and public topic/author/citation state. `LiteratureChangeSet` preserves newly detected works and newly observed citations by already-known works. Count increases alone are not used as evidence of a new work.

The first refresh is silent. A changed public-seed scope establishes a new silent baseline. A work disappearing from one bounded result page and later reappearing does not alert again. Failed/partial network requests never replace the cache or baseline. An older response cannot replace newer observations. This is change detection within the explored API sample, not exhaustive surveillance of the world's literature; newly detected does not necessarily mean newly published.

Today's Research Changes leads to a project's unreviewed changes. Mark reviewed retains historical records. Important changes are aggregated per project into one native notification after a durable notification claim. The at-most-once policy prevents relaunch duplicates; a crash after the claim but before OS delivery may omit a banner. The history remains available. Native notification clicks restore the main window and open that project's What's New tab. Actual OS banner delivery depends on macOS permission.

Monitoring starts with the project's first manual discovery. Existing monitored projects refresh sequentially on launch when at least a day has elapsed since the last attempt/success. A service failure stops that launch batch. Manual refresh remains available, with progress and cancellation. Weekly summaries are evaluated on refresh while the app is running, not scheduled wake-ups. Permission settings and the user's research data are not modified by tests.

## Storage / query contracts

Payload format **4** adds optional arrays: claimRelations, discoveryCaches, discoveryFeedback, literatureSnapshots, literatureChanges. Versions 1–3 decode and migrate explicitly after a raw-payload backup next to the SQLite database (`migration-format-{version}-{revision}.json`). Existing research, citation history, PDF anchors and Zotero references are preserved. SQLite table schema remains version **1**. Older app binaries refuse format 4 rather than overwriting it.

New Foundation-only types: ClaimRelationship, ClaimRelation, ClaimGraph; ProjectResearchProfile, DiscoveryRequest, DiscoveryProvider, DiscoveryWork/Batch/Cache/Recommendation/Reason/Category/Judgment/Feedback; LiteratureSnapshot/Change/ChangeKind/ChangeSet. `ResearchQuerying`, `ResearchQuery` and `ResearchQueryResult` expose graph, evidence, discovery and dated changes for a future command palette. The query interface does not parse natural language.

Network requests and graph/ranking preparation run off the UI thread. Saves continue on RepositoryWorker's serial queue. History is append-only; archive/retention controls and a normalized SQLite schema can be considered if long-running histories become large. The layered graph is intentionally deterministic; no physics simulation or new renderer is introduced.

## Verification commands

```sh
./scripts/build.sh --check
./scripts/check-reader.sh
./scripts/check-documents.sh
./scripts/check-appearance.sh /absolute/path/AcaTerminal.app
ACATERMINAL_DATA_DIR=/new/isolated/path ./scripts/check-lifecycle.sh /path/to/test.pdf
ACATERMINAL_DATA_DIR=/another/new/path ./scripts/check-advanced-flow.sh /path/to/test.pdf
ACATERMINAL_DATA_DIR=/third/new/path ./scripts/check-impact-flow.sh /path/to/test.pdf
./scripts/check-discovery-live.sh
```

Synthetic fixtures exist only in Tests and isolated scratch workspaces. The shipped app opens an empty library and does not seed demo claims, papers or projects. Live discovery verification uses a public DOI, without reading a user's research database or Keychain.
