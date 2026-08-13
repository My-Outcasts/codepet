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
        // NOT an assertion that the label is right. The English word is
        // deliberately standing in until Mona picks a translation, and this
        // test exists to make that visible rather than let a placeholder pass
        // as a decision. When she supplies one, this test SHOULD fail, and the
        // failure is the reminder to delete it.
        //
        // The word changed from "Engineering" to "Developer" on Aug 13 — a
        // decision about the ENGLISH label (see `testNoModeLabelCollidesWithADepartmentName`).
        // The Vietnamese one is still open.
        XCTAssertEqual(ChatMode.engineering.label(.vi), "Developer",
                       "if this failed, the Vietnamese label was chosen — delete this test")
    }

    func testNoModeLabelCollidesWithADepartmentName() {
        // The bug this catches shipped, and Mona found it by looking at the
        // composer: the mode picker said "Engineering" eight points below a
        // department chip that also said "Engineering". Behind the two words
        // are two DIFFERENT coding agents — the chip routes to the local one
        // when a project folder is linked (`EditCodeRouting`), editing files on
        // her own machine for the price of an ordinary turn; the mode starts
        // the cloud run that opens a GitHub branch and can spend 40 credits.
        //
        // So this is not a style rule about duplicate strings. Picking the
        // wrong one of two identically-named controls means the wrong machine
        // and the wrong bill, and nothing on screen distinguishes them.
        for mode in ChatMode.composerCases {
            for dept in DepartmentCatalog.all {
                for lang: AppLanguage in [.en, .vi] {
                    XCTAssertNotEqual(
                        mode.label(lang).lowercased(), dept.name.lowercased(),
                        "the \(mode) mode and the \(dept.key) department are both called "
                        + "\"\(dept.name)\" in \(lang) — they sit in the same composer"
                    )
                }
            }
        }
    }
}
