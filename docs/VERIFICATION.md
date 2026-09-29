# Build 7 — latest verification

See [Advanced verification](ADVANCED_VERIFICATION.md) for the current 128 checks/assertions, live OpenAlex discovery, performance measurements and remaining Dock/notification acceptance boundaries. Earlier build records follow for history.

# Interaction refinement — build 6

34 behavioral groups, 17 Reader assertions and 16 appearance assertions passed. The actual app passed all 12 theme center/whitespace/edge clicks, rapid theme changes, repeated disclosure toggles, full-row settings actions and Reader panel edge clicks. No database/model changes. See [interaction verification record](INTERACTION_POLISH.md).

# Latest verification — 2026-09-29

Phase A–H: final build passed; 34 offline behavioral groups, 10 impact application integration assertions, 17 PDFKit assertions, 9 document import/menu assertions and 16 appearance assertions passed. OpenAlex/arXiv live checks passed; Unpaywall and actual system notification banner delivery remain explicitly unverified. See [full delivery record](IMPACT_AND_FULL_TEXT.md).

The records below describe earlier milestones and are retained as history.

# Verification — 2026-09-28

## File-first workflow follow-up

See [new workflow verification](FILE_FIRST_WORKFLOW.md#verification): 18 core groups, 9 document checks, native PDFKit regressions and live native UI checks for direct double-click, right-click annotation, note saving without metadata/projects, and URL-first submission with Unknown state.

## Interface refinement follow-up

- Rebuilt the application after the spacing, language, menu, Reader and icon changes; all 15 offline behavioral groups passed.
- Native PDFKit integration checks passed again with the Reader's new initially closed panels. Focus restoration explicitly tests opened panels. The synthetic 320-page, 120-page and 52 MB raster documents prepared in approximately 172, 170 and 227 ms respectively, including the 150 ms layout settle. No frame-rate claim is made.
- Appearance checks validate packaged English/Chinese lookup, matching translation-key coverage, formatted counts and preservation of user-authored titles. The icon has an alpha channel, four fully transparent corners and an opaque book interior. All 16 checks passed.
- Native UI observations confirmed Chinese sidebar labels, menu titles and Add Paper controls. Settings screenshot and live language-switch checks were interrupted by concurrent window interaction and are not claimed as completed visual checks.
- Production sample code and entry points are removed. Historical sample files and real research files are preserved; the application opens only the real workspace.

Earlier sample-workspace checks below describe the previous build, before the sample feature was removed.

## Environment

Apple silicon macOS host; Apple Swift 5.8.1; macOS SDK 13.3. Full Xcode and an iOS SDK are absent. `swift build` reports missing PlatformPath on this Command Line Tools installation. The direct system-compiler build succeeds and produces a native macOS application.

## Passed

- Core compiled independently, then linked into a runnable checkpoint executable.
- Native SwiftUI shell built and launched. Subsequent Library/Projects, connector, Impact and Submission additions were rebuilt successfully.
- Final offline suite: **15 behavioral groups passed**, no external network or real credentials required.
- Live OpenAlex smoke check: DOI `10.1017/S0020818300033324` returned a valid Work and **4,016 citations at test time**. This observation is not seeded into the app or presented as a permanent fact.
- Native UI inspected at 1180×790 points in light and dark appearances. Sidebar, warm paper surface, controls, detail views and Settings were visible.
- In the separate sample workspace: created a paper with title/author/year/venue; saved a note as evidence linked to an existing claim; verified the paper gained claim/project links and the project displayed the evidence.
- Changed a sample submission's raw wording to “Required Reviews Completed”; Suggest mapped it to “Reviews complete”; saved it and inspected the appended timeline while earlier stages remained visible.
- Quit and relaunched the app. The real workspace remained empty. Reopening the sample workspace retained the new paper, evidence/project links and submission timeline.
- Restored system appearance after the dark-mode check. Test-only additions to the sample fixture were removed after saving a verification snapshot outside the deliverable source tree.
- App packaging uses an ad-hoc local signature. FinderInfo metadata in Documents initially prevented signing; the packaging script now removes only signing-incompatible FinderInfo/ResourceFork attributes from its generated bundle. Final `codesign --verify --strict` passed for the delivered bundle.

## Offline suite details

1. DOI/arXiv/ISBN normalization; title-review candidates; conflicting stronger identifiers.
2. Repeat import idempotence, note remapping, preservation of local titles/project membership and atomic ambiguity rejection.
3. Evidence/claim/paper/project associations and dangling-reference rejection.
4. Raw submission text, unknown statuses, change detection, future/backdated-event rejection.
5. SQLite round trip, schema creation, stale-writer protection and invalid-graph rejection.
6. Rejection of future database schema and malformed payload without resetting research.
7. ORCID checksum, redirect identity, state/code uniqueness and callback expiry.
8. Versioned AcaTex exchange and exclusion of local PDF paths.
9. Zotero fixture import spanning two pages, collection mapping, note association, HTML-to-text and header-only credentials.
10. OpenAlex fixture decoding, abstract reconstruction, annual history and provider attribution.
11. ORCID fixture token exchange, form encoding and credential-store separation.

## Not verified / release gates

- Real Zotero account authentication or import against the user's private library. Only synthetic paginated API fixtures were used; the user's Zotero library was not changed.
- Live ORCID OAuth: no registered client, callback or credentials were supplied. The personal developer flow is implemented and fixture-tested; consumer one-click sign-in is not complete.
- Real Keychain token persistence with a production ORCID client, token refresh/revocation, or a production identity session.
- iOS compilation, Intel hardware, full Xcode build, automated accessibility audit, long-running migration history, large-library load/performance, interrupted-system-write fault injection.
- Developer ID signature, notarization, sandboxed distribution and App Store acceptance.
- Real AcaTex ingestion or journal portal automation (not implemented in this scope).

The GitHub Actions workflow is supplied but has not run on a remote repository. Passing local checks is not a claim that these release gates are complete.

## Reading Environment verification

The follow-up implementation is tested with `scripts/check-reader.sh`. Fixtures are generated independently in a fresh run directory: 120 pages, 320 pages with 300 existing annotations, and a 24-page, 52 MB raster-heavy PDF. No copyrighted paper or user library is used.

Passed native PDFKit integration checks:

- First opening starts at the first page's top after layout settles.
- Open 320 pages; navigate to physical page 141; preserve page anchor through zoom and resize.
- Toggle Focus twice; recover prior panels and retain the same PDFDocument identity.
- Asynchronously find all 320 occurrences of a search term; navigate to the next result.
- Reduced Motion disables panel movement.
- Selection records physical page 14, quote and normalized line rectangles.
- Apply sidecar highlights once; verify original PDF bytes are unchanged.
- Close/reopen and restore the persisted page and zoom.
- Open the 120-page and raster-heavy fixtures and navigate rapidly between pages.
- Drain 12 queued background saves in order; reject a stale writer; block subsequent writes after the first failure.

Observed preparation-to-ready times in the local synthetic run, including a 150 ms initial-layout settle: approximately 176 ms (320 pages), 171 ms (120 pages), 224 ms (52 MB raster-heavy file). These are development observations, not benchmarks or a display-refresh-rate guarantee.

Native window checks observed continuous PDF pages, research/outline panes, selection floating controls and keyboard PDF search returning 1 / 320. Light and Dark reader surfaces were inspected. The user was interacting with the window during follow-up checks; an uninterrupted end-to-end popover/drag-drop UI run and Eye Comfort visual audit remain release checks.

Additional core coverage: version-1 payload migration; Project evidence without an existing Claim; idempotent same-project linking; position clamping/read state; official Zotero attachment mapping; rejection of publisher-link downloads; credential stripping on storage redirects.

Still required before making a smoothness claim: Instruments frame/hitch profiling on long real vector/scanned documents, 60/120 Hz displays, sustained scrolling while citation imports complete, and an accessibility audit with system Reduce Motion enabled. Real Zotero attachment downloads have not been tested against a user's account. Paper Tint remains off; OCR and automatic figure extraction are not implemented.
