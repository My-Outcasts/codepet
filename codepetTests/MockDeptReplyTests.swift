import XCTest
@testable import codepet

#if DEBUG
/// Prototype mode routes a turn to a department and stamps that department's pet on the
/// reply bubble (`CompanyStore.actingSpecialist`). Until this branch existed, the header
/// read "sage · Finance" while the words underneath were byte's generic three-moves copy —
/// the right pet arriving and then not sounding like one, in the demo whose entire claim is
/// that the right pet showed up.
///
/// These assertions hold the two halves of that: an armed department must change the words,
/// and arming one must change NOTHING else. The second half is why the branch sits last in
/// `route` — every scripted beat above it (the guided flow, the autoplay script) is depended
/// on word-for-word elsewhere.
///
/// Driven through `MockChat.reply` rather than `route`, which is private: `reply` is also the
/// path the app takes, so what is asserted here is the text a founder would actually read
/// (bold markers stripped, `{{product}}` filled).
final class MockDeptReplyTests: XCTestCase {

    /// A message that trips NONE of the keyword branches in `route`, so the turn reaches the
    /// department branch and, without a department, the generic fallthrough. If a future
    /// keyword makes this message scripted, `testNoDepartmentKeepsTheExactGenericReply` says so.
    private let neutral = "how would you think about this?"

    /// The generic fallthrough, verbatim as `reply` renders it. Pinned as a literal on
    /// purpose: comparing against another call of the same function would agree with itself
    /// no matter what the copy became.
    private let genericReply = """
    Here's how I'd think about it. Your leverage right now is momentum, not polish — the \
    goal this week is one real signal from one real user, not a perfect plan.

    So: (1) write your positioning in a single sentence and put it where a stranger can \
    see it, (2) book five short calls with people who have the problem, and (3) ship the \
    smallest thing they can actually touch. Do those three and you'll know more by Friday \
    than another month of planning would tell you.

    Want me to draft the positioning line or the outreach message to get those calls booked?
    """

    override func setUp() {
        super.setUp()
        // `reply` fills `{{product}}` from whatever brief a flow demo last captured, which is
        // process-wide state another suite may have set. Pin it so the copy is deterministic.
        MockChat.flowBrief = nil
    }

    override func tearDown() {
        MockChat.flowBrief = nil
        super.tearDown()
    }

    private func request(_ message: String,
                         dept: String?,
                         runnable: [RunnableRef] = []) -> CompanyChatRequest {
        CompanyChatRequest(companyId: "u1", language: "en", companionId: "byte", context: "",
                           history: [], userMessage: message, runnable: runnable, deptKey: dept)
    }

    private func text(_ message: String, dept: String?) async throws -> String {
        // `await` inside XCTUnwrap's autoclosure does not compile — unwrap the awaited value.
        let reply = await MockChat.reply(request(message, dept: dept))
        return try XCTUnwrap(reply).text
    }

    // MARK: - The eight departments

    /// The whole point of the branch: each department that has a pet answers in its own
    /// words, and none of them answers with byte's.
    ///
    /// Iterated over `DepartmentCompanions.map` rather than a hand-typed list, so casting a
    /// pet to a ninth department without writing its copy fails here instead of shipping a
    /// pet that speaks byte's lines. The count is asserted too — an iteration over a set that
    /// silently emptied would pass every assertion inside it.
    ///
    /// DELETE THE BRANCH AND THIS GOES RED: with no branch every key returns the generic
    /// reply, so both the distinctness check and the "differs from generic" check fail.
    func testEachDepartmentWithAPetAnswersInItsOwnWords() async throws {
        let keys = Set(DepartmentCompanions.map.keys)
        XCTAssertEqual(keys, ["eng", "design", "mkt", "sales", "support", "fin", "ops", "legal"],
                       "the departments with a pet changed — write copy for the new one")

        var seen: [String: String] = [:]
        for key in keys.sorted() {
            let reply = try await text(neutral, dept: key)
            XCTAssertFalse(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           "\(key) answered with an empty bubble")
            XCTAssertNotEqual(reply, genericReply,
                              "\(key) armed the chip and then answered in byte's generic words")
            if let owner = seen[reply] {
                XCTFail("\(key) and \(owner) share the same reply — one of them is not a specialist")
            }
            seen[reply] = key
        }
        XCTAssertEqual(seen.count, 8, "expected 8 distinct department replies, got \(seen.count)")
    }

