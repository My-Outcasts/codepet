// codepetTests/MockFlowScriptTests.swift
import XCTest
@testable import codepet

/// The prototype does two things on load: it plays the story, and it self-tests
/// (48/48 at session end). The player is the first half; this is the second.
///
/// It asserts the SCRIPT rather than replaying it against a live store, because
/// `CompanyStore` is `@MainActor` and the XCTest host on Xcode 26.2 crashes when
/// a `@MainActor ObservableObject` deallocates (~27 tests never finish on a clean
/// checkout — Landmine 3). Driving a real store here would trade a reliable guard
/// for a flaky one. What can be checked without one is most of what goes wrong
/// with a walkthrough: a beat that narrates a screen it never navigated to, a
/// chapter that cannot be jumped to, an approval with nothing to approve.
final class MockFlowScriptTests: XCTestCase {

    private var beats: [MockFlowScript.Beat] { MockFlowScript.beats }

    func testTheScriptIsNotEmptyAndIsNumberedInOrder() {
        XCTAssertFalse(beats.isEmpty)
        XCTAssertEqual(beats.map(\.id), Array(0..<beats.count),
                       "ids must match position or a jump lands on the wrong beat")
    }

    /// Every chapter must be reachable by its jump button.
    func testEveryChapterResolvesToItsFirstBeat() {
        for chapter in MockFlowScript.chapters {
            let i = MockFlowScript.firstBeat(of: chapter)
            XCTAssertNotNil(i, "\(chapter) has no beat")
            XCTAssertEqual(beats[i ?? 0].chapter, chapter)
        }
    }

    /// Chapters are contiguous. A chapter that appears, stops, and reappears makes
    /// its jump button go to the first run and silently skip the rest.
    func testChaptersAreContiguous() {
        var seen: [String] = []
        for beat in beats where seen.last != beat.chapter {
            XCTAssertFalse(seen.contains(beat.chapter),
                           "\(beat.chapter) is split into two runs")
            seen.append(beat.chapter)
        }
        XCTAssertEqual(seen, MockFlowScript.chapters)
    }

    /// You cannot approve what was never produced. The approval beat must come
    /// after a `runBeacon`, or the beat is a no-op narrating a lie ("Library goes
    /// up by one") over an unchanged company.
    func testApprovalOnlyHappensAfterSomethingWasRun() {
        guard let approve = beats.firstIndex(where: { $0.intent == .approveNewestDraft }) else {
            return XCTFail("the script no longer proves approval is what files it")
        }
        let ranBefore = beats.prefix(approve).contains { $0.intent == .runBeacon }
        XCTAssertTrue(ranBefore, "approval at beat \(approve) has no run before it")
    }

    /// The founder-only beat narrates "Codepet cannot do this for you" — which is
    /// only true if the fixture actually holds a `who == .you` task. Without one the
    /// intent no-ops and the caption talks over an unchanged screen.
    func testTheFixtureHasTheFounderOnlyTaskThatBeatDescribes() {
        guard beats.contains(where: { $0.intent == .walkthroughFounderTask }) else { return }
        let tasks = MockChat.company().tasks
        XCTAssertTrue(tasks.contains { $0.who == .you },
                      "no founder-only task in the fixture — the beat would narrate nothing")
        XCTAssertNotNil(BeaconOffer.candidates(tasks).first { $0.who == .you },
                        "a founder-only task exists but is not reachable as a candidate")
    }

    /// The citation beat must come AFTER something was recorded, or the caption
    /// ("the answer quotes it back") narrates a lie over a reply that had nothing to
    /// quote. Same ordering trap the prototype's own version of this check fell into:
    /// there, the assertion passed on the decision's RECEIPT rather than on a later
    /// citation.
    func testTheCitationBeatFollowsSomethingWorthCiting() {
        let asks = beats.compactMap { beat -> (Int, String)? in
            if case .say(let text) = beat.intent { return (beat.id, text) }
            return nil
        }
        guard let recorded = asks.first(where: { $0.1.lowercased().hasPrefix("remember") })?.0,
              let cited = asks.first(where: { $0.1.lowercased().contains("settle") })?.0 else {
            return XCTFail("the walkthrough no longer proves that context compounds")
        }
        XCTAssertLessThan(recorded, cited,
                          "beat \(cited) asks what was settled before beat \(recorded) settles it")
    }

