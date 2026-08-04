// codepet/Views/Settings/NotificationsPanel.swift
import SwiftUI

/// The two notification categories that actually exist. No email channel — Codepet has
/// no email infrastructure, and a dropdown offering "Email" would lie about what the
/// app can do.
enum NotificationCategory: String, CaseIterable, Identifiable {
    case sessionNudges, runFinished

    var id: String { rawValue }
    var key: String { rawValue }

    func title(_ lang: AppLanguage) -> String {
        switch self {
        case .sessionNudges: return lang == .vi ? "Nhắc nghỉ" : "Session nudges"
        case .runFinished:   return lang == .vi ? "Chạy xong" : "Run finished"
        }
    }

    func description(_ lang: AppLanguage) -> String {
        switch self {
        case .sessionNudges:
            return lang == .vi ? "Khi bạn đã lập trình một lúc lâu."
                               : "When you've been coding for a long stretch."
        case .runFinished:
            return lang == .vi ? "Khi một việc đang chạy hoàn tất."
                               : "When a run you started completes."
        }
    }

    /// An absent choice means in-app — the behaviour that existed before this panel.
    func channel(in prefs: FounderPrefs) -> NotificationChannel {
        prefs.notifications[key] ?? .inApp
    }

    /// The notifications map that results from choosing `channel` for this category — the
    /// whole of what `NotificationsPanel`'s picker decides, extracted so a test can drive
    /// the real rule instead of re-typing it.
    ///
    /// Choosing the DEFAULT (`.inApp`) REMOVES the key rather than writing `.inApp`
    /// explicitly. An absent key is what makes the "absent means in-app" contract in
    /// `channel(in:)` real, and it is the only shape that reads back as the default on a
    /// document written before this panel existed. The inverse of `channel(in:)`: for every
    /// channel `c`, `channel(in:)` over `applying(c, to:)` is `c` again.
    func applying(_ channel: NotificationChannel,
                  to notifications: [String: NotificationChannel]) -> [String: NotificationChannel] {
        var next = notifications
        if channel == .inApp {
            next.removeValue(forKey: key)
        } else {
            next[key] = channel
        }
        return next
    }
}

/// What notifications the founder's team can send, and through what channel. Two
/// categories only (session nudges, run finished) because those are the two that exist —
/// no email channel, because Codepet has no email infrastructure to send it through.
///
/// Holds a local draft rather than binding the pickers straight to `companyStore`, same
/// reason as `AISettingsPanel`: `setFounderPrefs` only updates `company.founderPrefs`
/// AFTER its Firestore await returns, so a directly-bound control would visibly snap
/// back to the old value for the length of that write.
///
/// "Back to default" REMOVES the category's key rather than writing `.inApp` explicitly.
/// An absent key is what makes the "absent means in-app" contract in `NotificationCategory
/// .channel(in:)` real, and `saveFounderPrefs` writes `founderPrefs` with `mergeFields`
/// (whole-field replace, not a deep merge — see its doc comment), so a removed key
/// actually disappears from the document instead of surviving as a stale entry.
struct NotificationsPanel: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang

    @State private var notifications: [String: NotificationChannel] = [:]
    @State private var loaded = false

    var body: some View {
        SettingsGroup {
            ForEach(Array(NotificationCategory.allCases.enumerated()), id: \.element.id) { idx, cat in
                if idx > 0 { SettingsDivider() }
                SettingsRow(label: cat.title(lang), description: cat.description(lang)) {
                    Picker("", selection: Binding(
                        get: { notifications[cat.key] ?? .inApp },
                        set: { channel in
                            // The rule (including "back to default removes the key") lives in
                            // `applying(_:to:)`, where a test can reach it — see its doc comment.
                            notifications = cat.applying(channel, to: notifications)
                            commit()
                        }
                    )) {
                        Text(lang == .vi ? "Tắt" : "Off").tag(NotificationChannel.off)
                        Text(lang == .vi ? "Trong ứng dụng" : "In-app").tag(NotificationChannel.inApp)
                    }
                    .labelsHidden().frame(width: 150)
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            notifications = companyStore.company.founderPrefs.notifications
            loaded = true
        }
    }

    /// Dropdowns commit immediately on change — same as `AISettingsPanel`'s pickers —
    /// there is no text field here to debounce.
    private func commit() {
        guard loaded else { return }
        var prefs = companyStore.company.founderPrefs
        guard prefs.notifications != notifications else { return }
        prefs.notifications = notifications
        Task { await companyStore.setFounderPrefs(prefs) }
    }
}
