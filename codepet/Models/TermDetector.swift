import Foundation

/// A minimal, store-agnostic view of one captured Claude Code event, so the
/// detector can be unit-tested without `ReflectionEventStore`.
struct CodeEvent {
    let isoTime: String
    let text: String
    let path: String
    let cwd: String
}

/// One place a term appeared in the user's real work.
struct TermOccurrence: Equatable {
    let file: String          // basename, e.g. "LoginView.swift" ("" if no file)
    let date: Date
    let snippet: String?      // short excerpt around the match
    let projectPath: String   // cwd of the event ("" if unknown)

    /// An occurrence that came from an actual file edit (has a real file path)
    /// — the signal that the term was *used in code*, not merely mentioned.
    var isAuthored: Bool { !file.isEmpty }
}

/// A term detected across the user's events, with everywhere it was seen and a
/// derived Encountered → Used → Mastered stage.
struct DetectedTerm: Equatable {
    let canonical: String
    let topicHint: String
    let occurrences: [TermOccurrence]   // most recent first

    var count: Int { occurrences.count }
    var distinctFiles: Set<String> { Set(occurrences.map(\.file).filter { !$0.isEmpty }) }
    var lastSeen: Date { occurrences.map(\.date).max() ?? .distantPast }
    var firstSeen: Date { occurrences.map(\.date).min() ?? .distantPast }

    /// Heuristic stage (the server uses this to match tone / celebrate):
    /// - mastered: used across 2+ files AND 3+ times (confident, repeated use)
    /// - used: appeared in at least one real file edit
    /// - encountered: only mentioned, never seen authored in a file
    var evolution: String {
        if distinctFiles.count >= 2 && count >= 3 { return "mastered" }
        if occurrences.contains(where: { $0.isAuthored }) { return "used" }
        return "encountered"
    }
}

/// Scans captured events for catalog terms and attributes each to the files and
/// dates it showed up in. Pure and deterministic — the orchestration (when to
/// scan, what to regenerate) lives in `DictionaryEnricher`.
enum TermDetector {

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Detect terms across `events`, returning the `maxTerms` most-seen, most
    /// recent first within each term. Occurrences are de-duplicated per
    /// (term, file, day) so a term edited many times in one file in one day
    /// counts once toward spread.
    static func detect(events: [CodeEvent], maxTerms: Int = 12) -> [DetectedTerm] {
        var byTerm: [String: (topic: String, occ: [TermOccurrence], seen: Set<String>)] = [:]

        for event in events {
            let haystack = (event.text + " " + event.path).lowercased()
            guard !haystack.isEmpty else { continue }
            let file = fileBasename(from: event)
            let date = isoFormatter.date(from: event.isoTime) ?? Date(timeIntervalSince1970: 0)
            let dayKey = Self.dayKey(date)

            for term in TermCatalog.terms {
                guard let pattern = term.patterns.first(where: { wordContains(haystack, $0) }) else { continue }
                let dedupeKey = "\(file)|\(dayKey)"
                var bucket = byTerm[term.canonical] ?? (term.topicHint, [], [])
                guard !bucket.seen.contains(dedupeKey) else { continue }   // one per file per day
                bucket.seen.insert(dedupeKey)
                bucket.occ.append(TermOccurrence(
                    file: file,
                    date: date,
                    snippet: snippet(around: pattern, in: event.text),
                    projectPath: event.cwd
                ))
                byTerm[term.canonical] = bucket
            }
        }

        let detected = byTerm.map { canonical, v in
            DetectedTerm(
                canonical: canonical,
                topicHint: v.topic,
                occurrences: v.occ.sorted { $0.date > $1.date }
            )
        }
        // Most-used first, then most-recent; cap to the server's batch limit.
        return Array(detected.sorted {
            $0.count != $1.count ? $0.count > $1.count : $0.lastSeen > $1.lastSeen
        }.prefix(maxTerms))
    }

    // MARK: - Matching helpers

    /// Whole-word-ish containment. For purely alphanumeric patterns we require
    /// non-word boundaries so "api" doesn't match inside "rapid". Patterns that
    /// already carry punctuation (".env", "async/await", "do {") match literally.
    static func wordContains(_ haystack: String, _ pattern: String) -> Bool {
        guard !pattern.isEmpty else { return false }
        let isAlnum = pattern.allSatisfy { $0.isLetter || $0.isNumber || $0 == " " }
        if !isAlnum { return haystack.contains(pattern) }

        var searchStart = haystack.startIndex
        while let r = haystack.range(of: pattern, range: searchStart..<haystack.endIndex) {
            let beforeOK = r.lowerBound == haystack.startIndex
                || !isWordChar(haystack[haystack.index(before: r.lowerBound)])
            let afterOK = r.upperBound == haystack.endIndex
                || !isWordChar(haystack[r.upperBound])
            if beforeOK && afterOK { return true }
            searchStart = r.upperBound
        }
        return false
    }

    private static func isWordChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_"
    }

    private static func fileBasename(from event: CodeEvent) -> String {
        let raw = event.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }
        let name = URL(fileURLWithPath: raw).lastPathComponent
        // Guard against a path that is really a directory or a tool token.
        return name.contains(".") ? name : ""
    }

    private static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    /// A short, single-line excerpt around the first match, for the server to
    /// ground the card's code example in the user's own code.
    private static func snippet(around pattern: String, in text: String, window: Int = 80) -> String? {
        let lower = text.lowercased()
        guard let r = lower.range(of: pattern) else { return nil }
        let start = lower.index(r.lowerBound, offsetBy: -window, limitedBy: lower.startIndex) ?? lower.startIndex
        let end = lower.index(r.upperBound, offsetBy: window, limitedBy: lower.endIndex) ?? lower.endIndex
        let slice = text[start..<end]
        return slice.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
