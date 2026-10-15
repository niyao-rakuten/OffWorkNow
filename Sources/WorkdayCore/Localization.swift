import Foundation

public enum AppLanguage: String, CaseIterable, Identifiable {
    case system, simplifiedChinese = "zh-Hans", english = "en"
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .system: return L10n.text("跟随系统")
        case .simplifiedChinese: return "简体中文"
        case .english: return "English"
        }
    }
    public func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard self == .system else { return self }
        return preferredLanguages.first?.hasPrefix("zh") == true ? .simplifiedChinese : .english
    }
}

/// App-only preference, independent of work schedules and their persisted schema.
public enum L10n {
    public static let preferenceKey = "appLanguage"
    public static var selection: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "system") ?? .system
    }
    public static var locale: Locale { Locale(identifier: selection.resolved().rawValue) }
    private static let catalogs: [String: [String: String]] = {
        var result: [String: [String: String]] = [:]
        for language in ["en", "zh-Hans"] {
            if let url = Bundle.module.url(forResource: language, withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let catalog = try? JSONDecoder().decode([String: String].self, from: data) {
                result[language] = catalog
            }
        }
        return result
    }()
    public static func text(_ key: String, language: AppLanguage? = nil) -> String {
        catalogs[(language ?? selection).resolved().rawValue]?[key] ?? key
    }
    /// Recover a catalog key for a selected canned message without choosing a new message.
    public static func sourceKey(for text: String) -> String {
        if catalogs["zh-Hans"]?[text] != nil { return text }
        return catalogs["en"]?.first(where: { $0.value == text })?.key ?? text
    }
    public static func format(_ key: String, _ arguments: String..., language: AppLanguage? = nil) -> String {
        // Substitute once, so user-provided text resembling a placeholder stays intact.
        let template = text(key, language: language)
        guard let regex = try? NSRegularExpression(pattern: #"\{([0-9]+)\}"#) else { return template }
        let source = template as NSString
        var output = "", cursor = 0
        for match in regex.matches(in: template, range: NSRange(location: 0, length: source.length)) {
            output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let index = Int(source.substring(with: match.range(at: 1)))!
            output += arguments.indices.contains(index) ? arguments[index] : source.substring(with: match.range)
            cursor = NSMaxRange(match.range)
        }
        output += source.substring(from: cursor)
        return output
    }
}
