// codepet/Models/MemoryDigest.swift
import Foundation

/// The pure half of the Memory panel: what derived coding memory READS as, and whether it
/// is allowed to reach a prompt at all.
///
/// Both live in a pure enum rather than inline in the view or the store because
/// `PetMemoryStore` is a `@MainActor` singleton backed by UserDefaults — awkward to inject,
/// and impossible to assert against without touching the founder's real memory. The wording
/// the founder reads and the switch that silences it are the two things worth proving, so
/// they are the two things that live here.
enum MemoryDigest {
    /// One readable line summarising every project's coding activity. Projects with zero
    /// sessions are ignored: `memories` gains an entry per project the app has seen, not per
    /// project actually worked in, so counting them would report "0 sessions" as a fact.
    static func codingActivityLine(memories: [String: PetMemory], lang: AppLanguage) -> String {
        let active = memories.values.filter { $0.totalSessions > 0 }
        guard !active.isEmpty else {
            return lang == .vi ? "Chưa có phiên lập trình nào." : "No coding sessions yet."
        }
        let sessions = active.reduce(0) { $0 + $1.totalSessions }
        // Streaks are per project, and they don't add up — the founder's streak is the best
        // one they're currently on, not the sum of unrelated lanes.
        let streak = active.map(\.currentStreak).max() ?? 0
        return lang == .vi
            ? "\(sessions) phiên · chuỗi \(streak) ngày"
            : "\(sessions) sessions · \(streak)-day streak"
    }

    /// The prompt-side gate for DERIVED coding memory — the second of the two stores
    /// `FounderPrefs.memoryEnabled` governs. `nil` (the payload field is omitted) when the
    /// founder has memory off, when there is no memory for the project, or when what memory
    /// there is holds no sessions.
    ///
    /// The facts half of the switch is enforced in `ChatContext.compose(memoryEnabled:)`.
    /// Both are pure, so "memory off means memory off" is provable for each store.
    static func codingMemoryPrompt(_ memory: PetMemory?, memoryEnabled: Bool) -> String? {
        guard memoryEnabled, let memory, memory.totalSessions > 0 else { return nil }
        return memory.toPromptString()
    }
}
