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

    func testEngineeringIsNowOfferedInTheComposer() {
        // Replaced its own predecessor. Until Task 10 this test asserted the
        // OPPOSITE — that `.engineering` was absent — and was written to fail the
        // moment the workspace shipped, which is exactly what happened. Kept
        // rather than deleted because the property is still worth pinning: the
        // composer must offer every mode whose send has somewhere to go.
        XCTAssertTrue(ChatMode.composerCases.contains(.engineering))
        XCTAssertEqual(Set(ChatMode.composerCases), Set(ChatMode.allCases),
                       "a mode with a working send is missing from the composer")
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
