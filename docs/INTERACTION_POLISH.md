# Interaction polish — build 6

2026-09-29. UI-only refinement of the existing MVP; no Core model, connector contract or database migration changes.

## Changes

- Theme options own their full 40-point-high rectangle, including text, whitespace and edges. Decorative borders do not intercept pointer events. Four equal-width options have no inactive padding gaps.
- `AcaButtonStyle` gives custom row/toolbar controls a restrained hover background, immediate pressed feedback and a persistent selected background. Native bordered buttons retain macOS feedback. Reader icon targets are 32 × 32 points.
- `DisclosureHeader` and `AcaDisclosure` put the title on the left and chevron on the right. The entire header is a button. Settings groups, optional submission details and full-text service status share this pattern. Accessibility exposes expanded/collapsed state.
- Settings checkboxes use one full-row action, eliminating nested hit targets. Label, center whitespace and checkbox edge all perform the same single toggle.
- Settings dropdowns use a native `NSPopUpButton` across the control width, including the trailing arrow. This also provides native keyboard and focus behavior.
- AcaMotion owns 120 ms feedback, 220 ms selection/page transitions and 240 ms panels. Reduce Motion removes panel movement and hover interpolation and uses a short 100 ms opacity transition where continuity helps. No springs or decorative scaling were added.
- Theme state changes immediately. Animation is scoped to selected backgrounds and page surfaces; it does not wrap the native window appearance transaction. Page changes use an overlapping opacity transition instead of stacking incoming/outgoing layouts.
- Reader panel visibility disables hit testing for hidden panels. Reader close/open transitions use the shared tokens while retaining PDFKit and reading-position behavior.
- Full-text opening shows progress beside the active action and suppresses repeated opening while busy. Notification permission requests show progress and reject duplicates. Submission URL lookup now also guards repeated invocation in the action itself.

## Mouse verification

Performed in an isolated app bundle and workspace, using the packaged build. No real research database was opened. Theme cases below used actual mouse coordinates derived from the visible 2× screenshot, not accessibility activation of the button.

| Control / scenario | Observed result |
| --- | --- |
| System / Light / Eye Comfort / Dark — center | All 4 selections succeeded |
| Same 4 options — whitespace beside text | All 4 selections succeeded |
| Same 4 options — within 2–3 points of the frame edge | All 4 selections succeeded |
| 9 rapid theme clicks | Last selection (Eye Comfort) correctly remained selected |
| Appearance header center whitespace / far right edge | Collapsed / expanded correctly |
| 10 rapid repeated header clicks | Returned to the expected expanded state, theme selection retained |
| Light / Dark / Eye Comfort, click title then trailing arrow | All 3 collapsed and expanded correctly |
| Restore Position row center whitespace / right edge | Toggled off / on, restored original value |
| Language popup far from its title | Native options menu opened |
| Submission optional details center / right edge | Expanded / collapsed; cancelled without saving a submission |
| Reader outline upper-left button edge | Outline appeared |
| Reader inspector lower-right button edge | Research inspector appeared |
| Focus shortcut enter / exit | Both panels hid and restored |
| Page navigation and PDF import | Settings → Submissions → test PDF Reader completed |

Light, Dark and Eye Comfort were visually inspected. Early QA automation lost its window target while an overly broad theme transaction was in use; animation was narrowed to local surfaces, and the complete theme mouse matrix then passed on the rebuilt app. This is not a frame-rate benchmark or a claim of a complete VoiceOver audit. Reduce Motion behavior is covered by the existing native Reader check plus code inspection of all animation call sites; global OS accessibility preferences were not modified.

## Regression checks

- Build/package succeeded on the installed Swift 5.8.1 toolchain.
- 34 offline behavioral groups passed (research, imports, impact, persistence, OAuth boundaries).
- 17 native Reader assertions passed: 120/320-page and scanned PDF, selection, search, zoom/resize anchors, focus panels, Reduce Motion, highlights and unchanged originals.
- 16 appearance/resource assertions passed, including English/Chinese key coverage and transparent system icon.
- No new tests merely duplicating the styling implementation were added; hit targets were verified using the actual application.

## Files

`Sources/AcaTerminal/DesignSystem.swift` contains the shared hit regions, feedback, headers, toggle rows and native dropdown adapter. Consumers updated: `PreferencesView.swift`, `ImpactPreferences.swift`, `FullTextView.swift`, `SubmissionsView.swift`, `ProjectsView.swift`, `ImpactView.swift`, `ShellView.swift`, `ReaderView.swift`, `ReaderWorkspace.swift`. Motion tokens stay in `ReaderSession.swift`; permission-request progress stays in `ResearchNotifications.swift`. Both localization resources and `Resources/Info.plist` (build 6) were updated.

AcaCore, AcaStorage, AcaConnectors and database format 3 are unchanged. No new dependency, network provider or sample content was added. The deliverable is still a locally signed developer build, not a notarized release.
