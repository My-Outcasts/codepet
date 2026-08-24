// codepet/Models/DepartmentRouter.swift
import Foundation

/// Which department a chat turn belongs to, and how sure we are.
///
/// **Why this is its own type.** Both recorded routing regressions came from one function
/// answering two questions at once, and `DepartmentCompanions` has already been split once for
/// exactly that reason — `actingSpecialist` → `actingDeptKey`, whose comment says the fusion
/// "cost the answer". *Who speaks*, *what they know*, and *how sure we are* are three
/// questions. This file owns the third and only the third: it returns a department key and
/// never resolves a pet. `DepartmentCompanions.specialistId(for:host:)` still decides whether
/// there is a handoff to show, which is why `host` is not a parameter here.
///
/// **Tier order is the safety model.** Tier 1 is `mentionedDeptKey`, unchanged and first, so
/// every message that routes today routes identically. The new tiers can only produce an
/// answer where there was none — never a different one.
enum DepartmentRouter {
    enum Tier: Equatable {
        /// The founder addressed a department by name — "ask finance". Today's behaviour.
        case addressed
        /// The founder's words match a department's vocabulary. New, and guarded (§4.3).
        case topical
        /// Nothing in this draft, but a department owns the conversation. New.
        case carryOver
    }

    struct Suggestion: Equatable {
        let deptKey: String
        let tier: Tier
        /// The term that fired, for the founder-facing "you mentioned …" hover. nil at tiers
        /// that matched on something other than a word. The view composes the sentence, so
        /// this stays a bare term and stays localizable.
        let matched: String?
    }

    // A lexicon hit is hand-curated, dense signal; a task-title hit is the founder's own
    // vocabulary and worth less on its own.
    private static let lexiconWeight = 3
    private static let taskWeight = 1
    // A department with many tasks must not win on volume alone.
    private static let taskScoreCap = 3
    /// One solid lexicon hit, minimum. A stray token cannot route a turn.
    private static let floor = 3
    /// The winner must beat the runner-up by this much. This is where "strongest wins,
    /// near-ties go to byte" lives: a genuinely two-department sentence fails here, and byte
    /// hosting an ambiguous question is the correct answer rather than a fallback.
    private static let margin = 2

    /// Remove text the founder did not write in their own voice.
    ///
    /// The Aug 7 regression was a pasted customer quote — *"emails me when something's off
    /// instead of using support"* — where one incidental word inside someone else's sentence
    /// changed who answered. Quoted spans and blockquoted lines do not vote.
    ///
    /// This catches the QUOTED shape only. An unquoted paste is defended by the floor and the
    /// margin and by nothing else; that is accepted because tier 2's failure mode is now a
    /// tentative chip the founder can see and dismiss before sending, not an answer already
    /// written in the wrong pet's name.
    static func stripQuoted(_ text: String) -> String {
        let unquoted = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix(">") }
            .joined(separator: "\n")

        var out = ""
        var inQuote = false
        for ch in unquoted {
            if ch == "\"" || ch == "\u{201C}" || ch == "\u{201D}" {
                inQuote.toggle()
                continue
            }
            if !inQuote { out.append(ch) }
        }
        return out
    }

    /// Whole-phrase containment, the same discipline `DepartmentCompanions.isAddressed` uses:
    /// a phrase must not match inside a longer word.
    private static func contains(phrase: String, in text: String) -> Bool {
        var search = text.startIndex
        while let r = text.range(of: phrase, range: search..<text.endIndex) {
            defer { search = r.upperBound }
            let beforeOK = r.lowerBound == text.startIndex
                || !text[text.index(before: r.lowerBound)].isLetter
            let afterOK = r.upperBound == text.endIndex || !text[r.upperBound].isLetter
            if beforeOK && afterOK { return true }
        }
        return false
    }

    /// Score one department, returning the total and the first term that fired.
    private static func score(deptKey: String,
                              tokens: Set<String>,
                              raw: String,
                              tasks: [RoadmapTask],
                              language: AppLanguage) -> (total: Int, matched: String?) {
        var hits = 0
        var matched: String?
        for term in DepartmentTopics.terms(for: deptKey, language: language) {
            let hit = term.contains(" ")
                ? contains(phrase: term, in: raw)
                : tokens.contains(term)
            if hit {
                hits += 1
                if matched == nil { matched = term }
            }
        }

        let titles = tasks.filter { $0.dept == deptKey }.map { $0.title }.joined(separator: " ")
        let taskScore = min(TextRelevance.overlap(tokens, TextRelevance.tokenize(titles)), taskScoreCap)

        return (lexiconWeight * hits + taskWeight * taskScore, matched)
    }

    /// The department to suggest, or nil to leave the turn with the host.
    ///
    /// Pure and deterministic: same inputs, same answer, no clock, no network, no state. That
    /// is what lets the two August regressions be held down by tests rather than by hope.
    static func suggest(text: String,
                        tasks: [RoadmapTask],
                        lastActed: String?,
                        language: AppLanguage) -> Suggestion? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Tier 1 — addressed by name. Today's rule, first, unchanged.
        if let key = DepartmentCompanions.mentionedDeptKey(in: trimmed) {
            return Suggestion(deptKey: key, tier: .addressed, matched: nil)
        }

        // Tier 2 — topical. Scored on the founder's own words, with quoted text removed.
        let raw = stripQuoted(trimmed).lowercased()
        let tokens = TextRelevance.tokenize(raw)
        let ranked = DepartmentTopics.map.keys
            .map { (key: $0, result: score(deptKey: $0, tokens: tokens, raw: raw,
                                           tasks: tasks, language: language)) }
            // Sorted by score, then by key, so a tie is broken the same way every run —
            // a non-deterministic winner would make the margin check untestable.
            .sorted { $0.result.total != $1.result.total
                        ? $0.result.total > $1.result.total
                        : $0.key < $1.key }

        if let best = ranked.first, best.result.total >= floor {
            let runnerUp = ranked.dropFirst().first?.result.total ?? 0
            if best.result.total - runnerUp >= margin {
                return Suggestion(deptKey: best.key, tier: .topical, matched: best.result.matched)
            }
        }

        // Tier 4 — nothing to go on. Tier 3 lands above this in Task 5.
        return nil
    }
}
