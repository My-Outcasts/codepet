// codepetTests/ShorterChecksItsWorkTests.swift
import XCTest
@testable import codepet

/// "Shorter" checks that the headline actually shrank, and asks once more with a hard word target
/// when it did not. Measured 5 Oct on a real draft: three notes in a row left a doc's `call` at
/// 7 → 7 → 6 lines — the model kept weighing a section arguing the sentence must be long.
@MainActor
final class ShorterChecksItsWorkTests: XCTestCase {
    private let long = Array(repeating: "word", count: 60).joined(separator: " ")
    private let short = Array(repeating: "word", count: 30).joined(separator: " ")

    private func doc(_ call: String) -> RunTaskResponse {
        var p = DeliverablePayload(); p.call = call
        return RunTaskResponse(kind: "doc", title: "D", body: call, payload: p)
    }
    private func drafted() -> RoadmapTask {
        var p = DeliverablePayload(); p.call = long
        return RoadmapTask(id: "t1", title: "T", detail: "", phase: .find, who: .does, drafted: true,
                           draft: Deliverable(kind: .doc, title: "D", body: long, sourceTaskId: "t1", payload: p))
    }
    private func store(_ replies: [RunTaskResponse], sent: @escaping (RunTaskRequest) -> Void) -> CompanyStore {
        var queue = replies
        let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                                companionId: "byte", onboardedAt: Date(), tasks: [drafted()])
        return CompanyStore(loader: { _ in seed }, tasksSaver: { _, _ in true },
                            taskRunner: { req in sent(req); return queue.isEmpty ? nil : queue.removeFirst() })
    }

    // MARK: pure rules

    func testLeadIsTheDocCallWhenThereIsOne() {
        var p = DeliverablePayload(); p.call = "the call"
        let d = Deliverable(kind: .doc, title: "T", body: "first paragraph\n\nsecond", payload: p)
        XCTAssertEqual(ReviseLength.lead(of: d), "the call")
    }

    func testLeadFallsBackToTheFirstParagraph() {
        let d = Deliverable(kind: .doc, title: "T", body: "first paragraph\n\nsecond")
        XCTAssertEqual(ReviseLength.lead(of: d), "first paragraph")
    }

    func testShrankEnoughNeedsAboutAFifthOff() {
        let a = Deliverable(kind: .doc, title: "T", body: long)
        XCTAssertFalse(ReviseLength.shrankEnough(before: a, after: Deliverable(kind: .doc, title: "T", body: long)))
        XCTAssertTrue(ReviseLength.shrankEnough(before: a, after: Deliverable(kind: .doc, title: "T", body: short)))
    }

    func testOnlyTheShorterChipIsChecked() {
        for lang in [AppLanguage.en, .vi] {
            XCTAssertTrue(ReviseKind.isShorter(note: ReviseKind.shorter.note(lang)))
            XCTAssertFalse(ReviseKind.isShorter(note: ReviseKind.punchier.note(lang)))
        }
        XCTAssertFalse(ReviseKind.isShorter(note: "make the pricing table bigger"))
    }

    func testFirmerNoteNamesAWordTarget() {
        let d = Deliverable(kind: .doc, title: "T", body: long)
        let note = ReviseLength.firmerNote(after: d, .en)
        XCTAssertTrue(note.contains("60"), note)    // what it is now
        XCTAssertTrue(note.contains("40"), note)    // two-thirds of that
        XCTAssertLessThan(note.count, 500)          // the server's clip
    }

    // MARK: the store

    func testShorterThatDidNotShrinkAsksOnceMore() async {
        var sent: [RunTaskRequest] = []
        let s = store([doc(long), doc(short)], sent: { sent.append($0) })
        await s.hydrate(companyId: "u")
        await s.reviseTaskDraft(taskId: "t1", reviseNote: ReviseKind.shorter.note(.en), language: .en)
        XCTAssertEqual(sent.count, 2)
        XCTAssertTrue(sent[1].reviseNote?.contains("40") ?? false)
        XCTAssertEqual(s.company.tasks[0].draft?.payload?.call, short)
    }

    func testShorterThatShrankRunsOnce() async {
        var sent: [RunTaskRequest] = []
        let s = store([doc(short)], sent: { sent.append($0) })
        await s.hydrate(companyId: "u")
        await s.reviseTaskDraft(taskId: "t1", reviseNote: ReviseKind.shorter.note(.en), language: .en)
        XCTAssertEqual(sent.count, 1)
    }

    /// Never more than one retry: a second miss keeps what it got rather than spending more plan.
    func testAtMostOneRetry() async {
        var sent: [RunTaskRequest] = []
        let s = store([doc(long), doc(long), doc(short)], sent: { sent.append($0) })
        await s.hydrate(companyId: "u")
        await s.reviseTaskDraft(taskId: "t1", reviseNote: ReviseKind.shorter.note(.en), language: .en)
        XCTAssertEqual(sent.count, 2)
    }

    func testOtherChipsAreNotRetried() async {
        var sent: [RunTaskRequest] = []
        let s = store([doc(long), doc(short)], sent: { sent.append($0) })
        await s.hydrate(companyId: "u")
        await s.reviseTaskDraft(taskId: "t1", reviseNote: ReviseKind.punchier.note(.en), language: .en)
        XCTAssertEqual(sent.count, 1)
    }
}