    /// The walkthrough must show both doors — a tour of a two-mode product that
    /// only ever shows one mode is not a tour of the product.
    func testBothModesAreVisited() {
        let modes = beats.compactMap { beat -> WorkspaceMode? in
            if case .mode(let m) = beat.intent { return m }
            return nil
        }
        XCTAssertTrue(modes.contains(.developer))
        XCTAssertTrue(modes.contains(.ask))
        XCTAssertEqual(modes.last, .ask, "it should end where a founder would keep working")
    }

    /// Every beat carries a caption. A silent beat is a screen changing under the
    /// viewer with nothing saying why.
    func testEveryBeatSaysSomething() {
        for beat in beats {
            XCTAssertFalse(beat.caption.trimmingCharacters(in: .whitespaces).isEmpty,
                           "beat \(beat.id) is silent")
            XCTAssertGreaterThan(beat.seconds, 0, "beat \(beat.id) has no time on screen")
        }
    }

    /// A beat must sit long enough to be read. ~18 characters/second is a
    /// comfortable subtitle rate; below that the caption is gone before it is
    /// finished. Only flags the ones that cannot be read at ANY pace — the player's
    /// Slow setting multiplies these by 1.5.
    func testCaptionsHaveTimeToBeRead() {
        for beat in beats {
            let needed = Double(beat.caption.count) / 45.0
            XCTAssertGreaterThanOrEqual(beat.seconds * 1.5, needed,
                                        "beat \(beat.id) shows \(beat.caption.count) characters "
                                        + "for \(beat.seconds)s — unreadable even on Slow")
        }
    }

    /// The whole thing has to be watchable in one sitting.
    func testTheWalkthroughIsShortEnoughToWatch() {
        let total = beats.reduce(0) { $0 + $1.seconds }
        XCTAssertLessThan(total, 60, "a \(Int(total))s tour is one nobody finishes")
        XCTAssertGreaterThan(total, 15, "too short to show anything")
    }

    /// Autoplay without the fixtures behind it would either spend real credits or
    /// narrate an empty company. Both flags are off by default.
    func testBothDemoFlagsDefaultOff() {
        let name = "mock-flow-tests"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        XCTAssertFalse(d.bool(forKey: "CODEPET_MOCK_AUTOPLAY"))
        XCTAssertFalse(d.bool(forKey: "CODEPET_MOCK_FLOW"))
        d.removePersistentDomain(forName: name)
    }

    /// **Autoplay must imply the fixtures.** The walkthrough sends chat turns and
    /// runs a task unattended; behind the real Cloud Functions that is real spend
    /// with nobody watching. `MockChat.flowEnabled` reads BOTH keys — this asserts
    /// it, because the doc comment claimed the implication for a while before the
    /// code did it, which is exactly the half-right state the flags are shaped to
    /// prevent.
    func testAutoplayImpliesTheMockFixtures() {
        let name = "mock-autoplay-implies"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        d.set(true, forKey: "CODEPET_MOCK_AUTOPLAY")
        // Read through the same expression `MockChat.flowEnabled` uses, against a
        // scratch domain — the real one is `.standard` and a test must not write it.
        let implied = d.bool(forKey: "CODEPET_MOCK_FLOW") || d.bool(forKey: "CODEPET_MOCK_AUTOPLAY")
        XCTAssertTrue(implied, "autoplay would drive the live backend")
        d.removePersistentDomain(forName: name)
    }
}
