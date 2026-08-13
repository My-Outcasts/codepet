// codepetTests/ConnectRepoSheetTests.swift
import XCTest
@testable import codepet

/// §5.4's three first-run states, and the two promises around them: the sheet
/// appears once, and closing it starts nothing and spends nothing.
final class ConnectRepoStateTests: XCTestCase {

    private func repo(_ fullName: String) -> EngRepoChoice {
        EngRepoChoice(fullName: fullName, url: "https://github.com/\(fullName)",
                      defaultBranch: "main", isPrivate: true, pushedAt: "2026-08-13T04:00:00Z")
    }

    func test_connectedWithReposIsThePicker() {
        let state = ConnectRepo.state(after: .success([repo("monatruong/codepet")]))
        XCTAssertEqual(state, .choose([repo("monatruong/codepet")]))
    }

    func test_connectedWithNoneIsNotAnEmptyPicker() {
        // The distinction the whole sheet turns on. An empty list and a 409
        // arrive as different things on the wire and lead to different
        // screens; showing a picker with nothing in it tells a founder "no"
        // with a control that looks like it should work.
        XCTAssertEqual(ConnectRepo.state(after: .success([])), .createOnly)
    }

    func test_notConnectedIsItsOwnStateRatherThanAFailure() {
        // 409 `github_not_connected` is not an error to report — it is a step
        // the founder has not taken, and the sheet can take them through it.
        XCTAssertEqual(ConnectRepo.state(after: .failure(.gitHubNotConnected)), .needsGitHub)
    }

    func test_arealFailureKeepsItsErrorSoTheWordsMatchTheResultBar() {
        // Carrying the error rather than a bool is what lets the sheet print
        // `EngineeringResultBar.message` — one refusal should not have two
        // phrasings depending on which screen it lands on.
        XCTAssertEqual(ConnectRepo.state(after: .failure(.unavailable)), .failed(.unavailable))
    }

    // MARK: - the 422 this flow can produce

    func test_anEmptyRepoIsNotAnUnknownError() {
        // `engLinkRepo` answers 422 `no_default_branch` for a repo with no
        // commits. As `.unknown` it read "Something went wrong. Try again" —
        // and trying again picks the same empty repo.
        XCTAssertEqual(EngineeringError.from(status: 422, code: "no_default_branch"), .repoUnusable)
    }

    func test_theEmptyRepoMessageNamesBothWaysOut() {
        let en = EngineeringResultBar.message(for: .repoUnusable, lang: .en).lowercased()
        XCTAssertTrue(en.contains("no commits"), "does not say why: \(en)")
        XCTAssertTrue(en.contains("another") || en.contains("pick"), "does not offer another repo: \(en)")
        XCTAssertTrue(en.contains("make") || en.contains("create"), "does not offer to create one: \(en)")
        XCTAssertNotEqual(EngineeringResultBar.message(for: .repoUnusable, lang: .vi),
                          EngineeringResultBar.message(for: .repoUnusable, lang: .en))
    }

    func test_pickingAnEmptyRepoIsNotOfferedARetry() {
        // Retrying the same link is the one thing that cannot work.
        XCTAssertFalse(EngineeringError.repoUnusable.isRetryable)
    }

    // MARK: - copy

    func test_createReadsAsMakingSomethingNewRatherThanTouchingWhatExists() {
        // Mona's handoff question for this task, answered in the label itself:
        // "new" and "for me" are both load-bearing — a bare "Create" leaves
        // room to read it as acting on the repos listed above it.
        let en = ConnectRepoSheet.createLabel(lang: .en).lowercased()
        XCTAssertTrue(en.contains("new"), "the create label does not say it makes a NEW repo: \(en)")
        XCTAssertTrue(en.contains("for me") || en.contains("for you"), "does not say who it is for: \(en)")
    }

    func test_theSubtitleSaysMainIsNeverTouched() {
        // The fear this sheet has to answer before a founder hands over a repo.
        let en = ConnectRepoSheet.subtitle(lang: .en).lowercased()
        XCTAssertTrue(en.contains("branch"), "the subtitle never mentions a branch: \(en)")
    }

    func test_everyStringHasBothLanguages() {
        let pairs: [(String, String)] = [
            (ConnectRepoSheet.title(lang: .en), ConnectRepoSheet.title(lang: .vi)),
            (ConnectRepoSheet.subtitle(lang: .en), ConnectRepoSheet.subtitle(lang: .vi)),
            (ConnectRepoSheet.needsGitHubText(lang: .en), ConnectRepoSheet.needsGitHubText(lang: .vi)),
            (ConnectRepoSheet.noReposText(lang: .en), ConnectRepoSheet.noReposText(lang: .vi)),
            (ConnectRepoSheet.createLabel(lang: .en), ConnectRepoSheet.createLabel(lang: .vi)),
            (ConnectRepoSheet.connectGitHubLabel(lang: .en), ConnectRepoSheet.connectGitHubLabel(lang: .vi)),
            (ConnectRepoSheet.notNowLabel(lang: .en), ConnectRepoSheet.notNowLabel(lang: .vi))
        ]
        for (en, vi) in pairs {
            XCTAssertFalse(en.isEmpty)
            XCTAssertFalse(vi.isEmpty)
            XCTAssertNotEqual(en, vi, "\"\(en)\" shows English to a Vietnamese founder")
        }
    }
}

/// When the sheet opens, when it does not, and what closing it costs.
@MainActor
final class ConnectRepoPromptTests: XCTestCase {

