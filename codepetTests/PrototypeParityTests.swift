// codepetTests/PrototypeParityTests.swift
import XCTest
@testable import codepet

/// Keeps the in-app walkthrough and the HTML prototype from drifting apart silently.
///
/// They are two independent implementations of the same story — no shared source,
/// no generator. `MockFlowScript` was written modelled on the prototype's shape
/// (`[chapter, duration, action, caption]` plus a stepper) and nothing since has
/// kept them honest with each other. On 20 Aug the prototype went to 33 beats while
/// the app sat at 18, and the only reason anyone noticed was reading both by hand.
///
/// **This does not force parity, and should not.** The prototype is the design
/// artifact: it can show `re_plan`, `Company → Learn`, a code run and five failure
/// states because it fakes all of them. The app can only walk what is built.
/// Forcing them equal would mean either deleting design from the prototype or
/// faking features in the app — and faking in the app is exactly the hazard the
/// unmocked `VirtualCompanyClient` demonstrated, where a demo beat would have spent
/// real money.
///
/// So: the prototype is the target, the app walkthrough is the progress bar, and
/// the gap between them is the backlog. This test makes the gap *counted* rather
/// than rediscovered by eye, and fails on the one thing that is always a mistake —
/// the app growing a chapter the design has no name for, undeclared.
final class PrototypeParityTests: XCTestCase {

    /// App chapters with deliberately no prototype counterpart. An entry here is a
    /// claim that the divergence was considered; a chapter missing from BOTH this
    /// list and the prototype fails the test.
    private let appOnly: [String: String] = [
        "Ask anything":
            "An ordinary grounded turn. The prototype folds this into `The first minute` "
            + "rather than giving it a chapter, and the app needs it standalone because its "
            + "opening has fewer beats.",
        "A real deliverable":
            "The draft arriving and being approved. The prototype covers both inside "
            + "`The first minute`; splitting them in the app keeps each caption short enough "
            + "to read at the pace the app plays.",
        "Where the state lives":
            "Browsing Roadmap and Library. The prototype demonstrates the five surfaces "
            + "inside other chapters rather than as a chapter of its own.",
        "Your company touches your code":
            "Developer's DORMANT state — the two doors, before anything is linked. Not the "
            + "prototype's `Into the code`, which is an actual run: naming it that would "
            + "claim a code change the app cannot yet perform.",
    ]

    /// The prototype, found from this file's own path. Tracked since `1ebd67e`, so
    /// a missing file is a real failure and not an environment quirk.
    private func prototypeSource() throws -> String {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // codepetTests/
            .deletingLastPathComponent()   // repo root
        let url = repo.appendingPathComponent(
            "docs/superpowers/prototypes/2026-08-17-two-mode-prototype.html")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("prototype not found at \(url.path) — tracked since 1ebd67e, so "
                          + "this means a partial checkout rather than a code problem")
        }
        return text
    }

    /// Chapter names from the prototype's `STORY`, whose beats are
    /// `["Chapter", 1234, function () {…}, "caption"]`.
    private func prototypeChapters(_ source: String) -> [String] {
        var found: [String] = []
        var seen = Set<String>()
        // Anchored on the numeric duration so prose mentioning a chapter in a caption
        // or a comment cannot be mistaken for a beat.
        let pattern = #"\[\s*"([^"]+)"\s*,\s*\d+\s*,"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = source as NSString
        for m in re.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: m.range(at: 1))
            if seen.insert(name).inserted { found.append(name) }
        }
        return found
    }

    /// The parse must find a plausible story, or every assertion below is vacuous —
    /// a broken regex would otherwise turn this whole file green.
    func testThePrototypeStoryParses() throws {
        let chapters = prototypeChapters(try prototypeSource())
        XCTAssertGreaterThanOrEqual(chapters.count, 10,
                                    "parsed only \(chapters) — the regex no longer matches STORY")
        XCTAssertTrue(chapters.contains("Signing in"), chapters.description)
        XCTAssertEqual(chapters.last, "Where it ends", "the story should end where it ends")
    }

    /// The failure that is always a mistake: the app names a moment the design has
    /// no name for, without saying so.
    func testTheAppInventsNoUndeclaredChapter() throws {
        let prototype = Set(prototypeChapters(try prototypeSource()))
        XCTAssertFalse(prototype.isEmpty, "parse failed — see testThePrototypeStoryParses")

        let undeclared = MockFlowScript.chapters.filter {
            !prototype.contains($0) && appOnly[$0] == nil
        }
        XCTAssertTrue(undeclared.isEmpty,
                      "the app walkthrough has chapters the prototype does not, and that are not "
                      + "declared in `appOnly`: \(undeclared). Either name it as the design does, "
                      + "or add it to `appOnly` with the reason it differs.")
    }

    /// An `appOnly` entry that the prototype has since adopted is stale — it would
    /// keep excusing a divergence that no longer exists.
    func testNoStaleAppOnlyEntries() throws {
        let prototype = Set(prototypeChapters(try prototypeSource()))
        for (chapter, _) in appOnly where prototype.contains(chapter) {
            XCTFail("`appOnly` still excuses \"\(chapter)\", but the prototype now has that "
                    + "chapter — drop the entry")
        }
        for (chapter, _) in appOnly where !MockFlowScript.chapters.contains(chapter) {
            XCTFail("`appOnly` names \"\(chapter)\", which the app walkthrough no longer has")
        }
    }

    /// Not an assertion about the size of the gap — closing it is a product decision,
    /// not a test's. This prints the backlog so it is counted rather than rediscovered.
    func testReportTheCoverageGap() throws {
        let prototype = prototypeChapters(try prototypeSource())
        let app = Set(MockFlowScript.chapters)
        let missing = prototype.filter { !app.contains($0) }
        print("[parity] prototype \(prototype.count) chapters, app \(MockFlowScript.chapters.count)")
        print("[parity] the app cannot yet walk: \(missing.joined(separator: ", "))")
        // The only hard rule: the app must not be empty of the design's vocabulary.
        // Sharing nothing would mean the two stories are no longer the same story.
        let shared = prototype.filter { app.contains($0) }
        XCTAssertGreaterThanOrEqual(shared.count, 4,
                                    "only \(shared) in common — these have stopped being one story")
    }
}
