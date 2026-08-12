// codepetTests/ChatModeEngineeringTests.swift
import XCTest
@testable import codepet

/// The fourth mode. `ChatComposer` renders `ChatMode.allCases`, so the control
/// appears with no view change — which also means a mistake here reaches the
/// founder's composer with nothing in between.
final class ChatModeEngineeringTests: XCTestCase {

    func testEngineeringExistsInTheModel() {
        XCTAssertTrue(ChatMode.allCases.contains(.engineering))
        XCTAssertEqual(ChatMode.allCases.count, 4)
    }

    func testEngineeringIsNotYetOfferedInTheComposer() {
        // The mode exists in the model but its workspace does not. ChatComposer
        // renders `composerCases`, so listing it there would put a control in
        // front of a founder whose send goes nowhere — the dead affordance this
        // codebase already removed once (`6982df0`).
        //
        // When EngineeringWorkspaceView lands, add `.engineering` to
        // `composerCases`; THIS TEST WILL FAIL, and that failure is the
        // reminder to delete it.
        XCTAssertFalse(ChatMode.composerCases.contains(.engineering),
                       "if this failed, the workspace shipped — delete this test")
        XCTAssertEqual(ChatMode.composerCases, [.ask, .plan, .build])
    }

    func testEngineeringDoesNotConveneTheRoom() {
        // A room DELIBERATES; engineering EXECUTES. Convening would also add
        // ~$0.20 per message to a mode that already spends real money on a run
        // — measured against ~$0.005 for an ordinary turn.
        XCTAssertFalse(ChatMode.engineering.convenesRoom)
    }

    func testOnlyPlanStillConvenesTheRoom() {
        // Guards the invariant rather than just the new case: adding a mode must
        // not widen what fans out to virtualCompanyRun.
        XCTAssertEqual(ChatMode.allCases.filter(\.convenesRoom), [.plan])
    }

    func testEngineeringSendsTheFoundersTextUnchanged() {
        // The other modes wrap text for a chat model. This text becomes
        // engStartRun's `ask` — the coding agent's actual instruction AND the
        // session title a founder scans a list of runs by. Framing copy would
        // end up in both.
        let ask = "add stripe checkout"
        XCTAssertEqual(ChatMode.engineering.shape(ask, language: .en), ask)
        XCTAssertEqual(ChatMode.engineering.shape(ask, language: .vi), ask)
    }

    func testTheOtherModesStillWrapTheirText() {
        // The regression this catches: making engineering identity by making
        // `shape` identity for everything.
        let text = "price the beta"
        XCTAssertNotEqual(ChatMode.plan.shape(text, language: .en), text)
        XCTAssertNotEqual(ChatMode.build.shape(text, language: .en), text)
        XCTAssertEqual(ChatMode.ask.shape(text, language: .en), text, "ask has always been identity")
    }

    func testEveryModeHasALabelInBothLanguages() {
        for mode in ChatMode.allCases {
            XCTAssertFalse(mode.label(.en).isEmpty, "\(mode) has no English label")
            XCTAssertFalse(mode.label(.vi).isEmpty, "\(mode) has no Vietnamese label")
        }
    }

    func testEngineeringsVietnameseLabelIsAKnownPlaceholder() {
        // NOT an assertion that the label is right — it is deliberately the
        // English word until Mona picks one, and this test exists to make that
        // visible rather than let a placeholder pass as a decision. When she
        // supplies a translation, this test SHOULD fail, and the failure is the
        // reminder to delete it.
        XCTAssertEqual(ChatMode.engineering.label(.vi), "Engineering",
                       "if this failed, the Vietnamese label was chosen — delete this test")
    }
}
