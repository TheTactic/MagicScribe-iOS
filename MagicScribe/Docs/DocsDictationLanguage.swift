import Foundation

/// en/es/fr — mirrors web's `localStorage['ms_docs_dictation_lang']`.
/// Persisted via @AppStorage directly in DocsEditorView (RawRepresentable
/// String enums work natively with @AppStorage, no wrapper needed). Never
/// affects magic-command matching — always English, already true of
/// MagicCommandParser.
nonisolated enum DocsDictationLanguage: String, CaseIterable, Identifiable {
    case en, es, fr

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .en: "English"
        case .es: "Español"
        case .fr: "Français"
        }
    }

    var flag: String {
        switch self {
        case .en: "🇬🇧"
        case .es: "🇪🇸"
        case .fr: "🇫🇷"
        }
    }
}
