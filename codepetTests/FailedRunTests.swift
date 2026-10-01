import XCTest
@testable import codepet

/// The Failed rule (CP-002 F, founder decisions 1 Oct). A sheet, site, calendar or screens whose
/// structure did not survive comes back as a failure: nothing is filed, the task stays runnable,
/// and the chat says who did not make what, with Try again.
@MainActor
final class FailedRunTests: XCTestCase {

    private func seed() -> CompanyState {
        CompanyState(brief: .init(), departments: [], library: [], stage: .building, companionId: "byte",
                     onboardedAt: Date(),
                     tasks: [RoadmapTask(id: "t1", title: "Build the pricing model", detail: "", phase: .find, who: .does)])
    }

    private let failure = RunTaskResponse(kind: "sheet", title: "", body: "", failed: "missing_structure")

    func testTheWireShapeDecodes() throws {
        let r = try JSONDecoder().decode(RunTaskResponse.self, from: Data(#"{"kind":"sheet","title":"","body":"","failed":"missing_structure"}"#.utf8))
        XCTAssertEqual(r.failed, "missing_structure")
        let ok = try JSONDecoder().decode(RunTaskResponse.self, from: Data(#"{"kind":"doc","title":"T","body":"b"}"#.utf8))
        XCTAssertNil(ok.failed, "an ordinary answer is not a failure")
    }

    func testAFailedRunFilesNothingAndSaysWhatItDidNotMake() async {
        var saves = 0
        let s = CompanyStore(loader: { [seed] _ in seed() }, tasksSaver: { _, _ in saves += 1; return true },
                             taskRunner: { [failure] _ in failure })
        await s.hydrate(companyId: "u")
        await s.runTask(s.company.tasks[0], language: .en)

        XCTAssertNil(s.company.tasks[0].draft, "nothing was made, so nothing is a draft")
        XCTAssertFalse(s.company.tasks[0].drafted, "the task stays runnable")
        XCTAssertTrue(s.company.library.isEmpty)
        XCTAssertEqual(saves, 0, "no task write for a run that produced nothing")
        XCTAssertFalse(s.chatMessages.contains { $0.draft != nil }, "no draft card")

        let msg = try? XCTUnwrap(s.chatMessages.last { $0.runProposal != nil })
        XCTAssertEqual(msg?.runProposal?.retry, true)
        XCTAssertEqual(msg?.runProposal?.taskId, "t1")
        XCTAssertEqual(msg?.runProposal?.buttonLabel(.en), "Try again")
        XCTAssertTrue(msg?.text.contains("couldn't finish the financial model") ?? false, msg?.text ?? "")
        XCTAssertTrue(msg?.text.contains("nothing was saved to your Library") ?? false, msg?.text ?? "")
    }

    func testTryAgainRunsTheSameTask() async {
        var calls = 0
        let s = CompanyStore(loader: { [seed] _ in seed() }, tasksSaver: { _, _ in true },
                             taskRunner: { [failure] _ in
                                 calls += 1
                                 return calls == 1 ? failure : RunTaskResponse(kind: "doc", title: "Pricing", body: "# A model, in prose")
                             })
        await s.hydrate(companyId: "u")
        await s.runTask(s.company.tasks[0], language: .en)
        guard let retry = s.chatMessages.last(where: { $0.runProposal?.retry == true }) else {
            return XCTFail("no Try again offered")
        }
        await s.confirmRun(messageId: retry.id, language: .en)
        XCTAssertEqual(calls, 2)
        XCTAssertNotNil(s.company.tasks[0].draft, "the second run produced a draft")
        XCTAssertTrue(s.chatMessages.first { $0.id == retry.id }?.actionConsumed ?? false, "Try again retires once pressed")
    }

    /// The run used the founder's Claude plan. The sentence must not claim otherwise.
    func testTheCopyNamesWhoAndWhatAndClaimsNothingFree() {
        for kind in ["sheet", "site", "calendar", "screens"] {
            for lang in [AppLanguage.en, .vi] {
                let line = RunFailureCopy.line(kind: kind, deptName: "Finance", lang: lang)
                XCTAssertTrue(line.hasPrefix("Finance "), line)
                for word in ["free", "charged", "spent", "credit", "miễn phí"] {
                    XCTAssertFalse(line.lowercased().contains(word), "\(kind)/\(lang): \(line)")
                }
            }
        }
        XCTAssertEqual(RunFailureCopy.line(kind: "site", deptName: nil, lang: .en),
                       "Codepet couldn't finish the landing page: its answer was missing the page itself, so nothing was saved to your Library.")
    }

    func testAnOrdinaryProposalKeepsItsLabel() {
        XCTAssertEqual(RunProposal(taskId: "t", title: "x", deptName: nil, companionId: nil).buttonLabel(.en), "Yes, start it")
    }
}
