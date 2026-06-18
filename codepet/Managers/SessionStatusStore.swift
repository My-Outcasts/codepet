import Foundation
import Combine

/// Tracks per-session lifecycle status the user controls from the Reflection
/// sidebar: **archived** (hidden from the main list but recoverable) and
/// **deleted** (hidden permanently).
///
/// The underlying coding events live in append-only JSONL files (`events.jsonl`
/// etc.) that CodePet continuously re-polls, so we can't physically remove a
/// session's lines — they would just reappear on the next poll. Instead we record
/// the user's intent here as a soft status and filter sessions out at render time.
/// State persists across launches in UserDefaults.
final class SessionStatusStore: ObservableObject {

    @Published private(set) var pinnedSessionIds: Set<String> = []
    @Published private(set) var archivedSessionIds: Set<String> = []
    @Published private(set) var deletedSessionIds: Set<String> = []
    /// User-supplied display names keyed by sessionId. Overrides the derived title.
    @Published private(set) var customTitles: [String: String] = [:]

    /// The active account's reflection-history start (set by ContentView on
    /// sign-in from `ReflectionAccountWatermark`). Sessions older than this are
    /// hidden so a new account doesn't see a prior user's coding history. Not
    /// persisted here — it's re-derived from the watermark file each launch.
    @Published var activeAccountStart: Date? = nil

    private let pinnedKey = "cp_reflection_pinned_sessions"
    private let archivedKey = "cp_reflection_archived_sessions"
    private let deletedKey = "cp_reflection_deleted_sessions"
    private let titlesKey = "cp_reflection_session_titles"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pinnedSessionIds = Set(defaults.stringArray(forKey: pinnedKey) ?? [])
        archivedSessionIds = Set(defaults.stringArray(forKey: archivedKey) ?? [])
        deletedSessionIds = Set(defaults.stringArray(forKey: deletedKey) ?? [])
        customTitles = (defaults.dictionary(forKey: titlesKey) as? [String: String]) ?? [:]
    }

    // MARK: - Queries

    func isPinned(_ id: String) -> Bool { pinnedSessionIds.contains(id) }
    func isArchived(_ id: String) -> Bool { archivedSessionIds.contains(id) }
    func isDeleted(_ id: String) -> Bool { deletedSessionIds.contains(id) }

    /// The user's custom name for a session, or nil if they never renamed it.
    func customTitle(for id: String) -> String? {
        guard let t = customTitles[id]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !t.isEmpty else { return nil }
        return t
    }

    // MARK: - Mutations

    /// Pin a session to the top of the sidebar. Pinning takes a session out of
    /// the archive (the two states are mutually exclusive).
    func pin(_ id: String) {
        guard !id.isEmpty else { return }
        pinnedSessionIds.insert(id)
        archivedSessionIds.remove(id)
        persist()
    }

    func unpin(_ id: String) {
        guard pinnedSessionIds.contains(id) else { return }
        pinnedSessionIds.remove(id)
        persist()
    }

    func togglePin(_ id: String) {
        if isPinned(id) { unpin(id) } else { pin(id) }
    }

    /// Hide a session from the main list, keeping it in the recoverable
    /// "Archived" section. Clears any pin/delete flag (archiving wins).
    func archive(_ id: String) {
        guard !id.isEmpty else { return }
        archivedSessionIds.insert(id)
        pinnedSessionIds.remove(id)
        deletedSessionIds.remove(id)
        persist()
    }

    /// Return an archived session to the main list.
    func unarchive(_ id: String) {
        guard archivedSessionIds.contains(id) else { return }
        archivedSessionIds.remove(id)
        persist()
    }

    /// Permanently hide a session from every list. Also clears pin/archive flags.
    func delete(_ id: String) {
        guard !id.isEmpty else { return }
        deletedSessionIds.insert(id)
        pinnedSessionIds.remove(id)
        archivedSessionIds.remove(id)
        persist()
    }

    /// Undo a delete — used by the "Undo" affordance after deletion.
    func restore(_ id: String) {
        guard deletedSessionIds.contains(id) else { return }
        deletedSessionIds.remove(id)
        persist()
    }

    /// Set or clear a session's custom display name. Pass nil/empty to reset
    /// back to the auto-derived title.
    func rename(_ id: String, to newTitle: String?) {
        guard !id.isEmpty else { return }
        let trimmed = newTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            customTitles[id] = trimmed
        } else {
            customTitles.removeValue(forKey: id)
        }
        persist()
    }

    /// Re-hydrate in-memory state from the (account-swapped) UserDefaults keys.
    /// Mirrors `init`. Leaves `activeAccountStart` alone (ContentView owns it).
    func reload() {
        pinnedSessionIds = Set(defaults.stringArray(forKey: pinnedKey) ?? [])
        archivedSessionIds = Set(defaults.stringArray(forKey: archivedKey) ?? [])
        deletedSessionIds = Set(defaults.stringArray(forKey: deletedKey) ?? [])
        customTitles = (defaults.dictionary(forKey: titlesKey) as? [String: String]) ?? [:]
    }

    /// Clear all pin/archive/delete flags and custom titles. Called on account
    /// switch so a new user doesn't inherit the previous user's session edits.
    func resetAll() {
        pinnedSessionIds = []
        archivedSessionIds = []
        deletedSessionIds = []
        customTitles = [:]
        defaults.removeObject(forKey: pinnedKey)
        defaults.removeObject(forKey: archivedKey)
        defaults.removeObject(forKey: deletedKey)
        defaults.removeObject(forKey: titlesKey)
    }

    private func persist() {
        defaults.set(Array(pinnedSessionIds), forKey: pinnedKey)
        defaults.set(Array(archivedSessionIds), forKey: archivedKey)
        defaults.set(Array(deletedSessionIds), forKey: deletedKey)
        defaults.set(customTitles, forKey: titlesKey)
    }
}
