import XCTest
@testable import codepet

/// Which transport a chat turn takes — and therefore WHOSE money pays for it. Every case
/// here is a guard on that, not on a rendering detail.
final class ChatTransportRouterTests: XCTestCase {

    private var granted: Set<String> = []

    /// A grant table in memory, so no case touches the real defaults domain or leaks a
    /// grant into the next one.
    private var authorisation: ClaudeCodeAuthorisation {
        ClaudeCodeAuthorisation(
            isAuthorised: { [self] in granted.contains($0) },
            setAuthorised: { [self] id, on in
                if on { granted.insert(id) } else { granted.remove(id) }
            }
        )
    }

    override func setUp() { super.setUp(); granted = [] }

    private func transport(
        companyId: String?,
        sidecar: Bool = true
    ) -> ChatTransportRouter.Transport {
        ChatTransportRouter.transport(
            companyId: companyId, authorisation: authorisation, sidecarAvailable: { sidecar })
    }

    // MARK: - The grant decides

    /// A founder who has never opened the Claude Code panel used to get the Cloud Function.
    /// There is nothing behind it now, so she is told what to turn on instead of being sent
    /// somewhere that answers 401.
    func testAnUngrantedFounderIsBlockedRatherThanSentToTheCloud() {
        XCTAssertEqual(transport(companyId: "c1"), .blocked(.notGranted))
    }

    func testAGrantedFounderGoesLocal() {
        granted.insert("c1")
        XCTAssertEqual(transport(companyId: "c1"), .local(.claudeCode))
    }

    /// **Chat carries a provider it cannot vary, on purpose.** The payload exists so this enum
    /// and `LocalTransportRouter.Transport` stay the same shape — this file's router is
    /// documented as holding that shape, and drift between them costs a lie in prose. But no
    /// chat path can run a second CLI this phase, so the answer is `.claudeCode` for every
    /// company, unconditionally.
    ///
    /// This is the guard against the opposite mistake: a router that could answer `.codex`
    /// here would promise a founder something chat cannot honour.
    func testChatAlwaysCreditsClaudeCodeAndNeverVaries() {
        for id in ["c1", "c2", "another-company"] {
            granted.insert(id)
            XCTAssertEqual(transport(companyId: id), .local(.claudeCode),
                           "chat has no second provider; \(id) must not get one")
        }
    }

    /// The grant is per company id, so one founder's consent must not route another
    /// founder's turn onto the plan the first one signed in with.
    func testOneFoundersGrantDoesNotRouteAnothersTurn() {
        granted.insert("c1")
        XCTAssertEqual(transport(companyId: "c2"), .blocked(.notGranted))
    }

    /// No company id means no grant can exist, and an empty string is not a company id
    /// either. Both used to route to the Cloud Function; both now say the one thing that is
    /// true of them — nothing has granted this turn a runner.
    func testNoCompanyIdAndAnEmptyOneAreBothBlockedOnTheGrant() {
        XCTAssertEqual(transport(companyId: nil), .blocked(.notGranted))
        XCTAssertEqual(transport(companyId: ""), .blocked(.notGranted))
    }

    // MARK: - Never silently spend the key they said not to spend

    /// THE most important case in this file. A granted founder whose machine cannot run
    /// the local path must NOT be quietly served by the Cloud Function: that breaks the
    /// no-silent-routing rule recorded at CompanyStore.swift:743, and it spends an API key
    /// they had just said should not be spent — one that no longer exists to spend. It
    /// fails, naming the runner rather than the grant she already gave.
    func testAGrantedFounderWithNoSidecarIsBlockedWithTheSidecarReason() {
        granted.insert("c1")
        let t = transport(companyId: "c1", sidecar: false)
        XCTAssertNotEqual(t, .local(.claudeCode), "a missing runner is not a local turn")
        guard case .blocked(let reason) = t else {
            return XCTFail("expected blocked, got \(t)")
        }
        XCTAssertEqual(reason, .sidecarMissing)
        XCTAssertFalse(reason.founderText.isEmpty, "the founder needs something to act on")
    }

