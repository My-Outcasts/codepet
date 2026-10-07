// codepetTests/ChatThreadArchiveTests.swift
import XCTest
@testable import codepet

/// The company chat's RECENT list survives a relaunch (it was in-memory only until 2026-09-25).
@MainActor
final class ChatThreadArchiveTests: XCTestCase {
    private var tmp: URL!
    override func setUp() {
        super.setUp()
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("cta-\(UUID().uuidString)")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: tmp); super.tearDown() }

    private final class MemoryArchive: ChatThreadArchiving {
        var byUid: [String: [ChatThread]] = [:]
        func load(uid: String) -> [ChatThread] { byUid[uid] ?? [] }
        func save(_ threads: [ChatThread], uid: String) { byUid[uid] = threads }
    }

    private func thread(_ messages: [CopilotMessage]) -> ChatThread {
        ChatThread(id: "t1", title: "Pants", messages: messages,
                   createdAt: Date(timeIntervalSince1970: 1_000), updatedAt: Date(timeIntervalSince1970: 2_000))
    }

    // MARK: - File

    func testRoundTripKeepsWhatWasSaidAndTheApprovedDraft() async {
        let archive = FileChatThreadArchive(root: tmp)
        let draft = Deliverable(kind: .doc, title: "Art direction", body: "Quiet paper.")
        let msgs = [CopilotMessage(role: .me, text: "make the page"),
                    CopilotMessage(role: .companion, text: "", draft: draft, draftApproved: true,
                                   companionId: "luna", deptName: "Design",
                                   execSteps: [ExecStep(label: "Read the brief", done: true)])]
        archive.save([thread(msgs)], uid: "uidA")
        FileChatThreadArchive.drain()

        let back = archive.load(uid: "uidA")
        XCTAssertEqual(back.count, 1)
        XCTAssertEqual(back[0].title, "Pants")
        XCTAssertEqual(back[0].messages.map(\.role), [.me, .companion])
        XCTAssertEqual(back[0].messages[0].text, "make the page")
        XCTAssertEqual(back[0].messages[1].draft?.body, "Quiet paper.")
        XCTAssertTrue(back[0].messages[1].draftApproved, "a restored card must not offer Approve again")
        XCTAssertEqual(back[0].messages[1].execSteps?.first?.label, "Read the brief")
    }

    /// 7 Oct, build 10: chat wrote two email drafts as cards (`draft_message`), the app was
    /// relaunched, and the thread came back as "Both versions are in the draft cards above" over
    /// nothing. `StoredMessage` kept `draft` (a run's deliverable) but never `drafts` (the
    /// message cards), so the emails were lost. They are part of what was said; they come back.
    func testRoundTripKeepsTheMessageDrafts() async {
        let archive = FileChatThreadArchive(root: tmp)
        let email = MessageDraftDTO(channel: "email", to: "Building manager",
                                    subject: "15 minutes about parcels?", body: "Chào anh/chị, …")
        let dm = MessageDraftDTO(channel: "dm", to: nil, subject: nil, body: "Quick question about lockers")
        let msgs = [CopilotMessage(role: .me, text: "Draft a short email to building managers"),
                    CopilotMessage(role: .companion, text: "I wrote two versions.", drafts: [email, dm])]
        archive.save([thread(msgs)], uid: "uidA")
        FileChatThreadArchive.drain()

        let back = archive.load(uid: "uidA").first?.messages ?? []
        XCTAssertEqual(back.count, 2)
        XCTAssertEqual(back.last?.drafts, [email, dm])
    }

    /// A reply that is ONLY cards (the model wrote no prose around them) is still worth keeping.
    func testAMessageThatIsOnlyDraftsIsKept() async {
        let archive = FileChatThreadArchive(root: tmp)
        let card = MessageDraftDTO(channel: "text", to: "Linh", subject: nil, body: "See you at 3?")
        archive.save([thread([CopilotMessage(role: .companion, text: "  ", drafts: [card])])], uid: "uidA")
        FileChatThreadArchive.drain()
        XCTAssertEqual(archive.load(uid: "uidA").first?.messages.first?.drafts, [card])
    }

    /// Files written before this field have no `drafts` key at all; they must still load.
    func testAFileWithoutDraftsStillLoads() throws {
        let json = #"[{"id":"t1","title":"Old","createdAt":1000,"updatedAt":2000,"kind":"ask","messages":[{"id":"m1","fromFounder":false,"createdAt":1000,"text":"hello","draftApproved":false}]}]"#
        let d = JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970
        let threads = try d.decode([StoredThread].self, from: Data(json.utf8))
        XCTAssertEqual(threads.first?.thread.messages.first?.drafts, [])
    }

    func testLiveOnlyRowsAreNotKept() async {
        let archive = FileChatThreadArchive(root: tmp)
        let msgs = [CopilotMessage(role: .me, text: "hi"),
                    CopilotMessage(role: .companion, text: "Task", producing: true),
                    CopilotMessage(role: .companion, text: "   ")]
        archive.save([thread(msgs)], uid: "uidA")
        FileChatThreadArchive.drain()
        XCTAssertEqual(archive.load(uid: "uidA").first?.messages.map(\.text), ["hi"])
    }

    func testAccountsDoNotSeeEachOthersHistory() async {
        let archive = FileChatThreadArchive(root: tmp)
        archive.save([thread([CopilotMessage(role: .me, text: "secret")])], uid: "uidA")
        FileChatThreadArchive.drain()
        XCTAssertEqual(archive.load(uid: "uidB").count, 0)
        XCTAssertNotEqual(archive.fileURL(uid: "uidA"), archive.fileURL(uid: "uidB"))
        XCTAssertTrue(archive.fileURL(uid: "../../x").path.hasPrefix(tmp.path), "a uid cannot leave the root")
    }

    func testAnUnreadableFileIsSetAsideNotOverwritten() async throws {
        let archive = FileChatThreadArchive(root: tmp)
        let url = archive.fileURL(uid: "uidA")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "not json".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(archive.load(uid: "uidA").count, 0)
        let kept = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        XCTAssertTrue(kept.contains { $0.contains("unreadable") }, "the founder's history is kept aside")
    }

    // MARK: - Store

    private func store(_ archive: MemoryArchive) -> CompanyStore {
        CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                     chatSender: { _ in CompanyChatReply(text: "Here's the plan", runTaskId: nil) },
                     chatStreamer: { _ in AsyncThrowingStream { $0.finish(throwing: URLError(.notConnectedToInternet)) } },
                     threadArchive: archive)
    }

    func testAConversationIsBackAfterARelaunch() async {
        let archive = MemoryArchive()
        let first = store(archive)
        await first.hydrate(companyId: "u")
        await first.sendChat("plan my launch", language: .en)
        XCTAssertEqual(archive.byUid["u"]?.count, 1, "the turn's end writes the thread")

        let relaunched = store(archive)
        await relaunched.hydrate(companyId: "u")
        XCTAssertEqual(relaunched.threads.count, 1)
        XCTAssertEqual(relaunched.threads[0].messages.first?.text, "plan my launch")
        XCTAssertTrue(relaunched.chatMessages.isEmpty, "the app opens on a new chat; history is in RECENT")
        withExtendedLifetime(first) {}
    }

    func testAnotherAccountStartsWithItsOwnHistory() async {
        let archive = MemoryArchive()
        let s = store(archive)
        await s.hydrate(companyId: "u")
        await s.sendChat("mine", language: .en)
        await s.hydrate(companyId: "v")
        XCTAssertTrue(s.threads.isEmpty)
        XCTAssertEqual(archive.byUid["u"]?.count, 1, "switching away does not erase the first account's file")
    }
}