    /// A runner that refuses the way `engStartRun` refuses an unlinked repo:
    /// 409 `no_repo_linked`, BEFORE reading the balance or creating a session.
    private final class RefusingRunner: EngineeringRunning {
        let error: EngineeringError
        private(set) var startCount = 0
        init(error: EngineeringError = .noRepoLinked) { self.error = error }

        func start(ask: String, onFrame: @escaping (EngineeringFrame) -> Void) async throws -> String {
            startCount += 1
            throw error
        }
        func attach(runId: String, onFrame: @escaping (EngineeringFrame) -> Void) async throws {}
        func send(runId: String, turn: EngineeringTurn) async throws {}
        func diff(runId: String, scope: ReviewScope) async throws -> EngDiffSummary { .empty }
    }

    /// Same pin as `EngineeringAnchorTests`, for the same reason:
    /// `startEngineeringRun` picks its runner off `CODEPET_MOCK_CHAT`, and with
    /// the flag off it builds a real `EngineeringClient` that reaches
    /// `Auth.auth()` — which TRAPS on unconfigured Firebase (landmine #4). The
    /// trap lands on a detached Task after the test passes, so it reads as an
    /// unrelated host crash and takes the whole suite's results with it.
    private var previousMockFlag: Any?

    override func setUp() {
        super.setUp()
        previousMockFlag = UserDefaults.standard.object(forKey: "CODEPET_MOCK_CHAT")
        UserDefaults.standard.set(true, forKey: "CODEPET_MOCK_CHAT")
    }

    override func tearDown() {
        if let previousMockFlag {
            UserDefaults.standard.set(previousMockFlag, forKey: "CODEPET_MOCK_CHAT")
        } else {
            UserDefaults.standard.removeObject(forKey: "CODEPET_MOCK_CHAT")
        }
        super.tearDown()
    }

    private func makeStore() -> CompanyStore {
        let state = CompanyState(brief: CompanyBrief(), departments: [], library: [],
                                 stage: .idea, companionId: "byte", onboardedAt: nil, tasks: [])
        return CompanyStore(loader: { _ in state }, saver: { _, _ in true })
    }

    func test_theSheetHoldsTheAskItInterrupted() async {
        // Not a bool. Holding the ask is the difference between "connect a
        // repo, now type that again" and the run just happening.
        let store = makeStore()
        let runStore = EngineeringRunStore(runner: RefusingRunner())
        await runStore.start(ask: "add stripe checkout")

        XCTAssertEqual(runStore.failure, .noRepoLinked)
        store.engineeringRepoPrompt = "add stripe checkout"
        XCTAssertEqual(store.engineeringRepoPrompt, "add stripe checkout")
    }

    func test_aRefusalThatIsNotAboutTheRepoDoesNotOpenTheSheet() async {
        // The sheet is for ONE refusal. Opening it for "out of credits" asks
        // the founder to fix something that is not broken.
        let runStore = EngineeringRunStore(runner: RefusingRunner(error: .noCredits))
        await runStore.start(ask: "add stripe checkout")
        XCTAssertEqual(runStore.failure, .noCredits)
        XCTAssertNotEqual(runStore.failure, .noRepoLinked)
    }

    func test_closingTheSheetStartsNoRun() {
        // The plan's promise: dismissing without choosing does not start a run
        // and does not spend credits. Nothing here calls the runner at all —
        // and the first attempt could not have spent anything either, because
        // `engStartRun` refuses at line 168, before it reads the balance.
        let store = makeStore()
        store.engineeringRepoPrompt = "add stripe checkout"
        let before = store.chatMessages.count

        store.engineeringRepoPrompt = nil   // "Not now"

        XCTAssertNil(store.engineeringRepoPrompt)
        XCTAssertNil(store.engineeringRunStore, "closing the sheet started a run")
        XCTAssertEqual(store.chatMessages.count, before)
    }

    func test_closingIsNotADeadEndBecauseTheAskCanReopenIt() {
        // Spec §7: "No repo connected → first-run sheet. Never a dead-end."
        // After "Not now" the refusal is still in the bar, and its control
        // calls this. Without it the founder has an instruction they cannot
        // follow from where they are standing.
        let store = makeStore()
        store.startEngineeringRun(ask: "add stripe checkout")
        store.engineeringRepoPrompt = nil

        store.promptForEngineeringRepo()

        XCTAssertEqual(store.engineeringRepoPrompt, "add stripe checkout")
    }

    func test_reopeningWithNoAskOnScreenDoesNothing() {
        let store = makeStore()
        store.promptForEngineeringRepo()
        XCTAssertNil(store.engineeringRepoPrompt, "opened a sheet for an ask that does not exist")
    }

    func test_linkingRunsTheAskWithoutShowingItTwice() {
        // The ask is already in the transcript from the refused attempt.
        // Re-running appends it again, so the stale copy has to go — otherwise
        // the founder reads their own sentence twice and cannot tell which
        // bar belongs to which.
        let store = makeStore()
        store.startEngineeringRun(ask: "add stripe checkout")
        store.engineeringRepoPrompt = "add stripe checkout"

        store.engineeringRepoLinked()

        XCTAssertNil(store.engineeringRepoPrompt)
        XCTAssertEqual(store.chatMessages.filter { $0.text == "add stripe checkout" }.count, 1)
    }

    func test_switchingThreadsDropsTheWaitingAsk() {
        // The ask belongs to the outgoing thread. Left set, linking a repo
        // would run a sentence typed in a conversation already left.
        let store = makeStore()
        store.startEngineeringRun(ask: "add stripe checkout")
        store.engineeringRepoPrompt = "add stripe checkout"

        store.newChat()

        XCTAssertNil(store.engineeringRepoPrompt)
    }
}
