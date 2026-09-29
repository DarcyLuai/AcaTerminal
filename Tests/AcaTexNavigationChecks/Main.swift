import AppKit
import AcaCore

@main struct AcaTexNavigationChecks {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        func application(_ name: String, version: Int?, scheme: String = "acatex", identifier: String = "com.texflow.academic-editor") throws -> URL {
            let url = root.appendingPathComponent(name + ".app")
            let contents = url.appendingPathComponent("Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            var info: [String: Any] = ["CFBundleIdentifier": identifier, "CFBundlePackageType": "APPL", "CFBundleURLTypes": [["CFBundleURLSchemes": [scheme]]]]
            if let version { info["AcaTeXResearchBridgeVersion"] = version }
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
            return url
        }
        func check(_ pass: Bool, _ message: String) {
            guard pass else { print("FAIL " + message); exit(1) }; print("PASS " + message)
        }
        let old = try application("Old", version: nil), current = try application("Current", version: 1)
        let unsupported = try application("Future", version: 2), wrongScheme = try application("Scheme", version: 1, scheme: "other")
        let wrongApp = try application("Other", version: 1, identifier: "other.application")
        check(AcaTexNavigation.compatibleApplication(in: [old]) == nil, "Older app falls back without dispatching an unsupported route")
        check(AcaTexNavigation.compatibleApplication(in: [old, current]) == current, "Compatible app selected when an old copy is registered")
        check(AcaTexNavigation.compatibleApplication(in: [unsupported, wrongScheme, wrongApp]) == nil, "Unsupported capability, missing scheme and unrelated app rejected")
        let document = "文稿 & /?#", mark = "CLAIM-003 & 研究"
        let route = ResearchRoute.acaTex(documentID: document, markID: mark)
        let components = URLComponents(url: route, resolvingAgainstBaseURL: false)!
        check(components.queryItems == [.init(name: "document", value: document), .init(name: "mark", value: mark)], "Opaque Unicode IDs and reserved characters round-trip without extra parameters")
        check(components.scheme == "acatex" && components.host == "research" && components.fragment == nil, "Exact-mark route contains identity only")
    }
}
