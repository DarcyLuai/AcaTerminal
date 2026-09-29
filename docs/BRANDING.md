# AcaTerminal application icon

The supplied open-book artwork is used only as the macOS application icon (Dock, Finder, app switcher and system application information). It is not displayed as an in-app logo, reader ornament, sidebar image or splash screen.

On 2026-09-28, the user requested removal of the white background. The current `Resources/AppIcon.png` is a transparent-background derivative: the book, silver page and gold stroke/star remain; the surrounding white canvas and ivory tile are removed. `scripts/build-icon.sh` uses Apple's `sips` and `iconutil` to produce the required icon sizes while retaining alpha.

## Editing provenance

- Original: user-supplied icon in this conversation.
- Tool: built-in imagegen (background extraction), no external source artwork.
- Final asset: `Resources/AppIcon.png`.
- Final prompt:

> Remove the entire background from the input icon. Extract ONLY the central open-book emblem and its gold diagonal swoosh and four-point star onto true transparency. REMOVE BOTH the outer white canvas AND the ivory rounded-square tile behind the book. No tile, no plate, no rectangle, no container, no floor, no cast shadow. Preserve the original open-book silhouette: dark navy left page/cover, gently curved pale silver-gray right page, gold diagonal arc ending in gold four-point star over the right page. Preserve the detailed original book shape and proportions. Center this standalone emblem in a square transparent canvas, enlarge it to occupy about 80% of the canvas height. Edges must be clean smooth antialiasing, NO white fringes or stray isolated pixels. All pixels outside the book/gold shapes transparent. Right page is part of the book, keep it. No text, no extra objects.

The code's GPL-3.0 license does not make a separate claim about the provenance or redistribution rights of user-supplied artwork.
