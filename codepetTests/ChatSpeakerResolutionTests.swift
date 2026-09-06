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

    /// The WIRING guard, not the resolution seam. Every test above calls `speakerFor`
    /// directly and would have passed even while the live app dropped the task on the
    /// floor — Task 3 already had those, and they were green the whole time this bug was
    /// live. This one goes through `sendChat`'s own `aboutTask:` parameter, exactly as
    /// `CopilotChatView.send(aboutTask:)` now forwards it, end to end into the appended
    /// companion placeholder's stamped `companionId`/`deptName` — so it goes red if a
    /// future edit drops `aboutTask` anywhere between `sendChat` and the message that gets
    /// appended, not only if `speakerFor` itself regresses.
    ///
    /// `text` is deliberately the exact photographed string, which names no department —
    /// if `aboutTask` were silently dropped in `sendChat`/`sendMessage`, this would fall
    /// back to keyword inference (nil) and the placeholder would carry the founder's own
    /// `company.companionId` ("byte") instead of Marketing's "nova".
    func testSendChatThreadsAboutTaskIntoTheAppendedMessage() async {
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             chatSender: { _ in nil },
                             chatStreamer: { _ in AsyncThrowingStream { $0.finish(throwing: CompanyChatStreamError.notSignedIn) } })
        await s.hydrate(companyId: "u")
        let task = task(id: "mur-interviews", dept: "mkt")
        await s.sendChat("Walk me through: \(task.title)", language: .en, aboutTask: task)
        let reply = s.chatMessages.first { $0.role == .companion }
        XCTAssertEqual(reply?.companionId, "nova", "the task's own department, not the founder's default companion")
        XCTAssertEqual(reply?.deptName, "Marketing")
    }
}