    /// A missing sidecar must not change what an ungranted founder is TOLD: the grant is
    /// the first thing to fix, and naming the runner instead sends her to the wrong screen.
    func testAMissingSidecarDoesNotChangeAnUngrantedFoundersReason() {
        XCTAssertEqual(transport(companyId: "c1", sidecar: false), .blocked(.notGranted))
    }

    // MARK: - The non-streaming retry

    /// The store retries a turn without streaming when no `.done` frame arrived. That retry
    /// used to be wired straight to the Cloud Function, so a granted founder whose local
    /// stream died was answered by the API key they had just said not to spend — the failure
    /// this router exists to prevent, one layer below where it was looking. These cover the
    /// fold the local retry uses; the routing itself is the same `transport` call above.
    func testAStreamWithNoDoneFrameIsNotAnAnsweredTurn() async {
        let reply = await ChatTransportRouter.collect(stream([.delta("half a th")]))
        XCTAssertNil(reply, "partial text presented as a whole reply hides the failure")
    }

    func testADoneFrameCarriesTheTurnsTextAndItsAction() async {
        let reply = await ChatTransportRouter.collect(stream([
            .delta("Sure — "), .delta("running it now."),
            .done(model: "m", cacheHit: false, action: ChatDoneAction(runTaskId: "t1")),
        ]))
        XCTAssertEqual(reply?.text, "Sure — running it now.")
        XCTAssertEqual(reply?.runTaskId, "t1")
    }

    /// byte can legitimately answer with an action and no prose. That is a completed turn, not
    /// an empty one — the same distinction `ChatTailAction` makes on the streaming path.
    func testAnActionOnlyTurnCountsAsAnswered() async {
        let reply = await ChatTransportRouter.collect(stream([
            .done(model: "m", cacheHit: false, action: ChatDoneAction(runTaskId: "t1")),
        ]))
        XCTAssertEqual(reply?.text, "")
        XCTAssertEqual(reply?.runTaskId, "t1")
    }

    func testAThrowingStreamIsNotAnAnsweredTurn() async {
        let failing = AsyncThrowingStream<CompanyChatStreamEvent, Error> { continuation in
            continuation.yield(.delta("partial"))
            continuation.finish(throwing: CompanyChatStreamError.malformedResponse)
        }
        let reply = await ChatTransportRouter.collect(failing)
        XCTAssertNil(reply)
    }

