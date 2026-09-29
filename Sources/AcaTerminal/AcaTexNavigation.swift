import AppKit

/// Capability detection prevents sending exact-mark links to older AcaTex installations.
enum AcaTexNavigation {
    static func compatibleApplication(in candidates: [URL]) -> URL? {
        candidates.first { url in
            guard let bundle = Bundle(url: url), bundle.bundleIdentifier == "com.texflow.academic-editor",
                  let version = bundle.object(forInfoDictionaryKey: "AcaTeXResearchBridgeVersion") as? NSNumber,
                  version.intValue == 1,
                  let types = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] else { return false }
            return types.contains { ($0["CFBundleURLSchemes"] as? [String])?.contains("acatex") == true }
        }
    }

    static func applicationURL(for route: URL, workspace: NSWorkspace = .shared) -> URL? {
        let installed = [URL(fileURLWithPath: "/Applications/AcaTeX.app"),
                         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/AcaTeX.app")]
        let registered = [workspace.urlForApplication(toOpen: route),
                          workspace.urlForApplication(withBundleIdentifier: "com.texflow.academic-editor")].compactMap { $0 }
        return compatibleApplication(in: installed + registered)
    }
}
