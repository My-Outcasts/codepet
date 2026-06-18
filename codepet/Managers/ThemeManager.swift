import SwiftUI

/// Manages light/dark mode theming across the app.
/// Access colors via `ThemeManager.shared.colors(for: appState.isDarkMode)`
class ThemeManager {

    static let shared = ThemeManager()

    struct ThemeColors {
        let background: Color
        let cardBackground: Color
        let textPrimary: Color
        let textSecondary: Color
        let textMuted: Color
        let divider: Color
        let energyBarTrack: Color
        let shadow: Color
        let loreBackground: LinearGradient
        let accentGold: Color
        let accentGreen: Color
        let accentRed: Color
    }

    // MARK: - Light Theme (Purple)
    let light = ThemeColors(
        background: Color(hex: "#F0EDF8"),
        cardBackground: Color(hex: "#F7F5FC"),
        textPrimary: Color(hex: "#2D2B3E"),
        textSecondary: Color(hex: "#2D2B3E").opacity(0.6),
        textMuted: Color(hex: "#2D2B3E").opacity(0.4),
        divider: Color(hex: "#D5D0E8"),
        energyBarTrack: Color(hex: "#D5D0E8"),
        shadow: Color(hex: "#2D2664").opacity(0.05),
        loreBackground: LinearGradient(
            colors: [Color(hex: "#1a1a2e"), Color(hex: "#16213e"), Color(hex: "#0f3460")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        accentGold: Color(hex: "#FFB800"),
        accentGreen: Color(hex: "#34C759"),
        accentRed: Color(hex: "#E06050")
    )

    // MARK: - Dark Theme
    let dark = ThemeColors(
        background: Color(hex: "#1C1C1E"),
        cardBackground: Color(hex: "#2C2C2E"),
        textPrimary: Color(hex: "#F5F5F5"),
        textSecondary: Color(hex: "#F5F5F5").opacity(0.65),
        textMuted: Color(hex: "#F5F5F5").opacity(0.4),
        divider: Color(hex: "#3A3A3C"),
        energyBarTrack: Color(hex: "#3A3A3C"),
        shadow: Color.black.opacity(0.2),
        loreBackground: LinearGradient(
            colors: [Color(hex: "#0D0D1A"), Color(hex: "#0E1525"), Color(hex: "#081A35")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ),
        accentGold: Color(hex: "#F0B429"),
        accentGreen: Color(hex: "#7EE088"),
        accentRed: Color(hex: "#FF6B6B")
    )

    func colors(for isDark: Bool) -> ThemeColors {
        isDark ? dark : light
    }
}

// MARK: - Theme Environment Key

struct ThemeColorsKey: EnvironmentKey {
    static let defaultValue: ThemeManager.ThemeColors = ThemeManager.shared.light
}

extension EnvironmentValues {
    var theme: ThemeManager.ThemeColors {
        get { self[ThemeColorsKey.self] }
        set { self[ThemeColorsKey.self] = newValue }
    }
}

// MARK: - View Modifier for easy theming

struct ThemedBackgroundModifier: ViewModifier {
    let isDark: Bool

    func body(content: Content) -> some View {
        let colors = ThemeManager.shared.colors(for: isDark)
        content
            .background(colors.background)
            .environment(\.theme, colors)
            .preferredColorScheme(isDark ? .dark : .light)
    }
}

extension View {
    func themed(isDark: Bool) -> some View {
        modifier(ThemedBackgroundModifier(isDark: isDark))
    }
}
