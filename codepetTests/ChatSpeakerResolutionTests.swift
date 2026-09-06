import XCTest
@testable import codepet

/// Who speaks for a turn that is ABOUT a task but names no department.
///
/// This is the gap the founder photographed: "Walk me through: Talk to 12 people about being
/// lonely" carries no department chip and no department word, so keyword inference returns
/// nil and the reply signed itself "Codepet" — on a Marketing task.
@MainActor
final class ChatSpeakerResolutionTests: XCTestCase {

    private func task(id: String, dept: String?) -> RoadmapTask {
        var t = DemoProject.murror.tasks.first { $0.id == "mur-interviews" }!
        t.dept = dept
        return t
    }

    func testATaskResolvesItsDepartmentsPet() {
        let store = CompanyStore()
        let spec = store.speakerFor(task: task(id: "mur-interviews", dept: "mkt"), text: "Walk me through: Talk to 12 people", department: nil)
        XCTAssertEqual(spec?.companionId, "nova")
        XCTAssertEqual(spec?.deptName, "Marketing")
    }

    /// Task first: its department is a fact, a keyword match is an inference.
    func testTheTaskWinsOverAKeywordInTheText() {
        let store = CompanyStore()
        let spec = store.speakerFor(task: task(id: "mur-stack", dept: "eng"), text: "ask marketing about this", department: nil)
        XCTAssertEqual(spec?.companionId, "byte", "the task's own department decides, not the word in the text")
    }

    /// A task with no department falls through to nil — the headerless state, not a "Codepet" row.
    func testATaskWithNoDepartmentYieldsNoSpeaker() {
        let store = CompanyStore()
        XCTAssertNil(store.speakerFor(task: task(id: "x", dept: nil), text: "hello", department: nil))
    }

    /// With no task, the existing keyword rule is untouched.
    func testWithNoTaskTheKeywordRuleStillApplies() {
        let store = CompanyStore()
        XCTAssertEqual(store.speakerFor(task: nil, text: "ask marketing about this", department: nil)?.companionId, "nova")
        XCTAssertNil(store.speakerFor(task: nil, text: "what should I do today?", department: nil))
    }
}
