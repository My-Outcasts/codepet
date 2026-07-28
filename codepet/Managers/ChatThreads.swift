// codepet/Managers/ChatThreads.swift
import Foundation

/// One chat conversation — a named bucket of `CopilotMessage`s. Codable so a
/// thread can be persisted to `companies/{uid}/threads/{id}` and hydrated on
/// launch. Native port of the web `ThreadMeta` (`lib/firebase/schema.ts`) + its
/// message array, merged into one struct.
struct ChatThread: Identifiable, Equatable, Codable {
    let id: String
    /// nil until the founder's first message derives one (or a rename sets a
    /// non-blank title) — rendered as "New chat" by the view, mirrors the web.
    var title: String?
    var messages: [CopilotMessage]
    let createdAt: Date
    var updatedAt: Date

    /// A copy safe to PERSIST: drops transient "producing" placeholders (they
    /// exist only mid-run) and clears streaming-only `execSteps`, so a saved
    /// thread never resurrects a half-finished run on the next launch.
    var persistable: ChatThread {
        var copy = self
        copy.messages = messages
            .filter { !$0.producing }
            .map { m in var mm = m; mm.execSteps = nil; return mm }
        return copy
    }
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
    // Prefer the founder's first message; fall back to the first non-empty
    // message of ANY role so a thread that so far only holds byte's seeded
    // question/greeting still gets a distinguishable name instead of "New chat".
    let source = messages.first(where: { $0.role == .me && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        ?? messages.first(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    guard let first = source else { return nil }
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

/// How long after its last message a thread still counts as the founder's
/// current working stretch. Inside it, launch resumes that thread; outside it,
/// launch opens the live hero instead — so quitting and reopening keeps your
/// place, while a new day still starts on the time-of-day greeting and the
/// roadmap landing cards. One constant to tune.
let threadResumeWindow: TimeInterval = 8 * 3600

/// Which thread launch should reopen, or nil to land on the empty hero. The
/// newest thread that actually holds messages, provided it was touched within
/// `window`. `now` is a parameter (not `Date()` inside) for testability, same as
/// `relativeTime`. A future-dated `updatedAt` (clock skew from another device)
/// counts as recent rather than stale.
///
/// Order-agnostic: callers may pass threads in any order (a Firestore query's
/// ordering isn't guaranteed to survive a decode-and-filter pass), so this sorts
/// before picking rather than trusting the input.
func pickResumeThreadId(in threads: [ChatThread], now: Date, within window: TimeInterval = threadResumeWindow) -> String? {
    guard let newest = sortThreadsByRecent(threads).first(where: { !$0.messages.isEmpty }) else { return nil }
    guard now.timeIntervalSince(newest.updatedAt) <= window else { return nil }
    return newest.id
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
