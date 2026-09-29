import Foundation

/// UI localization only. Provider identifiers and research content are never translated.
enum L10n {
    static var identifier: String {
        let selected = UserDefaults.standard.string(forKey: "interfaceLanguage") ?? "system"
        if selected != "system" { return selected == "zh-Hans" ? "zh-Hans" : "en" }
        return Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "zh-Hans" : "en"
    }
    static var locale: Locale { Locale(identifier: identifier) }
    static var isChinese: Bool { identifier == "zh-Hans" }
    static var resources: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }
    static func text(_ key: String, language: String? = nil, bundle: Bundle? = nil) -> String {
        guard let path = (bundle ?? resources).path(forResource: language ?? identifier, ofType: "lproj"), let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }
}
func tr(_ key: String) -> String { L10n.text(key) }
func trf(_ key: String, _ values: CVarArg...) -> String { String(format: tr(key), locale: L10n.locale, arguments: values) }
func pageLabel(_ page: String) -> String { trf("Page %@", page) }
