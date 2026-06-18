import Foundation

/// User-facing display language for the app's own copy (demo content,
/// localized SwiftUI strings). Separate from `languagePersona`
/// (developer/etc.), which controls *tone* not *language*.
///
/// Production AI enrichers (NarrativeEnricher, SessionSummaryEnricher)
/// also respect this setting — ReflectionComposition.updateLanguage()
/// syncs it whenever the user switches language.
enum AppLanguage: String, Codable, CaseIterable, Identifiable, Hashable {
    case vi
    case en

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vi: return "Tiếng Việt"
        case .en: return "English"
        }
    }

    var flag: String {
        switch self {
        case .vi: return "🇻🇳"
        case .en: return "🇺🇸"
        }
    }
}

/// A pair of strings (Vietnamese + English) used to attach UI copy to a
/// data structure without hardcoding either language at the call site.
struct L10n: Hashable {
    let vi: String
    let en: String

    func callAsFunction(_ language: AppLanguage) -> String {
        switch language {
        case .vi: return vi
        case .en: return en
        }
    }
}

// MARK: - SwiftUI environment integration

import SwiftUI

private struct UILanguageKey: EnvironmentKey {
    static let defaultValue: AppLanguage = .vi
}

extension EnvironmentValues {
    /// Current UI language injected by `CodePetApp` from `AppState.uiLanguage`.
    /// Views can read this with `@Environment(\.uiLanguage)` and pass it to
    /// `L10n` instances at render time. Cheap and avoids `@EnvironmentObject`
    /// dependency just for a single string.
    var uiLanguage: AppLanguage {
        get { self[UILanguageKey.self] }
        set { self[UILanguageKey.self] = newValue }
    }
}
