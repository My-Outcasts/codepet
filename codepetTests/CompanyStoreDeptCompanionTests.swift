// codepetTests/CompanyStoreDeptCompanionTests.swift
import XCTest
@testable import codepet

/// #3 — department → companion handoff: a department in focus (chip or a named
/// mention, or a dept-owned task run) brings in the mapped specialist — a host
/// handoff line + the reply/producing/draft attributed to that specialist.
@MainActor
final class CompanyStoreDeptCompanionTests: XCTestCase {
    private func seeded(companionId: String = "byte") -> CompanyState {
        CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .idea,
                     companionId: companionId, onboardedAt: Date(),
                     tasks: [RoadmapTask(id: "t1", title: "Write landing copy", detail: "hero + bullets",
                                         phase: .build, who: .draft, dept: "mkt")])
    }
    /// A streamer that yields one delta + a plain `.done` (no action) — the reply
    /// text lands in the placeholder; no run/nav/setup fires.
    private static func plainStreamer(_ leadIn: String)
        -> (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> {
        { _ in
            AsyncThrowingStream { c in
                c.yield(.delta(leadIn))
                c.yield(.done(model: "m", cacheHit: false, action: ChatDoneAction()))
                c.finish()
            }
        }
    }
    private func store(_ companionId: String = "byte") -> CompanyStore {
        CompanyStore(loader: { _ in self.seeded(companionId: companionId) }, saver: { _, _ in true },
                     chatSender: { _ in nil }, chatStreamer: Self.plainStreamer("Here's the plan"),
                     taskRunner: { _ in nil }, decisionExtractor: { _, _ in [] })
    }

    func testDeptChipInsertsHandoffAndAttributesReply() async {
        let s = store()
        await s.hydrate(companyId: "u")
        let mkt = DepartmentCatalog.find("mkt")
        await s.sendChat("what next?", language: .en, department: mkt)
        // me, handoff (host), reply (specialist)
        XCTAssertEqual(s.chatMessages.map(\.role), [.me, .companion, .companion])
        let handoff = s.chatMessages[1]
        XCTAssertNil(handoff.companionId)                 // host speaks the handoff
        XCTAssertTrue(handoff.text.contains("Nova"))      // mkt → nova
        let reply = s.chatMessages[2]
        XCTAssertEqual(reply.companionId, "nova")
        XCTAssertEqual(reply.deptName, "Marketing")
        XCTAssertEqual(reply.text, "Here's the plan")
    }

    func testTextMentionTriggersSpecialistWithoutChip() async {
        let s = store()
        await s.hydrate(companyId: "u")
        await s.sendChat("help me with marketing", language: .en)   // no chip, name mentioned
        XCTAssertEqual(s.chatMessages.last?.companionId, "nova")
        XCTAssertEqual(s.chatMessages.last?.deptName, "Marketing")
    }

    func testNoDeptNoHandoff() async {
        let s = store()
        await s.hydrate(companyId: "u")
        await s.sendChat("just a general question", language: .en)
        XCTAssertEqual(s.chatMessages.map(\.role), [.me, .companion])   // no handoff inserted
        XCTAssertNil(s.chatMessages.last?.companionId)
    }

    func testSpecialistEqualToHostIsNoOp() async {
        // Host is already nova → focusing marketing shouldn't insert a handoff.
        let s = store("nova")
        await s.hydrate(companyId: "u")
        await s.sendChat("marketing please", language: .en)
        XCTAssertEqual(s.chatMessages.map(\.role), [.me, .companion])
        XCTAssertNil(s.chatMessages.last?.companionId)
    }
}
