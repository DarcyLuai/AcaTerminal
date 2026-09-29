# Dependencies

No third-party Swift packages, JavaScript runtimes, vendor code or remote fonts.

| Dependency | Use | Distribution |
| --- | --- | --- |
| Swift / Foundation | Shared value models, Codable, URLSession, dates | Apple toolchain / OS runtime |
| SwiftUI / AppKit / Charts | Native macOS interface and chart | Apple SDK frameworks |
| Security.framework | Apple Keychain | Apple SDK framework |
| SQLite3 | Local transactional persistence | macOS/iOS system library; no bundled source |

Research references in PRIOR_ART.md are not dependencies. No upstream source or assets are included. System frameworks are dynamically resolved by the OS; local Core/Storage/Connectors modules are linked statically by the fallback build script.

Minimum verified toolchain: Apple Swift 5.8.1, macOS SDK 13.3, Apple silicon host. Full Xcode and iOS SDK verification are not available in this environment.
