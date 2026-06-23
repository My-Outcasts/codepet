import Foundation

/// How a single review rep resolved. `recurred` is the Codepet-native one: the
/// term reappeared in the user's *real* code, which is the strongest possible
/// retrieval (the generation effect — they produced it, didn't just re-read it)
/// and costs the user zero friction. The other three are self-grades from an
/// active recall card, used only for terms that did NOT recur on their own.
enum RecallGrade {
    case recurred   // passive: surfaced again in real code
    case gotIt      // active self-grade: recalled it
    case fuzzy      // active self-grade: half-remembered
    case forgot     // active self-grade: blanked
}

/// The spaced-repetition state for one term. Codable so it can ride along on a
/// `DictionaryEntry` (or in a parallel store map) and survive app launches.
/// `box` is the Leitner box (0 = just encountered … maxBox = deeply mastered);
/// `dueAt` is when the term next wants a rep.
struct ReviewState: Codable, Equatable {
    var box: Int
    var dueAt: Date
    var lastReviewed: Date?
}

/// Turns the passive Dictionary glossary into an active-recall engine.
///
/// Pure and deterministic — no I/O and no clock except the injected `now` — so
/// it is fully unit-testable, mirroring `TermDetector` / `TrajectoryDetector`.
/// All *policy* about WHEN to call these (the per-day passive-rep gate, the
/// daily review cap) lives here too, as pure functions, so the store and views
/// stay dumb.
///
/// The honesty contract mirrors the trajectory detector's: mastery is *earned*
/// by surviving a long gap and is *revocable* — a `forgot` demotes the box, so
/// "Mastered" can drop back to "Used". A sticker you can't lose isn't mastery.
struct SpacedScheduler {

    struct Config {
        /// Interval applied after a SUCCESSFUL rep into each box. Index = the new
        /// box. Reaching the last box parks the term at the longest interval.
        /// Days: encountered→2, used→5, strengthening→12, mastered→30, deep→90.
        var intervals: [TimeInterval] = [2, 5, 12, 30, 90].map { $0 * 86_400 }

        /// A half-remembered term comes back tomorrow (hold the box, shorten the
        /// gap) — friction stays low but the term doesn't drift.
        var fuzzyInterval: TimeInterval = 1 * 86_400

        /// A forgotten term resurfaces within hours (and drops a box).
        var forgotInterval: TimeInterval = 0.25 * 86_400

        /// Box at/above which the term reads as "mastered". Boxes 1…this-1 read
        /// as "used"; box 0 reads as "encountered".
        var masteredBox = 3

        /// Never surface more than this many active recall cards in one day —
        /// the guarantee it can't become homework.
        var dailyCap = 5

        init() {}
    }

    /// The top box; the term parks here at the longest interval.
    static func maxBox(_ config: Config = Config()) -> Int { config.intervals.count - 1 }

    // MARK: - Lifecycle

    /// State for a term the user has just encountered for the first time: box 0,
    /// first rep due after the shortest interval.
    static func initial(now: Date = Date(), config: Config = Config()) -> ReviewState {
        ReviewState(box: 0, dueAt: now.addingTimeInterval(config.intervals[0]), lastReviewed: nil)
    }

    /// Has this term reached its due date? (Inclusive — a term due exactly now is
    /// due.)
    static func isDue(_ state: ReviewState, now: Date = Date()) -> Bool {
        state.dueAt <= now
    }

    // MARK: - Transitions (the core, pure)

    /// Apply one resolved rep and return the new state. Success (`recurred` /
    /// `gotIt`) advances a box and pushes the next review out; `fuzzy` holds the
    /// box and brings it back tomorrow; `forgot` demotes a box and resurfaces it
    /// within hours.
    static func advance(
        _ state: ReviewState,
        grade: RecallGrade,
        now: Date = Date(),
        config: Config = Config()
    ) -> ReviewState {
        let top = maxBox(config)
        let newBox: Int
        let nextDue: Date

        switch grade {
        case .recurred, .gotIt:
            newBox = min(state.box + 1, top)
            nextDue = now.addingTimeInterval(config.intervals[newBox])
        case .fuzzy:
            newBox = state.box
            nextDue = now.addingTimeInterval(config.fuzzyInterval)
        case .forgot:
            newBox = max(state.box - 1, 0)
            nextDue = now.addingTimeInterval(config.forgotInterval)
        }

        return ReviewState(box: newBox, dueAt: nextDue, lastReviewed: now)
    }

    /// The passive path, with its gate built in: a real re-encounter only counts
    /// as a rep if the term is actually due. This stops a term that appears five
    /// times in one busy session from rocketing to "mastered" in an afternoon —
    /// spacing is the point. If it isn't due yet, the state is returned unchanged.
    static func applyRecurrence(
        _ state: ReviewState,
        now: Date = Date(),
        config: Config = Config()
    ) -> ReviewState {
        guard isDue(state, now: now) else { return state }
        return advance(state, grade: .recurred, now: now, config: config)
    }

    // MARK: - Selection

    /// The terms (by slug) due for an ACTIVE recall card, soonest-due first,
    /// capped at the daily limit. Deterministic: ties on due date break by slug,
    /// so the same set never reshuffles between renders.
    static func due(
        _ states: [String: ReviewState],
        now: Date = Date(),
        config: Config = Config()
    ) -> [String] {
        states
            .filter { isDue($0.value, now: now) }
            .sorted { a, b in
                a.value.dueAt != b.value.dueAt ? a.value.dueAt < b.value.dueAt : a.key < b.key
            }
            .prefix(config.dailyCap)
            .map(\.key)
    }

    // MARK: - Presentation mapping

    /// The `DictionaryEntry.evolution` stage a box corresponds to, so the
    /// existing Encountered → Used → Mastered pill stays the single source of
    /// truth and the ladder/ pill never disagree.
    static func stage(forBox box: Int, config: Config = Config()) -> String {
        if box <= 0 { return "encountered" }
        if box >= config.masteredBox { return "mastered" }
        return "used"
    }
}
