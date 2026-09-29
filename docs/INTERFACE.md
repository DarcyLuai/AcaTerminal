# Interface refinement — 2026-09-28

## Language

Settings → General → Interface language offers Follow System, English and 简体中文. Switching takes effect immediately and persists in UserDefaults. UI resources live under `Sources/AcaTerminal/Resources/{en,zh-Hans}.lproj`. Both the direct packager and SwiftPM include them.

Localization is an app-layer concern. Model identities, provider IDs, journal raw statuses, paper titles, quotations, claims and notes retain their original content. The language changes without changing ReaderSession/PDFDocument identity. Native system dialogs follow macOS language rules; service-provided technical error details may retain their original language.

## Layout

Settings and service connections use aligned label/control rows, fine dividers, consistent 42-point controls and 40-point spacing between sections. The content column is bounded, with comfortable margins and restrained 12–14 point typography. The reference screenshot supplied by the user informs spacing and hierarchy; no AcaTex code or assets are copied.

The Reader opens with the PDF centered and both side panels closed. Outline and Research remain one click away; Focus still retains/restores each pane's prior visibility. The top toolbar is quiet, zoom actions move into the overflow menu, and Highlight appears with a selection. The bottom shows page/progress and pending saves only. Permanent instructional paragraphs are removed from the reading surface.

## Application information and sample removal

The AcaTerminal menu contains About AcaTerminal and Privacy & Data. Local storage/privacy, original-PDF preservation, connector limitations, attribution and developer-release information live there rather than occupying working pages.

The production sample workspace, sample seed generator, command-line demo mode, sample banner, sample switcher and promotional footer were removed. A new workspace starts empty. Old `demo.sqlite` files are not opened by the app; historical files and user research are not destructively erased. Test fixtures remain confined to test scripts and isolated test directories.

The white icon background was removed; the image remains exclusive to the macOS system app icon. See [icon provenance](BRANDING.md).
