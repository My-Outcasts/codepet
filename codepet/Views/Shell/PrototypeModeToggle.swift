// codepet/Views/Shell/PrototypeModeToggle.swift
#if DEBUG
import SwiftUI

/// The prototype switch, as one control mounted in two shells.
///
/// It first went into `AccountMenuView` only — which is the OLD shell's top bar. The
/// two-mode rail's account row opens the settings modal instead, so the switch was
/// invisible from the surface it exists to serve. One view, two mounts, rather than
/// two copies that drift.
///
/// A `Toggle`, not a menu row, because this is a STATE that has to be readable at a
/// glance: "am I looking at fixtures or at my company" is the one question a demo
/// mode must never leave ambiguous, and an action row answers it only for as long as
/// you remember which way you left it.
struct PrototypeModeToggle: View {
    /// The rail has ~200pt and its own type scale; the menu is 230pt with a caption.
    var compact = false

    @EnvironmentObject private var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(isOn: Binding(
                get: { companyStore.prototypeModeOn },
                set: { on in Task { await companyStore.setPrototypeMode(on) } }
            )) {
                Text(lang == .vi ? "Chế độ nguyên mẫu" : "Prototype mode")
                    .font(CodepetTheme.inter(compact ? CodepetType.subheadline : 13,
                                             weight: .medium))
                    .foregroundColor(companyStore.prototypeModeOn
                                     ? CodepetTheme.accentPurple : CodepetTheme.bodyText)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            // Disabled WITH its reason rather than hidden: a switch that vanishes is
            // indistinguishable from one that was never built, and you would go
            // looking for it.
            .disabled(PrototypeMode.isLocked)
            Text(caption)
                .font(CodepetTheme.inter(CodepetType.footnote))
                .foregroundColor(CodepetTokens.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Says what the mode does and never claims more. The write sentence is the
    /// load-bearing one — it is the reason this is safe to leave switched on.
    private var caption: String {
        if PrototypeMode.isLocked {
            return lang == .vi
                ? "Bật bằng tham số khởi chạy — khởi động lại không kèm cờ để tắt."
                : "Held on by a launch argument — relaunch without it to switch off."
        }
        return companyStore.prototypeModeOn
            ? (lang == .vi
               ? "Công ty mẫu, 0 tín dụng. Không ghi gì lên tài khoản của bạn."
               : "A fixture company, 0 credits. Nothing is written to your account.")
            : (lang == .vi
               ? "Chạy toàn bộ sản phẩm trên dữ liệu mẫu."
               : "Runs the whole product on fixtures.")
    }
}
#endif
