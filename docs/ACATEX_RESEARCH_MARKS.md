# AcaTex ↔ AcaTerminal Research Marks — v0.1 build 11

## User workflow

In Project → ⋯ choose **Connect AcaTex Project…**, then select a saved local `.texflow` / `.acatex` / JSON document. The native adapter reads AcaTeX 0.8.6 paragraph-backed `content.attrs.researchObjects` and resolves their `anchorNodeId` to paragraph text. Save edits in AcaTex; returning to Terminal refreshes the connection. Refresh is also available manually. Unavailable/moved files retain local marks; reconnect the same document ID to relocate it.

Project → 论证 groups Questions, Claims, Hypotheses and Findings. Reader selection → right click → Evidence offers all these project marks and an optional new Claim. Choose a relationship yourself; the default is background. Evidence rows open the original PDF page/selection using the existing Reader.

**Export Research Marks…** writes an explicitly chosen `.acaresearch.json` exchange. In an AcaTex build advertising Research Bridge v1, use **File → Import Research Evidence…**, review the proposed relationships and select the links to retain. This stores evidence locally without rewriting manuscript prose or creating/updating argument marks. Omitted relationships are not deletions. Evidence can be exported from AcaTex for local backup or transfer.

**Open in AcaTex** now dispatches `acatex://research?document=…&mark=…` to an explicitly verified companion application. The app must advertise `AcaTeXResearchBridgeVersion = 1`, the AcaTex bundle identity, and the `acatex` URL scheme. Older installations fall back to Finder with an explanation. Navigation uses the original external mark ID, not the local UUID or display label. AcaTex resolves the local document, protects unsaved edits and navigates to the anchored paragraph. Its evidence panel can return to Terminal's exact source selection.

The companion feature is capability-detected: version number 0.8.6 alone is insufficient. Build 11 has been tested against the locally built AcaTex Research Bridge companion, including installed-app navigation. It does not require a cloud account. Automatic evidence synchronization, applying argument edits to AcaTex and inserting new Claims into a manuscript remain outside this implementation.

The interface shows mark type, text, provenance and necessary change/conflict status. Stable IDs remain internal; no invented visible C1/H1 numbering is added. Details of heuristic discovery connections sit inside the existing “Why this paper?” disclosure. Project navigation remains 文献 / 论证 / 动态.

## Identity and synchronization

- Interchange schema version **1** (`schemas/research-marks-v1.schema.json`); UTF-8 JSON, ISO-8601 timestamps. IDs are document-scoped, independent of visible numbering (C1, H1) and titles.
- One AcaTex document per Terminal project. Reconnecting the same document changes its file location. A document already bound elsewhere is rejected.
- Imported arguments reuse the existing Claim aggregate: optional `markType` distinguishes question/claim/hypothesis/finding; `markStatus` retains status. Existing nil values remain ordinary active Claims.
- `MarkBinding` maps local Claim UUID to unchanged external ID and connection. Native UUIDs are retained if not colliding; labels such as CLAIM-003 are retained verbatim in the binding.
- Three-way comparison uses baseline, current local value and current remote value (type/text/status). Remote-only edits update the same Claim; local-only edits remain pending; divergent edits produce a conflict. Conflicts retain both versions and resolution history. Exports are blocked for unresolved conflict/missing source.
- A sent local mark is pending until the same ID appears in the saved AcaTex document. Sending a file alone is not an acknowledgment. Missing remote marks never delete local work.
- EvidenceRelation is a flat per-evidence/per-mark association. A shared evidence item may qualify one mark and support another. Legacy contradicts remains decodable; new selection uses challenges.
- Local reads and file writes occur off the main thread; the small local merge uses the existing serialized UI-store/save pipeline. Startup, application activation and explicit refresh trigger reads, without continuous polling or cloud services.

## Exact source location and routing

Evidence includes the ResearchObject UUID, physical page label, quote, document fingerprint, and normalized PDF crop-box rectangles (zero-based physical page). Reader first uses matching-document rectangles, then quote lookup on the source page, then a page-only fallback. Scanned PDFs without selectable text do not acquire fabricated text anchors. Changed source files cannot be promised the same selection.

- `acaterminal://paper/<UUID>/evidence/<UUID>` routes only to an existing local evidence/paper pair.
- `acatex://research?document=<encoded ID>&mark=<encoded ID>` is dispatched only to a compatible installed AcaTex application; document and mark IDs are URL-encoded independently.
- Source references and exchange files may include local paths. They are local artifacts, not sent to network providers.

## Storage and privacy

SQLite `user_version` remains **1**, with the existing transactional workspace table. JSON payload format changes **4 → 5**. Connections, bindings, evidence relations, typed marks and discovery hints are optional additions; legacy evidence links are backfilled. Before migration, the original payload is atomically copied to `migration-format-4-<revision>.json`. Existing objects, claims, projects, citation history, notes, bookmarks and source PDFs are not deleted. Older Terminal builds intentionally reject format 5 rather than silently drop fields.

Project Discovery still sends at most five validated public DOI/OpenAlex IDs. Private mark text is only tokenized locally against already retrieved public results. Potential support/challenge/extension labels are keyword heuristics, never scholarly judgments. No AI, no private claims in query strings, no manuscript/PDF uploads. Projects with no public seed IDs cannot perform network discovery. Chinese semantic matching is not implemented; English token heuristics have limited multilingual recall.

## Tests / fixtures

`./scripts/build.sh --check` includes native AcaTex import, stable identity, duplicate prevention, conflicts, export guards, per-mark evidence relationships, persistence, migration, local discovery hints and route parsing. `./scripts/check-research-marks.sh <isolated-dir> prepare` generates a native AcaTex project and an independent PDF, captures a real PDFKit selection, saves SQLite and exports evidence.

These generated fixtures are not demo content inserted into user libraries. Build 9's integration report records the earlier isolated companion experiment; it is historical, not a requirement or current deliverable. See `BUILD10_VERIFICATION.md` for this Terminal-only polish and its verified boundaries.

## Build 11 verification

See [the integration report](BUILD11_VERIFICATION.md). This update adds no database migration: SQLite version 1 and payload format 5 remain unchanged. `scripts/check-acatex-navigation.sh` verifies capability fallback and opaque-ID routing. The Reader layout regression suite verifies that repeated unchanged layouts do not overwrite explicit evidence navigation.
