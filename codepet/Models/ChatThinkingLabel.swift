import Foundation

/// The streaming-state label copy. Pure + localized.
///
/// **Names the pet, because the row no longer shows one.** The working row used to be an
/// orb plus a generic verb, which told the founder that something was happening and nothing
/// about who was doing it — on a product whose whole claim is that eight departments each
/// have their own voice. Founder call, 7 Sep: drop the orb, say the name.
///
/// Still never fabricates. A missing pet or a missing title each fall back rather than
/// inventing one, so the row degrades to exactly the old copy instead of asserting a
/// specialist that is not working.
///
/// **The two title-less cases also ROTATE** (founder call, 7 Sep — the same day): one flat
/// string on every reply of every session read like a spinner with words. The two cases with
/// a real title do NOT rotate, and that asymmetry is the point — a title is something honest
/// to name, and the founder reads that line to know which deliverable is being written, so
/// it stays literal. With no title there is nothing to name, so the wording carries the
/// house voice instead.
///
/// `variant` is an INDEX into the phrase sets, not a random source — this type stays pure so
/// the wording is testable. `nextIndex(previous:count:roll:)` is the rotation rule;
/// `rolled()` is the one impure convenience the view uses, and `lastShown` is what makes
/// "never the same phrase twice running" true of what was actually on screen — see
/// `ChatThinkingRow`.
///
/// **`activity` (8 Sep) joins `taskTitle` as a second title-like, non-rotating case.** A tool
/// target — a filename, a fetched page, "the web" — is exactly the kind of honest name the
/// doc above already carves out an exception for: real work with a real subject, not a mood.
/// Same non-fabrication rule too: `ChatToolActivity` only ever reaches this label already
/// resolved (the sidecar's `toolActivity` returns `null` for anything it cannot honestly
/// describe, and no frame is sent for it), so `text` never has to guess here either — a
/// blank or missing target still falls back to plain rotation rather than naming nothing.
enum ChatThinkingLabel {

    /// The title-less phrases with NO pet to name, in a fixed order.
    ///
    /// **Index 0 is the plain anchor on purpose.** It is what `text` returns when no variant
    /// is supplied, so a caller that does not rotate — and any failure of the rotation —
    /// falls back to the calm line rather than to a joke. It also keeps the anchor inside the
    /// rotation, which is what stops the set reading as a bit.
    static func phrases(_ language: AppLanguage) -> [String] {
        switch language {
        case .vi:
            return ["Đang xử lý…", "Đang nấu…", "Đang tập trung…", "Chill, đang làm…",
                    "Đang làm đây…", "Chờ tí…", "Đang ngẫm…", "Vào guồng rồi…"]
        default:
            return ["Working on it…", "Cooking…", "Locking in…", "On it, no stress…",
                    "Doing the thing…", "Give me a sec…", "Chewing on this…", "In the zone…"]
        }
    }

    /// The same rotation, said about a named pet. `Self.nameToken` stands in for the name.
    ///
    /// A separate set rather than a prefix on `phrases`: "Luna" + "Cooking…" is not a
    /// sentence, and the two languages break differently — English needs the copula ("Luna
    /// is cooking…") while Vietnamese does not ("Luna đang nấu…"). Index 0 is again the
    /// anchor, and it is byte-identical to the copy this row shipped with, so the default
    /// variant reproduces it exactly.
    static func petPhrases(_ language: AppLanguage) -> [String] {
        switch language {
        case .vi:
            return ["\(nameToken) đang làm…", "\(nameToken) đang nấu…",
                    "\(nameToken) đang tập trung…", "\(nameToken) đang làm, chill…",
                    "\(nameToken) đang làm đây…", "\(nameToken) xin tí thời gian…",
                    "\(nameToken) đang ngẫm…", "\(nameToken) vào guồng rồi…"]
        default:
            return ["\(nameToken) is on it…", "\(nameToken) is cooking…",
                    "\(nameToken) is locking in…", "\(nameToken) has this, no stress…",
                    "\(nameToken) is doing the thing…", "\(nameToken) needs a sec…",
                    "\(nameToken) is chewing on this…", "\(nameToken) is in the zone…"]
        }
    }

    /// Where the pet's name goes in a `petPhrases` template. Not `%@`: nothing here goes
    /// through `String(format:)`, and a real format specifier in a plain string is an
    /// invitation for someone to later pass it to something that does.
    static let nameToken = "{pet}"

    /// How many phrases the rotation chooses from. Both sets in both languages carry the
    /// SAME count, so one rolled variant is a valid index in all four — the founder can
    /// change language, or a department handoff can land, while a reply is in flight.
    /// `testAllFourPhraseSetsAreTheSameLength` holds this.
    static var phraseCount: Int { phrases(.en).count }

