import XCTest
@testable import codepet

/// What a run says it is doing, per shape of work.
///
/// One generic script served all thirteen deliverable kinds, so generating a PLAN said
/// "Matching your tone and past decisions" — the founder's actual complaint on Aug 5. These
/// assertions pin the two properties that complaint was about: the script fits the work, and
/// every run has a checkpoint. The last one pins the promise made when adopting the web's
/// structure — no invented specifics.
final class ExecScriptTests: XCTestCase {

    private func labels(_ title: String, dept: String? = nil) -> [String] {
        ExecScript.steps(title: title, dept: dept, deptName: nil, decisionCount: 0, language: .en)
            .map(\.label)
    }

    func testAPlanRunReadsLikeAPlan() {
        let l = labels("Write a launch plan").joined(separator: " | ")
        XCTAssertTrue(l.contains("steps you'll need to run"), l)
        XCTAssertTrue(l.contains("Sequencing"), l)
        XCTAssertTrue(l.contains("checklist"), l)
        XCTAssertFalse(l.contains("Shaping it into sections"), "that is the doc script: \(l)")
    }

    func testShapeIsInferredFromTheTitleFirstThenTheDepartment() {
        XCTAssertEqual(ExecScript.shape(title: "Write your landing page copy", dept: "mkt"), .site)
        XCTAssertEqual(ExecScript.shape(title: "Draft a simple pricing plan", dept: "fin"), .plan)
        XCTAssertEqual(ExecScript.shape(title: "Build the projection model", dept: "fin"), .sheet)
        XCTAssertEqual(ExecScript.shape(title: "Sketch the onboarding flow", dept: "design"), .screens)
        XCTAssertEqual(ExecScript.shape(title: "Set up a waitlist signup", dept: "eng"), .code)
        XCTAssertEqual(ExecScript.shape(title: "Draft a support FAQ", dept: "support"), .doc)
        // The department only decides when the title says nothing.
        XCTAssertEqual(ExecScript.shape(title: "Housekeeping", dept: "eng"), .code)
        XCTAssertEqual(ExecScript.shape(title: "Housekeeping", dept: nil), .doc)
    }

    /// Every shape gets exactly one checkpoint — the beat where the run checks its own work.
    /// The native log had the styling for this and never generated one.
    func testEveryShapeHasExactlyOneCheckpoint() {
        for title in ["Write a launch plan", "Write your landing page copy", "Sketch the onboarding flow",
                      "Build the projection model", "Ship the API endpoint", "Draft a support FAQ"] {
            let steps = ExecScript.steps(title: title, dept: nil, deptName: nil,
                                         decisionCount: 0, language: .en)
            XCTAssertEqual(steps.filter { $0.kind == .checkpoint }.count, 1, title)
            XCTAssertEqual(steps.last?.kind, .normal, "a run ends on the deliverable arriving: \(title)")
        }
    }

    /// The promise made when adopting the web's structure: none of its invented specifics.
    /// The web prints "218 tests passed", "+11 −4" derived from the title's length, and
    /// ":3001" — none of which reflect anything that happened.
    func testNoScriptFabricatesASpecific() {
        let banned = ["tests passed", ":3001", "localhost", "Ran ", "actions"]
        for title in ["Write a launch plan", "Ship the API endpoint", "Write your landing page copy",
                      "Build the projection model", "Draft a support FAQ"] {
            let joined = labels(title, dept: "eng").joined(separator: " | ")
            for phrase in banned {
                XCTAssertFalse(joined.contains(phrase), "\(title) fabricates \(phrase): \(joined)")
            }
        }
    }

    /// The one number in the script that is real: how many decisions are on record.
    func testTheDecisionCountIsTheOnlyNumberAndItIsReal() {
        XCTAssertTrue(labels2(decisions: 4).contains { $0.contains("+ 4 decisions") })
        XCTAssertFalse(labels2(decisions: 0).contains { $0.contains("decisions") })
    }

    private func labels2(decisions: Int) -> [String] {
        ExecScript.steps(title: "Draft a support FAQ", dept: nil, deptName: nil,
                         decisionCount: decisions, language: .en).map(\.label)
    }
}
