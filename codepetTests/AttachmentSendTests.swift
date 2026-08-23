import XCTest
@testable import codepet

/// An attached file has to survive the trip from the composer to the wire, in the
/// exact shape `functions/` agreed to (`fe2e767`, `a75570c`). `CompanyStore` is driven
/// through injected closures, so this asserts on the request the store built.
///
/// **Why several of these assert on the JSON rather than on the Swift value.**
/// `companyChat.ts` applies `ChatRequestBody` with an `as` cast, so a key it does not
/// expect is *silently ignored* — `mediaType` instead of `media_type` produces no
/// error, no 400 and no image, only a reply that never saw the file, with nothing in
/// `functions:log` to find. A test that reads `req.attachments?.first?.mediaType`
/// passes whatever the CodingKey says. Only the encoded bytes can catch the spelling.
@MainActor
final class AttachmentSendTests: XCTestCase {

    /// Throws before yielding, which is what makes the non-streaming `chatSender` path
    /// run deterministically with no network and no `Auth.auth()` (unconfigured under
    /// XCTest, and it TRAPS rather than throwing). Copied from `ContextPinSendTests`.
    private static let failingStreamer: (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> = { _ in
        AsyncThrowingStream { $0.finish(throwing: CompanyChatStreamError.notSignedIn) }
    }

    /// Every request the store built, in order — the follow-up tests need the SECOND one.
    /// `CompanyStore.company` is `private(set)`, so state comes from the loader + `hydrate`.
    private func store(capturing onRequest: @escaping (CompanyChatRequest) -> Void) -> CompanyStore {
        CompanyStore(
            loader: { _ in
                CompanyState(brief: CompanyBrief(projectName: "Codepet",
                                                 oneLiner: "AI coding companion"),
                             departments: [], library: [], stage: .idea,
                             companionId: "byte", onboardedAt: Date(),
                             // A real task, so the pin in the last test resolves —
                             // `ChatContext.compose` skips a pin whose item is gone,
                             // which would make that assertion pass for the wrong reason.
                             tasks: [RoadmapTask(id: "t1", title: "Ship billing", detail: "",
                                                 phase: .build, who: .does)])
            },
            saver: { _, _ in true },
            chatSender: { req in
                onRequest(req)
                return CompanyChatReply(text: "A login form.", runTaskId: nil)
            },
            chatStreamer: Self.failingStreamer)
    }

    private func shot(_ name: String = "shot.png", data: String = "aGVsbG8=") -> ChatAttachment {
        ChatAttachment(id: "/tmp/\(name)#8", kind: .image, filename: name,
                       mediaType: "image/png", data: data, byteCount: 8)
    }

    private func json(_ req: CompanyChatRequest) throws -> [String: Any] {
        let data = try JSONEncoder().encode(req)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - This turn's file

    func testAnAttachmentReachesTheRequest() async throws {
        var captured: [CompanyChatRequest] = []
        let s = store { captured.append($0) }
        await s.hydrate(companyId: "u")

        await s.sendChat("what is this?", language: .en, attachments: [shot()])

        let req = try XCTUnwrap(captured.first, "no request was composed")
        XCTAssertEqual(req.attachments?.count, 1)
        XCTAssertEqual(req.attachments?.first?.mediaType, "image/png")
        XCTAssertEqual(req.attachments?.first?.kind, "image")
        XCTAssertEqual(req.attachments?.first?.data, "aGVsbG8=")
    }

    /// **The wire contract, byte for byte.** `media_type` in snake_case, and exactly the
    /// four keys the backend reads — `id` (an absolute path, so the founder's home
    /// directory) and `byteCount` must not be on the wire at all.
    func testTheAttachmentIsEncodedWithTheContractsExactKeys() async throws {
        var captured: [CompanyChatRequest] = []
        let s = store { captured.append($0) }
        await s.hydrate(companyId: "u")

        await s.sendChat("what is this?", language: .en, attachments: [shot()])

        let body = try json(try XCTUnwrap(captured.first))
        let list = try XCTUnwrap(body["attachments"] as? [[String: Any]])
        let one = try XCTUnwrap(list.first)
        XCTAssertEqual(Set(one.keys), ["kind", "filename", "media_type", "data"],
                       "the backend reads media_type; mediaType is silently ignored, and id would leak a path")
        XCTAssertEqual(one["media_type"] as? String, "image/png")
        XCTAssertEqual(one["filename"] as? String, "shot.png")
    }

    /// nil, not `[]`. `CompanyChatRequest` encodes optionals with `encodeIfPresent`, so
    /// nil keeps the key off the wire entirely instead of adding `"attachments":[]` to
    /// every request the app has ever sent.
    func testAnUnattachedSendOmitsTheKeyEntirely() async throws {
        var captured: [CompanyChatRequest] = []
        let s = store { captured.append($0) }
        await s.hydrate(companyId: "u")

        await s.sendChat("what should we charge?", language: .en)

        let req = try XCTUnwrap(captured.first)
        XCTAssertNil(req.attachments)
        XCTAssertFalse(try json(req).keys.contains("attachments"),
                       "an empty array would appear on every request in the app")
    }

    // MARK: - The follow-up question

    /// **The failure this whole field exists to prevent.** With `role` + `text` only on
    /// `ChatTurnDTO`, the first question about an image is answered and every follow-up
    /// reaches a model that cannot see it — which presents as the model forgetting, not
    /// as anything broken. The backend half (`ATTACHMENT_REPLAY_WINDOW`) has been live
    /// since `fe2e767`; this is the client half.
    func testAFollowUpReplaysTheImageOnItsHistoryTurn() async throws {
        var captured: [CompanyChatRequest] = []
        let s = store { captured.append($0) }
        await s.hydrate(companyId: "u")

        await s.sendChat("what is this?", language: .en, attachments: [shot()])
        await s.sendChat("and the button colour?", language: .en)

        XCTAssertEqual(captured.count, 2)
        let follow = captured[1]
        XCTAssertNil(follow.attachments, "the follow-up itself carries no new file")
        let carried = follow.history.filter { $0.attachments != nil }
        XCTAssertEqual(carried.count, 1, "the founder's earlier turn must still carry the image")
        XCTAssertEqual(carried.first?.role, "me")
        XCTAssertEqual(carried.first?.attachments?.first?.data, "aGVsbG8=")

        // Same key, same shape, on the history entry — not a second spelling.
        let body = try json(follow)
        let history = try XCTUnwrap(body["history"] as? [[String: Any]])
        let withFile = try XCTUnwrap(history.first { $0["attachments"] != nil })
        let one = try XCTUnwrap((withFile["attachments"] as? [[String: Any]])?.first)
        XCTAssertEqual(one["media_type"] as? String, "image/png")
    }

    /// The image is on the request OR on a history turn, never both in one request. The
    /// `.me` bubble is stamped before `history` is built from `dropLast()`, and if that
    /// order slipped the founder would upload and be billed for the same screenshot
    /// twice in a single turn.
    func testTheSendingTurnCarriesItsFileOnceOnly() async throws {
        var captured: [CompanyChatRequest] = []
        let s = store { captured.append($0) }
        await s.hydrate(companyId: "u")

        await s.sendChat("what is this?", language: .en, attachments: [shot()])

        let req = try XCTUnwrap(captured.first)
        XCTAssertNotNil(req.attachments)
        XCTAssertTrue(req.history.allSatisfy { $0.attachments == nil },
                      "this turn's file must ride the top level only")
    }

    /// A conversation with no attachments encodes exactly as it always has: no
    /// `attachments` key anywhere, on the request or on any history turn.
    func testAnOrdinaryConversationIsUnchangedOnTheWire() async throws {
        var captured: [CompanyChatRequest] = []
        let s = store { captured.append($0) }
        await s.hydrate(companyId: "u")

        await s.sendChat("hi", language: .en)
        await s.sendChat("and again", language: .en)

        let body = try json(try XCTUnwrap(captured.last))
        XCTAssertFalse(body.keys.contains("attachments"))
        let history = try XCTUnwrap(body["history"] as? [[String: Any]])
        XCTAssertFalse(history.isEmpty, "there must BE history, or this asserts nothing")
        XCTAssertTrue(history.allSatisfy { !$0.keys.contains("attachments") })
    }

    // MARK: - The cap, at the wire

    /// The store applies `AttachmentBudget` with its production constant, so a caller
    /// that never went through the composer still cannot build the request that 413s
    /// before it reaches the function. `AttachmentBudgetTests` pins the arithmetic; this
    /// pins that the store is the one applying it.
    func testAnOverSizedAttachmentNeverReachesTheWire() async throws {
        var captured: [CompanyChatRequest] = []
        let s = store { captured.append($0) }
        await s.hydrate(companyId: "u")

        let huge = ChatAttachment(
            id: "/tmp/huge.png#1", kind: .image, filename: "huge.png", mediaType: "image/png",
            data: String(repeating: "A", count: AttachmentBudget.maxTotalBase64Bytes + 1),
            byteCount: 1)
        await s.sendChat("what is this?", language: .en, attachments: [huge])

        let req = try XCTUnwrap(captured.first)
        XCTAssertNil(req.attachments, "over the total cap it is dropped, not sent and 413'd")
        XCTAssertFalse(try json(req).keys.contains("attachments"))
    }

    /// Attachments and pins ride the same send and neither displaces the other — they
    /// are one gesture to the founder and two independent fields on the wire.
    func testAPinAndAnAttachmentRideTheSameTurn() async throws {
        var captured: [CompanyChatRequest] = []
        let s = store { captured.append($0) }
        await s.hydrate(companyId: "u")

        await s.sendChat("what is this?", language: .en,
                         pinned: [.task(id: "t1", title: "Ship billing")],
                         attachments: [shot()])

        let req = try XCTUnwrap(captured.first)
        XCTAssertEqual(req.attachments?.count, 1)
        XCTAssertTrue(req.context.contains(ContextPin.groundingHeading),
                      "the pinned block and the attachment must not be alternatives")
    }
}