    /// Which phrase follows `previous`. Pure, so the one property that matters — a phrase
    /// never repeats back-to-back — is provable rather than hoped for.
    ///
    /// `roll` is any `Int`. It is reduced modulo the number of ALLOWED choices, which is
    /// `count - 1` rather than `count` precisely because `previous` is excluded, then mapped
    /// around the excluded index. Mapping (rather than re-rolling until the value differs) is
    /// what makes this terminate and stay pure.
    static func nextIndex(previous: Int?, count: Int, roll: Int) -> Int {
        guard count > 1 else { return 0 }
        // A `previous` outside the set cannot be excluded from it. Treat that as "no
        // previous" rather than shifting every later index up against a phantom, which
        // would silently make the last phrase unreachable.
        guard let previous, previous >= 0, previous < count else {
            return floorMod(roll, count)
        }
        let choice = floorMod(roll, count - 1)
        return choice < previous ? choice : choice + 1
    }

    /// `activity` is checked BEFORE `taskTitle` when both are somehow present. Reasoning:
    /// a tool call is the freshest, most literal thing happening right now — "Luna is
    /// reading web.murror.app…" mid-draft tells the founder more than the higher-level
    /// "Luna is drafting the positioning brief…" it would otherwise show — and today the
    /// two never actually co-occur (`activity` rides an ordinary chat turn, `taskTitle` a
    /// task run), so this ordering has no observable effect yet. It only decides what
    /// happens the day that changes, which is why it is written down rather than left to
    /// whichever branch happened to come first in the switch below.
    static func text(petName: String? = nil, taskTitle: String?,
                     activity: ChatToolActivity? = nil,
                     language: AppLanguage, variant: Int = 0) -> String {
        let pet = petName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = taskTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPet = !(pet ?? "").isEmpty
        let hasTitle = !(title ?? "").isEmpty

        if let line = activityText(activity, pet: hasPet ? pet : nil, language: language) {
            return line
        }

        switch (hasPet, hasTitle) {
        case (true, true):
            return language == .vi ? "\(pet!) đang soạn \(title!)…" : "\(pet!) is drafting \(title!)…"
        case (false, true):
            return language == .vi ? "Đang soạn \(title!)…" : "Drafting \(title!)…"
        case (true, false):
            let set = petPhrases(language)
            return set[floorMod(variant, set.count)]
                .replacingOccurrences(of: nameToken, with: pet!)
        case (false, false):
            let set = phrases(language)
            return set[floorMod(variant, set.count)]
        }
    }

    /// The literal line for one running tool call, or `nil` when there is nothing honest
    /// to say — `activity` absent, or a `readFile`/`fetchPage` whose target trims to
    /// empty. `nil` here is what makes `text` fall through to plain rotation instead of
    /// rendering "Luna is reading …" with nothing after "reading". `searchWeb` needs no
    /// target check: it never carries one.
    ///
    /// `pet` is already resolved (trimmed, blank-checked) by the caller — passed as `nil`
    /// rather than re-deriving, so this can't disagree with `text` about whether a pet
    /// name is present.
    private static func activityText(_ activity: ChatToolActivity?, pet: String?,
                                     language: AppLanguage) -> String? {
        guard let activity else { return nil }
        switch activity.kind {
        case .readFile, .fetchPage:
            let target = activity.target?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !target.isEmpty else { return nil }
            if let pet {
                return language == .vi ? "\(pet) đang đọc \(target)…" : "\(pet) is reading \(target)…"
            }
            return language == .vi ? "Đang đọc \(target)…" : "Reading \(target)…"
        case .searchWeb:
            if let pet {
                return language == .vi ? "\(pet) đang tìm trên web…" : "\(pet) is searching the web…"
            }
            return language == .vi ? "Đang tìm trên web…" : "Searching the web…"
        }
    }

    /// The phrase index last actually ON SCREEN — written by `ChatThinkingRow` in `.onAppear`,
    /// which fires once per appearance. Recording it there rather than where the roll happens
    /// is what keeps the no-repeat guarantee exact: SwiftUI may initialise a view struct
    /// several times for one appearance, and only the first roll is ever displayed.
    static var lastShown: Int?

    /// A fresh variant for a new turn. Reads the rotation state; does not write it.
    static func rolled() -> Int {
        nextIndex(previous: lastShown,
                  count: phraseCount,
                  roll: Int.random(in: 0..<max(phraseCount - 1, 1)))
    }

    /// `%` on a negative left operand is negative in Swift, which would index out of bounds.
    /// `abs` is not the fix — `abs(Int.min)` traps — so fold the sign instead.
    private static func floorMod(_ value: Int, _ modulus: Int) -> Int {
        precondition(modulus > 0, "floorMod needs a positive modulus")
        let m = value % modulus
        return m < 0 ? m + modulus : m
    }
}
