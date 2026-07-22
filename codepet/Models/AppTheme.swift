// codepet/Models/AppTheme.swift
import SwiftUI

/// The user's theme preference for the native web-product. `system` follows the
/// macOS appearance; `light`/`dark` force it. Drives `.preferredColorScheme`.
enum AppTheme: String, CaseIterable, Codable {
    case system, light, dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    func label(_ lang: AppLanguage) -> String {
        switch self {
        case .system: return lang == .vi ? "Hệ thống" : "System"
        case .light:  return lang == .vi ? "Sáng" : "Light"
        case .dark:   return lang == .vi ? "Tối" : "Dark"
        }
    }

    /// Cycle order for the tap control: System → Light → Dark → System.
    var next: AppTheme {
        switch self {
        case .system: return .light
        case .light:  return .dark
        case .dark:   return .system
        }
    }
}