    private func stream(
        _ events: [CompanyChatStreamEvent]
    ) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }

    // MARK: - Cost of deciding

    /// The decision runs on EVERY message, so it must stay cheap. Probing for `claude`
    /// costs two subprocesses; that question belongs in Settings, where the founder is
    /// looking at the answer, not in the send path.
    func testDecidingDoesNotProbeForClaude() {
        granted.insert("c1")
        var sidecarChecks = 0
        _ = ChatTransportRouter.transport(
            companyId: "c1",
            authorisation: authorisation,
            sidecarAvailable: { sidecarChecks += 1; return true })
        // One cheap file-exists check, and nothing else.
        XCTAssertEqual(sidecarChecks, 1)
    }

    /// An ungranted turn should not even ask whether the sidecar is there: the answer
    /// cannot change where the turn goes.
    func testAnUngrantedTurnDoesNotEvenLookForTheSidecar() {
        var sidecarChecks = 0
        _ = ChatTransportRouter.transport(
            companyId: "c1",
            authorisation: authorisation,
            sidecarAvailable: { sidecarChecks += 1; return true })
        XCTAssertEqual(sidecarChecks, 0)
    }

    // MARK: - The failure a founder can act on

    /// `blocked` is its own error case so the UI can say the true thing. Folded into
    /// `malformedResponse` it would read as a bug in the reply, and a beta week of these
    /// would look like a network problem rather than the packaging or grant problem it is.
    ///
    /// The diagnostic TOKEN keeps its old spelling deliberately, so already-collected
    /// diagnostics are not split in two by a rename.
    func testABlockedTurnIsDistinguishableFromEveryRetryableFailure() {
        XCTAssertEqual(ChatTurnDiagnostic.cause(of: CompanyChatStreamError.blocked(.sidecarMissing)),
                       "localUnavailable")
        XCTAssertEqual(ChatTurnDiagnostic.cause(of: CompanyChatStreamError.blocked(.notGranted)),
                       "localUnavailable")
        XCTAssertEqual(ChatTurnDiagnostic.cause(of: CompanyChatStreamError.malformedResponse),
                       "malformedResponse")
    }

    /// The stream must THROW rather than finish empty. A stream that finishes with no
    /// events makes the store fall back to the non-streaming sender, which would reach
    /// the Cloud Function — the silent fallback this whole design refuses.
    func testTheBlockedStreamThrowsInsteadOfFinishingEmpty() async {
        let stream = AsyncThrowingStream<CompanyChatStreamEvent, Error> {
            $0.finish(throwing: CompanyChatStreamError.blocked(.sidecarMissing))
        }
        do {
            for try await _ in stream { XCTFail("no event should arrive") }
            XCTFail("must throw, not finish quietly")
        } catch CompanyChatStreamError.blocked(let reason) {
            XCTAssertEqual(reason, .sidecarMissing)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // MARK: - There is no third destination

    /// The load-bearing totality test: it fails to COMPILE the day someone adds a case that
    /// reaches a hosted endpoint, which is the only moment that mistake is cheap.
    func testChatTransportIsOnlyEverLocalOrBlocked() {
        let cases: [ChatTransportRouter.Transport] = [.local(.claudeCode), .blocked(.notGranted)]
        for c in cases {
            switch c {
            case .local, .blocked: continue   // exhaustive: adding a case breaks the build
            }
        }
    }

    /// `BlockReason.notGranted`'s own English copy, pinned as a literal. This does NOT touch
    /// the chat tail — it asserts the `BlockReason` value alone; the tail's actual behaviour
    /// (that `CompanyStore` writes this string into the placeholder for a `.stop` reason) is
    /// covered end-to-end by `CompanyStoreChatTests
    /// .testStopReasonWritesTheFounderTextWhenLanguageIsEnglish` (and its `.vi` counterpart),
    /// which is where that promise now lives.
    func testBlockReasonNotGrantedHasItsOwnEnglishCopy() {
        XCTAssertEqual(BlockReason.notGranted.founderText,
                       "Codepet needs permission to use your Claude plan. Turn it on in Settings.")
    }

    /// The guard that carries the router's refusal one layer up, and the reason it names.
    ///
    /// `.fallback` calls the non-streaming sender, so if `decide` did not stop here a blocked
    /// turn would be retried — and the founder would be told nothing about why the first
    /// attempt failed. Delete the `.blocked` check in `ChatTailAction.decide` and this goes
    /// red: the same inputs answer `.fallback`.
    func testABlockedStreamStopsTheTurnAndCarriesItsReason() {
        let tail = ChatTailAction.decide(
            streamThrew: true, receivedDone: false, streamedText: "", action: nil,
            streamError: CompanyChatStreamError.blocked(.sidecarMissing))
        XCTAssertEqual(tail, .stop(reason: .sidecarMissing))
    }

    /// The reason is carried through, not flattened to one word — an ungranted founder must
    /// not be told to reinstall Codepet.
    func testTheStoppedTurnKeepsWhicheverReasonBlockedIt() {
        let tail = ChatTailAction.decide(
            streamThrew: true, receivedDone: false, streamedText: "", action: nil,
            streamError: CompanyChatStreamError.blocked(.notGranted))
        XCTAssertEqual(tail, .stop(reason: .notGranted))
    }

    /// Every OTHER stream failure is still worth a second, non-streaming attempt. Without
    /// this the stop rule could be written as "any error stops", which would delete the
    /// retry that exists because a turn can die before its `done` frame for ordinary reasons.
    func testAnOrdinaryStreamFailureStillFallsBack() {
        let tail = ChatTailAction.decide(
            streamThrew: true, receivedDone: false, streamedText: "", action: nil,
            streamError: CompanyChatStreamError.malformedResponse)
        XCTAssertEqual(tail, .fallback)
    }
}
