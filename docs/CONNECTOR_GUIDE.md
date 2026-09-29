# Connector guide

A connector imports AcaCore and Foundation. It must never depend on WorkspaceStore, SwiftUI or AppKit.

## Contracts

- `Connector`: stable identifier and displayName.
- `LibraryProvider`: `importLibrary() async throws -> LibraryImport` (objects, notes, collections).
- `CitationProvider`: DOI/object metrics plus researcher metrics by ORCID. Return provider, retrieval time, optional h-index and annual counts. “Missing” is not zero.
- `SubmissionConnector`: fetch submissions and refresh a submission. Keep statusRaw and event history. Preserve stable local IDs on refresh.
- `FullTextProvider`: resolve a ResearchObject into versioned access locations. Do not treat a closed publisher PDF URL as OA.
- `CitationMonitor`: return metrics and a complete citing-work ID set; mark/reject incomplete pagination before Core changes a baseline.
- `AcaTexBridge`: export an AcaResearchExchange value as portable data.
- `CredentialStore`: read/write/remove secrets; production implementation is Apple Keychain. Tests inject an in-memory store.
- `HTTPTransport`: async request → data; fixtures verify decoding and request construction without network access.

## Adding an integration

1. Read official API docs and check data/API terms. Record URLs and retrieval date. Do not reverse engineer undocumented endpoints or copy another connector.
2. Define scope, identifiers, authentication, pagination, rate limits, errors and cache freshness. No automatic sign-in or remote writes in v0.1.
3. Implement a separate value/actor type inside AcaConnectors. Use a scoped SourceReference (provider + account/library + externalID), and retain provider-specific provenance without secrets.
4. Never silently truncate imports. Return an error if a complete import cannot finish; the UI commits only a staged complete batch. Remote deletion does not delete local research.
5. Let ResearchObjectResolver handle identity. Identifier-free title matches remain review candidates. Notes must remap to the retained paper UUID when duplicates merge.
6. Use official authenticated HTTPS endpoints, or an explicitly allowed loopback transport. Deny redirects on authenticated requests. Redact request URLs, headers, tokens and bodies from errors/logs.
7. Handle cancellation, unauthorized access, 404, malformed data, 429 and server backoff. Preserve old snapshots after failure. Retrying must respect provider guidance.
8. Add representative synthetic fixtures and behavioral checks under Tests/AcaChecks. Never use a private user library or real tokens.

## Shipped adapters

| Adapter | Access | Authentication | Behavior |
| --- | --- | --- | --- |
| ZoteroProvider local | `http://127.0.0.1:23119/api/users/0/` | Official read API, enabled in Zotero settings; no app-side password | Collections/items/notes, pages of 100, excludes attachment files |
| ZoteroProvider web | `https://api.zotero.org/users/{id}/` | Dedicated read key in `Zotero-API-Key` header, Keychain | Same normalized output; no writes |
| OpenAlexProvider | `https://api.openalex.org/works/...`, `/authors/...` | Optional bearer key, Keychain | DOI/Work ID → metrics and OA locations; ORCID → author and all paginated works; citing-work cursor monitor (10,000 safety limit) |
| Local / Zotero full text | Existing sources and official Zotero file adapter | Existing credential boundary | Local file priority, no publisher login |
| UnpaywallFullTextProvider | `https://api.unpaywall.org/v2/{doi}?email=...` | User-supplied contact email | OA locations, published/accepted/preprint version, fixture verified |
| ArxivFullTextProvider | `https://arxiv.org/pdf/{id}` | None | Validated modern/legacy ID including explicit version, preprint |
| PublisherFullTextProvider | DOI/source landing page | Browser only | External page; institutional access may be required |
| ORCIDOAuthClient | `https://orcid.org/oauth/authorize`, `/oauth/token` | Personal registered API client; see OAUTH.md | Official code exchange; token to Keychain; identity flagged authenticated only after success |
| JSONResearchBridge | Local JSON export | None | Versioned citation payload, excludes PDF file URLs |

There are no dummy Crossref, Semantic Scholar or journal adapters pretending to work. Future EditorialManagerConnector, ScholarOneConnector and EmailConnector should be separate modules/types with independent verification. Browser sessions and password storage are excluded from v0.1. A future local bridge must require explicit user opt-in and a separate security/compatibility review.

## Caching

Saved research, snapshots, baselines and events are the offline cache. Refresh is manual or once on launch if the last attempt is at least 24 hours old and automatic refresh is enabled. Failed attempts also advance this threshold to avoid repeated requests. Weekly activity counts newly detected citation IDs, not an inferred citation-count subtraction. First monitoring is silent. Large raw-response caches, eviction and incremental Zotero versions are future work.

## PDF attachments

ZoteroProvider attaches `zotero-pdf` source references to their parent object. ZoteroAttachment validates a scoped source identifier, uses only the documented file endpoint, streams to the local cache and verifies available MD5 metadata. Download redirects reconstruct requests without API credentials and accept only HTTPS Zotero/storage hosts. Link-mode `linked_url` records never become downloads. UI opens a stable ReaderSession after the connector returns a local URL; the connector does not depend on PDFKit or UI internals. See [Reading Environment](READING_ENVIRONMENT.md).

## Submission URLs

`SubmissionLinkProvider` identifies official platform hosts, retrieves OpenReview public notes/decisions through API v2 and reads public citation meta tags on other websites. It never reads private journal sessions. See [file-first workflow](FILE_FIRST_WORKFLOW.md) for supported operations and unknown-date semantics.

## Project discovery

Implement `DiscoveryProvider.discover(DiscoveryRequest)` to return public `DiscoveryBatch` metadata. Do not accept ProjectResearchProfile in a network connector: it contains local/private text. DiscoveryRequest is an allowlist of up to five public DOI/OpenAlex seed identifiers. OpenAlexDiscoveryProvider uses official ID-based related/citing/topic/author queries with a 200-candidate bound. Ranking and claim keyword matching belong to AcaCore's local DiscoveryCache builder, not the transport or view. Treat failed subrequests as an unsuccessful batch; retain the previous local baseline. Keep provider IDs separate in feedback, caches and snapshots. See ADVANCED_RESEARCH.md for scope changes, silent baselines and at-most-once aggregate notifications.

## Local Research Mark documents

`ResearchMarkProjectReader.readProject(at:)` returns a validated schema-v1 ResearchMarkExchange. AcaTexProjectReader only reads the explicitly selected local native document (100 MB maximum); it does not follow source links, upload content or create an account. Keep paragraph anchor decoding inside the adapter, identity/conflict handling in AcaCore and routing/UI in the macOS target. Preserve external IDs exactly. Unknown formats, duplicate IDs and malformed files must fail without replacing the saved local database. See ACATEX_RESEARCH_MARKS.md for three-way merge and explicit outbound review.
