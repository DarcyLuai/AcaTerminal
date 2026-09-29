import Foundation
import AppKit

@main struct AppearanceChecks {
    static func main() throws {
        guard CommandLine.arguments.count == 3, let bundle = Bundle(path: CommandLine.arguments[1]) else { fatalError("Usage: AppearanceChecks app-path source-icon-path") }
        func require(_ value: Bool, _ text: String) { if !value { fatalError(text) }; print("PASS " + text) }
        for (key, expected) in [("Settings", "设置"), ("Interface language", "界面语言"), ("Open Reader", "打开阅读器"), ("Privacy & Data…", "隐私与数据说明…"), ("Add Evidence", "添加证据")] {
            require(L10n.text(key, language: "zh-Hans", bundle: bundle) == expected, "Chinese resource: " + key)
            require(L10n.text(key, language: "en", bundle: bundle) == key, "English resource: " + key)
        }
        let chinese = NSDictionary(contentsOfFile: bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "zh-Hans")!) as! [String:String]
        let english = NSDictionary(contentsOfFile: bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en")!) as! [String:String]
        require(Set(chinese.keys) == Set(english.keys), "English and Chinese key coverage matches")
        require(String(format: chinese["%d papers · %d claims"]!, 31, 7) == "31 篇文献 · 7 个论点", "Localized count formatting")
        let title = "Researcher's original title 原文"
        require(String(format: chinese["Add to %@"]!, title).contains(title), "Authored research title is preserved")
        let image = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))!
        require(image.hasAlpha, "App icon has an alpha channel")
        require([(0,0),(image.pixelsWide-1,0),(0,image.pixelsHigh-1),(image.pixelsWide-1,image.pixelsHigh-1)].allSatisfy { image.colorAt(x: $0.0, y: $0.1)!.alphaComponent == 0 }, "All icon corners are fully transparent")
        require(image.colorAt(x: image.pixelsWide / 3, y: image.pixelsHigh / 2)!.alphaComponent > 0.9, "Book artwork remains opaque")
    }
}
