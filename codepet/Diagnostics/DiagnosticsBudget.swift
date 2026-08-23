// codepet/Diagnostics/DiagnosticsBudget.swift
import Foundation

/// Decides which occurrences of a repeating failure get written, and which are only
/// counted.
///
/// This is the difference between diagnostics and a denial-of-service on our own
/// Firestore bill. The failure that motivated it is real: `NarrativeEnricher` fires
/// once per turn, and a founder who has hit their Anthropic quota fails EVERY turn —
/// `reason=quota` on a loop. One document per occurrence would be hundreds of writes an
/// hour, all saying the same sentence, and would bury the single occurrence of
/// something rare underneath them.
///
/// So: report on a ladder — the 1st, 2nd, 5th, 10th, 25th, 50th, 100th, then every
/// 500th — and put the running total in `count`. A thousand identical failures cost
/// eight documents and still report the number one thousand, which is the number that
/// would change a decision. Nothing is estimated and nothing is lost: `count` is exact.
///
/// A pure value type with no clock and no timer, because the alternative (a debounced
/// flush) has to answer "what about the events still in the buffer when the app dies",
/// and the answer is always "they are gone" — which is the worst possible property for
/// a system whose job is reporting deaths.
nonisolated struct DiagnosticsBudget: Equatable {
    /// The occurrence numbers that get written. After the last one, every
    /// `repeatInterval`-th occurrence.
    static let ladder = [1, 2, 5, 10, 25, 50, 100]
    static let repeatInterval = 500

    /// Ceiling on DISTINCT failure keys per launch. Bounds the document count even if
    /// something generates unbounded variety — an error whose `code` is a timestamp,
    /// say. Occurrences of keys already being tracked still count normally; only a NEW
    /// key past the ceiling is dropped.
    static let maxDistinctKeys = 40

    private var counts: [String: Int] = [:]
    /// Keys refused because the ceiling was already full. Kept only so
    /// `droppedKeyCount` can be reported honestly rather than the ceiling being silent.
    private var droppedKeys: Set<String> = []

    init() {}

    var trackedKeyCount: Int { counts.count }
    var droppedKeyCount: Int { droppedKeys.count }

    /// Records one occurrence of `key`.
    ///
    /// Returns the running count when this occurrence should be WRITTEN, or nil when it
    /// should only be counted. A nil return is not a failure — it means "we already
    /// told them about this one".
    mutating func admit(_ key: String) -> Int? {
        guard let existing = counts[key] else {
            guard counts.count < Self.maxDistinctKeys else {
                droppedKeys.insert(key)
                return nil
            }
            counts[key] = 1
            return 1
        }
        let next = existing + 1
        counts[key] = next
        if Self.ladder.contains(next) { return next }
        if next > (Self.ladder.last ?? 0), next % Self.repeatInterval == 0 { return next }
        return nil
    }
}