    /// Marketing and Sales are both cast to nova, and Operations and Legal both to glitch. The
    /// reply is keyed off the DEPARTMENT, not off the pet, so each pair must still differ —
    /// this is the assertion that would catch a `switch` written over `companionId`.
    ///
    /// Finance and Support used to be the second pair, both cast to sage. The 26 Aug recast
    /// gave Finance to crash, so that pair stopped sharing a pet and the case quietly stopped
    /// testing anything — it still passed, on two departments that no longer collide. Operations
    /// and Legal replace it because they genuinely share glitch. Finance/Support stays as a
    /// third case: it costs one comparison and it is the regression that would fire first if
    /// the cast moved back.
    ///
    /// DELETE THE BRANCH AND THIS GOES RED (both sides become the generic reply and compare equal).
    func testDepartmentsSharingOnePetStillAnswerDifferently() async throws {
        let mkt = try await text(neutral, dept: "mkt")
        let sales = try await text(neutral, dept: "sales")
        XCTAssertNotEqual(mkt, sales, "nova answers Marketing and Sales identically")

        let ops = try await text(neutral, dept: "ops")
        let legal = try await text(neutral, dept: "legal")
        XCTAssertNotEqual(ops, legal, "glitch answers Operations and Legal identically")

        let fin = try await text(neutral, dept: "fin")
        let support = try await text(neutral, dept: "support")
        XCTAssertNotEqual(fin, support, "Finance and Support answer identically")
    }

    // MARK: - What must NOT change

    /// The un-armed turn, pinned byte-for-byte.
    ///
    /// DELETE THE BRANCH AND THIS STAYS GREEN, deliberately — it is a pin, not a proof of the
    /// feature. What it catches is the branch reaching turns it has no business in (a gate
    /// written on `deptKey ?? ""`, or a default arm returning copy instead of nil) and any
    /// edit to the generic copy itself, which several other beats read as the "no department"
    /// answer.
    func testNoDepartmentKeepsTheExactGenericReply() async throws {
        let reply = try await text(neutral, dept: nil)
        XCTAssertEqual(reply, genericReply)
    }

    /// `product` is in `DepartmentCatalog` (the Virtual Company emits it on the wire) and has
    /// no pet. `actingSpecialist` already declines to hand those turns off, so the bubble is
    /// signed by byte — and it must therefore read as byte, not as a blank or a stub.
    ///
    /// DELETE THE BRANCH AND THIS STAYS GREEN. It fails if the gate is widened to
    /// `DepartmentCatalog.find(key) != nil`, which is the plausible wrong gate here, or if the
    /// unmapped case ever returns "" — both of which put an empty or half-written bubble on
    /// screen for a department the router really does emit.
    func testUnmappedDepartmentFallsThroughToTheGenericReply() async throws {
        XCTAssertNotNil(DepartmentCatalog.find("product"), "fixture assumption: product is in the catalog")
        XCTAssertNil(DepartmentCompanions.companionId(for: "product"), "fixture assumption: product has no pet")

        let reply = try await text(neutral, dept: "product")
        XCTAssertEqual(reply, genericReply)
    }

    /// Placement. The department branch is LAST, so arming a chip must not rewrite a scripted
    /// beat — the guided flow's "summarize" opener and the run branch's `runTaskId` are what
    /// `MockFlowTests`/`MockFlowScriptTests` and the autoplay walkthrough drive.
    ///
    /// DELETE THE BRANCH AND THIS STAYS GREEN. It goes red the moment the branch moves ABOVE
    /// the scripted branches, which is the one edit that silently breaks the demo this fixture
    /// exists for — and the reason the placement is worth a test rather than a comment.
    func testAnArmedDepartmentDoesNotOverrideAScriptedBeat() async throws {
        let summary = try await text("summarize where we are", dept: "fin")
        XCTAssertTrue(summary.hasPrefix("Here\u{2019}s where Codepet stands."),
                      "an armed department rewrote the guided flow's opener: \(summary.prefix(60))")

        let runnable = [RunnableRef(id: "mock-landing", title: "Write your landing page copy")]
        let run = await MockChat.reply(request("run the landing page",
                                                dept: "mkt",
                                                runnable: runnable))
        XCTAssertEqual(try XCTUnwrap(run).runTaskId, "mock-landing",
                       "an armed department swallowed the run action")
    }
}
#endif
