import Foundation

/// The streaming-state label copy. Pure + localized. Names the in-flight work
/// when a real title exists; otherwise a generic, honest verb — never fabricate
/// a task name.
enum ChatThinkingLabel {
    static func text(taskTitle: String?, language: AppLanguage) -> String {
        let title = taskTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let title, !title.isEmpty {
            return language == .vi ? "Đang soạn \(title)…" : "Drafting \(title)…"
        }
        return language == .vi ? "Đang xử lý…" : "Working on it…"
    }
}
