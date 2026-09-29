# Prior art — independently implemented AcaTerminal

Reviewed 2026-09-28, before application implementation: public repository descriptions, READMEs, top-level architecture/layout and available license files. No application implementation, UI, icon, branding, scraping selector or private endpoint was copied or vendored. The references are **not runtime dependencies**. Learning a workflow is not a claim of source-license compatibility.

| Project / URL | License found | What we learned | Concept adopted | Explicitly not copied |
| --- | --- | --- | --- | --- |
| [PaperSignal](https://github.com/zhao-xuan/PaperSignal) | No LICENSE found in root; GitHub license metadata null. Treat implementation as unavailable for reuse. | Browser extension orchestrates authenticated portal reads, local storage and status-change histories. README lists Editorial Manager, ScholarOne, Wiley, Nature, IEEE, ACS and OpenReview; existing browser sign-in avoids a separate password collector. | Preserve original journal statuses, local dated history and a connector boundary. | All JavaScript, selectors, DOM/session extraction, UI, assets, brand language and browser permissions. No browser-session functionality in v0.1. |
| [Zotero OpenAlex](https://github.com/danieleongari/zotero-openalex) | [GPL-3.0 license file](https://github.com/danieleongari/zotero-openalex/blob/main/LICENSE); exact “or later” applicability needs per-file review before any reuse. | DOI lookup enriches a Zotero item; Work/Author responses can be cached locally by identity with refresh timestamps. Citation graphs consume cached metadata. | DOI-based official API lookup, persistent provider references and dated local metrics. | Plugin code, Extra-field formats, graph implementation, database schema or settings UI. |
| [Zotero Citation Tally](https://github.com/daeh/zotero-citation-tally) | [AGPL-3.0](https://github.com/daeh/zotero-citation-tally/blob/main/LICENSE). | Crossref, Semantic Scholar and INSPIRE counts differ; provider-specific limits and retry behavior matter. | CitationProvider interface, explicit provider attribution and HTTP backoff. | Provider implementations, retry algorithms, color/UI system, unencrypted-key preference approach. |
| [Zotero Citegeist](https://github.com/phdemotions/zotero-citegeist) | [GPL-3.0-or-later](https://github.com/phdemotions/zotero-citegeist/blob/main/LICENSE), identified explicitly in README. | Annual trends, author h-index and forward/backward citation discovery answer different questions. Uses OpenAlex for author profiles and networks. | Source-attributed author metrics and annual citation history. | Graph rendering, code, journal ranking lists, logos, icons, wording and layouts. Network exploration is deferred. |
| [Zotero Research Bridge](https://github.com/z-jjj-y/zotero-research-bridge) | [MIT](https://github.com/z-jjj-y/zotero-research-bridge/blob/main/LICENSE), verified license text. | A loopback bearer-authenticated bridge separates library access from consumers; PDF access and scoped mutation flows remain local. It avoids direct writes to Zotero's SQLite database. | A library-provider boundary; read-only imports with explicit user initiation. | MCP implementation, plugins/skills, token discovery, mutation protocol code, PDF/analysis workflows. AcaTerminal uses Zotero's documented local read API directly; that API's read authentication differs from this project's bridge. |
| [Paper Status Tracker](https://github.com/GongShuai8210/Paper-Status-Tracker) | README claims MIT and links LICENSE, but no LICENSE exists in root as inspected. Reuse permission unverified. | Scheduled polling compares states and logs history locally; README describes ScholarOne/Editorial Manager browser login and email notifications. | Change detection and duplicate-observation suppression, independently specified. | Python code, scraping/login routines, password configuration, email behavior and schedules. v0.1 is manual-only. |

## Compatibility decision

AcaTerminal's original implementation is licensed under GPL-3.0-only. Reference implementations have not been incorporated; any proposed reuse still requires an explicit license and provenance review. MIT-licensed references would still require attribution and notice preservation if code were reused. No such reuse occurred. Missing/unverified licenses provide no basis for copying. This record is provenance engineering, not a legal compatibility opinion.

## Primary API sources used for new implementations

- [Zotero Web API v3 basics](https://www.zotero.org/support/dev/web_api/v3/basics): documented local/web endpoints, read-only API authentication, pagination and throttling. API key access is an official supported option.
- [OpenAlex API reference](https://help.openalex.org/api/) and [authentication](https://help.openalex.org/api/authentication/): official work/author retrieval and bearer credentials. Current authentication docs permit limited keyless use; older/deprecation pages contain different statements, so auth/rate failures remain explicit.
- [OpenAlex works](https://help.openalex.org/data/works/): work identifiers and DOI mapping.
- [ORCID authenticated iD tutorial](https://info.orcid.org/documentation/api-tutorials/api-tutorial-get-and-authenticated-orcid-id/) and [redirect URI rules](https://info.orcid.org/ufaqs/how-do-redirect-uris-work/): browser authorization, code exchange and registered redirect.
- [Apple SwiftData](https://developer.apple.com/documentation/swiftdata): assessed as a future storage option; unavailable in the installed SDK.

## AcaTex family reference

Inspected the user's existing AcaTex stylesheet at `src/renderer/styles/app.css` in the available local AcaTex project. Observations: restrained neutral surfaces, typographic hierarchy, fine separators and compact native-like controls. Implemented a new SwiftUI layout using native controls, warm paper surfaces and a muted sage accent, in line with the user's specification. No AcaTex logo, bundled image, stylesheet or UI implementation was copied into AcaTerminal.

## AcaTex Research Marks compatibility (build 9)

- Project: AcaTeX 0.8.6, local source, MIT (Copyright 2026 Darcy Lu).
- URL: https://github.com/DarcyLuai/AcaTeX (project identity from the local application's projectLinks metadata).
- Learned: researchObjects store stable IDs and paragraph anchorNodeId; visible C1/H1 numbering is positional and unsuitable for synchronization identity.
- Adopted: an independently implemented Foundation decoder of the saved local document contract; external IDs are mapped to existing Terminal Claim UUIDs.
- Not copied into AcaTerminal: React/Tiptap code, styles, icons, manuscript editor, typesetting engines, branding assets. The separate companion is an explicitly identified modification of the MIT AcaTex source, retaining its license; it is not incorporated as third-party source into AcaTerminal.
