// codepetTests/CompanyStoreWalkThroughTests.swift
import XCTest
@testable import codepet

/// "Walk me through it" is the founder-owned half of a department's work, and it used to lose
/// the department entirely.
///
/// `walkThroughTask` called `sendMessage` with no `department`, so the same Engineering task
/// answered two different ways depending on which button was pressed: "Have Codepet do it"
/// produced a run attributed to Crash · Engineering AND grounded in Engineering's focus, while
/// "Walk me through it" — sitting inches away on the same card — got the generic host with no
/// department grounding at all. The founder is doing the department's work either way.
@MainActor
final class CompanyStoreWalkThroughTests: XCTestCase {
    private static let failingStreamer: (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> = { _ in
        AsyncThrowingStream { $0.finish(throwing: CompanyChatStreamError.notSignedIn) }
    }

    /// A founder-owned Engineering task. `who: .you` is the state that shows "Walk me through it".
    private let task = RoadmapTask(id: "t1", title: "Pick a hosting provider", detail: "",
                                   phase: .foundation, who: .you, dept: "eng")

    private func store(capturing sent: @escaping (CompanyChatRequest) -> Void) -> CompanyStore {
        CompanyStore(loader: { _ in
                        CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .idea,
                                     companionId: "byte", onboardedAt: Date(), tasks: [])
                     },
                     saver: { _, _ in true },
                     chatSender: { req in
                         sent(req)
                         return CompanyChatReply(text: "Here's how", runTaskId: nil)
                     },
                     chatStreamer: Self.failingStreamer)
    }

    /// The grounding half: the model is told which department this is.
    func testWalkThroughGroundsTheReplyInTheTasksDepartment() async {
        var context: String?
        let s = store { context = $0.context }
        await s.hydrate(companyId: "u")
        await s.walkThroughTask(task, language: .en)
        XCTAssertEqual(context?.contains("focused on the Engineering department"), true,
                       "a walk-through of an Engineering task must carry Engineering's focus")
    }

    /// The attribution half: the department's own pet does the walking.
    func testWalkThroughIsSpokenByTheDepartmentSpecialist() async {
        let s = store { _ in }
        await s.hydrate(companyId: "u")
        await s.walkThroughTask(task, language: .en)
        let reply = s.chatMessages.last
        XCTAssertEqual(reply?.companionId, "byte")
        XCTAssertEqual(reply?.deptName, "Engineering")
    }

    /// A task with no department is still an ordinary host turn — no invented specialist,
    /// no invented grounding. Legacy boards predate `dept` and decode it as nil.
    func testADeptlessTaskStaysWithTheHost() async {
        var context: String?
        let s = store { context = $0.context }
        await s.hydrate(companyId: "u")
        await s.walkThroughTask(RoadmapTask(id: "t2", title: "Name the company", detail: "",
                                            phase: .find, who: .you),
                                language: .en)
        XCTAssertEqual(context?.contains("focused on the"), false)
        XCTAssertNil(s.chatMessages.last?.companionId)
    }
}
