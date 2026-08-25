// codepet/Managers/ChatThreads.swift
import Foundation

/// Which door a conversation belongs to — spec §10, "one thread collection, one
/// new field".
///
/// Ask's `RECENT` and Developer's `SESSIONS` are two filters over one collection,
/// not two collections. The app had neither: one shared buffer meant a code run
/// described in Developer appended its ask and its result card to the ASK
/// conversation, where the founder found them afterwards sitting between two
/// unrelated questions.
enum ChatThreadKind: String, Codable, Equatable {
    case ask
    case dev
}

/// One session-only chat conversation — a named bucket of `CopilotMessage`s.
/// Deliberately NOT Codable: Level 1 multi-thread history is in-memory only,
/// same as `chatMessages` itself (see `CopilotMessage`'s doc comment). Native
/// port of the web `ThreadMeta` (`lib/firebase/schema.ts`) + its message array,
/// merged into one struct since there's no persistence layer to split them.
struct ChatThread: Identifiable, Equatable {
    let id: String
    /// nil until the founder's first message derives one (or a rename sets a
    /// non-blank title) — rendered as "New chat" by the view, mirrors the web.
    var title: String?
    var messages: [CopilotMessage]
    let createdAt: Date
    var updatedAt: Date
    /// Defaulted so every existing call site keeps meaning what it meant.
    var kind: ChatThreadKind = .ask
}

/// The two filters §10 describes. Pure, because "which list does this thread
/// appear in" is the whole of the data model change and deserves a test that does
/// not need a store.
func threadsOfKind(_ kind: ChatThreadKind, in all: [ChatThread]) -> [ChatThread] {
    all.filter { $0.kind == kind }
}

// Pure, unit-testable helpers behind the thread switcher — ported from the
// web's `lib/chat/threads.ts`. No `CompanyStore`/SwiftUI dependency here so
// they can be exercised without `@MainActor` or any DI stub.

private let threadTitleMax = 40

/// Title a thread from its first founder (`.me`) message — no model call,
/// mirrors the web's `deriveThreadTitle` but reads straight off the message
/// list (the web takes the raw string; native derives it directly since a
/// thread's canonical source of truth is its message array). Whitespace is
/// collapsed to single spaces and the result truncated to ~40 chars with an
/// ellipsis. Returns nil when there is no `.me` message yet, OR its text is
/// blank — the view falls back to "New chat" for either case, same as the web.
func deriveThreadTitle(_ messages: [CopilotMessage]) -> String? {
    guard let first = messages.first(where: { $0.role == .me }) else { return nil }
    let collapsed = first.text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !collapsed.isEmpty else { return nil }
    guard collapsed.count > threadTitleMax else { return collapsed }
    let truncated = String(collapsed.prefix(threadTitleMax)).trimmingCharacters(in: .whitespaces)
    return truncated + "\u{2026}"
}

/// Newest-first by `updatedAt`. Does not mutate the input (mirrors the web).
func sortThreadsByRecent(_ threads: [ChatThread]) -> [ChatThread] {
    threads.sorted { $0.updatedAt > $1.updatedAt }
}

/// After deleting a thread, which thread should become active — the most
/// recently updated of what remains, or nil (→ the caller opens a fresh new
/// chat). Mirrors the web's `pickFallbackThreadId`, argument order flipped to
/// read naturally at the call site (`after:in:`).
func pickFallbackThreadId(after deletedId: String, in threads: [ChatThread]) -> String? {
    sortThreadsByRecent(threads.filter { $0.id != deletedId }).first?.id
}

/// Compact relative time for the history list — "just now" under a minute,
/// then minutes/hours/days. English only (the pure helper stays language-
/// neutral like the rest of `ChatThreads`; the view localizes surrounding
/// copy — "New chat", "Rename", "Delete" — the same way every other Copilot
/// string does). `now` is a parameter (not `Date()` inside) purely for
/// testability — mirrors the web taking `now` as an argument.
func relativeTime(_ date: Date, now: Date) -> String {
    let seconds = max(0, Int(now.timeIntervalSince(date)))
    if seconds < 60 { return "just now" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m ago" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h ago" }
    let days = hours / 24
    return "\(days)d ago"
}
