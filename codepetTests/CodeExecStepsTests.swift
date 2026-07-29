import XCTest
@testable import codepet

final class CodeExecStepsTests: XCTestCase {
    private func ev(_ kind: ClaudeCodeRunner.StreamEvent.Kind, tool: String? = nil, path: String? = nil, text: String) -> ClaudeCodeRunner.StreamEvent {
        ClaudeCodeRunner.StreamEvent(kind: kind, toolName: tool, filePath: path, text: text)
    }

    func test_toolUse_becomesADoneStep() {
        let s = CodeExecSteps.step(for: ev(.toolUse, tool: "Edit", path: "/p/App.swift", text: "Edited App.swift"))
        XCTAssertEqual(s?.label, "Edited App.swift")
        XCTAssertEqual(s?.done, true)
    }

    func test_toolUse_emptyText_mapsToNil() {
        XCTAssertNil(CodeExecSteps.step(for: ev(.toolUse, tool: "Edit", text: "   ")))
    }

    func test_nonActionableEvents_mapToNil() {
        XCTAssertNil(CodeExecSteps.step(for: ev(.system, text: "init")))
        XCTAssertNil(CodeExecSteps.step(for: ev(.assistantText, text: "Sure, on it.")))
        XCTAssertNil(CodeExecSteps.step(for: ev(.toolResult, text: "(done)")))
        XCTAssertNil(CodeExecSteps.step(for: ev(.result, text: "Run complete.")))
    }
}
