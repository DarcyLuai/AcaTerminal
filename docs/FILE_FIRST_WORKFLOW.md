# File-first reading and URL-first submissions

## Local documents

Import PDF, DOCX, DOC, RTF or TXT from Library, File → Import Documents (⌘O), Today, or directly into an existing Project. The filename supplies the initial title; author, year, DOI, abstract and paper/book classification are editable later. Metadata-only records remain available in the Library overflow menu. A project is not required for reading, highlighting or notes.

New imports copy the original into the workspace's `Documents/<object UUID>/` folder, off the main thread. A byte-identical PDF is opened directly. Word/RTF/text use Apple's attributed-string importer and Core Text to create a **text reading edition** with selectable pages. This edition intentionally reflows text; it does not promise Word layout, equations, tables or figure fidelity. Embedded image placeholders direct users to the original. The footer identifies the reading edition, and Reader's overflow menu opens the preserved original. Export from Word to PDF before import when original pagination/layout is essential. Both original and reading edition are backed up with the workspace. Pre-existing external-PDF links remain valid and unchanged.

Library uses NSTableView's native doubleAction to open the clicked row directly. Single click selects its metadata. There is no required intermediate detail-page action.

Select text, then right-click for Highlight, Note, Evidence, Claim and Copy. The bottom floating selection toolbar was removed. Notes preserve quote and physical reading-edition page without requiring a project, author or DOI; their inspector page link returns to the source. Evidence/Claim keep their separate project relationships and original-vs-authored text distinction. The original PDF/Word bytes are never edited by annotations.

## Submission links

The first field is the submission URL. Read From URL previews available information; Add Submission also performs lookup before saving a new URL. Optional details are disclosed below, and existing entries support Supplement Details and Refresh From URL. Network failures retain form contents so the user can retry or save supplemented data. Refresh never replaces manually supplied title/journal metadata.

Capabilities are explicit:

- OpenReview public `/forum?id=…` links: official API v2 retrieves title/venue and public Decision replies. Only official `/-/Decision` invitations are considered; comments are not decisions. Unknown raw decisions stay unknown; raw text is preserved. Response-size limits reject incomplete forum histories rather than guessing the latest decision.
- Editorial Manager, ScholarOne, Wiley, Nature, ACS and IEEE: identify the platform and retain its link. Their private submission states are **not automatically retrieved** in this build. There is no session extraction, password storage, private endpoint use or fabricated state. A platform-specific authenticated integration needs the user's actual portal and supported access mechanism.
- Other HTTPS websites: read public `citation_title` / `citation_journal_title` HTML metadata when available. Arbitrary page wording is never normalized into a submission status. Redirects are not automatically followed.

A URL without a readable status starts as **unknown**, not Submitted. If the submission date is not supplied, the local timestamp is labeled **Added** and `submissionDateUnknown` persists this distinction. A fetched decision's timeline timestamp is when AcaTerminal observed it, not a guessed journal decision date. Manual overrides remain possible and record manual provenance.

Official references consulted on 2026-09-28:

- [Apple attributed-string document types](https://developer.apple.com/documentation/foundation/nsattributedstring/documenttype)
- [OpenReview API v2](https://docs.openreview.net/reference/api-v2/openapi-definition)
- [OpenReview note retrieval](https://docs.openreview.net/how-to-guides/data-retrieval-and-modification/how-to-get-all-notes-for-submissions-reviews-rebuttals-etc)
- [Elsevier submission status and login](https://www.elsevier.support/publishing/answer/how-can-i-track-the-status-of-my-submitted-article)

## Verification

`build.sh --check`: 18 offline behavioral groups, including URL validation, platform boundaries, official-decision filtering, raw status, unknown dates, and refusal to scrape private portals.

`check-documents.sh`: 9 checks covering synthetic DOCX import without metadata, unchanged original bytes, selectable multi-page reading edition, source page association, byte-identical PDF copy, managed-file survival after source removal, empty-document cleanup, native menu actions, and TXT reading.

`check-reader.sh`: existing 120/320-page and 52 MB raster PDF tests passed, including zoom/resize/reopening anchors, sidecar highlights and background persistence. No full Word-rendering fidelity or frame-rate guarantee is made.

Native isolated-window QA confirmed direct Library double-click, PDF right-click menu, note editor with selected quote and physical page, saving a note with no project/metadata, and adding an Editorial Manager URL with Unknown status and Added date. Private journal authentication and live OpenReview decision retrieval have not been verified against user accounts.
