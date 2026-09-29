# Main-window lifecycle repair

The previous app was already a regular GUI application, with no LSUIElement or LSBackgroundOnly flag. It kept running after its last window closed but implemented no applicationShouldHandleReopen route. Its only explicit presentation callback was installed by ShellView for citation navigation. Thus there was no owned route from a Dock reopen request to the existing miniaturized main NSWindow or to the closed main Scene. Default AppKit untitled-document behavior is not the lifecycle contract of this single-Window research client.

An important AppKit distinction: hasVisibleWindows can be true for miniaturized windows. The new handler does not use that flag as a proxy for onscreen visibility. MainWindowLifecycle registers the actual main window through a zero-sized SwiftUI/AppKit probe, observes closure, and restores that same window with deminiaturize and makeKeyAndOrderFront. An attached sheet is respected. Settings windows never become the restoration target. Only a genuinely closed main window invokes the existing single Window scene (stable id `main`), with an in-flight guard. The scene retains WorkspaceStore and ReaderSession state. Activation happens on launch or an explicit presentation/reopen request.

AppDelegate's existing terminate-later/save-drain logic is retained. Main-window close saves the current reading position without resetting ReaderSession. There is no new database format or background-app policy in this repair.

Verification: 16 native AppKit lifecycle assertions passed, including yellow-button action, the standard Command-M action, Reader/PDF object identity, PDF search, Focus, sheet open/close, dark/comfort surfaces, hide/unhide, close/recreate, visible Settings, 20 consecutive miniaturize/reopen cycles, background save and quit drain. The checks run a real NSApplication event loop and call the actual delegate reopen handler. They do not simulate pointer input or assume miniaturization completes synchronously.

Verification boundary: the computer-use tool could not expose Dock's windowless accessibility surface. Native tests exercise the delegate against real AppKit windows, including 20 cycles with the same key window. On macOS 15.4.1, a synthetic callback after hiding can restore visibility while cooperative activation declines foreground focus. The hide test therefore asserts restoration of the original visible window and reports active/key state separately; it is not presented as a successful physical Dock click. Two overly strict hide/key test runs failed before this boundary was isolated. No focus-stealing retry loop was added to production.

A separate UI check used Finder's Open action on the already-running QA app, which sends the standard application reopen event. It restored the minimized/hidden main window with the current Library/Project destination intact, and normal navigation resumed. The literal Dock icon hit target, multiple displays/Spaces, and a full physical Dock acceptance matrix remain unverified. A close-window Finder follow-up was interrupted by concurrent user interaction with Finder; the native close/recreate-once test passed. No absolute 100% cross-machine guarantee is claimed.

Apple documents that activation is a request, not a synchronous guarantee: [AppKit activation](https://developer.apple.com/documentation/appkit/nsapplication/activate%28ignoringotherapps%3A%29), [cooperative activation introduction](https://developer-rno.apple.com/videos/play/wwdc2023/10054/).

Reproduce with a new isolated data path:

```
./scripts/build.sh --check
ACATERMINAL_DATA_DIR=/path/to/new/test-workspace ./scripts/check-lifecycle.sh /path/to/test.pdf
```

Official references: [NSApplicationDelegate reopen semantics](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldhandlereopen%28_%3Ahasvisiblewindows%3A%29?language=objc), [OpenWindowAction single-Window semantics](https://developer.apple.com/documentation/swiftui/openwindowaction).
