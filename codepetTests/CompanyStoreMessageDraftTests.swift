// codepetTests/CompanyStoreMessageDraftTests.swift
import XCTest
@testable import codepet

/// Where a drafted message LANDS in the transcript.
///
/// Founder report, Aug 10, with a screenshot: two complete messages typed as quoted prose in a
/// single bubble — no boundary, no Copy, nothing saved. `draft_message` makes them objects; the
/// question this suite answers is whether they arrive attached to the reply that introduced them
/// or as a second bubble. Her earlier note on the roadmap card settles it — "the response is
/// currently disjointed", two avatars and two name rows for one thought.
@MainActor
final class CompanyStoreMessageDraftTests: XCTestCase {

    private static let failingStreamer: (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> = { _ in
        AsyncThrowingStream { $0.finish(throwing: CompanyChatStreamError.notSignedIn) }
    }

    private func draft(_ body: String, to: String = "the two who asked") -> MessageDraftDTO {
        MessageDraftDTO(channel: "dm", to: to, subject: nil, body: body)
    }

    /// Streams `text` then a `done` carrying `drafts`, which is the real wire shape.
    private func store(text: String, drafts: [MessageDraftDTO]) -> CompanyStore {
        let streamer: (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> = { _ in
            AsyncThrowingStream { c in
                if !text.isEmpty { c.yield(.delta(text)) }
                c.yield(.done(model: "m", cacheHit: true,
                              action: ChatDoneAction(drafts: drafts)))
                c.finish()
            }
        }
        return CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                            chatSender: { _ in nil }, chatStreamer: streamer)
    }

    /// The reported turn: framing prose plus two drafts. One companion bubble, both drafts on it.
    func testBothDraftsAttachToTheOneReply() async {
        let s = store(text: "Here's two versions — one for each group.",
                      drafts: [draft("Hey [name] — the real offer is $39/month."),
                               draft("Quick heads up — we move to paid on [date].", to: "the other seven")])
        await s.hydrate(companyId: "u")
        await s.sendChat("write the outreach", language: .en)

        XCTAssertEqual(s.chatMessages.count, 2, "founder + ONE companion reply, not a second bubble")
        let reply = s.chatMessages.last
        XCTAssertEqual(reply?.role, .companion)
        XCTAssertEqual(reply?.drafts.count, 2)
        XCTAssertEqual(reply?.drafts.first?.body, "Hey [name] — the real offer is $39/month.")
    }

    /// Prose the companion wrote is the better reply — the lead-in must not overwrite it.
    func testTheCompanionsOwnFramingSurvives() async {
        let s = store(text: "Here's two versions — one for each group.", drafts: [draft("hi")])
        await s.hydrate(companyId: "u")
        await s.sendChat("write it", language: .en)
        XCTAssertEqual(s.chatMessages.last?.text, "Here's two versions — one for each group.")
    }

    /// A text-free turn is the shape `draft_message` is DESIGNED to produce, since the message
    /// text moved out of the reply. It must land as a card with a line above it, never as the
    /// "I can't reach my brain right now" that a wordless turn used to trigger.
    func testATextFreeTurnGetsALineAndKeepsItsCards() async {
        let s = store(text: "", drafts: [draft("Hey [name] — worth fifteen minutes?")])
        await s.hydrate(companyId: "u")
        await s.sendChat("write it", language: .en)

        let reply = s.chatMessages.last
        XCTAssertEqual(reply?.drafts.count, 1)
        let text = reply?.text ?? ""
        XCTAssertFalse(text.isEmpty, "a wordless turn must still say something")
        XCTAssertFalse(text.contains("can't reach my brain"), "got the failure copy: \(text)")
        XCTAssertFalse(text.contains("didn't have an answer"), "got the failure copy: \(text)")
        // Nothing is being produced and nothing is being sent — the line must not promise work.
        XCTAssertFalse(text.contains("putting that together"), "promised work it isn't doing: \(text)")
    }

    /// Drafts are content, not an action: nothing is applied, nothing is sent, and no roadmap
    /// task appears just because a message was written.
    func testDraftingChangesNothingInTheCompany() async {
        let s = store(text: "Here you go.", drafts: [draft("hi [name]")])
        await s.hydrate(companyId: "u")
        let tasksBefore = s.company.tasks.count
        await s.sendChat("write it", language: .en)
        XCTAssertEqual(s.company.tasks.count, tasksBefore)
        XCTAssertNil(s.chatMessages.last?.roadmapProposal)
        XCTAssertNil(s.chatMessages.last?.runProposal)
    }

    /// An empty drafts array must not manufacture a bubble.
    func testNoDraftsAttachesNothing() async {
        let s = store(text: "Just answering your question.", drafts: [])
        await s.hydrate(companyId: "u")
        await s.sendChat("what's next", language: .en)
        XCTAssertEqual(s.chatMessages.count, 2)
        XCTAssertTrue(s.chatMessages.last?.drafts.isEmpty ?? false)
    }
}
