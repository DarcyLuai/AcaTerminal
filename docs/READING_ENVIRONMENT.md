# AcaTerminal Reading Environment

Library → Paper → Reader → Evidence / Claim → Project.

## Everyday use

Import a PDF with the Library document-plus button, attach a PDF to an existing paper from its detail menu, or import a Zotero library with PDF attachments. Double-click a Library paper or choose **Open Reader**. Metadata-only records explain how to attach a PDF; no publisher content is fetched automatically.

The reader uses macOS PDFKit continuous vertical scrolling. Both side panes begin closed, leaving a centered reading surface. Outline, Pages and Figures share the left pane; the research inspector occupies the right. Each side pane has its own toolbar toggle. Figures lists PDF bookmarks explicitly labeled as figures; it does not invent a figure index for unstructured PDFs. Pages displays lazy thumbnails from a separate background document with a 12-image cache.

Select text for **Highlight / Evidence / Claim / Note / Copy**:

- Evidence retains the source quote, paper, physical page or page range, normalized line rectangles and document fingerprint. Select a Project and optionally a Claim. An unassigned excerpt remains visible in that Project.
- Claim displays the source statement separately and requires the researcher to enter **My Claim**. The original statement is saved as supporting evidence; quotation never silently becomes the user's claim.
- Note keeps user text separate from the selected source statement and page.
- Drag evidence from the inspector onto a claim in the same Project. Duplicate attachment is ignored; cross-project attachment is rejected. Projects also provides an explicit Attach to Claim menu.
- Highlights are local sidecar records. PDFKit annotations are added to the in-memory document only; the original file is never rewritten and no annotations are uploaded to Zotero.

`⌘F` searches the current PDF using PDFKit's asynchronous search. Result count updates as pages are searched; arrows or Return navigate. Short crossfades avoid a long journey through a large document. Image-only scans require an existing text layer for text selection/search; OCR is not shipped.

`⇧⌘F` toggles Focus. Side panes contract/fade over 260 ms; the reader centers within the chosen width. Exiting restores the previous panel visibility. Reduced Motion removes panel animation and search transitions. Back, title, search, highlight and note remain available. UI changes keep the same PDFView and PDFDocument.

## Appearance and preferences

System, Light, Eye Comfort and Dark are persisted in UserDefaults. Eye Comfort uses warm gray paper surroundings and high-contrast text; it is not a claim of medical benefit. It does not tint figures, photographs or formulas. **Paper Tint remains off in this version**: there is no page-wide filter. A future selective tint needs to preserve figure colors before it can be enabled.

Settings includes reading width, page gap, restore position, smooth navigation, reading progress, selection toolbar and automatic Project selection. These settings do not alter original PDFs. App artwork is still used only for the macOS app icon, never as a reader logo. Its white background has been removed. Settings and Reader support English and 简体中文; application declarations live in the macOS AcaTerminal menu.

## Position and persistence

A reading record stores paper UUID, SHA-256 document identity, zero-based physical page, normalized vertical/horizontal anchor, zoom, reader mode, last-open time and manual Read state. Page labels shown to the researcher are one-based physical page numbers; printed pagination may differ. Different file content gets a different identity so old highlights/positions are not applied to the wrong revision.

Position updates are debounced by 1.2 seconds and flushed when leaving the reader, changing active app, or quitting. A serial utility queue handles SQLite, validation and JSON encoding. Status distinguishes pending saves; failed writes keep in-memory changes exportable via Settings → Export Research Snapshot. Quit waits for queued writes and offers Keep Open or Export and Quit after a save failure. A snapshot is a recovery artifact, not an automatic merge/import feature.

Payload formats 1/2 upgrade to 3 on load without replacing research. Optional new fields allow old records to decode; the explicit migration assigns legacy evidence to its unique owning project when possible. Cross-project legacy evidence remains unassigned rather than guessing ownership. SQLite table schema remains version 1. Back up before running a new developer build; an older binary cannot read format 3 after the first save.

## Zotero attachment boundary

PDF attachment metadata is linked to the parent ResearchObject during import; standalone PDF attachments become library objects. On Open Reader, the official `/users/{id}/items/{key}/file` endpoint downloads a PDF to local Application Support/Attachments. Local API support depends on the installed Zotero version and enabled local access. Web API downloads use the saved read-only key; file access permission is required.

Downloads stream to disk, verify PDF signature bytes and compare an available MD5 version hash. Cache names include source identity and version/hash. Redirects permit HTTPS Zotero/storage hosts only and reconstruct the request without API credentials. Linked publisher URLs are excluded. WebDAV-only, unavailable or unsupported local files produce an explanation and a manual attachment path. No private account or live attachment service was used in verification.

## Official references

- [Apple PDFKit / PDFView](https://developer.apple.com/documentation/pdfkit/pdfview)
- [Apple HIG: Motion](https://developer.apple.com/design/human-interface-guidelines/motion)
- [SwiftUI accessibilityReduceMotion](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion)
- [Zotero documented attachment download](https://www.zotero.org/support/dev/web_api/v3/file_upload#ii_download_the_existing_file)

These references guide an independent implementation. No prior-art source code, browser session extraction or third-party rendering engine is included.
