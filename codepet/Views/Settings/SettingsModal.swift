// codepet/Views/Settings/SettingsModal.swift
import SwiftUI

/// The centered settings modal: scrim + panel, rail on the left, scrolling panel on the
/// right. Deliberately NOT a `.sheet` — a macOS sheet is window-attached and descends
/// from the titlebar, so it cannot be centered.
struct SettingsModal: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang

    /// Mirrors `companyStore.settingsSection` while open. The modal is only built when
    /// that value is non-nil, so the initial value is never used blind.
    @State private var selection: SettingsSection

    init(initial: SettingsSection) { _selection = State(initialValue: initial) }

    var body: some View {
        GeometryReader { geo in
            let size = ShellLayout.settingsPanelSize(forWidth: geo.size.width,
                                                     height: geo.size.height)
            let railCollapsed = ShellLayout.settingsRailCollapsed(forWidth: geo.size.width)

            ZStack {
                // Scrim: dismisses on click.
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .onTapGesture { companyStore.closeSettings() }

                panel(railCollapsed: railCollapsed)
                    .frame(width: size.width, height: size.height)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(CodepetTheme.pageBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(CodepetTheme.hairline, lineWidth: 1)
                    )
                    .codepetShadow(CodepetTheme.floatingShadow)
            }
        }
        // Escape closes. `onExitCommand` only fires when the modal owns the focused
        // responder, so a zero-size cancel-action button backs it up the same way
        // `AppShellView` routes ⌘B — the shortcut is live for as long as the modal is
        // in the tree, and both paths land on the same idempotent `closeSettings()`.
        .onExitCommand { companyStore.closeSettings() }
        .background(
            Button("") { companyStore.closeSettings() }
                .keyboardShortcut(.cancelAction)
                .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
        )
        // A deep link (or the account menu) can call `openSettings(_:)` while the modal
        // is already up. The overlay keeps its identity across that change, so `initial`
        // is not re-read — this is what actually moves the panel.
        .onChange(of: companyStore.settingsSection) { _, section in
            if let section { selection = section }
        }
    }

    @ViewBuilder private func panel(railCollapsed: Bool) -> some View {
        HStack(spacing: 0) {
            if !railCollapsed {
                SettingsRail(selection: $selection)
                SettingsDivider(axis: .vertical)
            }
            VStack(spacing: 0) {
                header(railCollapsed: railCollapsed)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        SettingsPanelHeader(title: selection.title(lang),
                                            subtitle: selection.subtitle(lang))
                        sectionBody(for: selection)
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
                }
            }
        }
    }

    /// Close button, plus the section dropdown that replaces the rail on a narrow window.
    @ViewBuilder private func header(railCollapsed: Bool) -> some View {
        HStack {
            if railCollapsed {
                Picker("", selection: $selection) {
                    ForEach(SettingsSection.allCases) { s in
                        Text(s.title(lang)).tag(s)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
            }
            Spacer()
            Button { companyStore.closeSettings() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(CodepetTheme.mutedText)
            }
            .buttonStyle(.plain)
            .help(lang == .vi ? "Đóng" : "Close")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    @ViewBuilder private func sectionBody(for section: SettingsSection) -> some View {
        switch section {
        case .preferences: PreferencesPanel()
        case .company: CompanyPanel()
        case .billing: BillingPanel()
        case .usage: UsagePanel()
        case .support: SupportPanel()
        case .advanced: AdvancedPanel()
        case .aiSettings, .memory, .notifications:
            // Claimed by Tasks 9, 11 and 12. No `default:` here on purpose — the switch
            // stays compiler-exhaustive so each of those tasks has to come here and take
            // its case rather than inheriting a placeholder forever.
            Text(lang == .vi ? "Đang chuyển sang cửa sổ này." : "Moving into this window.")
                .font(CodepetTheme.inter(13))
                .foregroundColor(CodepetTheme.mutedText)
        }
    }
}
