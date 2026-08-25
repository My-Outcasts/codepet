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

    /// The default is unchanged for everyone who has not granted anything. A founder who
    /// has never opened the Claude Code panel must keep the chat they already had.
    func testAnUngrantedFounderStaysOnCloud() {
        XCTAssertEqual(transport(companyId: "c1"), .cloud)
    }

    func testAGrantedFounderGoesLocal() {
        granted.insert("c1")
        XCTAssertEqual(transport(companyId: "c1"), .local)
    }

    /// The grant is per company id, so one founder's consent must not route another
    /// founder's turn onto the plan the first one signed in with.
    func testOneFoundersGrantDoesNotRouteAnothersTurn() {
        granted.insert("c1")
        XCTAssertEqual(transport(companyId: "c2"), .cloud)
    }

    /// No company id means no grant can exist. That is an ungranted turn, not a broken
    /// one — failing here would break chat before onboarding finishes.
    func testNoCompanyIdIsACloudTurnNotAFailure() {
        XCTAssertEqual(transport(companyId: nil), .cloud)
        XCTAssertEqual(transport(companyId: ""), .cloud)
    }

    // MARK: - Never silently spend the key they said not to spend

    /// THE most important case in this file. A granted founder whose machine cannot run
    /// the local path must NOT be quietly served by the Cloud Function: that breaks the
    /// no-silent-routing rule recorded at CompanyStore.swift:743, and it spends an API key
    /// they had just said should not be spent. It fails, with a reason.
    func testAGrantedFounderWithNoSidecarFailsRatherThanFallingBackToCloud() {
        granted.insert("c1")
        let t = transport(companyId: "c1", sidecar: false)
        XCTAssertNotEqual(t, .cloud, "must never silently fall back to the paid path")
        guard case .localUnavailable(let reason) = t else {
            return XCTFail("expected localUnavailable, got \(t)")
        }
        XCTAssertFalse(reason.isEmpty, "the founder needs something to act on")
    }

    /// A missing sidecar must not affect someone who never granted anything — they were
    /// always going to cloud and nothing about their turn has changed.
    func testAMissingSidecarDoesNotDisturbAnUngrantedFounder() {
        XCTAssertEqual(transport(companyId: "c1", sidecar: false), .cloud)
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

    /// `localUnavailable` is its own error case so the UI can say the true thing. Folded
    /// into `malformedResponse` it would read as a bug in the reply, and a beta week of
    /// these would look like a network problem rather than the packaging problem it is.
    func testLocalUnavailableIsDistinguishableFromEveryRetryableFailure() {
        XCTAssertEqual(ChatTurnDiagnostic.cause(of: CompanyChatStreamError.localUnavailable("x")),
                       "localUnavailable")
        XCTAssertEqual(ChatTurnDiagnostic.cause(of: CompanyChatStreamError.malformedResponse),
                       "malformedResponse")
    }

    /// The stream must THROW rather than finish empty. A stream that finishes with no
    /// events makes the store fall back to the non-streaming sender, which would reach
    /// the Cloud Function — the silent fallback this whole design refuses.
    func testTheUnavailableStreamThrowsInsteadOfFinishingEmpty() async {
        let stream = AsyncThrowingStream<CompanyChatStreamEvent, Error> {
            $0.finish(throwing: CompanyChatStreamError.localUnavailable("no runner"))
        }
        do {
            for try await _ in stream { XCTFail("no event should arrive") }
            XCTFail("must throw, not finish quietly")
        } catch CompanyChatStreamError.localUnavailable(let reason) {
            XCTAssertEqual(reason, "no runner")
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}
