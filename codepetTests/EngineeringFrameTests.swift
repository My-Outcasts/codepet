// codepetTests/EngineeringFrameTests.swift
import XCTest
@testable import codepet

/// The wire contract with `engStream.ts`, written from the payloads that file
/// actually constructs rather than from a description of them.
///
/// Every fixture below quotes the `writeFrame` call it came from. A test built
/// from an assumed shape passes over a decoder that can never work against the
/// real relay — which has already happened twice in this project, once on an
/// SDK error field and once on GitHub's deployment statuses.
final class EngineeringFrameTests: XCTestCase {

    private func decode(_ event: String, _ json: String) -> EngineeringFrame? {
        EngineeringFrame.decode(event: event, data: Data(json.utf8))
    }

    // MARK: - step  (engStream.ts:182 — writeFrame(res, "step", toExecStep(event)))

    func testDecodesAStepFrame() {
        guard case .step(let step)? = decode("step", #"{"id":"sevt_1","label":"read billing.ts","done":false}"#) else {
            return XCTFail("expected a step frame")
        }
        XCTAssertEqual(step.id, "sevt_1")
        XCTAssertEqual(step.label, "read billing.ts")
        XCTAssertFalse(step.done)
    }

    func testAStepRendersAsMonoBecauseItIsARealToolCall() {
        // Narration arrives as a `message` frame; every `step` has a real path
        // or command behind it, which is what `.mono` is for.
        guard case .step(let step)? = decode("step", #"{"id":"s","label":"ran npm test","done":true}"#) else {
            return XCTFail("expected a step frame")
        }
        XCTAssertEqual(step.kind, .mono)
    }

    func testATrueDoneWithAnEmptyLabelIsAcceptedAsACompletionMarker() {
        // engEvents.ts documents this shape: it completes an EARLIER step by
        // id rather than adding a row. Rejecting the empty label would leave
        // every finished step spinning forever.
        guard case .step(let step)? = decode("step", #"{"id":"sevt_1","label":"","done":true}"#) else {
            return XCTFail("a completion marker must decode")
        }
        XCTAssertTrue(step.done)
        XCTAssertTrue(step.label.isEmpty)
    }

    func testAStepWithNoIdIsDropped() {
        // Without an id there is nothing to complete later, and the store
        // would accumulate duplicate rows for the same tool call.
        XCTAssertNil(decode("step", #"{"label":"orphan","done":false}"#))
        XCTAssertNil(decode("step", #"{"id":"","label":"orphan"}"#))
    }

    // MARK: - message  (engStream.ts:190 — writeFrame(res, "message", { text }))

    func testDecodesAMessageFrame() {
        guard case .message(let text)? = decode("message", #"{"text":"I'll start by reading the repo."}"#) else {
            return XCTFail("expected a message frame")
        }
        XCTAssertEqual(text, "I'll start by reading the repo.")
    }

    func testAnEmptyMessageIsDroppedRatherThanRenderedAsABlankTurn() {
        XCTAssertNil(decode("message", #"{"text":""}"#))
    }

    // MARK: - approval  (engStream.ts:193 — { toolUseId, name, input })

    func testDecodesAnApprovalFrame() {
        let json = #"{"toolUseId":"tu_1","name":"bash","input":{"command":"npm install stripe"}}"#
        guard case .approval(let approval)? = decode("approval", json) else {
            return XCTFail("expected an approval frame")
        }
        XCTAssertEqual(approval.id, "tu_1")
        XCTAssertEqual(approval.name, "bash")
        XCTAssertEqual(approval.input, "npm install stripe")
    }

    func testTheApprovalIdIsTheToolUseIdEngSendTurnAnswersAgainst() {
        // engSendTurn keys `user.tool_confirmation` on this exact value. Any
        // other id silently answers nothing and the run stays paused.
        guard case .approval(let approval)? = decode(
            "approval", #"{"toolUseId":"tu_9","name":"bash","input":{}}"#
        ) else {
            return XCTFail("expected an approval frame")
        }
        XCTAssertEqual(approval.id, "tu_9")
    }

    func testAnApprovalWithNoToolUseIdIsDropped() {
        // A card that cannot be answered is worse than no card: it blocks the
        // transcript on a question with no working button.
        XCTAssertNil(decode("approval", #"{"name":"bash","input":{"command":"ls"}}"#))
    }

    func testAnApprovalWithAnUnknownToolStillDecodes() {
        // A tool this client has never heard of is still a real permission ask
        // the run is blocked on.
        guard case .approval(let approval)? = decode(
            "approval", #"{"toolUseId":"tu_2","input":{"pattern":"*.ts"}}"#
        ) else {
            return XCTFail("an unknown tool must still produce a card")
        }
        XCTAssertEqual(approval.name, "tool")
    }

    // MARK: - rendering an input a founder can answer

    func testABashCommandIsShownAsTheCommandNotAsJSON() {
        // The command IS the question. Showing {"command":"..."} makes someone
        // read JSON to answer yes or no.
        XCTAssertEqual(EngineeringFrame.renderInput(["command": "npm install stripe"]),
                       "npm install stripe")
    }

    func testAFileToolIsShownAsItsPath() {
        XCTAssertEqual(EngineeringFrame.renderInput(["file_path": "/workspace/repo/a.ts"]),
                       "/workspace/repo/a.ts")
    }

    func testAnUnrecognisedInputFallsBackToStableJSON() {
        // Sorted keys so the same input renders identically every time — an
        // approval card that reshuffles between renders looks like a new ask.
        let rendered = EngineeringFrame.renderInput(["b": "2", "a": "1"])
        XCTAssertEqual(rendered, #"{"a":"1","b":"2"}"#)
    }

    func testAMissingInputRendersEmptyRatherThanCrashing() {
        XCTAssertEqual(EngineeringFrame.renderInput(nil), "")
    }

    // MARK: - done and error

    func testDecodesDone() {
        guard case .done(let reason)? = decode("done", #"{"runId":"r","stopReason":"end_turn"}"#) else {
            return XCTFail("expected a done frame")
        }
        XCTAssertEqual(reason, "end_turn")
    }

    func testDoneWithoutAStopReasonDefaultsToEndTurnLikeTheRelayDoes() {
        // engStream.ts:218 applies the same default; disagreeing would make a
        // finished run render as a failure.
        guard case .done(let reason)? = decode("done", #"{"runId":"r"}"#) else {
            return XCTFail("expected a done frame")
        }
        XCTAssertEqual(reason, "end_turn")
    }

    func testDecodesError() {
        guard case .failure(let code)? = decode("error", #"{"error":"stream_failed"}"#) else {
            return XCTFail("expected an error frame")
        }
        XCTAssertEqual(code, "stream_failed")
    }

    // MARK: - what must never crash a live run

    func testAnUnknownEventNameIsIgnored() {
        // The relay may gain frames before this client knows them.
        XCTAssertNil(decode("something_new", "{}"))
    }

    func testMalformedJSONIsIgnoredRatherThanThrowing() {
        // A paid run already in flight must not be abandoned over one
        // unreadable frame.
        XCTAssertNil(decode("step", "not json"))
        XCTAssertNil(decode("message", ""))
    }

    func testAJSONArrayWhereAnObjectWasExpectedIsIgnored() {
        XCTAssertNil(decode("step", "[1,2,3]"))
    }
}
