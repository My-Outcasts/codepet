// codepetTests/EngineeringReachabilityTests.swift
import XCTest
@testable import codepet

/// Can the founder actually GET to each engineering surface?
///
/// This suite exists because the answer was no, and every other suite was
/// green. `EngineeringResultBar` and `EngineeringApprovalCard` were built,
/// unit-tested, layout-tested and given `#Preview`s — and nothing in the app
/// ever constructed either one. `openEngineeringReview()` had no caller. A run
/// started, streamed frames into its store, paused for permission and stopped
/// at its budget entirely invisibly: the founder saw their own message and
/// then nothing, forever.
///
/// No unit test can catch that, because every unit was correct. The missing
/// property is between them — "something reachable renders this" — so the only
/// honest way to assert it is to look at the sources.
///
/// It reads the tree via `#filePath`, which is the test file's own location at
/// compile time and therefore correct in any checkout, including CI. `#Preview`
/// blocks are stripped before searching: a preview is exactly what these views
/// already had, and counting one as reachability would make this suite green
/// against the bug it exists to prevent.
final class EngineeringReachabilityTests: XCTestCase {

    /// Every `.swift` file under `codepet/`, with `#if DEBUG` regions removed.
    private static let sources: [String: String] = {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // codepetTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("codepet")
        guard let walker = FileManager.default.enumerator(at: root,
                                                          includingPropertiesForKeys: nil)
        else { return [:] }
        var out: [String: String] = [:]
        for case let url as URL in walker where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            out[url.lastPathComponent] = stripDebugRegions(text)
        }
        return out
    }()

    /// Drops `#if DEBUG` … `#endif`, tracking nesting so an inner `#if` cannot
    /// close an outer one. Preview code lives in these regions; so does the
    /// mock-runner branch, which is deliberate — a surface only a mock reaches
    /// is not a surface the founder reaches.
    private static func stripDebugRegions(_ text: String) -> String {
        var depth = 0            // how many #if of any kind we are inside
        var debugAt: Int?        // the depth at which a DEBUG region opened
        var kept: [Substring] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("#if") {
                depth += 1
                if debugAt == nil, t.contains("DEBUG") { debugAt = depth }
                continue
            }
            if t.hasPrefix("#endif") {
                if debugAt == depth { debugAt = nil }
                depth = max(0, depth - 1)
                continue
            }
            if debugAt == nil { kept.append(line) }
        }
        return kept.joined(separator: "\n")
    }

    /// Files that mention `needle`, ignoring the one that defines the type.
    private func callers(of needle: String, definedIn definition: String) -> [String] {
        Self.sources
            .filter { $0.key != definition && $0.value.contains(needle) }
            .keys.sorted()
    }

    func testTheSourcesWereFoundAtAll() {
        // Without this, every assertion below passes vacuously on an empty
        // dictionary — the suite would go green precisely when it stopped
        // being able to check anything.
        XCTAssertGreaterThan(Self.sources.count, 50,
                             "found \(Self.sources.count) source files; the path is wrong")
        XCTAssertNotNil(Self.sources["CopilotChatView.swift"])
    }

    func testTheResultBarIsRenderedSomewhereTheFounderCanSee() {
        let sites = callers(of: "EngineeringResultBar(", definedIn: "EngineeringResultBar.swift")
        XCTAssertFalse(sites.isEmpty,
                       "nothing outside a #Preview constructs the result bar — an engineering run is invisible")
    }

    func testTheApprovalCardIsRenderedSomewhereTheFounderCanSee() {
        // The worst of the three to lose: the run does not merely look stuck,
        // it IS stuck, waiting on an answer to a question never asked.
        let sites = callers(of: "EngineeringApprovalCard(", definedIn: "EngineeringApprovalCard.swift")
        XCTAssertFalse(sites.isEmpty,
                       "nothing constructs the approval card — a paused run can never be answered")
    }

    func testTheReviewPaneIsReachable() {
        XCTAssertFalse(callers(of: "ReviewPane(", definedIn: "ReviewPane.swift").isEmpty,
                       "nothing constructs the Review pane")
        XCTAssertFalse(callers(of: "EngineeringWorkspaceView(", definedIn: "EngineeringWorkspaceView.swift").isEmpty,
                       "nothing constructs the workspace that holds the Review pane")
    }

    func testSomethingActuallyOpensReview() {
        // The workspace renders when `engineeringReviewRunId` is set, and only
        // `openEngineeringReview()` sets it. Rendering it is not enough if no
        // control ever asks for it — which was the shipped state.
        let sites = callers(of: "openEngineeringReview()", definedIn: "CompanyStore.swift")
        XCTAssertFalse(sites.isEmpty,
                       "no control calls openEngineeringReview() — the pane can render but never opens")
    }

    func testTheConnectRepoSheetIsPresentedSomewhere() {
        // Without this the refusal "connect one first" is a true statement
        // with nothing anywhere that connects one — the exact dead end the
        // spec's §7 forbids for this state.
        XCTAssertFalse(callers(of: "ConnectRepoSheet(", definedIn: "ConnectRepoSheet.swift").isEmpty,
                       "nothing presents the connect-or-create sheet")
    }

    func testTheRefusalCanReopenTheSheet() {
        // The sheet shows once. After "Not now", the control on the refusal is
        // the only way back; if nothing calls this, closing it is permanent.
        XCTAssertFalse(callers(of: "promptForEngineeringRepo()", definedIn: "CompanyStore.swift").isEmpty,
                       "no control reopens the connect sheet after it is dismissed")
    }

    func testTheEngineeringModeHasASendPath() {
        XCTAssertFalse(callers(of: "startEngineeringRun(", definedIn: "CompanyStore.swift").isEmpty,
                       "no surface starts an engineering run")
    }
}

