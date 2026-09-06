// codepetTests/WalkthroughAskTests.swift
import XCTest
@testable import codepet

/// `WalkthroughAsk` is what makes "compose the text, forget to pass the task" a compile error
/// instead of a silently wrong attribution — the mistake that shipped twice: `MockFlowPlayer`'s
/// `.walkthroughFounderTask` beat (`329891a`) and `CopilotChatView.runBeacon`'s `.walkthrough`
/// case (`a4b7a16`). Both call sites built the same string independently; this suite pins the
/// one composer both now share.
@MainActor
final class WalkthroughAskTests: XCTestCase {

    private func task(dept: String?) -> RoadmapTask {
        // A title that names no department, on purpose — this is exactly the photographed
        // bug's shape: "Walk me through: Talk to 12 people about being lonely" has no
        // department word in it, so a dropped task falls back to keyword inference and finds
        // nothing.
        var t = DemoProject.murror.tasks.first { $0.id == "mur-interviews" }!
        t.dept = dept
        return t
    }

    // MARK: - The pure composer, both languages

    func testComposeInEnglish() {
        let t = task(dept: "mkt")
        let ask = WalkthroughAsk.compose(for: t, language: .en)
        XCTAssertEqual(ask.text, "Walk me through: \(t.title)")
    }

    func testComposeInVietnamese() {
        let t = task(dept: "mkt")
        let ask = WalkthroughAsk.compose(for: t, language: .vi)
        XCTAssertEqual(ask.text, "Hướng dẫn tôi làm: \(t.title)")
    }

    /// The returned task is the one passed in — not a copy that dropped a field, not a
    /// different task entirely. This is the half of the invariant that isn't captured by
    /// checking `text` alone.
    func testComposeReturnsTheSameTaskThatWasPassedIn() {
        let t = task(dept: "eng")
        XCTAssertEqual(WalkthroughAsk.compose(for: t, language: .en).task, t)
        XCTAssertEqual(WalkthroughAsk.compose(for: t, language: .vi).task, t)
    }

    // MARK: - The regression this exists to prevent

    /// **This is the test that would go RED if the bug were reintroduced at the composer
    /// level** — e.g. a future edit to `compose` that builds the right string but hands back
    /// the wrong task (a stale default, a lookup gone wrong, anything that decouples the two
    /// halves again). It runs the composed `ask.task` through the SAME resolution the app uses
    /// (`speakerFor`, `329891a`) and asserts the reply attributes to the task's own department
    /// rather than falling back to keyword inference over a title that names none — which is
    /// the founder-photographed failure mode this whole change exists to make impossible.
    func testTheComposedTaskResolvesItsOwnDepartmentsPetNotAKeywordGuess() {
        let t = task(dept: "mkt")
        let store = CompanyStore()
        let enAsk = WalkthroughAsk.compose(for: t, language: .en)
        let enSpec = store.speakerFor(task: enAsk.task, text: enAsk.text, department: nil)
        XCTAssertEqual(enSpec?.companionId, "nova")
        XCTAssertEqual(enSpec?.deptName, "Marketing")

        let viAsk = WalkthroughAsk.compose(for: t, language: .vi)
        let viSpec = store.speakerFor(task: viAsk.task, text: viAsk.text, department: nil)
        XCTAssertEqual(viSpec?.companionId, "nova")
        XCTAssertEqual(viSpec?.deptName, "Marketing")
    }
}
