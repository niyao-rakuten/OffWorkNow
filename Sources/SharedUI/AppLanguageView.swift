import SwiftUI
import WorkdayCore

@MainActor final class AppLanguageStore: ObservableObject {
    static let shared = AppLanguageStore()
    @Published var selection: AppLanguage {
        didSet { UserDefaults.standard.set(selection.rawValue, forKey: L10n.preferenceKey) }
    }
    private init() { selection = L10n.selection }
}

/// Refreshes all native date controls without resetting view identity or settings drafts.
struct AppLanguageView<Content: View>: View {
    @ObservedObject private var language = AppLanguageStore.shared
    @ViewBuilder let content: () -> Content
    var body: some View { content().environment(\.locale, L10n.locale) }
}

struct AppLanguagePicker: View {
    @ObservedObject private var language = AppLanguageStore.shared
    var body: some View {
        Picker(L10n.text("语言"), selection: $language.selection) {
            ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
        }
        Text(L10n.text("立即生效，无需重启。")).font(.caption).foregroundStyle(.secondary)
    }
}
