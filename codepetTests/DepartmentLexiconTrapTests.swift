import XCTest
@testable import codepet

/// **Words that must never steal a turn.**
///
/// The lexicon was tuned against a 56-message corpus of realistic founder phrasings (hit 48 /
/// miss 8 / wrong 0 / false-positive 0). The *positive* half of that corpus is judgement — which
/// department a vague sentence "should" reach is arguable, and freezing my guesses into
/// assertions would make this suite an opinion rather than a guard. This file keeps the half
/// that is not arguable: sentences where a founder is plainly not addressing a department, which
/// must stay with byte.
///
/// This is the direction that actually hurts. A miss is invisible — byte answers, which is what
/// happened before this feature existed. A false positive puts the wrong pet's name on an answer,
/// which is the Aug 7 and Aug 10 shape both recorded in `DepartmentCompanions`.
///
/// Three terms were DELETED because these cases caught them firing, and each had been flagged by
/// review before anyone measured it:
/// - `deal` and `demo` (sales) — ordinary English. The sales sense now lives in the phrases
///   `book a demo` / `demo call` / `close the deal` / `deal size`.
/// - `crash` (eng) — also a **pet's own name**, so "crash is my favourite pet" routed to
///   Engineering. Replaced by `crashes` / `crashed` / `crashing`, which keeps every fault
///   report and drops the collision. (Crash speaks for Finance since 26 Aug; the collision
///   was with the name, not the department, so the fix is unaffected.)
///
/// Adding a term that makes any case here fire means the term is too broad. Fix the vocabulary,
/// not this test.
final class DepartmentLexiconTrapTests: XCTestCase {

    private func assertHostedByByte(_ message: String,
                                    _ why: String,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let s = DepartmentRouter.suggest(text: message, tasks: [], lastActed: nil, language: .en)
        XCTAssertNil(s, "\(why) — \"\(message)\" routed to \(s?.deptKey ?? "-") on \"\(s?.matched ?? "-")\"",
                     file: file, line: line)
    }

    /// Ordinary English that happens to contain a business-sounding word.
    func testEverydaySenseOfASalesWordDoesNotRoute() {
        assertHostedByByte("that was a good deal on the laptop", "\"deal\" in its everyday sense")
        assertHostedByByte("let me demo it to you quickly", "\"demo\" can be showing anyone anything")
    }

    /// The pets have names, and one of them is an Engineering word.
    func testAPetsOwnNameDoesNotRouteToItsDepartment() {
        assertHostedByByte("crash is my favourite pet", "\"crash\" is a pet's name")
    }

    /// Generic founder talk — the most common thing typed into this box.
    func testGenericFounderTalkStaysWithTheHost() {
        assertHostedByByte("what should I focus on this week", "no department named or implied")
        assertHostedByByte("can you summarize where we are", "a request to the host")
        assertHostedByByte("give me a plan for the next two weeks", "planning is byte's job")
        assertHostedByByte("this is taking longer than I thought", "a feeling, not a domain")
        assertHostedByByte("what did I decide about this last month", "a memory lookup")
    }

    /// The two recorded regressions, in the shapes that caused them. Tier 1 refuses these by
    /// requiring a department to be ADDRESSED; tier 2 must not fire on them either.
    func testTheAugustRegressionShapesStayDead() {
        assertHostedByByte("the app is well designed", "\"designed\" must not match \"design\"")
        assertHostedByByte("I am happy with design so far", "a department NAME merely mentioned")
    }

    /// A word ending in `s` that is nobody's plural — guards the singular/plural rule against
    /// being "simplified" into stripping the founder's token instead of widening ours.
    func testAWordEndingInSIsNotTreatedAsAPlural() {
        assertHostedByByte("our focus is unclear", "\"focus\" is not the plural of anything")
    }

    /// Genuinely two-department sentences fail the margin and stay with byte, rather than the
    /// router picking one at random. Measured: legal `commercially` ties design `font` at 3–3.
    func testAGenuinelyAmbiguousSentenceStaysWithTheHost() {
        assertHostedByByte("can I use this font commercially", "legal and design tie on the margin")
    }
}
