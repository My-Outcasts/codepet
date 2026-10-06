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

    // MARK: - no greeting after onboarding

    private func task(_ id: String) -> RoadmapTask {
        RoadmapTask(id: id, title: "Task " + id, detail: "", phase: .find, who: .does)
    }

    private func store(greeted: @escaping () -> Void = {}) -> CompanyStore {
        CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                     roadmapFetcher: { _, _, _ in [self.task("a"), self.task("b")] },
                     tasksSaver: { _, _ in true },
                     greetedSaver: { _, _ in greeted(); return true })
    }

    /// The greeting ran only at hydrate — before onboarding, when a new account has no tasks,
    /// so the gate (needs tasks) skipped it and it never came. Finishing onboarding must greet.
    func testFinishingOnboardingWithARoadmapGreetsOnce() async {
        var saves = 0
        let s = store(greeted: { saves += 1 })
        await s.hydrate(companyId: "u")
        await s.greetIfNeeded(language: .en)                  // what ContentView does at sign-in
        XCTAssertTrue(s.chatMessages.isEmpty, "no tasks yet, so no greeting at sign-in")
        _ = await s.scaffoldFromOnboarding(brief: CompanyBrief(projectName: "Shelfie"), token: s.onboardingToken)
        await s.finishOnboarding(brief: CompanyBrief(projectName: "Shelfie"), token: s.onboardingToken)
        XCTAssertEqual(s.chatMessages.count, 1, "the founder should be greeted once onboarding ends")
        XCTAssertEqual(saves, 1)
    }

    /// CP-067: the scaffold can still be running when she presses Start building. The greeting
    /// must arrive when its roadmap lands, not be skipped for good.
    func testARoadmapThatLandsAfterFinishStillGreets() async {
        let s = store()
        await s.hydrate(companyId: "u")
        let token = s.onboardingToken
        await s.finishOnboarding(brief: CompanyBrief(projectName: "Shelfie"), token: token)
        XCTAssertTrue(s.chatMessages.isEmpty, "no roadmap yet")
        _ = await s.scaffoldFromOnboarding(brief: CompanyBrief(projectName: "Shelfie"), token: token)
        XCTAssertEqual(s.chatMessages.count, 1)
    }

    func testStillInTheWizardDoesNotGreet() async {
        let s = store()
        await s.hydrate(companyId: "u")
        _ = await s.scaffoldFromOnboarding(brief: CompanyBrief(projectName: "Shelfie"), token: s.onboardingToken)
        XCTAssertTrue(s.chatMessages.isEmpty, "the reveal is still on screen; greet after Start building")
    }
}
