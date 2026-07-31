import XCTest
import SwiftUI
@testable import codepet

final class MessageCardStyleTests: XCTestCase {
    private let sentinel = Color.pink   // stand-in companion accent

    func testHueTable() {
        XCTAssertEqual(MessageCardStyle.hue(for: .draft, companionAccent: sentinel), CodepetTheme.accentGold)
        XCTAssertEqual(MessageCardStyle.hue(for: .interview, companionAccent: sentinel), CodepetTheme.accentBlue)
        XCTAssertEqual(MessageCardStyle.hue(for: .setupSuggestion, companionAccent: sentinel), CodepetTheme.accentTeal)
        XCTAssertEqual(MessageCardStyle.hue(for: .noted, companionAccent: sentinel), CodepetTheme.mutedText)
        XCTAssertEqual(MessageCardStyle.hue(for: .navChip, companionAccent: sentinel), CodepetTheme.hairline)
        // firstRunAction returns the companion accent verbatim
        XCTAssertEqual(MessageCardStyle.hue(for: .firstRunAction, companionAccent: sentinel), sentinel)
    }

    func testKindNilForPlainText() {
        let m = CopilotMessage(role: .companion, text: "hello")
        XCTAssertNil(MessageCardStyle.kind(for: m))
    }

    func testKindNilForProducing() {
        let m = CopilotMessage(role: .companion, text: "", producing: true)
        XCTAssertNil(MessageCardStyle.kind(for: m))
    }

    func testKindPerPayload() {
        // Construct minimal valid instances of each payload type by reading their
        // initializers (Deliverable, InterviewGap, SetupAction, FirstRunAction,
        // RememberedFact, NavAction). Set them via CopilotMessage's init args.
        // draft:
        XCTAssertEqual(MessageCardStyle.kind(for: msg(draft: minimalDraft())), .draft)
        // interview:
        XCTAssertEqual(MessageCardStyle.kind(for: msg(interview: minimalGap())), .interview)
        // setupSuggestion:
        XCTAssertEqual(MessageCardStyle.kind(for: msg(setupSuggestion: minimalSetup())), .setupSuggestion)
        // firstRunAction:
        XCTAssertEqual(MessageCardStyle.kind(for: msg(firstRunAction: minimalAction())), .firstRunAction)
        // noted:
        XCTAssertEqual(MessageCardStyle.kind(for: msg(noted: [minimalFact()])), .noted)
        // navChip:
        XCTAssertEqual(MessageCardStyle.kind(for: msg(navChip: minimalNav())), .navChip)
    }

    func testPrecedenceDraftBeatsInterview() {
        let m = msg(draft: minimalDraft(), interview: minimalGap())
        XCTAssertEqual(MessageCardStyle.kind(for: m), .draft)
    }

    // MARK: - Helpers

    /// Thin wrapper over CopilotMessage.init — only the payload args under test
    /// vary; role/text are fixed placeholders.
    private func msg(
        draft: Deliverable? = nil,
        interview: InterviewGap? = nil,
        setupSuggestion: SetupAction? = nil,
        firstRunAction: FirstRunAction? = nil,
        noted: [RememberedFact]? = nil,
        navChip: NavAction? = nil
    ) -> CopilotMessage {
        CopilotMessage(
            role: .companion, text: "",
            draft: draft, firstRunAction: firstRunAction, interview: interview,
            navChip: navChip, setupSuggestion: setupSuggestion, noted: noted)
    }

    // Deliverable(id: String = UUID(), kind:, title:, body:, createdAt: nil,
    // sourceTaskId: nil, payload: nil) — codepet/Models/Deliverable.swift.
    private func minimalDraft() -> Deliverable {
        Deliverable(kind: .doc, title: "t", body: "b")
    }

    // InterviewGap is a plain enum { goal, traction, problem } —
    // codepet/Models/EnrichInterview.swift. No init needed.
    private func minimalGap() -> InterviewGap { .goal }

    // SetupAction(category:, name:) — codepet/Services/CompanyChatClient.swift.
    private func minimalSetup() -> SetupAction {
        SetupAction(category: "c", name: "n")
    }

    // FirstRunAction(taskId:, taskTitle:) — codepet/Models/FirstRunGreeting.swift.
    private func minimalAction() -> FirstRunAction {
        FirstRunAction(taskId: "id", taskTitle: "title")
    }

    // RememberedFact(topic:, statement:) — codepet/Services/CompanyChatClient.swift.
    private func minimalFact() -> RememberedFact {
        RememberedFact(topic: "topic", statement: "statement")
    }

    // NavAction(destination:, target:) — codepet/Services/CompanyChatClient.swift.
    private func minimalNav() -> NavAction {
        NavAction(destination: "d", target: nil)
    }
}
