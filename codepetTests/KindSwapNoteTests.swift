import XCTest
@testable import codepet

/// CP-062: a screens task filed under Engineering comes back as a doc — only Design may make
/// screens — and nothing said why, so it read as the app ignoring the request (5 Oct, build 7).
/// Founder's call: keep the doc, and the draft card says "Engineering writes this as a doc —
/// Design makes screens."
@MainActor
final class KindSwapNoteTests: XCTestCase {

    // MARK: - the wire

    func testTheRunResponseCarriesTheSwap() throws {
        let json = ##"{"kind":"doc","title":"Onboarding","body":"# x","coerced":{"from":"screens","dept":"design"}}"##
        let r = try JSONDecoder().decode(RunTaskResponse.self, from: Data(json.utf8))
        XCTAssertEqual(r.coerced, KindSwap(from: "screens", dept: "design"))
    }

    func testAResponseWithoutTheFieldStillDecodes() throws {
        let r = try JSONDecoder().decode(RunTaskResponse.self, from: Data(#"{"kind":"doc","title":"t","body":"b"}"#.utf8))
        XCTAssertNil(r.coerced)
    }

    func testADraftKeepsTheSwapThroughSaveAndLoad() throws {
        let d = Deliverable(id: "d1", kind: .doc, title: "t", body: "b",
                            coerced: KindSwap(from: "screens", dept: "design"))
        let back = try JSONDecoder().decode(Deliverable.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(back.coerced, KindSwap(from: "screens", dept: "design"))
    }

    // MARK: - the words

    func testTheNoteNamesWhoWroteItAndWhoMakesTheThing() {
        XCTAssertEqual(DraftCardCopy.kindSwapNote(KindSwap(from: "screens", dept: "design"),
                                                  writer: "Engineering", .en),
                       "Engineering writes this as a doc — Design makes screens.")
        XCTAssertEqual(DraftCardCopy.kindSwapNote(KindSwap(from: "sheet", dept: "fin"),
                                                  writer: "Engineering", .en),
                       "Engineering writes this as a doc — Finance makes models.")
        XCTAssertEqual(DraftCardCopy.kindSwapNote(KindSwap(from: "site", dept: "design"),
                                                  writer: "Finance", .en),
                       "Finance writes this as a doc — Design makes landing pages.")
    }

    func testTheNoteHasAVietnameseForm() {
        XCTAssertEqual(DraftCardCopy.kindSwapNote(KindSwap(from: "screens", dept: "design"),
                                                  writer: "Engineering", .vi),
                       "Engineering viết việc này thành tài liệu — Design mới làm màn hình.")
    }

    func testNoNoteForAKindItDoesNotKnow() {
        XCTAssertNil(DraftCardCopy.kindSwapNote(KindSwap(from: "poster", dept: "design"),
                                                writer: "Engineering", .en))
    }

    // MARK: - end to end through the store

    private static let deadStream: (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> = { _ in
        AsyncThrowingStream { $0.finish(throwing: CompanyChatStreamError.notSignedIn) }
    }

    func testARunWhoseKindWasSwappedPutsTheSwapOnTheDraft() async {
        let s = CompanyStore(
            loader: { _ in
                CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .idea,
                             companionId: "byte", onboardedAt: Date(),
                             tasks: [RoadmapTask(id: "t1", title: "Design the onboarding screens",
                                                 detail: "", phase: .find, who: .does, dept: "eng")])
            },
            saver: { _, _ in true }, tasksSaver: { _, _ in true },
            chatSender: { _ in CompanyChatReply(text: "On it", runTaskId: "t1") },
            chatStreamer: Self.deadStream,
            taskRunner: { _ in
                var r = RunTaskResponse(kind: "doc", title: "Onboarding", body: "# Six screens")
                r.coerced = KindSwap(from: "screens", dept: "design")
                return r
            },
            librarySaver: { _, _ in true }, firstApprovalSaver: { _, _ in true },
            decisionExtractor: { _, _ in [] })
        await s.hydrate(companyId: "u")
        await s.sendChat("run it", language: .en)
        XCTAssertEqual(s.chatMessages.last(where: { $0.draft != nil })?.draft?.coerced,
                       KindSwap(from: "screens", dept: "design"))
    }
}
