// codepet/Models/ThreadSearch.swift
import Foundation

/// Finding a conversation by name.
///
/// Claude Code puts a magnifier at the very top of its sidebar, and it is the
/// affordance this rail was missing most: the rail lists a slice of the threads and
/// nothing else searches them, so an older conversation could only be found by
/// scanning `ThreadListView`.
///
/// **`localizedStandardContains`, not `lowercased().contains`.** The threads here are
/// titled in Vietnamese as often as English — "Chuẩn bị launch sản phẩm" — and
/// lowercasing does nothing about diacritics, so a founder typing `chuan` would get
/// nothing while looking straight at the row. `localizedStandardContains` is
/// case- AND diacritic-insensitive and locale-aware, which is the whole reason to
/// reach for it over the obvious comparison.
enum ThreadSearch {

    /// Threads whose title matches, in the order given. An empty or whitespace query
    /// matches everything, so the caller can pass the field's contents straight in
    /// and not special-case the empty state.
    static func matches(_ threads: [ChatThread], query: String,
                        untitled: String) -> [ChatThread] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return threads }
        return threads.filter { thread in
            // A thread with no title still has to be findable — it shows as "New chat"
            // in the rail, so that is the string the founder can see and would type.
            let title = thread.title ?? untitled
            return title.localizedStandardContains(needle)
        }
    }

    /// Whether the founder is actively searching. Drives the two things that change:
    /// the list stops being capped, and "no matches" becomes sayable.
    static func isSearching(_ query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
