import XCTest
@testable import codepet

/// The pin has to survive the trip from the composer to the wire. `CompanyStore` is
/// driven through injected closures, so this asserts on the request the store built
/// rather than on a network call.
@MainActor
final class ContextPinSendTests: XCTestCase {

    /// A `chatStreamer` that throws before yielding — this is what makes the
    /// non-streaming `chatSender` path run deterministically, with no network and no
    /// `Auth.auth()` (unconfigured under XCTest, and it TRAPS rather than throwing).
    /// Copied from `CompanyStoreChatTests`, which is the pattern of record.
    private static let failingStreamer: (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> = { _ in
        AsyncThrowingStream { $0.finish(throwing: CompanyChatStreamError.notSignedIn) }
    }

    /// `CompanyStore.company` is `private(set)` — state is seeded through the
    /// LOADER and `hydrate`, never by assigning to `store.company`.
    private func store(capturing onRequest: @escaping (CompanyChatRequest) -> Void) -> CompanyStore {
        CompanyStore(
            loader: { _ in
                CompanyState(brief: CompanyBrief(projectName: "Codepet", oneLiner: "AI coding companion"),
                             departments: [],
                             library: [Deliverable(id: "d1", kind: .doc, title: "Pricing page",
                                                   body: "We charge $20/mo for Pro.",
                                                   createdAt: "2026-08-20T10:00:00Z")],
                             stage: .idea, companionId: "byte", onboardedAt: Date(),
                             tasks: [RoadmapTask(id: "t1", title: "Ship billing", detail: "",
                                                 phase: .build, who: .does)])
            },
            saver: { _, _ in true },
            chatSender: { req in
                onRequest(req)
                return CompanyChatReply(text: "ok", runTaskId: nil)
            },
            chatStreamer: Self.failingStreamer)
    }

    func testAPinnedDeliverableReachesTheRequestContext() async {
        var captured: CompanyChatRequest?
        let s = store { captured = $0 }
        await s.hydrate(companyId: "u")

        await s.sendChat("What should we charge?", language: .en,
                         pinned: [.deliverable(id: "d1", title: "Pricing page")])

        guard let req = captured else { return XCTFail("no request was composed") }
        XCTAssertTrue(req.context.contains(ContextPin.groundingHeading),
                      "the pinned block never reached the wire")
        XCTAssertTrue(req.context.contains("We charge $20/mo for Pro."))
    }

    /// The default path is untouched: no `pinned:` argument, no pinned block.
    ///
    /// Honest about its reach: NO deletion in this change makes this test red —
    /// dropping either `pinned:` hop only breaks the test above. The empty case is
    /// already held by `ChatContextPinTests.testAPinToADeletedItemIsSkippedEntirely`
    /// inside `compose`. What this adds is the same claim at the STORE boundary, so
    /// a future refactor that holds pins as store state and forgets to clear them
    /// after a send — the failure `ContextPin`'s own doc comment warns about — is
    /// caught here rather than in the founder's credit balance.
    func testAnUnpinnedSendCarriesNoPinnedBlock() async {
        var captured: CompanyChatRequest?
        let s = store { captured = $0 }
        await s.hydrate(companyId: "u")

        await s.sendChat("What should we charge?", language: .en)

        guard let req = captured else { return XCTFail("no request was composed") }
        XCTAssertFalse(req.context.contains(ContextPin.groundingHeading))
    }
}