/// The anchor that puts a run's bar next to the ask that started it.
@MainActor
final class EngineeringAnchorTests: XCTestCase {

    /// `startEngineeringRun` picks its runner off `CODEPET_MOCK_CHAT`, and with
    /// the flag off it builds a real `EngineeringClient` that reaches
    /// `Auth.auth()` — which TRAPS rather than throwing when `FirebaseApp` is
    /// unconfigured (landmine #4). The trap lands on the detached Task after
    /// the test has already passed, so it reads as an unrelated host crash.
    /// Pinned here and restored, because it is process-global state.
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

    /// Injected loader/saver, never the bare `CompanyStore()`. The default
    /// loader reaches `Auth.auth()`, which TRAPS rather than throwing when
    /// `FirebaseApp` is unconfigured — landmine #4 in CLAUDE.md. The suite
    /// still passes with the bare init; it just leaves a fatal error in the
    /// log that looks exactly like the Xcode 26.2 host crash and is not it.
    private func makeStore() -> CompanyStore {
        let state = CompanyState(brief: CompanyBrief(), departments: [], library: [],
                                 stage: .idea, companionId: "byte", onboardedAt: nil, tasks: [])
        return CompanyStore(loader: { _ in state }, saver: { _, _ in true })
    }

    func testStartingARunAnchorsItToTheAskThatStartedIt() {
        let store = makeStore()
        store.startEngineeringRun(ask: "add stripe checkout")
        XCTAssertEqual(store.engineeringRunAnchorId, store.chatMessages.last?.id,
                       "the bar would render against the wrong message, or none")
    }

    func testABlankAskStartsNothingAndAnchorsNothing() {
        let store = makeStore()
        store.startEngineeringRun(ask: "   ")
        XCTAssertNil(store.engineeringRunAnchorId)
        XCTAssertTrue(store.chatMessages.isEmpty)
    }

    func testANewChatDropsTheRunRatherThanLeakingItIntoTheEmptyThread() {
        // The anchor message is gone with the outgoing thread. Left set, the
        // bar renders against a message this thread does not contain — or
        // silently vanishes while the founder believes the run is still theirs.
        let store = makeStore()
        store.startEngineeringRun(ask: "add stripe checkout")
        store.newChat()
        XCTAssertNil(store.engineeringRunAnchorId)
        XCTAssertNil(store.engineeringRunStore)
        XCTAssertNil(store.engineeringReviewRunId)
    }
}
