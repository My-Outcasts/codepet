import XCTest
import SwiftUI
@testable import codepet

/// First-run polish found walking build 8 with a fresh account on 5 Oct.
@MainActor
final class FirstRunPolishTests: XCTestCase {

    // MARK: - CP-066: chat's Grant button is a first grant, not a re-run

    func testChatsGrantAskDoesNotSayReRunning() {
        let en = ProviderConsentCopy.chatMessage(.claudeCode, lang: .en)
        XCTAssertEqual(en, "Answering here uses your Claude plan. Allow Codepet to spend it?")
        XCTAssertFalse(en.contains("Re-running"))
        XCTAssertFalse(ProviderConsentCopy.chatMessage(.claudeCode, lang: .vi).contains("Chạy lại"))
    }

    // MARK: - CP-064: the onboarding button never wraps a letter per line

    func testThePrimaryButtonStaysOneLineInANarrowColumn() throws {
        let narrow = OnboardingPrimaryButtonLabel(title: "Continue", enabled: true)
            .frame(width: 40)                       // far narrower than the word
        let r = ImageRenderer(content: narrow)
        r.scale = 1
        let cg = try XCTUnwrap(r.cgImage)
        XCTAssertLessThan(cg.height, 60, "Continue wrapped onto several lines (5 Oct: one letter per line)")
    }
}
