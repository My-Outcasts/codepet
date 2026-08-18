// codepetTests/TwoModeHeroTests.swift
import SwiftUI
import XCTest
@testable import codepet

/// Guards for the pieces the two-mode hero and composer are built out of. Pure
/// values only — the XCTest host on Xcode 26.2 crashes when a `@MainActor`
/// `ObservableObject` deallocates, so anything provable off a value type is.
final class TwoModeHeroTests: XCTestCase {

    private func task(_ id: String, _ title: String, who: TaskWho = .does,
                      phase: RoadmapPhase = .find, dept: String? = nil,
                      done: Bool = false, drafted: Bool = false,
                      dependsOn: [String] = []) -> RoadmapTask {
        RoadmapTask(id: id, title: title, detail: "", phase: phase, who: who,
                    dependsOn: dependsOn, done: done, drafted: drafted, dept: dept)
    }

    private func company(tasks: [RoadmapTask], founder: String? = "Mona",
                         project: String? = "Codepet") -> CompanyState {
        var c = CompanyState.empty
        c.brief.founderName = founder
        c.brief.projectName = project
        c.tasks = tasks
        return c
    }

    // MARK: - The greeting accents one word, not the whole line

    /// The prototype accents only the verb (`.greet b`). A gradient across the
    /// whole sentence — what the dock does — makes the sentence the decoration.
    func testQuestionSegmentsAccentOnlyTheVerb() {
        let s = ChatLandingState(company: company(tasks: []), now: Date(), language: .en)
        let segments = s.questionSegments
        XCTAssertEqual(segments.filter(\.accent).map(\.text), ["build"])
        XCTAssertEqual(segments.map(\.text).joined(), s.question,
                       "the segments must reassemble into exactly the question")
    }

    func testQuestionSegmentsAccentTheVietnameseVerb() {
        let s = ChatLandingState(company: company(tasks: []), now: Date(), language: .vi)
        XCTAssertEqual(s.questionSegments.filter(\.accent).map(\.text), ["xây"])
        XCTAssertEqual(s.questionSegments.map(\.text).joined(), s.question)
    }

    /// A project whose name contains the verb must not light up twice — only the
    /// FIRST occurrence is the verb, and the rest is the founder's own noun.
    func testQuestionSegmentsAccentOnlyTheFirstOccurrence() {
        let s = ChatLandingState(company: company(tasks: [], project: "Buildkite"),
                                 now: Date(), language: .en)
        XCTAssertEqual(s.questionSegments.filter(\.accent).count, 1)
        XCTAssertEqual(s.questionSegments.map(\.text).joined(), s.question)
    }

    // MARK: - Who is signed in — ONE answer

    /// The bug this replaces: the rail said "Founder" while the hero said "there",
    /// both on screen at once, for the same unknown founder.
    func testTheRailAndTheHeroCannotDisagreeAboutAnUnknownFounder() {
        let brief = CompanyBrief()
        let label = FounderName.label(brief: brief, accountName: nil, language: .en)
        let greeting = ChatLandingState(company: company(tasks: [], founder: nil),
                                        now: Date(), language: .en).greeting
        XCTAssertEqual(label, "You")
        XCTAssertFalse(greeting.contains("Founder"))
        XCTAssertFalse(greeting.contains("there"),
                       "no placeholder noun — the clause is dropped instead: \(greeting)")
    }

