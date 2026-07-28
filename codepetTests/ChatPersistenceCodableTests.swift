// codepetTests/ChatPersistenceCodableTests.swift
import XCTest
@testable import codepet

/// Chat persistence — CopilotMessage/ChatThread must survive a JSON round-trip
/// (they're written to companies/{uid}/threads/{id}), and a thread's persistable
/// projection must drop transient run state.
final class ChatPersistenceCodableTests: XCTestCase {
    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func testPlainMessageRoundTrips() throws {
        let m = CopilotMessage(role: .me, text: "hello")
        XCTAssertEqual(try roundTrip(m), m)
    }

    func testRichMessagesRoundTrip() throws {
        let draft = Deliverable(id: "d1", kind: DeliverableKind(raw: "plan"), title: "Plan",
                                body: "# Body", createdAt: "2026-07-28T00:00:00Z", sourceTaskId: "t1", payload: nil)
        let cases: [CopilotMessage] = [
            CopilotMessage(role: .companion, text: "reply", companionId: "nova", deptName: "Marketing"),
            CopilotMessage(role: .companion, text: "", draft: draft, draftApproved: true),
            CopilotMessage(role: .companion, text: "q", interview: .goal, interviewAnswered: false),
            CopilotMessage(role: .companion, text: "", navChip: NavAction(destination: "roadmap", target: nil)),
            CopilotMessage(role: .companion, text: "", setupSuggestion: SetupAction(category: "eng", name: "GitHub")),
            CopilotMessage(role: .companion, text: "", noted: [RememberedFact(topic: "t", statement: "s")]),
            CopilotMessage(role: .companion, text: "greet", firstRunAction: FirstRunAction(taskId: "t1", taskTitle: "T")),
        ]
        for m in cases { XCTAssertEqual(try roundTrip(m), m) }
    }

    func testThreadRoundTrips() throws {
        let t = ChatThread(id: "th1", title: "My chat",
                           messages: [CopilotMessage(role: .me, text: "hi"),
                                      CopilotMessage(role: .companion, text: "hey")],
                           createdAt: Date(timeIntervalSince1970: 1_000_000),
                           updatedAt: Date(timeIntervalSince1970: 1_000_100))
        XCTAssertEqual(try roundTrip(t), t)
    }

    func testPersistableStripsTransientRunState() {
        let steps = [ExecStep(label: "Reading brief", done: true)]
        let t = ChatThread(id: "th1", title: nil, messages: [
            CopilotMessage(role: .me, text: "run it"),
            CopilotMessage(role: .companion, text: "producing", producing: true, execSteps: steps),
            CopilotMessage(role: .companion, text: "done", execSteps: steps),
        ], createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 1))
        let p = t.persistable
        XCTAssertEqual(p.messages.count, 2)                       // producing dropped
        XCTAssertFalse(p.messages.contains { $0.producing })
        XCTAssertTrue(p.messages.allSatisfy { $0.execSteps == nil })  // exec state cleared
        XCTAssertEqual(p.messages.map(\.text), ["run it", "done"])
    }
}