    /// "Good afternoon." is a complete greeting. "Good afternoon, there." is a
    /// stock chatbot tic that makes the app sound like it is pretending to know you.
    func testAnUnknownFounderGetsAGreetingWithNoNameClause() {
        let at3pm = Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: Date())!
        let s = ChatLandingState(company: company(tasks: [], founder: nil),
                                 now: at3pm, language: .en)
        XCTAssertEqual(s.greeting, "Good afternoon.")
    }

    func testAKnownFounderIsNamed() {
        let at3pm = Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: Date())!
        let s = ChatLandingState(company: company(tasks: [], founder: "Mona"),
                                 now: at3pm, language: .en)
        XCTAssertEqual(s.greeting, "Good afternoon, Mona.")
    }

    /// A founder who signed in with Google was called "there" by an app that
    /// already had their name — `AuthManager` captures it into
    /// `AppState.displayName` and no greeting ever read it.
    func testTheAccountNameIsUsedWhenTheBriefHasNone() {
        let at3pm = Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: Date())!
        let s = ChatLandingState(company: company(tasks: [], founder: nil), now: at3pm,
                                 language: .en, accountName: "Mona Truong")
        XCTAssertEqual(s.greeting, "Good afternoon, Mona Truong.")
    }

    /// The brief is what the founder typed about their own company; the account
    /// name is whatever their Google profile happens to say.
    func testTheBriefOutranksTheAccountName() {
        XCTAssertEqual(FounderName.resolve(brief: {
            var b = CompanyBrief(); b.founderName = "Mona"; return b
        }(), accountName: "monatruong@gmail.com"), "Mona")
    }

    /// A brief saved with a stray space is not a name.
    func testWhitespaceOnlyNamesCountAsAbsent() {
        var b = CompanyBrief()
        b.founderName = "   "
        XCTAssertNil(FounderName.resolve(brief: b, accountName: "  "))
        XCTAssertEqual(FounderName.resolve(brief: b, accountName: " Mona "), "Mona")
    }

    // MARK: - The beacon card

    /// A department-owned task: the department drafts, the founder approves. The
    /// department is NAMED — "someone can draft this" is not an offer.
    func testOfferForADepartmentTaskNamesTheDepartmentAndOffersToRun() {
        let t = task("t1", "Write your positioning one-pager", dept: "mkt")
        let offer = BeaconOffer.offer(for: t, in: [t], host: "byte", language: .en)
        XCTAssertEqual(offer?.primary, .run("Run it"))
        XCTAssertEqual(offer?.title, "Write your positioning one-pager")
        XCTAssertTrue(offer?.detail.contains("Marketing") == true, offer?.detail ?? "nil")
    }

    /// `who == .you` cannot be run for the founder, so the button must not say it
    /// will be. This is the prototype's second beacon.
    func testOfferForAFounderOnlyTaskOffersAWalkthroughNotARun() {
        let t = task("t1", "Talk to 5 potential users", who: .you)
        let offer = BeaconOffer.offer(for: t, in: [t], host: "byte", language: .en)
        XCTAssertEqual(offer?.primary, .walkthrough("Walk me through it"))
        XCTAssertTrue(offer?.detail.contains("byte") == true, offer?.detail ?? "nil")
    }

    /// A draft already exists. Re-running would spend credits to produce a second
    /// copy of something the founder is already being asked to look at.
    func testOfferForADraftedTaskOffersReviewNotRun() {
        let t = task("t1", "Write your positioning one-pager", dept: "mkt", drafted: true)
        let offer = BeaconOffer.offer(for: t, in: [t], host: "byte", language: .en)
        XCTAssertEqual(offer?.primary, .review("Review it"))
    }

    /// `drafted` outranks `who`: a founder-only task can still have a prepared
    /// draft waiting, and the waiting draft is the newer fact.
    func testADraftedFounderTaskStillOffersReview() {
        let t = task("t1", "Talk to 5 potential users", who: .you, drafted: true)
        XCTAssertEqual(BeaconOffer.offer(for: t, in: [t], host: "byte", language: .en)?.primary,
                       .review("Review it"))
    }

    /// One actionable task means `Something else` would do nothing, so it must not
    /// be on screen.
    func testSomethingElseIsHiddenWhenThereIsNowhereElseToGo() {
        let t = task("t1", "The only thing", dept: "mkt")
        XCTAssertEqual(BeaconOffer.offer(for: t, in: [t], host: "byte", language: .en)?.canSkip,
                       false)
    }

    func testSomethingElseAppearsWhenASecondCandidateExists() {
        let a = task("t1", "First", dept: "mkt")
        let b = task("t2", "Second", dept: "eng")
        XCTAssertEqual(BeaconOffer.offer(for: a, in: [a, b], host: "byte", language: .en)?.canSkip,
                       true)
    }

    /// Two tasks in the SAME department still means there is somewhere else to go.
    /// `RoadmapEngine.suggestedNext` dedupes by department, which is right for a
    /// parallel fan-out and wrong for this button — hence `candidates`.
    func testSomethingElseAppearsForTwoTasksInOneDepartment() {
        let a = task("t1", "First", dept: "mkt")
        let b = task("t2", "Second", dept: "mkt")
        XCTAssertEqual(BeaconOffer.offer(for: a, in: [a, b], host: "byte", language: .en)?.canSkip,
                       true)
    }

    func testNoBeaconMeansNoOffer() {
        XCTAssertNil(BeaconOffer.offer(for: nil, in: [], host: "byte", language: .en))
    }

    // MARK: - `Something else` walks the same list the beacon starts

    /// If `candidates.first` ever stopped being the beacon, the card would open on
    /// one task and the skip button would jump backwards into another.
    func testCandidatesStartAtTheBeacon() {
        let tasks = [task("t1", "First", dept: "mkt"),
                     task("t2", "Second", dept: "eng"),
                     task("t3", "Third", dept: "design")]
        XCTAssertEqual(BeaconOffer.candidates(tasks).first?.id,
                       RoadmapEngine.nextStep(tasks)?.id)
    }

    func testCandidatesExcludeDoneAndBlockedWork() {
        let tasks = [task("t1", "Done", dept: "mkt", done: true),
                     task("t2", "Open", dept: "eng"),
                     task("t3", "Blocked", dept: "design", dependsOn: ["t2"])]
        XCTAssertEqual(BeaconOffer.candidates(tasks).map(\.id), ["t2"])
    }

    // MARK: - Which shell is hosting the chat

    /// The dock's collapse button and history icon are dock facts. In the pane
    /// there is no dock to collapse and the rail's Recent list IS the history.
    func testTwoModeDropsTheDockChrome() {
        XCTAssertTrue(ChatSurface.dock.showsDockChrome)
        XCTAssertFalse(ChatSurface.twoMode.showsDockChrome)
    }

    /// The composer's mode pill retires with `ChatMode` — the mode is a place in
    /// the rail. If this ever flips back the two-mode shell asks the founder the
    /// same question twice.
    func testTwoModeHasNoComposerModePill() {
        XCTAssertFalse(ChatSurface.twoMode.showsModePill)
        XCTAssertTrue(ChatSurface.dock.showsModePill, "main's shell keeps it")
    }

    func testTwoModeShowsThreeDepartmentChips() {
        XCTAssertEqual(ChatSurface.twoMode.visibleDeptChips, 3)
        XCTAssertEqual(ChatSurface.dock.visibleDeptChips, 2, "380pt fits two")
    }

    /// The default is what makes all of this additive: `AppShellView` sets nothing
    /// and must keep rendering exactly what it rendered before.
    func testTheDefaultSurfaceIsTheDock() {
        XCTAssertEqual(EnvironmentValues().chatSurface, .dock)
    }

    // MARK: - The rail must not jump between modes

    /// The hint's visibility is a property of the account, not of where the
    /// founder is standing. Gated on `mode` it made the rail two lines taller in
    /// Ask than in Developer, so every switch bumped `+ New` and the nav below it.
    func testTheHintRetiresOnceDeveloperHasBeenOpenedAndNotBefore() {
        let name = "two-mode-hint-\(#function)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)

        XCTAssertTrue(WorkspaceMode.showsHint(in: d), "a new account is told what the two doors are")
        WorkspaceMode.ask.persist(to: d)
        XCTAssertTrue(WorkspaceMode.showsHint(in: d), "staying in Ask does not retire it")
        WorkspaceMode.developer.persist(to: d)
        XCTAssertFalse(WorkspaceMode.showsHint(in: d))
        WorkspaceMode.ask.persist(to: d)
        XCTAssertFalse(WorkspaceMode.showsHint(in: d), "going back to Ask must not bring it back")

        d.removePersistentDomain(forName: name)
    }
}
